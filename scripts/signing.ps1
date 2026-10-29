#Requires -Version 7.0
. "$PSScriptRoot/env.ps1"
$secret = Join-Path $ProjectRoot '.secrets'
$keystore = Join-Path $secret 'tag-music-local.jks'
$properties = Join-Path $ProjectRoot 'android/key.properties'
New-Item -ItemType Directory -Force $secret | Out-Null
if ((Test-Path $keystore) -and (Test-Path $properties)) { Write-Output '沿用已有本地签名。'; return }
if ((Test-Path $keystore) -or (Test-Path $properties)) { throw '签名文件不完整；恢复已有密钥和配置，不得重新生成掩盖升级问题。' }
$password = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$env:TAG_MUSIC_KEY_PASSWORD = $password
try {
    & "$env:JAVA_HOME/bin/keytool.exe" -genkeypair -keystore $keystore -storetype JKS -alias tag-music -keyalg RSA -keysize 3072 -validity 10000 -storepass:env TAG_MUSIC_KEY_PASSWORD -keypass:env TAG_MUSIC_KEY_PASSWORD -dname 'CN=Tag Music Local, O=Tag Music, C=CN'
    if ($LASTEXITCODE -ne 0) { throw '创建签名失败' }
    @("storePassword=$password", "keyPassword=$password", 'keyAlias=tag-music', "storeFile=$($keystore.Replace('\','/'))") | Set-Content $properties -Encoding utf8
} finally { Remove-Item Env:TAG_MUSIC_KEY_PASSWORD -ErrorAction SilentlyContinue }
Write-Output '本地持久签名已创建。请安全备份 .secrets 和 android/key.properties；不要提交 Git。'
