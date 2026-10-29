#Requires -Version 7.0
param([ValidateSet('all','android','windows')][string]$Target = 'all', [ValidateRange(1,2100000000)][int]$BuildNumber = 7, [ValidatePattern('^R[0-9]+$')][string]$Round = 'R1')
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
$report = Join-Path $ProjectRoot "artifacts/$Round"
$versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+')
if (!$versionMatch.Success) { throw '无法读取 pubspec 版本。' }
$version = $versionMatch.Groups[1].Value
New-Item -ItemType Directory -Force $report | Out-Null
& "$PSScriptRoot/restore.ps1" -Round $Round
$lockedDependencies = (Get-FileHash pubspec.lock -Algorithm SHA256).Hash
$revision = (& git rev-parse --short HEAD 2>$null)
if (!$revision) { $revision = 'uncommitted' }
if (& git status --porcelain --untracked-files=normal) { $revision = "$revision-dirty" }
if ($Target -in 'all','android') {
    & "$PSScriptRoot/signing.ps1"
    Invoke-Checked $Flutter @('build','apk','--release',"--build-number=$BuildNumber","--dart-define=GIT_REVISION=$revision") "$report/build-android-$BuildNumber.log"
    Copy-Item build/app/outputs/flutter-apk/app-release.apk "$report/tag-music-$version+$BuildNumber.apk"
}
if ($Target -in 'all','windows') {
    & "$PSScriptRoot/prepare-windows.ps1"
    Invoke-Checked $Flutter @('build','windows','--release',"--build-number=$BuildNumber","--dart-define=GIT_REVISION=$revision") "$report/build-windows-$BuildNumber.log"
    $release = Join-Path $ProjectRoot 'build/windows/x64/runner/Release'
    Copy-Item LICENSE "$release/LICENSE.txt"
    Copy-Item docs/THIRD_PARTY.md "$release/THIRD_PARTY.md"
    $runtimeLicenses = Join-Path $release 'licenses'
    New-Item -ItemType Directory -Force $runtimeLicenses | Out-Null
    $sdkRoot = Split-Path (Split-Path $Flutter)
    Copy-Item "$sdkRoot/LICENSE" "$runtimeLicenses/FLUTTER.txt"
    Copy-Item "$sdkRoot/bin/cache/LICENSE*" $runtimeLicenses
    Copy-Item "$sdkRoot/bin/cache/artifacts/engine/windows-x64/license*.md" $runtimeLicenses
    New-Item -ItemType Directory -Force "$runtimeLicenses/native" | Out-Null
    Copy-Item assets/licenses/native/* "$runtimeLicenses/native" -Force
    Compress-Archive -Path "$release/*" -DestinationPath "$report/tag-music-windows-$version+$BuildNumber.zip" -Force
}
if ((Get-FileHash pubspec.lock -Algorithm SHA256).Hash -ne $lockedDependencies) { throw '构建期间锁文件发生变化，拒绝将产物标为已验证。' }
Get-ChildItem $report -File | Where-Object Extension -in '.apk','.zip' | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLowerInvariant())  $(Split-Path $_.Path -Leaf)" } | Set-Content "$report/SHA256SUMS.txt"
@{target=$Target; version=$version; build=$BuildNumber; revision=$revision; builtAt=[DateTimeOffset]::Now.ToString('o')} | ConvertTo-Json | Set-Content "$report/build-$Target-$BuildNumber.json"
