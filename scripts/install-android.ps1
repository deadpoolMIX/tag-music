#Requires -Version 7.0
param([string]$Serial, [int]$BuildNumber = 8, [string]$Version = '0.2.0', [ValidatePattern('^R[0-9]+$')][string]$Round = 'R1')
. "$PSScriptRoot/env.ps1"
$adb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'
$report = Join-Path $ProjectRoot "artifacts/$Round"
$apk = Join-Path $report "tag-music-$Version+$BuildNumber.apk"
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
$appPid = $null
for ($attempt = 0; $attempt -lt 4; $attempt++) {
    $appPid = [string](& $adb -s $Serial shell pidof -s app.tagmusic.player)
    $appPid = $appPid.Trim()
    if ($appPid) { break }
    Start-Sleep -Milliseconds 500
}
if (!$appPid) {
    & $adb -s $Serial shell dumpsys activity exit-info app.tagmusic.player | Set-Content "$report/android-exit-$BuildNumber.log"
    throw '应用启动后未找到进程，请检查本应用退出记录。'
}
Invoke-Checked $adb @('-s',$Serial,'logcat','-d',"--pid=$appPid",'-t','1200') "$report/android-$BuildNumber.log"
& $adb -s $Serial shell dumpsys package app.tagmusic.player | Select-String 'versionCode=|versionName=|firstInstallTime=|lastUpdateTime=' | Set-Content "$report/android-package-$BuildNumber.txt"
