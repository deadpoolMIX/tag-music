#Requires -Version 7.0
# Run only inside a user-confirmed phone-operation batch, with samples visible.
param([Parameter(Mandatory)][ValidateSet('formats','switches','controls')][string]$Section, [int]$BuildNumber = 6)
. "$PSScriptRoot/android-ui.ps1"
$evidence = Join-Path $ProjectRoot "artifacts/R1/android$BuildNumber"
New-Item -ItemType Directory -Force $evidence | Out-Null
$packageInfoText = & $R1Adb shell dumpsys package app.tagmusic.player
if (($packageInfoText -join "`n") -notmatch "versionCode=$BuildNumber(?:\s|$)") { throw 'Phone version does not match this test batch' }

function Get-TagSession {
    param([string]$Name)
    $lines = @(& $R1Adb shell dumpsys media_session)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*package=app\.tagmusic\.player$') { $start = $i; break }
    }
    if ($start -lt 0) { throw 'Tag Music media session is missing' }
    $body = $lines[$start..([Math]::Min($start+12,$lines.Count-1))] -join "`n"
    $state = [regex]::Match($body, 'state=(\w+)\(\d+\), position=(\d+)')
    if (!$state.Success) { throw 'Cannot read Tag Music playback state' }
    if ($Name) { $body | Set-Content (Join-Path $evidence "$Name.txt") }
    $reportedPosition = [long]$state.Groups[2].Value
    $projectedPosition = $reportedPosition
    if ($state.Groups[1].Value -eq 'PLAYING' -and $body -match 'updated=(\d+)') {
        $updated = [long]$Matches[1]
        $uptimeText = [string](& $R1Adb shell cat /proc/uptime)
        $uptimeMillis = [long]([double]::Parse(($uptimeText -split '\s+')[0],[Globalization.CultureInfo]::InvariantCulture)*1000)
        $projectedPosition += [Math]::Max(0,$uptimeMillis-$updated)
    }
    [pscustomobject]@{state=$state.Groups[1].Value;position=$projectedPosition;reportedPosition=$reportedPosition;body=$body}
}

function Assert-TagPlaying {
    param([string]$Name)
    $state = Get-TagSession -Name $Name
    if ($state.state -ne 'PLAYING' -or $state.position -lt 100 -or $state.body -notmatch 'description=中文测试音, Tag Music,' -or $state.body -notmatch 'error=null') {
        throw "Playback/metadata assertion failed: $Name"
    }
    @{check=$Name;state=$state.state;position=$state.position;reportedPosition=$state.reportedPosition;recordedAt=[DateTimeOffset]::Now.ToString('o')} | ConvertTo-Json -Compress | Add-Content (Join-Path $evidence 'operations.jsonl')
}

function Pause-TagPlayback {
    # audio_service maps genuine hardware play/pause key events to a toggle.
    # Never send a second event when already paused.
    $state = Get-TagSession
    if ($state.state -eq 'PLAYING') {
        & $R1Adb shell input keyevent 127
        Start-Sleep -Milliseconds 300
        $state = Get-TagSession
        if ($state.state -eq 'PLAYING') { throw 'Media pause did not take effect' }
        if ($state.state -eq 'PAUSED' -and $state.reportedPosition -lt 100) { throw 'Backend position did not advance before pause' }
    }
}

try {
    Pause-TagPlayback
    if ($Section -eq 'formats') {
        foreach ($extension in @('flac','m4a','mp3','ogg','opus','wav')) {
            Invoke-PhoneTap -Label "中文测试-$extension.$extension"
            Start-Sleep -Milliseconds 850
            Assert-TagPlaying -Name "format-$extension"
            Pause-TagPlayback
            Write-Output "PASS metadata and PLAYING state: $extension"
        }
    } elseif ($Section -eq 'switches') {
        for ($i=0; $i -lt 30; $i++) {
            $extension = if ($i % 2 -eq 0) { 'flac' } else { 'mp3' }
            Invoke-PhoneTap -Label "中文测试-$extension.$extension"
            Start-Sleep -Milliseconds 500
            Assert-TagPlaying -Name ('switch-{0:D2}' -f ($i+1))
            Pause-TagPlayback
            Write-Output "PASS switch $($i+1)/30: $extension"
        }
    } else {
        $ui = Get-PhoneUi -Name "phone-$BuildNumber-seek-source"
        $nodes = @($ui.SelectNodes('//node') | Where-Object class -eq 'android.widget.SeekBar')
        if ($nodes.Count -ne 1) { throw 'Expected one observed seek bar' }
        $bounds = [regex]::Match($nodes[0].bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        if (!$bounds.Success) { throw 'Seek thumb bounds missing' }
        $x = [int](([int]$bounds.Groups[1].Value+[int]$bounds.Groups[3].Value)/2)
        $y = [int](([int]$bounds.Groups[2].Value+[int]$bounds.Groups[4].Value)/2)
        # Track extent is visible in android-5-flac-playing.png on this 1260px device.
        if ($y -lt 2100 -or $y -gt 2350) { throw 'Phone layout changed; reobserve before dragging' }
        & $R1Adb shell input swipe $x $y 700 $y 500
        Start-Sleep -Milliseconds 350
        $seek = Get-TagSession -Name 'seek-paused'
        if ($seek.position -lt 8000 -or $seek.position -gt 19000 -or $seek.state -ne 'PAUSED') { throw 'Seek did not update paused position' }
        Start-Sleep -Milliseconds 700
        $paused = Get-TagSession -Name 'pause-stable'
        if ([Math]::Abs($paused.position-$seek.position) -gt 150) { throw 'Paused position is moving' }
        Invoke-PhoneTap -Label '播放'
        Start-Sleep -Milliseconds 800
        Assert-TagPlaying -Name 'resume-after-seek'
        $resumed = Get-TagSession
        if ($resumed.position -lt $paused.position+400) { throw 'Resume did not advance position' }
        Pause-TagPlayback
        Invoke-PhoneTap -Label '停止'
        Start-Sleep -Milliseconds 250
        $stopped = Get-TagSession -Name 'stop'
        if ($stopped.state -ne 'NONE') { throw 'Stop did not unload playback' }
        Invoke-PhoneTap -Label '播放'
        Start-Sleep -Milliseconds 850
        Assert-TagPlaying -Name 'play-after-stop'
        Write-Output 'PASS seek, pause stability, resume and stop/reopen'
    }
} finally {
    Pause-TagPlayback
    $appProcess = [string](& $R1Adb shell pidof -s app.tagmusic.player)
    if ($appProcess.Trim()) {
        & $R1Adb logcat -d "--pid=$($appProcess.Trim())" -t 20000 | Set-Content (Join-Path $evidence "$Section-logcat.log")
    }
}
