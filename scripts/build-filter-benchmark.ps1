#Requires -Version 7.0
param([ValidateSet('all','android','windows')][string]$Target = 'all', [ValidateRange(1,2100000000)][int]$BenchmarkBuildNumber = 1)
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
if ($Target -in 'all','android') {
    & "$PSScriptRoot/build-tag-benchmark.ps1" -Round R4 -BenchmarkBuildNumber $BenchmarkBuildNumber
}
if ($Target -in 'all','windows') {
    $report = Join-Path $ProjectRoot 'artifacts/R4/benchmark'
    New-Item -ItemType Directory -Force $report | Out-Null
    $zip = Join-Path $report "filter-benchmark-windows-release-$BenchmarkBuildNumber.zip"
    $result = Join-Path $report "filter-benchmark-windows-release-$BenchmarkBuildNumber.json"
    if ((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $result)) { throw '性能包或报告已存在，必须使用新测试编号。' }
    & "$PSScriptRoot/prepare-windows.ps1"
    Invoke-Checked $Flutter @('build','windows','--release','--target','integration_test/filter_benchmark_test.dart',"--build-number=$BenchmarkBuildNumber","--dart-define=FILTER_BENCHMARK_OUTPUT=$result") "$report/build-windows-release-$BenchmarkBuildNumber.log"
    Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath $zip
    $revision = & git rev-parse --short HEAD
    if (& git status --porcelain --untracked-files=normal) { $revision = "$revision-dirty" }
    @{
        platform='windows'; mode='release'; build=$BenchmarkBuildNumber; revision=$revision
        archive=(Split-Path $zip -Leaf); sha256=(Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
        expectedReport=$result; database='isolated temporary SQLite; no user library opened'
        productionCandidate='not a production candidate; executable must be run only after batch authorization'
    } | ConvertTo-Json | Set-Content "$report/package-windows-release-$BenchmarkBuildNumber.json"
}
