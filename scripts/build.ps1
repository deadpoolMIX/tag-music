#Requires -Version 7.0
param([ValidateSet('all','android','windows')][string]$Target = 'all', [ValidateRange(1,2100000000)][int]$BuildNumber = 1)
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
$report = Join-Path $ProjectRoot 'artifacts/R0'
New-Item -ItemType Directory -Force $report | Out-Null
& "$PSScriptRoot/restore.ps1"
$revision = (& git rev-parse --short HEAD 2>$null)
if (!$revision) { $revision = 'uncommitted' }
if ($Target -in 'all','android') {
    & "$PSScriptRoot/signing.ps1"
    Invoke-Checked $Flutter @('build','apk','--release','--no-pub',"--build-number=$BuildNumber","--dart-define=GIT_REVISION=$revision") "$report/build-android-$BuildNumber.log"
    Copy-Item build/app/outputs/flutter-apk/app-release.apk "$report/tag-music-0.1.0+$BuildNumber.apk"
}
if ($Target -in 'all','windows') {
    & "$PSScriptRoot/prepare-windows.ps1"
    Invoke-Checked $Flutter @('build','windows','--release','--no-pub',"--build-number=$BuildNumber","--dart-define=GIT_REVISION=$revision") "$report/build-windows-$BuildNumber.log"
    $release = Join-Path $ProjectRoot 'build/windows/x64/runner/Release'
    Copy-Item LICENSE "$release/LICENSE.txt"
    Copy-Item docs/THIRD_PARTY.md "$release/THIRD_PARTY.md"
    $runtimeLicenses = Join-Path $release 'licenses'
    New-Item -ItemType Directory -Force $runtimeLicenses | Out-Null
    $sdkRoot = Split-Path (Split-Path $Flutter)
    Copy-Item "$sdkRoot/LICENSE" "$runtimeLicenses/FLUTTER.txt"
    Copy-Item "$sdkRoot/bin/cache/LICENSE*" $runtimeLicenses
    Copy-Item "$sdkRoot/bin/cache/artifacts/engine/windows-x64/license*.md" $runtimeLicenses
    Compress-Archive -Path "$release/*" -DestinationPath "$report/tag-music-windows-0.1.0+$BuildNumber.zip" -Force
}
Get-ChildItem $report -File | Where-Object Extension -in '.apk','.zip' | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLowerInvariant())  $(Split-Path $_.Path -Leaf)" } | Set-Content "$report/SHA256SUMS.txt"
@{target=$Target; version='0.1.0'; build=$BuildNumber; revision=$revision; builtAt=[DateTimeOffset]::Now.ToString('o')} | ConvertTo-Json | Set-Content "$report/build-$Target-$BuildNumber.json"
