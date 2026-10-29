#Requires -Version 7.0
. "$PSScriptRoot/env.ps1"
Set-Location $ProjectRoot
$report = Join-Path $ProjectRoot 'artifacts/R0'
New-Item -ItemType Directory -Force $report | Out-Null
$log = Join-Path $report 'pub-get.log'
for ($attempt = 0; $attempt -lt 2; $attempt++) {
    Add-Content $log "[$([DateTimeOffset]::Now.ToString('o'))] flutter pub get --enforce-lockfile"
    $restoreOutput = & $Flutter pub get --enforce-lockfile 2>&1
    $restoreExit = $LASTEXITCODE
    $restoreOutput | Tee-Object -FilePath $log -Append
    if ($restoreExit -eq 0) {
        & "$PSScriptRoot/prepare-windows.ps1"
        return
    }
    if ($attempt -eq 0 -and ($restoreOutput -join "`n") -match 'Building with plugins requires symlink support') {
        & "$PSScriptRoot/prepare-windows.ps1"
    } else {
        throw "依赖恢复失败，日志：$log"
    }
}
