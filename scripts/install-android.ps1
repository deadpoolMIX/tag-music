#Requires -Version 7.0
param([string]$Serial, [int]$BuildNumber = 1)
. "$PSScriptRoot/env.ps1"
$adb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'
$report = Join-Path $ProjectRoot 'artifacts/R0'
$apk = Join-Path $report "tag-music-0.1.0+$BuildNumber.apk"
if (!(Test-Path $apk)) { throw "找不到 $apk，请先构建。" }
$devices = & $adb devices
$connected = @($devices | Where-Object { $_ -match '^([^\s]+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if (!$Serial) {
    if ($connected.Count -ne 1) { throw '需要且只能有一台已授权设备，或通过 -Serial 指定。请连接 USB 并在手机确认调试授权。' }
    $Serial = $connected[0]
}
if ($Serial -notin $connected) { throw '指定设备未连接或未授权。' }
Invoke-Checked $adb @('-s',$Serial,'install','-r',$apk) "$report/install-$BuildNumber.log"
Invoke-Checked $adb @('-s',$Serial,'shell','am','start','-n','app.tagmusic.player/.MainActivity') "$report/launch-$BuildNumber.log"
& $adb -s $Serial logcat -d -t 1200 | Set-Content "$report/android-$BuildNumber.log"
