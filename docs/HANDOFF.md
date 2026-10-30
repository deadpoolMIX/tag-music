# 当前交接

更新：2026-10-30 11:58 北京时间。当前轮次 **R1，开发中**；锁屏项**待手机验收**，不进入R2。用户要求停止反复自动锁屏验证，改由其手动体验验收。设备输入已结束，不自行恢复；后台文件检查/文档可继续。

## 源码、版本与产物

- 修复源码提交 **51f4af1**，应用/已安装手机均 **0.2.0+9**。后续仅测试辅助/交接变更见当前HEAD。双端release包内标识51f4af1，不能冒称后续提交构建。
- +9 APK：artifacts/R1/tag-music-0.2.0+9.apk，SHA256 5c627e9eb37ae8c5f2e69bb3cdaa9087a8767ccdc36e75d9a5b664c08ce57cdd。
- +9 Windows ZIP：artifacts/R1/tag-music-windows-0.2.0+9.zip，SHA256 cce371e7203147719536d28f459addc13cf249d3676853b62e3b089f46d70322。
- 21项测试、分析/格式、双端release构建、+8/+9原签名一致/固定ID/API29检查、包内原生哈希/运行文件/8份许可文本比对通过。test-9.log、analyze-9.log、format-9.log、build-all-9.json、package-audit-9.json、source-manifest-9.json、SHA256SUMS.txt。source-comparison-9.txt是在构建完成时99项文件匹配；后续测试脚本和文档有变化，应用源码未改。

## 已处理问题和 +9 自动证据

- 用户+6反馈锁屏文字一行跳两行、Play偶发不响应及图标/声音反向。+7改切歌loading与完整元数据原子发布、队列内toggle，但独立Play映射MUTE91被Android媒体键过滤，实际通知无回调。+8改MediaAction.playPause85，18次通知操作通过；保留android7/notification-button-root-cause.json及历史失败。
- +8日志确认解码错误后底层playing仍true。+9独立失败状态立即向页面/系统发布未播放，串行卸载失败曲目/释放焦点，重试重新打开；选曲代次保护避免旧错误清理误停新曲。新增错误图标/FD释放重试和切歌保护测试。
- 手机+8→+9原签名覆盖，未卸载/清数据。首次安装仍2026-10-29 20:14:50，通知granted、两个SAF授权/深色主题保持，重开目录2无需授权恢复7个样本。android9/upgrade-state.txt、android-9-samples.png。
- +9六格式中文元数据/系统PLAYING及暂停后真实进度通过；应用拖动/暂停稳定/恢复/停止卸载重开通过。30次FLAC/MP3交替，受管FD播放恒1，总FD234–239，首235末235。formats-check.log、controls-check.log、switches-check.log、descriptor-audit.json及各session/logcat证据。
- 坏MP3错误页显示播放三角而非暂停，系统ERROR/playing=false，受管FD降0；随后有效曲目恢复。android-9-bad-file.png已查看，bad-file-logcat.log。7个手机样本哈希与原创源文件一致：android9/phone-fixture-readonly-check.json。
- +9通知栏6轮18次真实Play/Pause/Next/Previous通过，核对最终图标、会话和不同样本opened。android9/shade-card-check.log、card-operations.jsonl及各shade会话/UI。

## 锁屏当前边界及用户手测决定

- +9首轮锁屏前两轮6次通过，第3轮Play未到达PLAYING。点击前json显示Awake/ON/仍锁定，但lastWakeAge=7264ms，本机窗口覆盖熄屏时限7000ms；key224在已醒时不重置时限。不能将此记作产品通过或确定全部产品失败。
- 有效锁屏录屏h264/630x1400，实际62.145秒，抽帧已查看标题/歌手两行。android9/lock-first-attempt/保留首轮完整失败/录屏/JSON/UI；lock-recording-probe.json。不能以抽帧声称所有瞬间无跳动。
- 测试辅助改每次观察前sleep/wake重置时限，tap前要求醒来不足5秒且ON/仍锁定，避免旧树点击；仅测试脚本，不改变手机安全或显示设置。重试有4次成功记录后，用户指出此处耗时过多并要求自行验收，立即Ctrl+C终止脚本，不再跑完整循环，不标锁屏稳定性通过。
- 收尾时样本自动播至坏MP3，真实会话 **ERROR、position0**；没有盲发播放/暂停键，不冒称PAUSED。device-batch-9-manual-handoff.json、android9/manual-handoff-session.txt、final-before-manual-logcat.log。请用户先解锁选正常曲目，重点按R1-ACCEPTANCE的5项手测反馈；助手不再输入。

## Windows 已完成及工具限制

- 用户范围：软件内基本播放操作、最小化/后台持续播放；不实施外部媒体卡片、SMTC、系统媒体键或托盘播放按钮。Android卡片需求保留。
- +9Release实际启动、界面文字正常；Computer Use截图FrameArrived/window capture超时，动态控件缓存不可用、坐标几何不可用；快捷键关闭后进程为空。windows9/release-window-text.json。未拿到Release播放/截图，不冒充成功。
- +9源码原生Debug集成六格式、seek/暂停、坏文件错误与卸载/恢复、20次排队切歌通过；Flutter重绘截图windows9/windows-native-playback.png已查看。用户手动最小化/恢复测试窗口，20秒默认WH-1000XM3输出回环每秒均检测440Hz。windows9/background-output-loopback.json/wav、minimized-user-confirmation.json、restored-user-confirmation.json、integration-playback.log。不是完全自动最小化，也不是Release截图。
- 初次后台等待90秒因工具窗口操作失败而超时，第二次窗口被用户误关，终止退出79并出现测试临时目录已不存在；失败日志分别integration-playback-capture-timeout.log、integration-playback-user-closed.log。核实进程终止后才重跑，第三次全套通过。电脑测试进程已退出，已明确告知电脑可用。
- 已向用户解释Windows前台输入不宜并行，普通鼠标键盘可能触发重新观察，Esc停止不自行恢复，蓝色边框不是完成标志，结束以明确消息为准；官方文档https://learn.chatgpt.com/docs/computer-use未说明蓝框关闭时机。无自行操作Codex自身界面。

## 下一步及未验证

1. 等用户+9锁屏5项体验结果。失败时收集大约发生时间/动作及本应用日志，先定位，不盲目重复自动锁屏循环。当前目标仍active，不能当作已验收或目标完成。
2. +9真实进程重启后的默认不自动播放、重开授权/主题保持、系统目录选择取消不丢列表尚未本批完成；先吸收用户反馈，再安排明确范围的收尾。新批影响设备操作须交互确认，不能用旧授权自动恢复。
3. Release Windows截图/真实UI播放因工具限制未验证；当前有效Windows声音证据为原生Debug及用户手动最小化的回环，保留边界。
4. R0已验收；R1仅临时曲目列表和持久目录授权，无R2曲库/标签/歌单。Android只读SAF/显式借用FD，不推导真实路径；LGPL3+及公开再分发对应源码/子依赖通知缺口保留THIRD_PARTY，R9核全，其他系统/手机未覆盖。
