# 第三方组件与许可

原创代码 MIT；不复制 Harmonoid 源码、设计素材或许可受限实现。

R0 使用 Flutter / Dart、flutter_localizations、flutter_riverpod、shared_preferences 和 package_info_plus。实际依赖及版本见 `pubspec.lock`，组件许可由 Flutter 构建收集并在应用“设置 → 开源许可”中显示。打包交付须保留该入口与此说明；Flutter SDK 自带的 `LICENSE` 和 `bin/cache/LICENSE.*` 为运行时许可资料。

R0 尚未引入 media_kit、libmpv 或 FFmpeg。R1 必须核对实际原生二进制版本、编解码构建选项、再分发许可、源码来源及对应源码获取方式，不得只依据 Dart 包许可证判断整体发行包。

依赖原始说明：[Flutter](https://github.com/flutter/flutter/blob/master/LICENSE)、[Riverpod](https://pub.dev/packages/flutter_riverpod)、[shared_preferences](https://pub.dev/packages/shared_preferences)、[package_info_plus](https://pub.dev/packages/package_info_plus)。
