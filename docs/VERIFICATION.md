# 日常检查与打包

仅在需要验证或打包时读取。本项目用 PowerShell 7，Flutter 命令串行执行。[环境与持久签名](TOOLCHAIN.md)

## 检查

- 按改动选现有 `test/` 用例，优先做定向检查。`. ./scripts/env.ps1` 加载当前进程环境，`& ./scripts/restore.ps1 -Round R9` 按锁文件恢复依赖。需要完整主机入口时使用 `& ./scripts/check.ps1 -Round R9`。
- 数据库迁移用 `library_test.dart`、`tag_test.dart` 和 `playlist_test.dart` 的现有旧库、回滚及 schema 基线。真实覆盖安装与设备集成另行授权。
- 旧规模基准与设备专测命令按需查 `git show b17c284:docs/VERIFICATION.md`。历史报告仍在原来的 `artifacts/Rxx/`。

## 三包构建

先确认产品版本、源码检查点和已用构建号。以下数字只作参数示例，每次交付使用尚未用过的三个构建号。

```powershell
& ./scripts/build.ps1 -Target windows -BuildNumber 74 -Round R9
& ./scripts/build.ps1 -Target android -BuildNumber 75 -Round R9
& ./scripts/build.ps1 -Target android -BuildNumber 76 -Round R9 -OriginPlayerTrial
```

- 在 `artifacts/R9/` 核对构建元数据、EXE 版本及包哈希。两个 APK 用 Android Build Tools 的 `aapt2 dump badging` 和 `apksigner verify --print-certs` 核对包名、版本、最低 API 及各自的旧签名。现有 `verify-apk.ps1` 仅针对正式包，随身听包须单独核对。
- 原生音频和许可审计用 `scripts/verify-packages.py`，显式传实际 `--round R9 --version … --build … --native-reference-round R1`，APK 与 ZIP 用 `--android-archive`、`--windows-archive` 指定，两个变体用不同报告路径。
- 三包都核对后复制到 `output/`，按文件名核对副本哈希。原包和报告保留于 `artifacts/R9/`。重复运行会追加或覆盖固定日志时，先保留原证据。
- `install-android.ps1` 会安装、启动并读日志，执行前须有覆盖这些操作的本批授权。
