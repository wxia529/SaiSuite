param(
    [string]$Device = 'emulator-5558',
    [string]$Flutter = 'E:\apps\flutter\bin\flutter.bat',
    [string]$Adb = 'E:\Android\Sdk\platform-tools\adb.exe',
    [switch]$ObserveOnly
)

$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskLogDir = Join-Path $taskRoot '.buildlog'
$taskLogPath = Join-Path $taskLogDir 'image-editor-integration.log'
if ((& $Adb -s $Device shell getprop ro.build.version.sdk).Trim() -ne '36') {
    throw 'The default image-editor test requires an Android API 36 device.'
}
New-Item -ItemType Directory -Path $taskLogDir -Force | Out-Null
$taskJob = $null
if (-not $ObserveOnly) {
    Set-Content -LiteralPath $taskLogPath -Value ''
    $taskJob = Start-Job -ArgumentList $taskRoot, $Flutter, $Device, $taskLogPath -ScriptBlock {
        param($repo, $flutterCommand, $serial, $log)
        Set-Location -LiteralPath $repo
        & $flutterCommand test integration_test/image_editor_test.dart -d $serial *> $log
        return $LASTEXITCODE
    }
}

# The test only exports its generated sample. Act on the real document UI;
# do not guess coordinates or click other apps.
$taskStage = 0
$taskDeadline = (Get-Date).AddMinutes(8)
try {
    while ((Get-Date) -lt $taskDeadline -and $taskStage -lt 2) {
        $taskLog = Get-Content -LiteralPath $taskLogPath -Raw
        if ($taskLog -match 'Some tests failed\.|All tests passed!') { break }
        $taskMarker = if ($taskStage -eq 0) { 'EDITOR_TEST_WAIT_CANCEL_SAVE' } else { 'EDITOR_TEST_WAIT_SUCCESS_SAVE' }
        if ($taskLog -match $taskMarker) {
            $taskFocus = (& $Adb -s $Device shell dumpsys window) -join "`n"
            if ($taskFocus -match 'mCurrentFocus=.*documentsui') {
                & $Adb -s $Device shell uiautomator dump /sdcard/Download/saisuite-editor-save-ui.xml | Out-Null
                $taskXmlText = (& $Adb -s $Device shell cat /sdcard/Download/saisuite-editor-save-ui.xml) -join "`n"
                [xml]$taskXml = $taskXmlText
                Set-Content -LiteralPath (Join-Path $taskLogDir "image-editor-save-stage-$taskStage.xml") -Value $taskXmlText -Encoding UTF8
                if ($taskStage -eq 0) {
                    & $Adb -s $Device shell input keyevent KEYCODE_BACK
                    Write-Output 'Cancelled the first system-save dialog.'
                    $taskStage = 1
                } else {
                    $taskButtons = @($taskXml.SelectNodes('//node') | Where-Object {
                        $_.text -match '^(SAVE|Save|保存)$' -and $_.clickable -eq 'true' -and $_.enabled -eq 'true'
                    })
                    if ($taskButtons.Count -ne 1) { throw 'Cannot identify the system Save button.' }
                    if ($taskButtons[0].bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid Save button bounds.' }
                    $taskX = [int](([int]$matches[1] + [int]$matches[3]) / 2)
                    $taskY = [int](([int]$matches[2] + [int]$matches[4]) / 2)
                    & $Adb -s $Device shell input tap $taskX $taskY
                    Write-Output 'Confirmed the second system-save dialog.'
                    $taskStage = 2
                }
            }
        }
        Start-Sleep -Seconds 1
    }
    if ($taskStage -ne 2) { throw "System-save checks incomplete (stage $taskStage). See $taskLogPath" }
    if ($null -ne $taskJob) {
        $taskFinished = Wait-Job -Job $taskJob -Timeout 90
        if ($null -eq $taskFinished) { throw 'The test did not complete after system save.' }
        $taskExit = Receive-Job -Job $taskJob
        if ($taskExit -ne 0) { throw "Image-editor test failed. See $taskLogPath" }
        Get-Content -LiteralPath $taskLogPath -Tail 8
    }
} finally {
    if ($null -ne $taskJob) {
        if ($taskJob.State -eq 'Running') { Stop-Job -Job $taskJob }
        Remove-Job -Job $taskJob
    }
}
