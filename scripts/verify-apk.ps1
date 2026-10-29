#Requires -Version 7.0
param([int[]]$BuildNumbers = @(5), [string]$Version = '0.2.0', [ValidatePattern('^R[0-9]+$')][string]$Round = 'R1')
. "$PSScriptRoot/env.ps1"
$report = Join-Path $ProjectRoot "artifacts/$Round"
$buildTools = Get-ChildItem (Join-Path $env:ANDROID_HOME 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools) { throw '缺少 Android Build Tools。' }
$previousCertificate = $null
foreach ($number in $BuildNumbers) {
    $apk = Join-Path $report "tag-music-$Version+$number.apk"
    if (!(Test-Path $apk)) { throw "找不到 $apk" }
    $signingLog = Join-Path $report "apk-signature-$number.txt"
    Invoke-Checked (Join-Path $buildTools.FullName 'apksigner.bat') @('verify','--verbose','--print-certs',$apk) $signingLog
    $text = Get-Content $signingLog -Raw
    $certificate = [regex]::Match($text,'Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)').Groups[1].Value
    if (!$certificate) { throw '未取得 APK 签名证书指纹。' }
    if ($previousCertificate -and $certificate -ne $previousCertificate) { throw '覆盖升级包签名不一致。' }
    $previousCertificate = $certificate
    $manifestLog = Join-Path $report "apk-manifest-$number.txt"
    Invoke-Checked (Join-Path $buildTools.FullName 'aapt2.exe') @('dump','badging',$apk) $manifestLog
    $manifest = Get-Content $manifestLog -Raw
    if ($manifest -notmatch "package: name='app.tagmusic.player' versionCode='$number' versionName='$([regex]::Escape($Version))'") { throw 'APK 应用标识或版本不正确。' }
    if ($manifest -notmatch "sdkVersion:'29'") { throw 'APK 最低 Android API 不正确。' }
}
Write-Output 'APK 签名、升级签名一致性、应用标识、版本与最低系统要求检查通过。'
