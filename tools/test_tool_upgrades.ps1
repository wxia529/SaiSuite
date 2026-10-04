param([string]$Device = 'emulator-5558')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$adb = 'E:\Android\Sdk\platform-tools\adb.exe'
$flutter = 'E:\apps\flutter\bin\flutter.bat'
$api = (& $adb -s $Device shell getprop ro.build.version.sdk).Trim()
if ($api -ne '36') { throw "Expected API 36, found $api on $Device" }
$fixture = Join-Path $root '.buildlog\saisuite-video-fixture.mp4'
if (-not (Test-Path -LiteralPath $fixture)) {
    Invoke-WebRequest -Uri 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4' -OutFile $fixture
}
& $flutter build apk --debug *> .buildlog\tool-upgrades-debug-build.log
if ($LASTEXITCODE -ne 0) { throw 'Debug build failed; inspect log' }
& $adb -s $Device install -r build\app\outputs\flutter-apk\app-debug.apk
if ($LASTEXITCODE -ne 0) { throw 'APK installation failed' }
& $adb -s $Device push $fixture /data/local/tmp/saisuite-video-fixture.mp4
& $adb -s $Device shell run-as io.github.wxia529.saisuite.dev cp /data/local/tmp/saisuite-video-fixture.mp4 cache/saisuite-video-fixture.mp4
if ($LASTEXITCODE -ne 0) { throw 'Fixture preparation failed' }
& $flutter test integration_test\tool_upgrades_test.dart -d $Device --reporter expanded *> .buildlog\tool-upgrades-integration.log
if ($LASTEXITCODE -ne 0) { throw 'Integration failed; inspect .buildlog/tool-upgrades-integration.log' }
Get-Content .buildlog\tool-upgrades-integration.log -Tail 10
