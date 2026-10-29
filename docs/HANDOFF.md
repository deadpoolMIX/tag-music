# 当前交接

- 更新时间：2026-10-30 00:12，北京时间。当前轮次 **R1 双端播放技术验证**，自动验证通过，状态 **待手机验收**。R0 已双端通过；不进入 R2。
- 当前版本 **0.2.0+6**。源码基于本地提交 `3ef58c3`，收尾提交见本文件所在 HEAD；双端包内构建标识仍为 `3ef58c3-dirty`，不能改称收尾提交构建。仅本地 Git，无远程。
- 用户已逐批授权 +5/+6 双端验证，并手动反馈“已允许播放通知”“已开启锁屏通知”；授权不等于体验验收。本批设备操作已经结束，手机停在 7 个样本列表且未播放，Windows +6 测试窗口已关闭。新的设备操作必须重新交互确认。
- 手机 V2309A / Android 16 / arm64 实际安装 +6。固定 ID `app.tagmusic.player`，原签名，首次安装时间仍为 2026-10-29 20:14:50，深色主题和两个 SAF 授权保留。没有卸载、清数据或全盘权限。

## 实现与自动验证

- Windows 文件夹选择；Android SAF 只读持久授权/递归读取；六格式中文元数据、单播放器、串行切歌、进度、暂停、停止、坏文件恢复；Android 基本后台和媒体通知。R1 只保存目录授权，不保存曲目列表、队列和位置；持久曲库、标签、歌单尚未实现。
- +4 元数据重开 `/proc/self/fd` 被拒；+5 改借用授权 FD，通过 libc `pread64/lseek64` 只读，不推导音乐真实路径、不整首复制。+5/+6 已在目标手机六格式实测通过。历史失败保留于轮次日志。
- +5 本机系统拦截通知；+6 增加用户主动触发的通知授权和设置入口，返回时刷新。用户允许后实际通知/锁屏卡片可见，卡片暂停、继续、上下曲通过。当前卡片未显示进度条，系统卡片拖动未验证；应用内拖动已通过。
- +6 对相同媒体信息和正常时钟进度去重，保留 seek/状态/错误更新；正常播放至少 8 秒通知入队增量为 0。格式、静态分析、16 项单元/界面测试通过。
- Android +6 release：六格式元数据/播放状态、暂停拖动约 14 秒、暂停稳定、继续/停止重开、30 次交替切歌、坏文件到 WAV 恢复、选择器取消、后台/熄屏、进程重启后重新打开 7 首且无新授权通过。切歌受管 FD 播放 1、卸载 0；总 FD 243–248，首 245、末 244，无持续增长。7 个样本哈希与源一致。PLAYING 与截图不能代替用户听感。
- Windows +6 原生 Debug 集成回归：六格式、进度/暂停、坏文件恢复、20 次切歌通过；20 秒默认 WH-1000XM3 输出回环检测到 440Hz，截图已查看。+6 Release 已启动且界面文本正常；截图工具 FrameArrived 超时，保留文本，不把 Debug 画面当作 Release。测试窗口已关闭。

## 产物与证据

- APK：`artifacts/R1/tag-music-0.2.0+6.apk`；SHA256 `2c062364b3ed992563bb8f8cae6a8539e9ac6a2a4f2a910c8174e275d44f9199`。
- Windows：`artifacts/R1/tag-music-windows-0.2.0+6.zip`；SHA256 `73d78cdbd312eb262bb57c7f0b1dc814f529e8a1de866cddbd76dd04768ddd35`。
- `artifacts/R1/`：build-{android,windows}-6.log、apk-signature-6.txt、apk-manifest-6.txt、apk-permissions-6.txt、package-audit-6.json、SHA256SUMS.txt。签名与 R0 一致；包内原生哈希、运行文件和 8 份许可文本比对通过。
- 源码匹配：source-manifest-6.json、source-comparison-6.txt（26 个应用/manifest 文件）；Windows 隔离目录 `.tools/windows-build-6`，记录 windows-build-isolation-6.json。产物、密钥、SDK、缓存不提交。
- `artifacts/R1/android6/`：六格式会话、controls/switches 日志、descriptor-audit.json、notification-update-audit.json、card-controls-check.json、restart-grant-check.json、phone-fixture-readonly-check.json、installed-package.txt；截图位于 R1 的 android-6-{notification-playing,lockscreen-playing,settings-version,badfile,final-stopped}.png。
- `artifacts/R1/windows6/`：integration-playback.log、windows-native-playback.png、output-loopback.json/wav、release-window-text.txt。报告入口 `artifacts/R1/REPORT.md`。

## 下一步与限制

- 等待用户按 `docs/rounds/R1-ACCEPTANCE.md` 的 7 项反馈听感与操作体验；尚无 R1 全部通过反馈，必须写“待手机验收”。有失败先修复，不自行进入 R2。
- 系统卡片拖动未验证；Android 10、其他手机和 Windows 11 没有本轮实机覆盖。复杂音频焦点/蓝牙、Windows SMTC/托盘属于 R7。
- 实际原生库含 LGPL3+，不整体称 MIT。Windows 历史完整对应源码/子依赖通知、Android helper 固定源码仍有公开再分发前缺口，详见 `docs/THIRD_PARTY.md`，R9 继续核全。
- 工具链 hook/空格路径修复及 junction 约束见 `docs/TOOLCHAIN.md`；Flutter 检查、测试、构建串行。+3/+4/+5 失败包和日志全部保留。
