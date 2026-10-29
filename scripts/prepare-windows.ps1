#Requires -Version 7.0
# Flutter accepts NTFS junctions as plugin links. This avoids changing OS settings.
. "$PSScriptRoot/env.ps1"
$manifest = Join-Path $ProjectRoot '.flutter-plugins-dependencies'
if (!(Test-Path $manifest)) { throw '请先执行 flutter pub get。' }
$plugins = (Get-Content $manifest -Raw | ConvertFrom-Json).plugins.windows
$links = Join-Path $ProjectRoot 'windows/flutter/ephemeral/.plugin_symlinks'
New-Item -ItemType Directory -Force $links | Out-Null
foreach ($plugin in $plugins) {
    if ($plugin.name -notmatch '^[a-z0-9_]+$') { throw '插件名格式无效。' }
    $target = (Resolve-Path -LiteralPath $plugin.path).ProviderPath.TrimEnd('\','/')
    $link = Join-Path $links $plugin.name
    $existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if (!$existing.LinkType -or [IO.Path]::GetFullPath($existing.Target).TrimEnd('\','/') -ne $target) {
            throw "插件链接与锁定依赖不一致：$link。请检查后重新生成 ephemeral 目录。"
        }
    } else {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    }
}
