#Requires -Version 7.0
# Test helpers. Call only within an explicitly authorized device-operation batch.
. "$PSScriptRoot/env.ps1"
$R1Adb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'

function Get-PhoneUi {
    param([string]$Name = 'phone-ui')
    $remote = "/sdcard/tagmusic-r1-$([Guid]::NewGuid().ToString('N')).xml"
    $output = & $R1Adb shell uiautomator dump --compressed $remote 2>&1
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch 'UI hierchary dumped to:') {
        throw "没有获得新的手机 UI 快照，禁止沿用旧 XML：$output"
    }
    $local = Join-Path $ProjectRoot "artifacts/R1/$Name.xml"
    & $R1Adb pull $remote $local 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'UI snapshot pull failed' }
    & $R1Adb shell rm $remote | Out-Null
    return [xml](Get-Content $local -Raw)
}

function Show-PhoneUi {
    param([string]$Name = 'phone-ui')
    $ui = Get-PhoneUi -Name $Name
    $ui.SelectNodes('//node') | Where-Object { $_.text -or $_.'content-desc' } | ForEach-Object {
        [pscustomobject]@{text=$_.text;description=$_.'content-desc';bounds=$_.bounds;selected=$_.selected}
    } | ConvertTo-Json
}

function Invoke-PhoneTap {
    param([Parameter(Mandatory)][string]$Label)
    $ui = Get-PhoneUi
    $nodes = @($ui.SelectNodes('//node') | Where-Object { $_.text -eq $Label -or $_.'content-desc' -eq $Label })
    if ($nodes.Count -ne 1) { throw "不能唯一定位：$Label（$($nodes.Count)）" }
    $bounds = [regex]::Match($nodes[0].bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (!$bounds.Success) { throw 'Invalid bounds' }
    $x = [int](($bounds.Groups[1].Value -as [int]) + ($bounds.Groups[3].Value -as [int])) / 2
    $y = [int](($bounds.Groups[2].Value -as [int]) + ($bounds.Groups[4].Value -as [int])) / 2
    & $R1Adb shell input tap ([int]$x) ([int]$y)
}

function Save-PhoneScreenshot {
    param([Parameter(Mandatory)][string]$Name)
    & $R1Adb exec-out screencap -p > (Join-Path $ProjectRoot "artifacts/R1/$Name.png")
}
