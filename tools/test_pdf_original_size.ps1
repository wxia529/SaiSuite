param([string]$Device = 'emulator-5558')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$adb = 'E:\Android\Sdk\platform-tools\adb.exe'
$flutter = 'E:\apps\flutter\bin\flutter.bat'
$python = 'C:\Users\xwt\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if ((& $adb -s $Device shell getprop ro.build.version.sdk).Trim() -ne '36') { throw 'Expected API 36 device' }
@'
from pathlib import Path
from PIL import Image, ImageDraw
folder = Path('.buildlog/pdf-original-size-fixtures'); folder.mkdir(parents=True, exist_ok=True)
wide = Image.new('RGBA', (5000,200), (0,0,0,0)); draw = ImageDraw.Draw(wide)
draw.rectangle((0,0,99,99), fill=(255,0,0,255)); draw.rectangle((4900,100,4999,199), fill=(0,0,255,128)); wide.save(folder/'wide.png')
Image.new('RGB',(240,480),(0,255,0)).save(folder/'portrait.png')
image = Image.new('RGB',(180,120)); draw=ImageDraw.Draw(image)
for box, color in [((0,0,89,59),'red'),((90,0,179,59),'green'),((0,60,89,119),'blue'),((90,60,179,119),'yellow')]: draw.rectangle(box,fill=color)
for i in range(1,9):
    exif=Image.Exif(); exif[274]=i; image.save(folder/f'orientation-{i}.jpg', quality=100, subsampling=0, exif=exif)
Image.new('RGB',(4001,4001),'white').save(folder/'oversize.png')
'@ | & $python -X utf8 -
if ($LASTEXITCODE -ne 0) { throw 'Fixture generation failed' }
& $flutter build apk --debug *> .buildlog\pdf-original-size-debug-build.log
if ($LASTEXITCODE -ne 0) { throw 'Debug build failed' }
& $adb -s $Device install -r build\app\outputs\flutter-apk\app-debug.apk
if ($LASTEXITCODE -ne 0) { throw 'Install failed' }
& $adb -s $Device push .buildlog/pdf-original-size-fixtures /data/local/tmp/
& $adb -s $Device shell run-as io.github.wxia529.saisuite.dev mkdir -p cache/pdf-original-size-fixtures
foreach ($file in Get-ChildItem -LiteralPath .buildlog/pdf-original-size-fixtures -File) {
    & $adb -s $Device shell run-as io.github.wxia529.saisuite.dev cp "/data/local/tmp/pdf-original-size-fixtures/$($file.Name)" "cache/pdf-original-size-fixtures/$($file.Name)"
    if ($LASTEXITCODE -ne 0) { throw 'Fixture copy failed' }
}
$log = Join-Path $root '.buildlog\pdf-original-size-integration.log'
Set-Content -LiteralPath $log -Value ''
$job = Start-Job -ArgumentList $root,$flutter,$Device,$log -ScriptBlock {
    param($repo,$command,$serial,$output)
    Set-Location -LiteralPath $repo
    & $command test integration_test/pdf_original_size_test.dart -d $serial --reporter expanded *> $output
    return $LASTEXITCODE
}
$copied = $false
$deadline = (Get-Date).AddMinutes(6)
try {
    while ($job.State -eq 'Running' -and (Get-Date) -lt $deadline) {
        if (-not $copied -and (Get-Content -LiteralPath $log -Raw) -match 'PDF_ORIGINAL_SIZE_READY') {
            $start = [System.Diagnostics.ProcessStartInfo]::new($adb)
            $start.UseShellExecute = $false; $start.CreateNoWindow = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
            foreach ($argument in @('-s',$Device,'exec-out','run-as','io.github.wxia529.saisuite.dev','cat','cache/saisuite_pdf_original_size_test.pdf')) { $start.ArgumentList.Add($argument) }
            $process = [System.Diagnostics.Process]::Start($start)
            $stream = [System.IO.File]::Create((Join-Path $root '.buildlog\pdf-original-size-verified.pdf'))
            try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
            $failure = $process.StandardError.ReadToEnd(); $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "PDF capture failed: $failure" }
            $process.Dispose(); $copied = $true
        }
        Start-Sleep -Milliseconds 500
    }
    if ($job.State -eq 'Running') { throw 'Integration timed out' }
    $result = Receive-Job $job
    if ($result[-1] -ne 0 -or -not $copied) { throw 'Integration failed; inspect log' }
    Get-Content -LiteralPath $log -Tail 8
    & $python -X utf8 tools/verify_pdf_original_size.py *> .buildlog\pdf-original-size-independent.log
    if ($LASTEXITCODE -ne 0) { throw 'Independent PDF inspection failed' }
    Get-Content .buildlog\pdf-original-size-independent.log -Tail 3
} finally { if ($job.State -eq 'Running') { Stop-Job $job }; Remove-Job $job -Force }
