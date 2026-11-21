# 第三方组件与许可

原创代码 MIT；不复制 Harmonoid 源码、设计素材或许可受限实现。

R0 使用 Flutter / Dart、flutter_localizations、flutter_riverpod、shared_preferences 和 package_info_plus。实际依赖及版本见 `pubspec.lock`，组件许可由 Flutter 构建收集并在应用“设置 → 开源许可”中显示。打包交付须保留该入口与此说明；Flutter SDK 自带的 `LICENSE` 和 `bin/cache/LICENSE.*` 为运行时许可资料。

R0 尚未引入 media_kit、libmpv 或 FFmpeg。R1 必须核对实际原生二进制版本、编解码构建选项、再分发许可、源码来源及对应源码获取方式，不得只依据 Dart 包许可证判断整体发行包。

依赖原始说明：[Flutter](https://github.com/flutter/flutter/blob/master/LICENSE)、[Riverpod](https://pub.dev/packages/flutter_riverpod)、[shared_preferences](https://pub.dev/packages/shared_preferences)、[package_info_plus](https://pub.dev/packages/package_info_plus)。

## R1 实际音频依赖核对（2026-10-29）

上述 R0 文字保留历史边界。R1 已锁定 media_kit 1.2.6、media_kit_libs_audio 1.0.7、audio_service 0.18.19、audio_session 0.2.4、audio_metadata_reader 1.8.1、file_selector 1.1.0。应用许可入口增加原生文本，Windows ZIP 另带 `licenses/native/`。

| 平台 | 实际原生库 | 核对结果 |
|---|---|---|
| Windows | media_kit_libs_windows_audio 1.0.9 → `mpv-dev-x86_64-20230924-git-652a1dd.7z`，MD5 与插件常量一致；DLL SHA256 `0a5a0b476866c91a639a4e511e8153968f8fa23564461b0aa09acdba816164a4` | 实际 API 返回 mpv `v0.36.0-403-g652a1dd907`、FFmpeg `n6.0`、`-Dgpl=false`；DLL 的 FFmpeg 配置为 `--disable-gpl --disable-nonfree --enable-version3`，各 FFmpeg 库声明 LGPL 3 或更高版本 |
| Android | media_kit_libs_android_audio 1.3.8 → default flavor v1.1.8 四个 JAR | libmpv 实际字符串为 `mpv 0.35.1-dirty`，FFmpeg 声明 LGPL 3 或更高版本；二进制配置禁 GPL/nonfree、启 version3。构建标签提交 `87744be8b337c50ed54961249b7a97c5e8cc37c9` 指定 mpv 0.35.1、FFmpeg 6.0、mbedTLS 3.6.1、libxml2 2.10.3，并携带 mpv/FFmpeg 补丁；不将 dirty 版本声称为未修改原版 |

证据：`artifacts/R1/native-{windows,android}-audit.json`、`android-native-jar-sha256.txt`、`libmpv-*-release.json`、`libmpv-android-audio-build-*`。Windows 查询脚本为 `scripts/audit-native.py`。

原生库包含 LGPL 组件，整个安装包不能统称 MIT；原创应用代码仍为 MIT。`assets/licenses/native/` 保存 LGPL 2.1、LGPL 3、后者引用的 GPL 3、mpv Copyright、FFmpeg License、mbedTLS 和 libxml2 文本；GPL 文本被 LGPL 引用不表示启用了 GPL 编解码器。应用不添加阻止调试 LGPL 修改所需逆向分析的限制。

来源：[Windows 发行包](https://github.com/media-kit/libmpv-win32-audio-build/releases/tag/2023-09-24)、[Windows mpv 精确源码](https://github.com/mpv-player/mpv/tree/652a1dd90711839acdccc08004056d25514ef2d8)、[FFmpeg n6.0](https://github.com/FFmpeg/FFmpeg/tree/n6.0)、[Android 构建标签](https://github.com/media-kit/libmpv-android-audio-build/tree/87744be8b337c50ed54961249b7a97c5e8cc37c9)、[mpv 许可](https://github.com/mpv-player/mpv/blob/652a1dd90711839acdccc08004056d25514ef2d8/Copyright)、[FFmpeg 许可](https://github.com/FFmpeg/FFmpeg/blob/n6.0/LICENSE.md)。

审计边界：Windows 历史发行标签只有 version 文件，当前 master 不能证明 2023 发行包的完整精确构建来源。DLL 另静态包含其他依赖；完整对应源码、构建材料及所有原生子组件通知须在公开再分发前归档核全。Android helper 的构建引用 main 而非固定提交，也存在源码重现性缺口。R1 仅本机/目标手机技术验证，不将这些缺口记作最终再分发合规完成；R9 必须继续处理。

## R2 曲库依赖（2026-10-30）

新增精确直接依赖 Drift 2.35.3、drift_flutter 0.3.1、path_provider 2.1.6、path 1.9.1、uuid 4.6.0；生成工具 drift_dev 2.35.2 / build_runner 2.17.1。SQLite Dart 包实际锁定 sqlite3 3.5.2，使用默认普通SQLite原生资产，不配置SQLCipher或加密。传递依赖中的 sqlite3_flutter_libs / sqlcipher_flutter_libs 为 eol 占位包，不能据包名声称打包了SQLCipher。

Drift / sqlite3 Dart绑定的许可文本以锁定包内LICENSE及应用“开源许可”为准（MIT）；SQLite源码的许可声明见[SQLite官方版权说明](https://www.sqlite.org/copyright.html)。预编译原生资产来源是 [sqlite3.dart sqlite3-3.5.2 release](https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-3.5.2)，下载钩子按包内asset_hashes.dart核对SHA256。R2包内实际原生资产哈希与版本另存artifacts/R2，不将Dart包版本当SQLite引擎版本。既有音频原生库的LGPL及R9再分发缺口保持。

## R9 个人使用版

局域网同步使用 cryptography 2.9.0 的 AES-GCM 实现（Apache-2.0）。许可由 Flutter 收录至应用的「开源许可」。 [cryptography 锁定版本](https://pub.dev/packages/cryptography/versions/2.9.0)

完整依赖版本见仓库根目录的 `pubspec.lock`。备份校验使用 `crypto 3.0.8`，FFI 使用 `ffi 2.2.0`，两者均按锁定包的 BSD 三条款许可保留署名和条款。文件选择器的 Windows、Android 实现同样使用 BSD 三条款许可。Dart 依赖许可可在「设置 → 开源许可」查看。

Windows 便携包附带原创 MIT 许可、Flutter 运行时许可和原生音频库许可。两个 Android 变体通过同一应用入口提供原生音频库许可。Windows 音频库的完整对应源码及静态子组件通知、Android 构建引用的 helper 精确版本仍需核全。个人使用版保留这些公开发行前的待办项。

「编辑歌曲」使用 flutter_taglib 1.6.0（Apache-2.0）和 image 4.12.0。Windows 和 Android 的 TagLib 桥接库取自插件的预编译发行版。插件构建配方使用 TagLib 2.3（MPL-1.1 或 LGPL-2.1）与 utfcpp 4.0.9（BSL-1.0）。许可文本随包提供，实际预编译文件及包内副本的哈希留在 `artifacts/R9/`。 [flutter_taglib 二进制与源码入口](https://github.com/axel10/flutter_taglib/releases/tag/desktop-binaries-v1.6.0) · [TagLib 源码](https://github.com/taglib/taglib/tree/v2.3) · [utfcpp 源码](https://github.com/nemtrif/utfcpp/tree/v4.0.9)
