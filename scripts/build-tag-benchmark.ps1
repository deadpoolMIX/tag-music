#Requires -Version 7.0
param([ValidateRange(1,2100000000)][int]$BenchmarkBuildNumber = 1, [ValidateSet('R3','R4')][string]$Round = 'R3')
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
$report = Join-Path $ProjectRoot "artifacts/$Round/benchmark"
New-Item -ItemType Directory -Force $report | Out-Null
$kind = if ($Round -eq 'R4') { 'filter' } else { 'tag' }
$apk = Join-Path $report "$kind-benchmark-release-$BenchmarkBuildNumber.apk"
if (Test-Path -LiteralPath $apk) { throw "测试包已存在，必须使用新编号：$apk" }
$previousBenchmark = $env:TAG_MUSIC_BENCHMARK
$previousRound = $env:TAG_MUSIC_BENCHMARK_ROUND
try {
    $env:TAG_MUSIC_BENCHMARK = '1'
    $env:TAG_MUSIC_BENCHMARK_ROUND = $Round
    Invoke-Checked $Flutter @('build','apk','--release','--target',"integration_test/${kind}_benchmark_test.dart","--build-number=$BenchmarkBuildNumber") "$report/build-release-$BenchmarkBuildNumber.log"
    Copy-Item build/app/outputs/flutter-apk/app-release.apk $apk
} finally {
    $env:TAG_MUSIC_BENCHMARK = $previousBenchmark
    $env:TAG_MUSIC_BENCHMARK_ROUND = $previousRound
}
$buildTools = Get-ChildItem (Join-Path $env:ANDROID_HOME 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools) { throw '缺少 Android Build Tools。' }
$manifestLog = Join-Path $report "manifest-release-$BenchmarkBuildNumber.txt"
Invoke-Checked (Join-Path $buildTools.FullName 'aapt2.exe') @('dump','badging',$apk) $manifestLog
$manifest = Get-Content $manifestLog -Raw
if ($manifest -notmatch "package: name='app.tagmusic.player.benchmark' versionCode='$BenchmarkBuildNumber'") { throw '测试包隔离标识不正确，拒绝用于设备。' }
if ($manifest -notmatch "application-label:'Tag Music $Round Benchmark'") { throw '测试包名称不正确。' }
Invoke-Checked (Join-Path $buildTools.FullName 'apksigner.bat') @('verify','--verbose','--print-certs',$apk) "$report/signature-release-$BenchmarkBuildNumber.txt"
$revision = & git rev-parse --short HEAD
if (& git status --porcelain --untracked-files=normal) { $revision = "$revision-dirty" }
@{
    package='app.tagmusic.player.benchmark'
    mode='release'
    build=$BenchmarkBuildNumber
    revision=$revision
    apk=(Split-Path $apk -Leaf)
    sha256=(Get-FileHash -Algorithm SHA256 $apk).Hash.ToLowerInvariant()
    productionCandidate='separate application ID; not a production candidate'
    round=$Round
} | ConvertTo-Json | Set-Content "$report/package-release-$BenchmarkBuildNumber.json"
