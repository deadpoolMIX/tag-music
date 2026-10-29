#Requires -Version 7.0
# hooks_runner 1.5.0 invokes native executables through cmd.exe on Windows.
# Quoted arguments plus a spaced SDK path fail. Use direct Process.start for exe.
param([Parameter(Mandatory)][string]$SdkRoot)
$ErrorActionPreference = 'Stop'
$source = Join-Path $SdkRoot 'packages/flutter_tools/lib/src/isolated/native_assets/native_assets.dart'
if (!(Test-Path $source)) { return }
$text = [IO.File]::ReadAllText($source)
$before = ".resolve('bin/cache/dart-sdk/bin/dart');"
$after = ".resolve(globals.platform.isWindows ? 'bin/cache/dart-sdk/bin/dart.exe' : 'bin/cache/dart-sdk/bin/dart');"
if ($text.Contains($after)) { [IO.File]::WriteAllText($source, $text.Replace($after, $before)) }
$toolPubspec = Join-Path $SdkRoot 'packages/flutter_tools/pubspec.yaml'
$toolText = [IO.File]::ReadAllText($toolPubspec)
if ($toolText.Contains('# Tag Music Windows hooks workaround')) { return }
$toolConfig = Join-Path $SdkRoot 'packages/flutter_tools/.dart_tool/package_config.json'
if (!(Test-Path $toolConfig)) { return }
$config = Get-Content $toolConfig -Raw | ConvertFrom-Json
$hooks = $config.packages | Where-Object name -eq 'hooks_runner'
if (!$hooks -or $hooks.rootUri -notmatch 'hooks_runner-1\.5\.0') { return }
$upstream = ([Uri]$hooks.rootUri).LocalPath
$localCopy = Join-Path $SdkRoot '../patches/hooks_runner-1.5.0'
if (!(Test-Path $localCopy)) { Copy-Item -LiteralPath $upstream -Destination $localCopy -Recurse }
$processSource = Join-Path $localCopy 'lib/src/utils/run_process.dart'
$processText = [IO.File]::ReadAllText($processSource)
$pattern = 'runInShell:\s*Platform\.isWindows &&\s*\(!includeParentEnvironment \|\| workingDirectory != null\),'
if ($processText -notmatch $pattern) { throw 'hooks_runner 源码与已核实版本不符。' }
$processText = [regex]::Replace($processText, $pattern, "runInShell: Platform.isWindows && (executable.path.endsWith('.bat') || executable.path.endsWith('.cmd')),")
[IO.File]::WriteAllText($processSource, $processText)
$backupDirectory = Join-Path $SdkRoot '../backups'
New-Item -ItemType Directory -Force $backupDirectory | Out-Null
Copy-Item -LiteralPath $toolPubspec -Destination (Join-Path $backupDirectory 'flutter_tools.pubspec.original') -Force
$override = "`n# Tag Music Windows hooks workaround`ndependency_overrides:`n  hooks_runner:`n    path: ../../../patches/hooks_runner-1.5.0`n"
if ($toolText -match '(?m)^dependency_overrides:') { throw 'SDK 已有 dependency_overrides，请先核对。' }
[IO.File]::WriteAllText($toolPubspec, $toolText + $override)
foreach ($name in @('flutter_tools.snapshot','flutter_tools.stamp')) {
    $cached = Join-Path $SdkRoot "bin/cache/$name"
    if (Test-Path -LiteralPath $cached) { Remove-Item -LiteralPath $cached }
}
Write-Output 'Applied local hooks_runner 1.5.0 Windows process fix; SDK pubspec backed up.'
