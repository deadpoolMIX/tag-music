#Requires -Version 7.0
param([ValidatePattern('^R[0-9]+$')][string]$Round = 'R1')
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
$report = Join-Path $ProjectRoot "artifacts/$Round"
New-Item -ItemType Directory -Force $report | Out-Null
& "$PSScriptRoot/restore.ps1" -Round $Round
if ($Round -eq 'R1') {
    $env:TAG_MUSIC_FIXTURES = Join-Path $report 'fixtures'
    if (!(Test-Path "$env:TAG_MUSIC_FIXTURES/SOURCE.json")) { & "$PSScriptRoot/make-audio-fixtures.ps1" -OutputDirectory $env:TAG_MUSIC_FIXTURES }
}
if ($Round -eq 'R2') {
    $env:TAG_MUSIC_LIBRARY_FIXTURES = Join-Path $report 'fixtures'
    if (!(Test-Path "$env:TAG_MUSIC_LIBRARY_FIXTURES/SOURCE.json")) { & "$PSScriptRoot/make-library-fixtures.ps1" -OutputDirectory $env:TAG_MUSIC_LIBRARY_FIXTURES }
    $env:TAG_MUSIC_FIXTURES = Join-Path $env:TAG_MUSIC_LIBRARY_FIXTURES 'source'
    $env:TAG_MUSIC_LIBRARY_REPORT = Join-Path $report 'library-benchmark.json'
}
Invoke-Checked (Join-Path (Split-Path $Flutter) 'dart.bat') @('format','--output=none','--set-exit-if-changed','lib','test','integration_test') "$report/format.log"
Invoke-Checked $Flutter @('analyze','--fatal-infos') "$report/analyze.log"
Invoke-Checked $Flutter @('test','--reporter','expanded') "$report/test.log"
