# 当前交接

- 更新：2026-10-30 00:55 北京时间。当前 **R1，开发中**。+7 通知卡片播放失败已真机复现；+8 候选已完成19项测试和双端发布构建，**未安装、未真机验证**。不进入R2。
- 当前源码 **0.2.0+8**，基于2c83b32，收尾提交见本文件所在HEAD。包内标识 **2c83b32-dirty**，不能改称后续提交构建。仅本地Git；密钥/SDK/产物不提交。
- 手机仍 **0.2.0+7**，固定app.tagmusic.player，原签名，首次安装2026-10-29 20:14:50；此前主题和两个SAF授权保留。最后已条件暂停，停在通知中心。旧Windows+7测试窗口已恢复并通过Alt+F4退出，随后进程查询为空。
- 用户明确Windows只需软件内操作后放后台继续播放，不需软件外媒体卡片/SMTC/系统媒体键/托盘播放按钮；Android通知/锁屏需求保持。PLAN已记录范围变更，原始归档不改。

## 失败复现与候选修复

- 用户+6反馈锁屏切歌标题/歌手先一行后两行跳动、播放偶发无响应须切歌恢复、实际播放显示▶或实际暂停显示Ⅱ；其他验收项正常。
- +7已修复切歌临时idle导致停服、残缺新媒体信息先发布、点击排队前读取旧状态；18项测试和基础六格式/进度/30次切歌通过，但不等于卡片问题全部解决。
- 本批获用户交互明确允许继续已安装+7验证后，实际点击通知Play，4秒后仍PAUSED且Dart无mediaCommand。相同卡片Next立即送达next，打开OGG并PLAYING。Play原生PendingIntent requestCode91显示sent=true、canceled=false。失败证据不覆盖为通过。
- audio_service0.18.19把通知play映射KEYCODE_MUTE91。AOSP Android16 MediaController.dispatchMediaButtonEvent过滤非媒体键，KeyEvent.isMediaSessionKey不含MUTE；与真机无回调而Next有效相吻合。证据为源码及链路推断，修复仍需实际按钮复验。源码链接保存android7/notification-button-root-cause.json及R1日志。
- +8将通知主按钮改为标准 **MediaAction.playPause（键码85）**，保留随实际状态变化的Play/Pause图标和标签，沿用+7队列内toggle判断；显式play/pause入口仍保留。没有改第三方缓存、原生库、权限或依赖。
- 新增传输动作/图标/标签合约测试，全套 **19项测试**、分析/格式、双端release、签名/API29/版本、包内原生哈希/运行文件及8份许可检查通过；26项应用/manifest文件与构建快照一致。构建通过不能代替真机。

## 已有证据与当前批次

- +7基础：手机六格式、应用内seek/暂停/继续/停止重开、30次切歌通过，受管FD播放1卸载0，总FD234–240、首尾236；切歌采样无idle/残缺媒体项。Windows原生Debug六格式/进度/暂停/坏文件/20次切歌和20秒回环440Hz通过，Release启动/文本正常。上述均保持+7边界，不冒充+8。
- 最新+7卡片失败：artifacts/R1/android7/shade-card-check.log、shade-cycle-1-play-session.txt、shade-card-logcat.log、shade-next-after-play-failure.log、pending-intents-failure.txt、audio-service-button-mapping.txt、notification-button-root-cause.json、shade-card-recording.mp4；截图android-7-shade-play-failure.png。
- 用户最新授权“允许本批+7继续验证”，记录device-batch-7-continue-authorization.json；该批未授权安装+8。已发出+8双端验证交互确认，**尚未收到明确答复**。等待回复前不安装或操作新批次设备。
- Android+8通知/锁屏反复按钮、图标/文字布局/短录屏、六格式/切歌/坏文件恢复/重启授权与主题/样本只读哈希全部未验证。Windows+8实际运行及最小化后持续输出未验证。系统卡片进度条此前未显示，不称拖动通过。

## +8产物

- APK：artifacts/R1/tag-music-0.2.0+8.apk；SHA256 **1d7618506deda3eefc2e562df8e04a7c39629e4ee9d31155c13c29d6a76101e6**。
- Windows：artifacts/R1/tag-music-windows-0.2.0+8.zip；SHA256 **192caebfb8b144294bdc4ce234fd76414b1045c04b6f25084eb2bba8e15b00be**。
- build-{android,windows}-8.log/json、apk-signature-8.txt、apk-manifest-8.txt、package-audit-8.json、source-manifest-8.json、source-comparison-8.txt、test-8.log、analyze-8.log、format-8.log、final-validation-8.txt、SHA256SUMS.txt。签名与R0一致；未卸载/清数据。
- 总报告artifacts/R1/REPORT.md；7项清单docs/rounds/R1-ACCEPTANCE.md；手机卡片辅助脚本verify-android-media-card.ps1已真机执行并正确报告+7失败，切歌检查还要求opened样本变化。

## 下一步

- 收到+8批次明确允许后原签名覆盖升级，优先复测真正通知/锁屏按钮的响应、切歌文本/图标同步，保存命令和状态日志/短录屏；补足其余手机回归，Windows只测软件内操作和最小化后台持续输出。系统授权/解锁由用户完成。
- 自动检查及运行验证都通过后，再请用户做手机体验验收；当前没有+8通过反馈，不能标双端通过。R1只有临时曲目列表及目录授权，没有持久曲库/标签/歌单。
- Android10/其他手机/Windows11未覆盖；复杂Android音频焦点/蓝牙后续R7。原生库含LGPL3+，完整对应源码/子依赖通知及helper固定源码缺口见THIRD_PARTY，R9继续核全。所有历史失败、包、日志保留。
