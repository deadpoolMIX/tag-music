# 当前交接

- 轮次：R0，工程与交接底座。
- 状态：**双端通过**。R0 自动验证通过，用户已通过交互式选项确认 `0.1.0+2` 的 7 项手机体验全部通过；R0 已完成。
- 本轮日志：`docs/rounds/R0.md`。
- 文档入口：`docs/README.md`；给人看的简明开发日志为 `docs/开发日志.md`，顶部注明每行一项、北京时间精确到分钟的写入规则，后续完成工作时追加。
- 现状：双端平台工程已生成，Material 3 中文空壳、主题持久化、版本诊断、签名与脚本均已实现；尚不提供音乐导入或播放。
- 工具链：Flutter 3.47.8 / Dart 3.13.7 官方 SHA256 已验证；Visual Studio Community 2022 17.14.43 + C++、Android SDK / Command-line Tools 23.0 均就绪。`doctor.log` 全部通过。
- 验证：格式、静态分析、6 项单元/界面测试、PowerShell 语法检查通过；新机器首次插件清单恢复/junction 自动准备通过。Windows 原生集成测试通过（实际设置写入、重新初始化恢复、版本、诊断复制），截图已检查。双端 +1、+2 发布构建完成；Android 实际发布版已验证安装启动、主题保存、真实进程重启恢复、覆盖升级保留主题与首次安装时间。
- 版本与产物：两端当前均为 `0.1.0+2`。Windows ZIP：`artifacts/R0/tag-music-windows-0.1.0+2.zip`，构建提交 `f28bbd0`；Android APK：`artifacts/R0/tag-music-0.1.0+2.apk`，构建提交 `41cea26`。两平台于不同阶段构建，共用 Dart 应用代码一致；逐平台准确元数据见 `verified-{windows,android}-2.json`，SHA256 见 `SHA256SUMS.txt`。历史 `build-2.json` 只记录最后一次构建，后续脚本已改逐目标文件名。
- 手机：V2309A / Android 16 / arm64，已安装 +2；7 项用户体验验收全部通过。本批手机操作已结束，再操作需新的交互确认。首次安装时间 20:14:50，升级时间 20:19:05，未卸载/清数据。USB 安装系统确认由用户在手机手动允许，已实际完成。
- 签名：已创建 `.secrets/tag-music-local.jks`，配置 `android/key.properties`；两者及 SDK、产物均已确认 Git 忽略。固定应用 ID `app.tagmusic.player`，最低 API 29，debug/release 沿用同一签名。
- 证据总入口：`artifacts/R0/REPORT.md`。目录内有 doctor、SDK/Gradle 校验、检查日志、双端构建、Windows 原生测试、APK 签名/manifest、手机进程日志、两端截图、升级无障碍断言与逐平台元数据。手机验收说明：`docs/rounds/R0-ACCEPTANCE.md`。
- 工具故障：computer-use 窗口截图超时、元素缓存点击失败；已使用真实原生集成测试导出画面并检查，不声称该点击成功。Windows 插件通过项目内 NTFS junction 准备，无需开启系统开发者模式。
- 电脑/手机操作约束：影响用户使用或需要请示时，必须用交互式选项确认并等待明确回复，覆盖前台应用启动/关闭、窗口/鼠标键盘、手机安装/升级与界面测试。仅授权已说明的本批操作，下一批须重新确认，不能超时默认同意。此要求已写入 AGENTS；本轮所有已确认的操作批次均已结束。
- 验收证据：用户交互式选项原文为“7项全部通过”，对应 `docs/rounds/R0-ACCEPTANCE.md` 中 `0.1.0+2` 的 1–7 项，无失败或未测项。记录见 `artifacts/R0/phone-acceptance.json`，最终逐项完成审查见 `artifacts/R0/completion-audit.md`；重新计算的四个构建产物 SHA256 全部一致。
- 未验证边界：Android 没有执行 Flutter integration_test，实际执行发布版 ADB 生命周期/升级检查并由用户完成 7 项体验验收。Android 10 和 Windows 11 未实机验证，R0 优先验收的当前电脑和手机均已通过。R0 没有音乐导入/播放，不宣称具备播放能力。
- 下一步：本对话止于已完成的 R0。新对话可执行 R1“双端播放技术验证”，先读本规范、计划、本交接和 R0 日志；R1 必须在目标手机验证目录授权、元数据、播放及基本后台能力，并核对实际原生音频库许可。影响设备使用的操作仍须新的交互式确认。
- Git：本地 main，无远程；`b472e58` 初始工程，`f28bbd0` Windows 链接/证据修复，`f3abd01` Kotlin 跨盘修复，`41cea26` 双设备交互确认规则，`7ce5ee1` 最终锁定恢复/工作流。最后一次交接提交见本文件所在 HEAD。密钥和产物未入 Git，写入 Git 元数据需执行权限。

## R0 完成后的目录维护

用户要求新增简明日志并整理目录。原始计划已原样移至 `docs/archive/PLAN.original.md`，R0 验收文件移至 `docs/rounds/R0-ACCEPTANCE.md`；当前有效入口与链接已更新。历史日志和产物报告中的旧路径保留为当时记录，映射见文档目录。

工具安装包集中到 `.tools/downloads/`，下载分段放 `partial/`、清单备份放 `.tools/backups/`，SDK 仍在 `.tools/flutter`。bootstrap 已同步读取新的完整 SDK 安装包位置；原始计划、SDK 和 Gradle 安装包移动前后 SHA256 一致。仅调整文档、下载缓存位置和对应脚本路径，已验收应用、签名和产物均沿用原文件。

