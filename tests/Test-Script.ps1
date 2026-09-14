# No network, credential access, or desktop changes.
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../CuaLink.ps1'
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errors)
if ($errors) { throw ($errors.Message -join '; ') }
foreach ($name in 'Read-LinkConfig','Read-Port','Show-Connection','New-BearerToken') {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if (-not $fn) { throw "Missing function: $name" }
    Invoke-Expression $fn.Extent.Text
}
$tokens=@(1..10 | ForEach-Object { New-BearerToken })
if (@($tokens | Select-Object -Unique).Count -ne 10 -or @($tokens | Where-Object {$_ -notmatch '^[A-F0-9]{64}$'}).Count) { throw 'Token generator failed' }
$temp=[IO.Path]::GetTempFileName()
try {
    $valid=@{BearerToken=('a'*64);SshHost='example.test';SshUser='test';SshAuthMode='key';SshPort=22;LocalPort=19222;RemotePort=19222}
    function Check-Config($value, [bool]$accepted) {
        $lines=@('[CuaLink]')
        foreach ($key in $value.Keys) { $lines += "$key=$($value[$key])" }
        $lines | Set-Content -LiteralPath $temp -Encoding UTF8
        $rejected=$false
        try { $null=Read-LinkConfig $temp } catch { $rejected=$true }
        if ($rejected -eq $accepted) { throw "Unexpected configuration validation result (expected accepted=$accepted)." }
    }
    Check-Config $valid $true
    foreach ($name in @($valid.Keys)) {
        $copy=$valid.Clone(); $copy.Remove($name); Check-Config $copy $false
    }
    foreach ($mode in 'key','password') {
        $copy=$valid.Clone(); $copy.SshAuthMode=$mode; Check-Config $copy $true
    }
    foreach ($value in '"22"',22.5,0,65536,$null,$true) {
        $copy=$valid.Clone(); $copy.SshPort=$value; Check-Config $copy $false
    }
    foreach ($value in '',('a'*31),('a'*4097),('a'*32+' b')) {
        $copy=$valid.Clone(); $copy.BearerToken=$value; Check-Config $copy $false
    }
    $copy=$valid.Clone(); $copy.UseConfig='true'; Check-Config $copy $false
    $copy=$valid.Clone(); $copy.SshPassword='not-allowed'; Check-Config $copy $false
    Check-Config @{} $true
    Check-Config @{SshPort='22'} $false # A partial configuration must not silently prompt.
    foreach ($invalid in '', '[Other]', 'SshHost=example.test', "[CuaLink]`nSshHost=`nsshhost=", "[CuaLink]`n[CuaLink]") {
        Set-Content -LiteralPath $temp -Value $invalid -Encoding UTF8
        $rejected=$false
        try { $null=Read-LinkConfig $temp } catch { $rejected=$true }
        if (-not $rejected) { throw 'Invalid INI accepted' }
    }
    Set-Content -LiteralPath $temp -Encoding UTF8 -Value " ; comment`n# comment`n`n[CUAlink]`n SshHost = "
    if ((Read-LinkConfig $temp).IsPreset) { throw 'Whitespace/comment parsing failed' }
    $copy=$valid.Clone(); $copy.BearerToken=('a'*32+'=;#'); Check-Config $copy $true
    if ((Read-LinkConfig $temp).BearerToken -ne $copy.BearerToken) { throw 'Token punctuation was altered' }
    $template=Read-LinkConfig (Join-Path $PSScriptRoot '../config.example.ini')
    if ($template.IsPreset) { throw 'Unsafe template defaults' }
    if ((Get-Content (Join-Path $PSScriptRoot '../config.example.ini') -Raw) -match '(?m)^\s*[;#]|UseConfig') { throw 'Template should be clean and switch-free' }
} finally { Remove-Item -LiteralPath $temp -Force }
foreach ($port in -1,65536) {
    $rejected=$false
    try { Read-Port 'test' $port 22 } catch { $rejected=$true }
    if (-not $rejected) { throw "Invalid port $port was accepted" }
}
# Validate the public template without evaluating or changing its settings.
$source=Get-Content $path -Raw
if ($source -match '\$UseScriptConfig') { throw 'Inline configuration returned' }
if ($source -match '\$SshPassword') { throw 'Preset password support returned' }
if ($source -match 'ToHexString|::HashData|\$IsWindows|pwsh\.exe') { throw 'PowerShell 7 dependency returned' }
$display=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-Connection'},$true).Extent.Text
$last=-1
foreach ($label in 'CUA link:','SSH target:','MCP Transport:','MCP address:','Authorization:') {
    $index=$display.IndexOf($label)
    if ($index -le $last) { throw "Incorrect output order: $label" }
    $last=$index
}
if ($display.Contains('Bearer Token:')) { throw 'Duplicate token output' }
Write-Host 'PASS: syntax, preset validation, port bounds, public defaults, display order.'
