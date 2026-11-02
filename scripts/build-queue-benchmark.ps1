#Requires -Version 7.0
param([ValidateSet('all','android','windows')][string]$Target = 'all', [ValidateRange(1,2100000000)][int]$BenchmarkBuildNumber = 1)
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
if ($Target -in 'all','android') {
    & "$PSScriptRoot/build-tag-benchmark.ps1" -Round R5 -BenchmarkBuildNumber $BenchmarkBuildNumber
}
if ($Target -in 'all','windows') {
    $report = Join-Path $ProjectRoot 'artifacts/R5/benchmark'
    New-Item -ItemType Directory -Force $report | Out-Null
    $zip = Join-Path $report "queue-benchmark-windows-release-$BenchmarkBuildNumber.zip"
    $result = Join-Path $report "queue-benchmark-windows-release-$BenchmarkBuildNumber.json"
    if ((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $result)) { throw '性能包或报告已存在，必须使用新测试编号。' }
    $revision = & git rev-parse --short HEAD
    if (& git status --porcelain --untracked-files=normal) { $revision = "$revision-dirty" }
    & "$PSScriptRoot/prepare-windows.ps1"
    Invoke-Checked $Flutter @('build','windows','--release','--target','integration_test/queue_benchmark_test.dart',"--build-number=$BenchmarkBuildNumber","--dart-define=QUEUE_BENCHMARK_BUILD=$BenchmarkBuildNumber","--dart-define=QUEUE_BENCHMARK_REVISION=$revision","--dart-define=QUEUE_BENCHMARK_OUTPUT=$result") "$report/build-windows-release-$BenchmarkBuildNumber.log"
    $release = Join-Path $ProjectRoot 'build/windows/x64/runner/Release'
    Copy-Item LICENSE "$release/LICENSE.txt"
    Copy-Item docs/THIRD_PARTY.md "$release/THIRD_PARTY.md"
    $runtimeLicenses = Join-Path $release 'licenses'
    New-Item -ItemType Directory -Force "$runtimeLicenses/native" | Out-Null
    $sdkRoot = Split-Path (Split-Path $Flutter)
    Copy-Item "$sdkRoot/LICENSE" "$runtimeLicenses/FLUTTER.txt"
    Copy-Item "$sdkRoot/bin/cache/LICENSE*" $runtimeLicenses
    Copy-Item "$sdkRoot/bin/cache/artifacts/engine/windows-x64/license*.md" $runtimeLicenses
    Copy-Item assets/licenses/native/* "$runtimeLicenses/native" -Force
    Compress-Archive -Path "$release/*" -DestinationPath $zip
    @{
        platform='windows'; mode='release'; build=$BenchmarkBuildNumber; revision=$revision; round='R5'
        archive=(Split-Path $zip -Leaf); sha256=(Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
        expectedReport=$result; database='isolated temporary SQLite; no user library opened'
        productionCandidate='not a production candidate; executable must be run only after batch authorization'
    } | ConvertTo-Json | Set-Content "$report/package-windows-release-$BenchmarkBuildNumber.json"
}
