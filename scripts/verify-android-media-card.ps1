#Requires -Version 7.0
# Only run with a confirmed batch, Tag Music's sample card visible and paused.
param([ValidateSet('shade','lock')][string]$Surface, [int]$BuildNumber=8, [ValidateRange(1,10)][int]$Cycles=6)
. "$PSScriptRoot/android-ui.ps1"
$evidence=Join-Path $ProjectRoot "artifacts/R1/android$BuildNumber"
$packageText=(& $R1Adb shell dumpsys package app.tagmusic.player) -join "`n"
if($packageText -notmatch "versionCode=$BuildNumber(?:\s|$)"){throw 'Wrong installed build'}
$cardProcessId=([string](& $R1Adb shell pidof -s app.tagmusic.player)).Trim()
if(!$cardProcessId){throw 'Tag Music process missing'}

function Get-LastOpenedSample {
    $logLines=@(& $R1Adb logcat -d "--pid=$cardProcessId" -t 2000)
    $opened=@($logLines|ForEach-Object {if($_ -match 'R1 (\{.*\})$'){$Matches[1]|ConvertFrom-Json}}|Where-Object event -eq opened|Select-Object -Last 1)
    if($opened.Count -ne 1){throw 'No completed sample open in app log'}
    return $opened[0].name
}

function Get-CardSession {
    param([string]$Name)
    $lines=@(& $R1Adb shell dumpsys media_session)
    $match=$lines|Select-String '^\s*package=app\.tagmusic\.player$'|Select-Object -First 1
    if(!$match){throw 'Tag Music session missing'}
    $start=$match.LineNumber-1
    $body=$lines[$start..([Math]::Min($start+12,$lines.Count-1))] -join "`n"
    if($Name){$body|Set-Content (Join-Path $evidence "$Surface-$Name-session.txt")}
    $state=[regex]::Match($body,'state=(\w+)\(\d+\)')
    if(!$state.Success){throw 'Missing session state'}
    [pscustomobject]@{state=$state.Groups[1].Value;body=$body}
}

function Get-SampleCard {
    param([string]$Name)
    if($Surface -eq 'lock'){
        # Wake the display without dismissing or authenticating the keyguard.
        # A sleeping device can still dump its old lock UI, but ignores taps.
        & $R1Adb shell input keyevent 224
        $power=(& $R1Adb shell dumpsys power) -join "`n"
        $policy=(& $R1Adb shell dumpsys window policy) -join "`n"
        if($power -notmatch 'mWakefulness=Awake' -or $policy -notmatch '(?m)^\s*showing=true'){
            throw 'Lock test requires an awake display with keyguard still showing'
        }
        $policy|Set-Content (Join-Path $evidence "lock-$Name-policy.txt")
    }
    $ui=Get-PhoneUi -Name "phone-$BuildNumber-$Surface-$Name"
    $rows=@($ui.SelectNodes('//node')|Where-Object {$_.'resource-id' -eq 'com.android.systemui:id/expandableNotificationRow' -and $_.text -eq 'Tag Music'})
    if($rows.Count -ne 1){throw 'Expected one observed Tag Music media row'}
    $row=$rows[0]
    $texts=@($row.SelectNodes('.//node')|ForEach-Object {$_.text})
    if($texts -notcontains '中文测试音' -or $texts -notcontains 'Tag Music'){throw 'Incomplete sample title/artist on card'}
    return $row
}

function Invoke-CardAction {
    param([string]$Label,[string]$Expected,[string]$Name)
    $row=Get-SampleCard -Name "$Name-before"
    $buttons=@($row.SelectNodes('.//node')|Where-Object {$_.'content-desc' -eq $Label})
    if($buttons.Count -ne 1){throw "Card action unavailable: $Label"}
    $bounds=[regex]::Match($buttons[0].bounds,'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if(!$bounds.Success){throw 'Invalid observed bounds'}
    $x=[int](([int]$bounds.Groups[1].Value+[int]$bounds.Groups[3].Value)/2)
    $y=[int](([int]$bounds.Groups[2].Value+[int]$bounds.Groups[4].Value)/2)
    $openedBefore=Get-LastOpenedSample
    $openedAfter=$openedBefore
    $isSwitch=$Label -in 'Next','Previous'
    $timer=[Diagnostics.Stopwatch]::StartNew()
    & $R1Adb shell input tap $x $y
    do {
        $session=Get-CardSession
        if($isSwitch){$openedAfter=Get-LastOpenedSample}
        if($session.state -eq $Expected -and $session.body -match 'description=中文测试音, Tag Music,' -and $session.body -match 'error=null' -and (!$isSwitch -or $openedBefore -ne $openedAfter)){break}
        Start-Sleep -Milliseconds 100
    } while($timer.Elapsed.TotalSeconds -lt 4)
    $latency=$timer.ElapsedMilliseconds
    $session=Get-CardSession -Name $Name
    if($session.state -ne $Expected){throw "Card action $Label did not reach $Expected"}
    if($isSwitch -and $openedBefore -eq $openedAfter){throw 'Card switch did not open a different sample'}
    $after=Get-SampleCard -Name "$Name-after"
    $expectedIcon=if($Expected -eq 'PLAYING'){'Pause'}else{'Play'}
    if(@($after.SelectNodes('.//node')|Where-Object {$_.'content-desc' -eq $expectedIcon}).Count -ne 1){throw "Icon/session mismatch after $Label"}
    @{surface=$Surface;check=$Name;action=$Label;expected=$Expected;observed=$session.state;openedBefore=$openedBefore;openedAfter=$openedAfter;nativeObservationMs=$latency;icon=$expectedIcon;recordedAt=[DateTimeOffset]::Now.ToString('o')}|ConvertTo-Json -Compress|Add-Content (Join-Path $evidence 'card-operations.jsonl')
    Write-Output "PASS $Surface $Name $Label -> $Expected ($latency ms observation)"
}

try {
    if((Get-CardSession).state -ne 'PAUSED'){throw 'Start with paused sample card'}
    for($i=1;$i -le $Cycles;$i++){
        Invoke-CardAction -Label 'Play' -Expected 'PLAYING' -Name "cycle-$i-play"
        $direction=if($i%2 -eq 1){'Next'}else{'Previous'}
        Invoke-CardAction -Label $direction -Expected 'PLAYING' -Name "cycle-$i-switch"
        Invoke-CardAction -Label 'Pause' -Expected 'PAUSED' -Name "cycle-$i-pause"
    }
} finally {
    if((Get-CardSession).state -eq 'PLAYING'){& $R1Adb shell input keyevent 127}
    $processIdText=[string](& $R1Adb shell pidof -s app.tagmusic.player)
    & $R1Adb logcat -d "--pid=$($processIdText.Trim())" -t 20000|Set-Content (Join-Path $evidence "$Surface-card-logcat.log")
}
