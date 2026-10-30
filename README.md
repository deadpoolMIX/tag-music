# Tag Music

Windows / Android 本地音乐播放器，Flutter + Material 3。R0、R1 已双端通过，当前验收版为 `0.2.0+9`；具备目录授权、元数据和单曲播放技术验证能力，准确证据与边界见交接。持久曲库、标签与歌单尚未实现，R2 须在新对话开展。

开发入口：先读 [AGENTS.md](AGENTS.md)、[计划](docs/PLAN.md)、[交接](docs/HANDOFF.md)。

查看进展：[简明开发日志](docs/开发日志.md)；查看全部说明：[文档目录](docs/README.md)。

```powershell
pwsh -File scripts/bootstrap.ps1
pwsh -File scripts/check.ps1
pwsh -File scripts/build.ps1 -Target all -BuildNumber 9 -Round R1
pwsh -File scripts/verify-apk.ps1 -BuildNumbers 9 -Version 0.2.0 -Round R1
pwsh -File scripts/install-android.ps1 -BuildNumber 9 -Version 0.2.0 -Round R1
```

使用项目内 SDK 时，运行 Flutter 命令前先 `. ./scripts/env.ps1`，执行 `& ./scripts/restore.ps1` 恢复锁定依赖并准备 Windows 插件目录，再运行 Flutter 命令。测试与构建须串行。R1 从已验收的 `0.1.0+2` 原签名覆盖升级，保留主题与首次安装时间。历史包验证可显式传入 `-Round R0 -Version 0.1.0 -BuildNumbers 1,2`。

助手启动/关闭前台应用、操作电脑或手机界面、安装/升级手机应用前，按 AGENTS 规则先提供交互式选项，得到本批确认后执行。

构建产物按轮次位于 `artifacts/Rxx/`，SDK 位于 `.tools/`。两者均不入 Git。签名通过 `scripts/signing.ps1` 首次创建，此后必须沿用，密钥和配置需自行安全备份。

原创代码 MIT；第三方许可见应用“设置 → 开源许可”和 [第三方说明](docs/THIRD_PARTY.md)。

项目目录按用途组织：

| 目录 | 用途 |
|---|---|
| `docs/` | 计划、简明日志、交接、工具链与许可；`rounds/` 放轮次日志和验收，`archive/` 放历史原件 |
| `lib/` | Flutter 应用代码 |
| `test/`、`integration_test/` | 单元/界面测试、原生集成测试 |
| `android/`、`windows/` | 两个平台工程 |
| `scripts/` | 环境、检查、构建、签名与安装脚本 |
| `artifacts/R0/` | 已验收安装包、校验值、报告、截图和原始日志 |
| `.tools/` | 本地 SDK；`downloads/` 放安装包，`downloads/partial/` 放历史下载分段，`backups/` 放工具临时备份 |
| `.secrets/` | 本地持久签名密钥，不提交 Git |
| `build/`、`.dart_tool/`、`.idea/` | 工具自动生成的构建、缓存与 IDE 配置 |

根目录保留 README、AGENTS、LICENSE 和 Flutter 必需的工程配置。最初的计划原件已原样归档至 `docs/archive/PLAN.original.md`。
