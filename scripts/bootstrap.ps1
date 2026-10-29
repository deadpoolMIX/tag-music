#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root '.tools'
New-Item -ItemType Directory -Force $tools | Out-Null
$downloads = Join-Path $tools 'downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null
$archive = Join-Path $downloads 'flutter-sdk.zip'
$expected = '11e19ea3409808fe3b3765ea8149640c299e58cce6eda7c9f38fc1b4a193eb6e'
if (!(Test-Path (Join-Path $tools 'flutter/bin/flutter.bat'))) {
    if (!(Test-Path $archive)) {
        Invoke-WebRequest 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.8-stable.zip' -OutFile $archive
    }
    if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Flutter SDK 校验失败' }
    & tar -xf $archive -C $tools
    if ($LASTEXITCODE -ne 0) { throw 'SDK 解压失败' }
}
. "$PSScriptRoot/env.ps1"
& $Flutter --version
if ($LASTEXITCODE -ne 0) { throw 'Flutter SDK 启动失败，请检查解压完整性与网络。' }
& $Flutter doctor -v
if ($LASTEXITCODE -ne 0) { throw '请依据 doctor 结果补齐 Android SDK 与 Visual Studio C++，参见 docs/TOOLCHAIN.md。' }
