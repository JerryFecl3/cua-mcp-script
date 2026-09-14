#requires -Version 5.1
param(
    [ValidateSet('menu','start','stop','status','worker')][string]$Action = 'menu',
    [switch]$NoPause
)

# Connection settings live in config.ini; see docs/configuration.md.

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'cua-mcp-script requires Windows PowerShell 5.1 or later on Windows.' }
function New-BearerToken {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [BitConverter]::ToString($bytes).Replace('-', '')
}
$sha = [Security.Cryptography.SHA256]::Create()
try { $instanceId = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLowerInvariant()))).Replace('-', '').Substring(0,16) }
finally { $sha.Dispose() }
$pipe = '\\.\pipe\cua-mcp-script-' + $instanceId
$runtime = Join-Path $PSScriptRoot '.runtime'
New-Item -ItemType Directory -Force $runtime | Out-Null
$stateFile = Join-Path $runtime 'state.json'
$stopFile = Join-Path $runtime 'stop.request'
$configFile = Join-Path $runtime 'launch.json'
$lockFile = Join-Path $runtime 'supervisor.lock'
$inputFile = Join-Path $runtime 'stdin.empty'
if (-not (Test-Path $inputFile)) { [IO.File]::WriteAllText($inputFile, '') }

function Read-State {
    if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json }
}
function Get-Supervisor($state) {
    if (-not $state) { return $null }
    $p = Get-Process -Id $state.supervisorPid -ErrorAction SilentlyContinue
    if ($p -and $p.StartTime.ToUniversalTime().Ticks.ToString() -eq $state.started) { return $p }
    return $null
}
function Publish-State($value) {
    $value | ConvertTo-Json | Set-Content "$stateFile.tmp"
    Move-Item -LiteralPath "$stateFile.tmp" -Destination $stateFile -Force
}
function Read-LinkConfig([string]$Path) {
    try { $lines = Get-Content -LiteralPath $Path -Encoding UTF8 }
    catch { throw 'Cannot read config.ini. Copy config.example.ini and edit your settings.' }
    $values = @{}
    $section = $false
    $allowed = @('UseConfig','BearerToken','SshHost','SshUser','SshAuthMode','SshPort','LocalPort','RemotePort')
    foreach ($line in $lines) {
        $text = $line.Trim()
        if (-not $text -or $text.StartsWith(';') -or $text.StartsWith('#')) { continue }
        if ($text.StartsWith('[')) {
            if ($text -ne '[CuaLink]' -or $section) { throw 'config.ini must have exactly one [CuaLink] section.' }
            $section = $true
            continue
        }
        $separator = $text.IndexOf('=')
        if (-not $section -or $separator -lt 1) { throw 'config.ini: expected Key=Value under [CuaLink].' }
        $name = $text.Substring(0,$separator).Trim()
        if ($name -notin $allowed -or $values.ContainsKey($name)) {
            throw 'config.ini has an unknown or duplicate setting. Refer to config.example.ini; passwords cannot be stored in config.'
        }
        $values[$name] = $text.Substring($separator+1).Trim()
    }
    if ($values.UseConfig -notin 'true','false') { throw 'config.ini: UseConfig must be true or false (without quotes).' }
    $values.UseConfig = $values.UseConfig -eq 'true'
    $settings = [pscustomobject]$values
    if (-not $settings.UseConfig) { return $settings }
    foreach ($name in 'BearerToken','SshHost','SshUser','SshAuthMode') {
        if ($settings.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($settings.$name)) {
            throw "config.ini: $name is required when UseConfig is true. Fill every setting or set UseConfig to false."
        }
    }
    if ($settings.SshAuthMode -notin 'key','password') { throw 'config.ini: SshAuthMode must be key or password.' }
    foreach ($name in 'SshPort','LocalPort','RemotePort') {
        $value = 0
        if (-not [int]::TryParse($settings.$name,[ref]$value) -or $value -lt 1 -or $value -gt 65535) {
            throw "config.ini: $name must be an integer between 1 and 65535."
        }
        $settings.$name = $value
    }
    if ($settings.BearerToken.Length -lt 32 -or $settings.BearerToken.Length -gt 4096 -or $settings.BearerToken -match '\s') {
        throw 'config.ini: BearerToken must contain 32-4096 non-whitespace characters.'
    }
    if ($settings.SshHost -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.:-]*$') { throw 'config.ini: Invalid SshHost.' }
    if ($settings.SshUser -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$') { throw 'config.ini: Invalid SshUser.' }
    return $settings
}
function Show-Connection($state) {
    Write-Host "`n========== MCP CONNECTION =========="
    Write-Host "CUA link: $($state.status)"
    if ($state.status -eq 'running') {
        Write-Host "SSH target: $($state.sshTarget) connected"
    } else {
        Write-Host "SSH target: $($state.sshTarget) disconnected"
    }
    Write-Host 'MCP Transport: Streamable HTTP'
    Write-Host "MCP address: $($state.url)"
    if ($state.status -eq 'running') {
        $saved=Get-Content $configFile -Raw | ConvertFrom-Json
        $token=[Net.NetworkCredential]::new('',(ConvertTo-SecureString $saved.token)).Password
        Write-Host "Authorization: Bearer $token"
    }
    Write-Host "====================================`n"
}
function Read-Port([string]$Label, [int]$Value, [int]$Default) {
    if ($Value -eq 0) {
        $answer = Read-Host "$Label [$Default]"
        if ($answer -eq '') { $Value=$Default }
        elseif (-not [int]::TryParse($answer, [ref]$Value)) { throw "$Label must be an integer." }
    }
    if ($Value -lt 1 -or $Value -gt 65535) { throw "$Label must be between 1 and 65535." }
    return $Value
}
function New-Askpass {
    # OpenSSH accepts passwords through SSH_ASKPASS, not a password argument.
    # Compile the small adapter using the Windows .NET Framework compiler.
    $source = @"
using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
class CuaAskpass {
    static int Main() {
        try {
            byte[] data = Convert.FromBase64String(File.ReadAllText(Environment.GetEnvironmentVariable("CUA_PASSWORD_FILE")));
            byte[] plain = ProtectedData.Unprotect(data, null, DataProtectionScope.CurrentUser);
            Console.WriteLine(Encoding.UTF8.GetString(plain));
            Array.Clear(plain, 0, plain.Length);
            return 0;
        } catch { return 1; }
    }
}
"@
    $source | Set-Content "$runtime/askpass.cs"
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (-not (Test-Path $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
    if (-not (Test-Path $compiler)) { throw 'Windows .NET Framework C# compiler is required for SSH password mode.' }
    & $compiler /nologo /target:exe "/out:$runtime\askpass.exe" /reference:System.Security.dll "$runtime\askpass.cs" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile SSH password adapter.' }
}
function Probe-Mcp {
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cua-link","version":"1"}}}'
    $r = Invoke-RestMethod "http://127.0.0.1:$LocalPort/mcp" -Method Post -Headers @{Authorization="Bearer $BearerToken";Accept='application/json, text/event-stream'} -ContentType 'application/json' -Body $body -TimeoutSec 2
    return $r.result.serverInfo.name -eq 'cua-driver'
}

if ($Action -eq 'worker') {
    $lock=$null; $cua=$null; $sshProcess=$null; $state=$null
    try {
        $lock = [IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
        Remove-Item $stopFile -ErrorAction SilentlyContinue
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        $LocalPort=[int]$config.localPort; $RemotePort=[int]$config.remotePort
        $SshPort=[int]$config.sshPort; $SshHost=$config.sshHost; $SshUser=$config.sshUser
        $BearerToken = [Net.NetworkCredential]::new('', (ConvertTo-SecureString $config.token)).Password
        $self=Get-Process -Id $PID
        $state=@{supervisorPid=$PID;started=$self.StartTime.ToUniversalTime().Ticks.ToString();status='starting';error='';url="http://127.0.0.1:$RemotePort/mcp";sshTarget="${SshUser}@${SshHost}"}
        Publish-State $state
        $probe=[Net.Sockets.TcpClient]::new()
        try { $probe.Connect('127.0.0.1',$LocalPort); throw "Local port $LocalPort is already in use." }
        catch [Net.Sockets.SocketException] { }
        finally { $probe.Dispose() }
        $env:CUA_DRIVER_RS_MCP_HTTP_PORT="$LocalPort"
        $env:CUA_DRIVER_RS_MCP_HTTP_TOKEN=$BearerToken
        $bundledDriver = Join-Path $PSScriptRoot 'cua/cua-driver.exe'
        $driver = if (Test-Path $bundledDriver) { (Resolve-Path $bundledDriver).Path } else { (Get-Command cua-driver -ErrorAction Stop).Source }
        $cua=Start-Process $driver -ArgumentList 'serve','--socket',$pipe -WindowStyle Hidden -RedirectStandardInput $inputFile -PassThru -RedirectStandardOutput "$runtime/cua.stdout.log" -RedirectStandardError "$runtime/cua.stderr.log"
        $ready=$false
        for ($i=0; $i -lt 30; $i++) {
            if (Test-Path $stopFile) { throw 'Start cancelled.' }
            if ($cua.HasExited) { throw 'CUA exited; see cua.stderr.log.' }
            try { if (Probe-Mcp) { $ready=$true; break } } catch { }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) { throw 'CUA HTTP initialization timed out.' }
        $auth=@('-o','BatchMode=yes')
        if ($config.passwordMode) {
            $env:SSH_ASKPASS=Join-Path $runtime 'askpass.exe'
            $env:SSH_ASKPASS_REQUIRE='force'
            $env:DISPLAY='cua-link'
            $env:CUA_PASSWORD_FILE=Join-Path $runtime 'password.dpapi'
            $auth=@('-o','BatchMode=no','-o','NumberOfPasswordPrompts=1','-o','PreferredAuthentications=password','-o','PubkeyAuthentication=no')
        }
        $common=@('-p',"$SshPort",'-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=8')+$auth
        # Preflight authenticates and rejects a remote port conflict before declaring success.
        $check="if ss -ltnH 'sport = :$RemotePort' | grep -q .; then exit 23; fi"
        & ssh @common "${SshUser}@${SshHost}" $check 1>$null 2>"$runtime/ssh-check.stderr.log"
        if ($LASTEXITCODE -eq 23) { throw "Remote port $RemotePort is already in use." }
        if ($LASTEXITCODE -ne 0) { throw 'SSH login failed. See ssh-check.stderr.log. Unknown host keys must first be verified with an ordinary SSH login.' }
        $sshArgs=@('-NT')+$common+@('-o','ExitOnForwardFailure=yes','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=3','-R',"127.0.0.1:${RemotePort}:127.0.0.1:${LocalPort}","${SshUser}@${SshHost}")
        $sshProcess=Start-Process ssh -ArgumentList $sshArgs -WindowStyle Hidden -RedirectStandardInput $inputFile -PassThru -RedirectStandardError "$runtime/ssh.stderr.log"
        $connected=$false
        for ($i=0; $i -lt 10; $i++) {
            if (Test-Path $stopFile) { throw 'Start cancelled.' }
            if ($sshProcess.HasExited) { throw 'SSH tunnel exited; see ssh.stderr.log.' }
            $code=& ssh @common "${SshUser}@${SshHost}" "curl --max-time 2 -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:$RemotePort/mcp" 2>$null
            if ($LASTEXITCODE -eq 0 -and "$code" -eq '401' -and -not $sshProcess.HasExited) { $connected=$true; break }
            Start-Sleep -Milliseconds 300
        }
        if (-not $connected) { throw 'Remote endpoint did not become ready; see SSH logs.' }
        $state.status='running'; Publish-State $state
        while (-not (Test-Path $stopFile)) {
            if ($cua.HasExited -or $sshProcess.HasExited) { throw 'CUA or SSH exited; both services have been stopped. See logs.' }
            Start-Sleep -Milliseconds 300
        }
        $state.status='stopped'
    } catch {
        if ($state) { $state.status='failed'; $state.error=$_.Exception.Message }
        else { $_ | Out-String | Write-Error -ErrorAction Continue }
    } finally {
        if ($sshProcess -and -not $sshProcess.HasExited) { Stop-Process -Id $sshProcess.Id -ErrorAction SilentlyContinue }
        if ($cua -and -not $cua.HasExited) { Stop-Process -Id $cua.Id -ErrorAction SilentlyContinue }
        if ($state) {
            Publish-State $state
            Remove-Item "$runtime/password.dpapi" -ErrorAction SilentlyContinue
        }
        if ($lock) { $lock.Dispose() }
    }
    exit
}

$frontendLock = $null
try {
    $frontendLock = [IO.File]::Open((Join-Path $runtime 'frontend.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $userConfigFile = Join-Path $PSScriptRoot 'config.ini'
    if ($Action -in 'menu','start' -and -not (Test-Path -LiteralPath $userConfigFile)) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.example.ini') -Destination $userConfigFile
        Write-Host 'Created config.ini. Edit it to enable preset configuration.'
    }
    if ($Action -eq 'menu') {
        Write-Host '1. Start   2. Stop   3. Status'
        switch (Read-Host 'Select [1]') {
            '' {$Action='start'} '1' {$Action='start'} 'start' {$Action='start'}
            '2' {$Action='stop'} 'stop' {$Action='stop'}
            '3' {$Action='status'} 'status' {$Action='status'}
            default { throw 'Choose 1, 2 or 3.' }
        }
    }
    $state=Read-State; $supervisor=Get-Supervisor $state
    switch ($Action) {
        'start' {
            if (-not $supervisor) {
                $settings = Read-LinkConfig $userConfigFile
                if ($settings.UseConfig) {
                    $BearerToken=$settings.BearerToken; $SshHost=$settings.SshHost; $SshUser=$settings.SshUser
                    $SshAuthMode=$settings.SshAuthMode; $SshPort=$settings.SshPort
                    $LocalPort=$settings.LocalPort; $RemotePort=$settings.RemotePort
                    if ($SshAuthMode -eq 'key') { $secret=[Security.SecureString]::new() }
                    else {
                        $secret=Read-Host 'SSH password' -AsSecureString
                        if ($secret.Length -eq 0) { throw 'SSH password is required in password mode.' }
                    }
                } else {
                    $SshHost=Read-Host 'SSH host address'
                    $SshUser=Read-Host 'SSH username'
                    $SshPort=Read-Port 'SSH port' 0 22
                    $LocalPort=Read-Port 'Windows CUA port' 0 19222
                    $RemotePort=Read-Port 'Debian mapped port' 0 19222
                    $secret=Read-Host 'SSH password (Enter for key authentication)' -AsSecureString
                    $BearerToken=''
                }
                if ($SshHost -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.:-]*$') { throw 'Invalid SSH host address.' }
                if ($SshUser -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$') { throw 'Invalid SSH username.' }
                $SshPort=Read-Port 'SSH port' $SshPort 22
                $LocalPort=Read-Port 'Windows CUA port' $LocalPort 19222
                $RemotePort=Read-Port 'Debian mapped port' $RemotePort 19222
                $passwordMode=$secret.Length -gt 0
                if ($passwordMode) {
                    New-Askpass
                    $plain=[Net.NetworkCredential]::new('', $secret).Password
                    $bytes=[Text.Encoding]::UTF8.GetBytes($plain)
                    $encrypted=[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
                    [Convert]::ToBase64String($encrypted) | Set-Content "$runtime/password.dpapi"
                    [Array]::Clear($bytes,0,$bytes.Length); $plain=$null
                }
                if (-not $BearerToken) { $BearerToken=New-BearerToken }
                if ($BearerToken.Length -lt 32 -or $BearerToken.Length -gt 4096 -or $BearerToken -match '\s') { throw 'Bearer token must contain 32-4096 non-whitespace characters.' }
                $config=@{sshHost=$SshHost;sshUser=$SshUser;sshPort=$SshPort;localPort=$LocalPort;remotePort=$RemotePort;passwordMode=$passwordMode;token=(ConvertTo-SecureString $BearerToken -AsPlainText -Force | ConvertFrom-SecureString)}
                $config | ConvertTo-Json | Set-Content $configFile
                # Always use the in-box 5.1 host, even if launched from PowerShell 7.
                $engine=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
                if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
                    $engine=Join-Path $env:WINDIR 'Sysnative/WindowsPowerShell/v1.0/powershell.exe'
                }
                $worker=Start-Process $engine -ArgumentList '-NoProfile','-File',('"'+$PSCommandPath+'"'),'worker' -WindowStyle Hidden -RedirectStandardInput $inputFile -PassThru -RedirectStandardOutput "$runtime/supervisor.stdout.log" -RedirectStandardError "$runtime/supervisor.stderr.log"
                $deadline=(Get-Date).AddSeconds(120)
                do {
                    Start-Sleep -Milliseconds 300
                    $state=Read-State
                    if ($state -and $state.supervisorPid -eq $worker.Id -and $state.status -eq 'running') { break }
                    if ($worker.HasExited -or ($state -and $state.supervisorPid -eq $worker.Id -and $state.status -eq 'failed')) { throw "Start failed: $($state.error) See .runtime logs." }
                    if ((Get-Date) -gt $deadline) { Set-Content $stopFile 'stop'; throw 'Start timed out; shutdown requested.' }
                } while ($true)
            } elseif ($state.status -ne 'running') { throw "Service is $($state.status). Please retry shortly." }
            Show-Connection $state
            Write-Host 'Services stay running after this window closes. Run this script again and choose Stop.'
        }
        'stop' {
            if ($supervisor) {
                Set-Content $stopFile 'stop'
                if (-not $supervisor.WaitForExit(30000)) { throw 'Stop is still pending; check status and logs.' }
            }
            Write-Host 'CUA link stopped.'
        }
        'status' {
            if ($supervisor) { Show-Connection $state }
            elseif ($state) { $state.status='stopped'; Show-Connection $state; if ($state.error) { Write-Host "Last error: $($state.error)" } }
            else { Write-Host 'CUA link: stopped' }
        }
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($frontendLock) { $frontendLock.Dispose(); $frontendLock=$null }
    if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
}
if ($frontendLock) { $frontendLock.Dispose(); $frontendLock=$null }
if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }


