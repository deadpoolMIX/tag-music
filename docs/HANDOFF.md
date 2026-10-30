# 当前交接（压缩恢复入口）

更新：2026-10-30 11:23 北京时间。用户要求完成手头工作后压缩对话；本批验证已收尾，下一步从本文件继续。目标仍是原计划，**R1状态开发中**，不进入R2，不标目标完成。

## 当前源码与设备

- 应用源码/已安装手机均 **0.2.0+8**，修复源码提交7678f42；后续纯交接和测试辅助脚本提交见本文件所在HEAD。双端包内仍标识 **2c83b32-dirty**，不改称后续提交构建。
- 手机固定ID app.tagmusic.player、原持久签名；+7→+8原签名覆盖成功，未卸载/清数据，首次安装仍2026-10-29 20:14:50，通知权限granted=true，两个SAF目录授权保留，目录2无需新授权恢复7个样本。深色界面截图可见。
- 本批获交互回复允许恢复+8双端验证，记录artifacts/R1/device-batch-8-authorization.json。用户另反馈手机已放置好可测锁屏。收尾时媒体会话实际 **PAUSED**，证据android8/stopped-at-handoff-session.txt；尝试媒体Stop后仍PAUSED，不能声称已卸载/FD归零。本批设备操作结束；后续新批次重新交互确认。
- Windows本批只发现无Tag Music窗口，**没有启动+8或验证后台输出**；不要将+7原生回归/回环作为+8结论。Windows仅需软件内操作和后台播放，不要实现SMTC、外部卡片、系统媒体键或托盘播放按钮。Android通知/锁屏需求保留。

## 修复背景及当前证据

- 用户+6反馈：锁屏切歌标题/歌手先一行后两行跳动，播放点击偶发无反应须切歌恢复，实际播放显示▶或实际暂停显示Ⅱ；其他项正常。
- +7修复切歌临时idle停服/残缺元数据先发布/点击排队前读旧状态；但通知Play真机仍无Dart回调。组件audio_service0.18.19将play映射MUTE91，AOSP媒体控制器过滤该非媒体键；Next正常，原生pending intent送出而无回调。失败证据及原始源码链接见android7/notification-button-root-cause.json。
- +8通知主按钮改 **MediaAction.playPause85**，保留真实Play/Pause图标标签；沿用队列内toggle判断，显式play/pause接口保留，无新权限/依赖/第三方缓存修改。
- +8既有 **19项测试**、分析/格式、双端release构建、签名/版本/API29及包内原生哈希/运行文件/8份许可检查通过；26项应用/manifest源码与快照匹配。
- **本批真实通知栏6轮共18次操作全部通过**：Play6/Pause6/Next3/Previous3；每次按实际卡片按钮、媒体会话、最终图标检查，切歌必须确认不同样本opened。Play/Pause观测136–156ms；切歌观测含日志轮询，不能当纯引擎延迟。证据android8/card-operations.jsonl、shade-card-check.log、shade-card-logcat.log、shade-*-session.txt、phone-8-shade-*.xml、shade-card-recording.mp4。录屏抽帧已查看，标题/歌手两行可见，不能以抽帧证明所有瞬间无跳动。

## 锁屏未通过与脚本限制（优先处理）

- 后台熄屏8秒会话仍PLAYING、error=null，锁屏卡片截图可见：android8/locked-playing-session.txt、locked-power-state.txt及android-8-lockscreen-playing.png。
- 起初锁屏发生无空闲UI快照和系统showing true→false变化；没有据此记卡片成功。用户将手机放到摄像头看不到脸的位置后重试。
- 测试脚本新增逐次key224唤醒并检查Awake和keyguard showing=true（没有解锁或认证）。**锁屏首个Play成功，约142ms，随后Next没有打开另一首样本，脚本正确失败**；不能称锁屏稳定性通过。
- 后续power/display确认为 **Asleep/OFF**。UI dump可返回旧锁屏树，检查Awake之后到实际tap之前仍会熄屏。下一步应在实际tap前再次唤醒并核对显示ON/仍锁定，解决测试时序；不要盲用旧XML，不修改用户安全/解锁设置。
- 两次锁屏screenrecord返回INVALID_LAYER_STACK，录屏无效，留存lock-recording.log和lock-card-recording-invalid.mp4；不当作成功录屏。需重新在屏幕ON期间录制短片。
- 证据android8/lock-card-check.log、lock-card-logcat.log、lock-cycle-1-*-session.txt、lock-*-policy.txt、lock-display-power-investigation.txt、lock-initial-investigation-logcat.log、card-check-summary.json。
- 样本自动播放到坏MP3时观察到错误文字但应用按钮仍显示Ⅱ（android-8-before-lock-retry.png）；后续恢复FLAC成功，但独立坏文件完整回归未做。需进一步核对错误状态图标，不能据此宣称所有播放状态已同步。

## 其余未完成与继续顺序

1. 新设备批次确认后先稳定锁屏测试时序，反复播放/暂停/上下曲、快速点击、文字布局及图标/声音同步，保存有效录屏和命令状态日志；有产品失败先修复。
2. +8完整六格式/应用进度/至少30次切歌FD、坏文件恢复、重启授权/主题/无自动播放、7个样本只读哈希尚未本批完成；+7历史通过不冒充+8。
3. Windows +8发布版实际软件内播放和最小化后低音量默认输出回环未做。使用computer-use技能的sky接口；旧版曾有FrameArrived截图超时/索引缓存问题，激活并刷新正确窗口，必要时键盘操作，不能绕用PowerShell UI Automation。实体Esc表示停止设备输入。
4. 全部自动验证完成后再给用户5–8项手机清单；尚无+8手机体验通过反馈，状态仍开发中。目录/主题/系统授权保留不等于听感通过。

## 产物与其他边界

- APK artifacts/R1/tag-music-0.2.0+8.apk，SHA256 1d7618506deda3eefc2e562df8e04a7c39629e4ee9d31155c13c29d6a76101e6。
- Windows ZIP artifacts/R1/tag-music-windows-0.2.0+8.zip，SHA256 192caebfb8b144294bdc4ce234fd76414b1045c04b6f25084eb2bba8e15b00be。
- 审计package-audit-8.json、source-manifest-8.json、source-comparison-8.txt、test-8.log、analyze-8.log、build-{android,windows}-8.log/json、SHA256SUMS.txt；总报告REPORT.md，历史追加日志docs/rounds/R1.md。
- R0已验收，R1只有临时曲目列表/持久目录授权；没有R2持久曲库/标签/歌单。音乐只读SAF URI/借用FD，无真实路径推导。原生LGPL3+及公开再分发源码/子依赖通知缺口见THIRD_PARTY，R9核全；Android10/其他手机/Windows11未覆盖。
- 当前工具没有直接触发本聊天压缩的入口。官方文档列出用户输入/compact可压缩上下文；用户可在本批结束后发送。此次未改变目标状态为暂停或完成。
