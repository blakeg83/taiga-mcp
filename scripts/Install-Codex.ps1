#Requires -Version 7.3
<#
.SYNOPSIS
Publishes Taiga MCP and installs its server connection and two skills into Codex.
.DESCRIPTION
Run with PowerShell 7.3+, the SDK from global.json, and Codex CLI on PATH.
Re-registers the taiga connection, preserving its environment variables. Other
Codex connections/settings are retained; the original config is backed up.
Existing Taiga-specific tool filters/timeouts are reset to Codex defaults.
Uses existing credentials, process environment, or prompts on first setup.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'TaigaMCP')
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This script supports Windows only.' }
$PSNativeCommandArgumentPassing = 'Standard'
Get-Command dotnet, codex -ErrorAction Stop | Out-Null
$repoRoot = Split-Path $PSScriptRoot -Parent
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$codexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$configPath = Join-Path $codexDirectory 'config.toml'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$releasePath = Join-Path $InstallRoot "releases\$stamp"
$runtime = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }

# Let Codex parse/write its own TOML instead of maintaining a custom parser.
New-Item -ItemType Directory -Force -Path $codexDirectory | Out-Null
$serverJson = & codex mcp list --json
if ($LASTEXITCODE -ne 0) { throw 'Could not read Codex MCP configuration.' }
$existing = $serverJson | ConvertFrom-Json | Where-Object name -EQ 'taiga'
if ($existing -and $existing.transport.type -ne 'stdio') { throw 'The taiga connection uses HTTP. Rename it before installing this local server.' }
$serverEnvironment = @{}
if ($existing -and $existing.transport.env) {
    foreach ($property in $existing.transport.env.PSObject.Properties) {
        $serverEnvironment[$property.Name] = [string]$property.Value
    }
}
if ($existing -and $existing.transport.env_vars) {
    foreach ($name in $existing.transport.env_vars) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($null -eq $value) { throw "Set inherited environment variable $name before running setup." }
        $serverEnvironment[$name] = $value
    }
}
foreach ($name in @('TAIGA__USERNAME', 'TAIGA__PASSWORD', 'TAIGA__BASEURL')) {
    if ([string]::IsNullOrWhiteSpace($serverEnvironment[$name])) {
        $serverEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
}
if ([string]::IsNullOrWhiteSpace($serverEnvironment['TAIGA__USERNAME'])) {
    $serverEnvironment['TAIGA__USERNAME'] = Read-Host 'Taiga username'
}
if ([string]::IsNullOrWhiteSpace($serverEnvironment['TAIGA__PASSWORD'])) {
    $password = Read-Host 'Taiga password' -AsSecureString
    $serverEnvironment['TAIGA__PASSWORD'] = [Net.NetworkCredential]::new('', $password).Password
}
if ([string]::IsNullOrWhiteSpace($serverEnvironment['TAIGA__USERNAME']) -or [string]::IsNullOrWhiteSpace($serverEnvironment['TAIGA__PASSWORD'])) {
    throw 'Taiga username and password must not be blank.'
}
if ([string]::IsNullOrWhiteSpace($serverEnvironment['TAIGA__BASEURL'])) {
    $serverEnvironment['TAIGA__BASEURL'] = 'https://api.taiga.io/api/v1/'
}

Push-Location $repoRoot
try {
    & dotnet publish .\TaigaMCP.csproj -c Release -r $runtime --self-contained true `
        -p:PublishSingleFile=true --artifacts-path (Join-Path $InstallRoot "build\$stamp") -o $releasePath
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed; Codex configuration was not changed.' }
}
finally { Pop-Location }
$executable = Join-Path $releasePath 'TaigaMCP.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Published TaigaMCP.exe was not found.' }

foreach ($name in @('taiga-backlog-publisher', 'taiga-story-loop-lite')) {
    $destination = Join-Path $codexDirectory "skills\$name"
    if (-not (Test-Path -LiteralPath $destination)) {
        $destination = Join-Path $env:USERPROFILE ".agents\skills\$name"
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path (Join-Path $repoRoot ".agents\skills\$name\*") -Destination $destination -Recurse -Force
}
if (Test-Path -LiteralPath $configPath) {
    Copy-Item -LiteralPath $configPath -Destination "$configPath.backup-$stamp"
}
$codexArguments = @('mcp', 'add', 'taiga')
foreach ($name in $serverEnvironment.Keys) {
    $codexArguments += @('--env', "$name=$($serverEnvironment[$name])")
}
$codexArguments += @('--', $executable)
& codex @codexArguments
if ($LASTEXITCODE -ne 0) { throw 'Codex registration failed. The previous config backup is beside config.toml.' }
Write-Host "Installed Taiga MCP: $executable"
Write-Host 'Installed both skills. Restart Codex and open a new chat.'
