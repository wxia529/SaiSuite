param(
  [string]$Flutter = 'flutter',
  [string]$Python = 'python',
  [string]$OutputDirectory = 'dist/development/windows'
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $taskRoot
& $Python -X utf8 tools/prepare_windows.py
if ($LASTEXITCODE -ne 0) { throw 'Windows processing runtime preparation failed' }
$taskPubOutput = & $Flutter pub get 2>&1
$taskPubOutput | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0 -and !($taskPubOutput -match 'symlink support')) { throw 'Flutter dependency resolution failed' }
# Directory junctions need neither administrator rights nor Developer Mode.
# Flutter accepts them as existing plugin links. Only this project's ephemeral
# plugin directory is modified; Pub cache contents are never changed.
$taskLinkRoot = Join-Path $taskRoot 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Path $taskLinkRoot -Force | Out-Null
$taskPlugins = Get-Content .flutter-plugins-dependencies -Raw | ConvertFrom-Json
foreach ($taskPlugin in $taskPlugins.plugins.windows) {
  $taskLink = Join-Path $taskLinkRoot $taskPlugin.name
  if (!(Test-Path -LiteralPath $taskLink)) {
    New-Item -ItemType Junction -Path $taskLink -Target $taskPlugin.path | Out-Null
  }
}
# Complete generated native registration after resolving any link privilege error.
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter plugin registration failed' }
# Let the release command regenerate plugin registration in release mode. A prior
# test/debug command may have registered dev-only plugins, even after pub get.
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
& $Python -X utf8 tools/package_windows.py --output $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Windows packaging failed' }
& $Python -X utf8 tools/build_windows_installer.py --output $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Windows installer packaging failed' }
