param([Parameter(Mandatory=$true)][string]$ImagePath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
[Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null
$taskAwaitMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await-Operation($Operation, [Type]$ResultType) {
    $taskOperation = $taskAwaitMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $taskOperation.Wait()
    $taskOperation.Result
}
$taskFile = Await-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
$taskStream = Await-Operation ($taskFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$taskBitmap = $null
try {
    $taskDecoder = Await-Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($taskStream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $taskBitmap = Await-Operation ($taskDecoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $taskEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('zh-Hans-CN'))
    if ($null -eq $taskEngine) { throw 'Chinese OCR language resources unavailable. Install Chinese OCR resources in Windows Settings.' }
    $taskResult = Await-Operation ($taskEngine.RecognizeAsync($taskBitmap)) ([Windows.Media.Ocr.OcrResult])
    $taskLines = @($taskResult.Lines | ForEach-Object {
        $taskWords = @($_.Words)
        $taskLeft = ($taskWords | ForEach-Object {$_.BoundingRect.X} | Measure-Object -Minimum).Minimum
        $taskTop = ($taskWords | ForEach-Object {$_.BoundingRect.Y} | Measure-Object -Minimum).Minimum
        $taskRight = ($taskWords | ForEach-Object {$_.BoundingRect.X + $_.BoundingRect.Width} | Measure-Object -Maximum).Maximum
        $taskBottom = ($taskWords | ForEach-Object {$_.BoundingRect.Y + $_.BoundingRect.Height} | Measure-Object -Maximum).Maximum
        @{text=$_.Text; box=@($taskLeft,$taskTop,$taskRight,$taskBottom)}
    })
    @{text=$taskResult.Text; lines=$taskLines} | ConvertTo-Json -Depth 6 -Compress
} finally {
    if ($null -ne $taskBitmap) { $taskBitmap.Dispose() }
    $taskStream.Dispose()
}
