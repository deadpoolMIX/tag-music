# Dot-source from other scripts. No machine-wide PATH changes.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Flutter = Join-Path $ProjectRoot '.tools/flutter/bin/flutter.bat'
if (!(Test-Path $Flutter)) {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if (!$command) { throw 'Flutter 未安装：请先运行 scripts/bootstrap.ps1。' }
    $Flutter = $command.Source
}
if ($Flutter.StartsWith((Join-Path $ProjectRoot '.tools'), [StringComparison]::OrdinalIgnoreCase)) {
    & "$PSScriptRoot/prepare-flutter.ps1" -SdkRoot (Split-Path (Split-Path $Flutter))
}
if (!$env:ANDROID_HOME) { $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
if (!$env:JAVA_HOME) { $env:JAVA_HOME = 'C:/Program Files/Android/Android Studio/jbr' }
$env:PATH = "$(Split-Path $Flutter);$env:JAVA_HOME/bin;$env:ANDROID_HOME/platform-tools;$env:PATH"
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

function Invoke-Checked {
    param([string]$File, [string[]]$Arguments, [string]$Log)
    Add-Content -LiteralPath $Log -Value "[$([DateTimeOffset]::Now.ToString('o'))] $File $($Arguments -join ' ')"
    & $File @Arguments 2>&1 | Tee-Object -FilePath $Log -Append
    if ($LASTEXITCODE -ne 0) { throw "$File 执行失败，退出码 $LASTEXITCODE；日志：$Log" }
}
