#Requires -Version 7.0
param([string]$OutputDirectory = "$PSScriptRoot/../artifacts/R2/fixtures")
$ErrorActionPreference = 'Stop'
$source = Join-Path $OutputDirectory 'source'
if (!(Test-Path "$source/SOURCE.json")) { & "$PSScriptRoot/make-audio-fixtures.ps1" -OutputDirectory $source }
$primary = Join-Path $OutputDirectory 'primary/子目录'
$secondary = Join-Path $OutputDirectory 'secondary'
New-Item -ItemType Directory -Force $primary,$secondary | Out-Null
Get-ChildItem $source -File | Where-Object Extension -in '.wav','.mp3','.flac','.m4a','.ogg','.opus' | Copy-Item -Destination $primary
Copy-Item "$source/中文测试-wav.wav" "$secondary/另一个位置.wav"
# Original solid-color cover for a deterministic embedded-art fixture.
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'color=c=0x386A56:s=128x128:d=1' -frames:v 1 "$OutputDirectory/cover.png"
if ($LASTEXITCODE -ne 0) { throw '封面样本生成失败' }
& ffmpeg -hide_banner -loglevel error -y -i "$source/中文测试-flac.flac" -i "$OutputDirectory/cover.png" -map 0:a -map 1:v -c copy -disposition:v attached_pic -metadata 'title=封面测试音' "$primary/内嵌封面.flac"
if ($LASTEXITCODE -ne 0) { throw '内嵌封面样本生成失败' }
@{source='R1 original 440 Hz audio and original solid-color 128x128 PNG';license='CC0-1.0';primaryTracks=8;secondaryTracks=1;createdAt=[DateTimeOffset]::Now.ToString('o')} | ConvertTo-Json | Set-Content "$OutputDirectory/SOURCE.json"
Get-ChildItem $OutputDirectory -Recurse -File | Where-Object Name -ne 'SHA256SUMS.txt' | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetRelativePath($OutputDirectory,$_.Path))" } | Set-Content "$OutputDirectory/SHA256SUMS.txt"
