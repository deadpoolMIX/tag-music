# Tag Music

Windows / Android 本地音乐播放器，Flutter + Material 3。当前只实施 R0 工程空壳，尚不支持导入和播放。

开发入口：先读 [AGENTS.md](AGENTS.md)、[计划](docs/PLAN.md)、[交接](docs/HANDOFF.md)。

```powershell
pwsh -File scripts/bootstrap.ps1
pwsh -File scripts/check.ps1
pwsh -File scripts/build.ps1 -Target all -BuildNumber 1
pwsh -File scripts/install-android.ps1 -BuildNumber 1
```

使用项目内 SDK 时，运行 Flutter 命令前先 `. ./scripts/env.ps1`，然后 `& $Flutter run -d windows`。

构建产物位于 `artifacts/R0/`，SDK 位于 `.tools/`。两者均不入 Git。签名通过 `scripts/signing.ps1` 首次创建，此后必须沿用，密钥和配置需自行安全备份。

原创代码 MIT；第三方许可见应用“设置 → 开源许可”和 [第三方说明](docs/THIRD_PARTY.md)。
