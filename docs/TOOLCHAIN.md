# R0 工具链

以实际 `artifacts/R0/doctor.log`、锁文件和构建报告为准。不要求修改系统 PATH，`scripts/env.ps1` 只设置当前进程环境。

| 工具 | 锁定 / 路径 |
|---|---|
| Flutter stable | 3.47.8，SDK revision 737ba8f885dc774b53b442759999a312c9461e4e |
| Dart | SDK 随附 3.13.7 |
| SDK ZIP SHA256 | `11e19ea3409808fe3b3765ea8149640c299e58cce6eda7c9f38fc1b4a193eb6e` |
| Flutter 位置 | `.tools/flutter`（由 bootstrap 下载并校验） |
| Java | Android Studio 内置 OpenJDK 21.0.10 |
| Android SDK | 默认 `%LOCALAPPDATA%/Android/Sdk`，可设 `ANDROID_HOME` |
| Android Command-line Tools | 23.0，官方包 `commandlinetools-win-16111833_latest.zip` |
| Android 最低版本 | Android 10，API 29 |
| Android compile / target SDK | API 36 |
| Android Gradle Plugin / Kotlin | 9.1.0 / 2.4.0，Flutter 模板配置 |
| Gradle | 9.3.1，wrapper 配置包含官方 distributionSha256Sum |
| Android NDK | 28.2.13676358，Flutter 3.47.8 默认值 |
| Android 应用标识 | `app.tagmusic.player`，后续不得变更 |
| Windows C++ | Visual Studio Community 2022 17.14.43，Desktop development with C++ 工作负载及推荐组件 |
| PowerShell | 7，脚本 `#Requires -Version 7.0` |

本机验证环境：Windows 10 Pro 22H2 x64、MSVC 14.44.35207、Windows SDK 10.0.26100.0；测试手机 V2309A，Android 16 / API 36 / arm64。Android 10 与 Windows 11 尚未实机验证。

本机没有普通进程创建符号链接的权限。`scripts/prepare-windows.ps1` 按 Flutter 生成的依赖清单，在 `windows/flutter/ephemeral/.plugin_symlinks` 内创建 NTFS junction，Flutter 可识别并复用，无需修改系统开发者模式。`check.ps1`、`build.ps1` 已集成；手动使用 `flutter run -d windows` 前也需先执行此脚本。新增/升级插件时若 Flutter 自身在更新链接时失败，先准备链接并重试；不要修改 SDK 源码。

本机 Pub 缓存在 C 盘、项目在 D 盘，首次 Kotlin 增量缓存报 `this and base files have different roots`。项目级 `android/gradle.properties` 关闭 `kotlin.incremental`，保留普通编译与 Gradle 其他缓存；配置依据 [Kotlin 官方文档](https://kotlinlang.org/docs/gradle-compilation-and-caches.html)。

Flutter SDK 使用官方发布索引锁定，不自动升级。Dart 包精确直接依赖写在 `pubspec.yaml`，传递依赖锁在 `pubspec.lock`。音频、Drift 和原生组件在 R1/R2 实际接入时锁定并验证，不为 R0 空壳提前打包解码器。

首次环境缺失时：运行 bootstrap；若缺 Visual Studio C++，安装上述工作负载；通过 Android Studio SDK Manager 安装 SDK Platform、Build Tools、Command-line Tools。执行 `flutter doctor -v`，依据结果补齐，不把未验证项当通过。新机器可通过 `flutter doctor --android-licenses` 阅读并接受所需 SDK 协议。

## 本地持久签名

`scripts/signing.ps1` 生成 `.secrets/tag-music-local.jks` 和 `android/key.properties`。密码随机生成，不写日志、不入 Git。配置与密钥仅一项存在时脚本拒绝生成，须恢复原文件。

这是本地侧载签名，不是商店发布凭据。保留同一应用 ID、同一密钥且递增构建号，使用 `adb install -r` 覆盖安装。不得卸载、清数据或重签名来掩盖升级失败。密钥丢失会失去对已安装版本的覆盖升级能力。

## 来源

- [Flutter 官方发布索引](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)
- [Windows 开发环境](https://docs.flutter.dev/platform-integration/windows/setup)
- [Android 开发环境](https://docs.flutter.dev/platform-integration/android/setup)
- [Android 构建及签名](https://docs.flutter.dev/deployment/android)
- [Android SDK 官方仓库索引](https://dl.google.com/android/repository/repository2-1.xml)
