# No network, credential access, or desktop changes.
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../CuaLink.ps1'
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errors)
if ($errors) { throw ($errors.Message -join '; ') }
foreach ($name in 'Assert-ScriptConfig','Read-Port','Show-Connection') {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if (-not $fn) { throw "Missing function: $name" }
    Invoke-Expression $fn.Extent.Text
}
$BearerToken='a'*64; $SshHost='example.test'; $SshUser='test'; $SshAuthMode='key'
$SshPort=22; $LocalPort=19222; $RemotePort=19222
Assert-ScriptConfig
foreach ($name in 'BearerToken','SshHost','SshUser','SshAuthMode','SshPort','LocalPort','RemotePort') {
    $original=Get-Variable $name -ValueOnly
    Set-Variable $name $null
    $rejected=$false
    try { Assert-ScriptConfig } catch { $rejected=$true }
    if (-not $rejected) { throw "Missing $name was accepted" }
    Set-Variable $name $original
}
$SshAuthMode='password'; Assert-ScriptConfig # Password is prompted, never preset.
foreach ($port in -1,65536) {
    $rejected=$false
    try { Read-Port 'test' $port 22 } catch { $rejected=$true }
    if (-not $rejected) { throw "Invalid port $port was accepted" }
}
# Validate the public template without evaluating or changing its settings.
$source=Get-Content $path -Raw
if ($source -notmatch '(?m)^\$BearerToken = ''''' -or $source -notmatch '(?m)^\$UseScriptConfig = \$false') { throw 'Unsafe distribution defaults' }
if ($source -match '\$SshPassword') { throw 'Preset password support returned' }
$display=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Show-Connection'},$true).Extent.Text
$last=-1
foreach ($label in 'CUA link:','SSH target:','MCP Transport:','MCP address:','Authorization:') {
    $index=$display.IndexOf($label)
    if ($index -le $last) { throw "Incorrect output order: $label" }
    $last=$index
}
if ($display.Contains('Bearer Token:')) { throw 'Duplicate token output' }
Write-Host 'PASS: syntax, preset validation, port bounds, public defaults, display order.'
