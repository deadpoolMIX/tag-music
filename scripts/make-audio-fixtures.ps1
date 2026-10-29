#Requires -Version 7.0
param([string]$OutputDirectory = "$PSScriptRoot/../artifacts/R1/fixtures")
$ErrorActionPreference = 'Stop'
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$formats = @(
    @{extension='wav';codec='pcm_s16le'},
    @{extension='mp3';codec='libmp3lame'},
    @{extension='flac';codec='flac'},
    @{extension='m4a';codec='aac'},
    @{extension='ogg';codec='libvorbis'},
    @{extension='opus';codec='libopus'}
)
foreach ($format in $formats) {
    $file = Join-Path $OutputDirectory "中文测试-$($format.extension).$($format.extension)"
    # Original synthesized tone; amplitude is intentionally modest.
    & $ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=24' -af 'volume=0.25' -ac 2 -c:a $format.codec -metadata 'title=中文测试音' -metadata 'artist=Tag Music' -metadata 'album=R1 原创合成样本' $file
    if ($LASTEXITCODE -ne 0) { throw "生成样本失败：$file" }
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory '坏文件.mp3'), 'This is intentionally invalid audio.')
@{
    generator = (& $ffmpeg -version | Select-Object -First 1)
    source = 'Original 440 Hz synthesized sine, 24 seconds, stereo 48 kHz, volume=0.25'
    license = 'CC0-1.0; original generated test audio dedicated to the public domain'
    createdAt = [DateTimeOffset]::Now.ToString('o')
} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'SOURCE.json')
Get-ChildItem $OutputDirectory -File | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLowerInvariant())  $(Split-Path $_.Path -Leaf)" } | Set-Content (Join-Path $OutputDirectory 'SHA256SUMS.txt')
