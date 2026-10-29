# 当前交接

- 轮次：R0，工程与交接底座。
- 状态：开发中；用户于 2026-10-29 明确恢复 R0。
- 本轮日志：`docs/rounds/R0.md`。
- 现状：已建本地 main Git 仓库、AGENTS、完整计划副本、日志、工具链/许可/手机验收文档；已编写 Flutter 空壳、主题持久化、版本诊断、测试及 PowerShell 脚本。尚未完成 Flutter SDK 下载校验/解压、平台工程生成、依赖解析、测试或双端构建。
- 工具链：Android Studio/SDK 已有；本轮安装 Command-line Tools 23.0。Visual Studio Community 2022 17.14.43 + C++ 推荐组件安装已启动，暂停时仍在安装，不强杀安装器；恢复时先检查其结果。
- Flutter：锁定 3.47.8 / Dart 3.13.7。下载分段保存在 `.tools/`，完整 SDK 未经校验，不可使用；暂停时停止本轮下载进程。可用完整前缀与分段恢复组装，必须核对 `scripts/bootstrap.ps1` 中的官方 SHA256。失败分段不得视为成功。
- 手机：初次无设备，后经用户连接，ADB 识别 V2309A / Android 16 / arm64（已授权）。尚未安装应用、未运行手机测试。用户正在使用手机，未经恢复指令不得继续手机操作。
- 版本：计划 `0.1.0+1`，无产物、无签名密钥、无代码提交。代码与脚本均未通过执行验证，PowerShell 仅做过语法检查通过。
- 证据：`artifacts/R0/android-sdk.txt` 已保存已装 Android 包清单；尚无 APK、Windows ZIP、截图或正式检查报告。
- 下一步：等待用户明确恢复。恢复后检查安装器、完成 SDK 校验与解压，生成 android/windows 平台目录（保留已有代码与规范），配置固定应用 ID `app.tagmusic.player`、API 29 和持久签名；解析依赖，执行测试、双端构建与 Windows 实跑；确认用户可用手机后再安装和验收。
- Git：本地 main，无远程；全部文件仍未提交。Git 元数据是只读沙箱项，写入需执行权限。已设置仓库级通用身份 Tag Music Developer / developer@tagmusic.local，避免沿用其他项目全局身份。

