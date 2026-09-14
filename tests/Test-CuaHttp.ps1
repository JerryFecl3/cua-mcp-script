param([Parameter(Mandatory)][string]$Driver, [switch]$Desktop)
$ErrorActionPreference='Stop'
$Driver=(Resolve-Path $Driver).Path
$testRoot=Join-Path $env:TEMP ('cua-mcp-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testRoot | Out-Null
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start(); $port=$listener.LocalEndpoint.Port; $listener.Stop()
$priorPort=$env:CUA_DRIVER_RS_MCP_HTTP_PORT; $priorToken=$env:CUA_DRIVER_RS_MCP_HTTP_TOKEN
$env:CUA_DRIVER_RS_MCP_HTTP_PORT="$port"
$env:CUA_DRIVER_RS_MCP_HTTP_TOKEN=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$headers=@{Authorization="Bearer $env:CUA_DRIVER_RS_MCP_HTTP_TOKEN";Accept='application/json, text/event-stream';'MCP-Protocol-Version'='2025-06-18'}
$url="http://127.0.0.1:$port/mcp"
function Rpc($method,$params) {
    $body=@{jsonrpc='2.0';id=1;method=$method;params=$params}|ConvertTo-Json -Depth 12 -Compress
    $r=Invoke-RestMethod $url -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 10
    if ($r.error) { throw ($r.error|ConvertTo-Json -Compress) }
    return $r.result
}
$p=$null
try {
    $p=Start-Process $Driver -ArgumentList 'serve','--socket',('\\.\pipe\cua-ci-'+[guid]::NewGuid().ToString('N')) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$testRoot/out.log" -RedirectStandardError "$testRoot/err.log"
    $init=$null
    for($i=0;$i -lt 30;$i++) {
        if ($p.HasExited) { throw 'Driver exited before HTTP initialization' }
        try { $init=Rpc initialize @{protocolVersion='2025-06-18';capabilities=@{};clientInfo=@{name='cua-mcp-script-test';version='1'}}; break } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $init -or $init.serverInfo.name -ne 'cua-driver') { throw 'HTTP initialization failed' }
    $unauthorized=Invoke-WebRequest $url -Method Post -ContentType 'application/json' -Body '{}' -SkipHttpErrorCheck
    if ([int]$unauthorized.StatusCode -ne 401) { throw 'Unauthenticated request was not rejected with 401' }
    $tools=Rpc 'tools/list' @{}
    foreach($name in 'list_windows','get_window_state','launch_app','type_text') {
        if($name -notin $tools.tools.name) { throw "Required tool missing: $name" }
    }
    if($Desktop) {
        $windows=Rpc 'tools/call' @{name='list_windows';arguments=@{}}
        $target=$windows.structuredContent.windows | Where-Object { $_.app_name -eq 'explorer.exe' -and $_.is_on_screen } | Select-Object -First 1
        if(-not $target){throw 'No interactive Explorer window; open an empty test folder on the dedicated desktop'}
        $snapshot=Rpc 'tools/call' @{name='get_window_state';arguments=@{pid=$target.pid;window_id=$target.window_id;max_dimension=640;max_elements=30}}
        if($snapshot.isError -or -not ($snapshot.content | Where-Object {$_.type -eq 'image' -and $_.data})) { throw 'Desktop screenshot did not arrive as an MCP image' }
    }
    Write-Host "PASS: CUA $($init.serverInfo.version), HTTP auth, handshake, required tools; desktop=$Desktop"
} finally {
    if($p -and -not $p.HasExited){Stop-Process -Id $p.Id; $p.WaitForExit(10000) | Out-Null}
    $env:CUA_DRIVER_RS_MCP_HTTP_PORT=$priorPort; $env:CUA_DRIVER_RS_MCP_HTTP_TOKEN=$priorToken
}
$check=[Net.Sockets.TcpClient]::new()
try {$check.Connect('127.0.0.1',$port);throw 'Port still listening after shutdown'} catch [Net.Sockets.SocketException] {} finally {$check.Dispose()}
