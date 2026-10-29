#Requires -Version 7.0
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
$report = Join-Path $ProjectRoot 'artifacts/R0'
New-Item -ItemType Directory -Force $report | Out-Null
Invoke-Checked $Flutter @('pub','get','--enforce-lockfile') "$report/pub-get.log"
& "$PSScriptRoot/prepare-windows.ps1"
Invoke-Checked (Join-Path (Split-Path $Flutter) 'dart.bat') @('format','--output=none','--set-exit-if-changed','lib','test','integration_test') "$report/format.log"
Invoke-Checked $Flutter @('analyze','--fatal-infos') "$report/analyze.log"
Invoke-Checked $Flutter @('test','--reporter','expanded') "$report/test.log"
