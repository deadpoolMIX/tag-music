# 当前交接

- 当前轮次：**R1 双端播放技术验证**；产品状态 **开发中**，用户体验 **待手机验收**。R0 0.1.0+2 已双端通过；不进入 R2。
- 用户最新指令：完成手头工作后停止，额度不足。当前描述符修复、测试、双端构建、产物审计和交接已收尾；执行目标按该指令暂停。不要自动继续测试或推进后续轮次。
- 最新源码/构建：**0.2.0+5**，Android和Windows release均构建成功；本轮源码在本文件所在本地HEAD，构建时仍标识 `635b43c-dirty`，不能把产物声明为带有新提交号。无远程；密钥、SDK、产物不提交。
- 手机实际安装：V2309A / Android16 / arm64，仍为 **0.2.0+4**，已原签名从+2→+3→+4覆盖升级，首次安装时间保持2026-10-29 20:14:50，深色保留；从未卸载/清数据。固定ID app.tagmusic.player、最低API29、原有签名沿用。
- 最新产物：artifacts/R1/tag-music-0.2.0+5.apk、tag-music-windows-0.2.0+5.zip；SHA256SUMS.txt。package-audit-5.json已核对实际包内原生库SHA256、运行文件和8份原生许可文本；APK签名/版本验证日志apk-signature-5.txt、apk-manifest-5.txt。+3/+4失败与中间包保留。
- 源码匹配：source-manifest-5.json记录独立Windows构建的97文件快照；source-comparison-5.txt确认应用/manifest文件仍匹配。Windows旧+4窗口未关闭，+5在忽略目录.tools/windows-build-5独立构建，隔离记录windows-build-isolation-5.json。没有安装或启动+5，不声称+5实跑通过。
- 已实现：Windows目录选择；Android SAF只读持久授权/递归读取；元数据异步读取；单播放器/串行切歌/进度/暂停/停止/错误恢复；audio_service基本后台通知与audio_session；运行诊断与原生许可入口。R1只保存目录位置/授权，歌曲是临时列表；没有R2持久曲库、UUID、标签或歌单。
- 最新检查：格式、静态分析、**13项单元/界面测试**通过；脚本AST/Python语法与源码空白检查通过。新增借用描述符适配器的seek/EOF/关闭/拒绝写入及六格式元数据解析测试；源为内存描述符，不能替代Android libc/SAF实测。
- 本轮新发现：+4 MP3系统媒体会话实际PLAYING、24秒时长和进度可观察，通知图标资源ID有效，无旧CustomAction图标错误；managedDescriptors=1、persistedReadGrants=2。**但元数据重新打开/proc/self/fd被PathAccessException拒绝**，只能退回文件名；该真机关卡失败，不能记作R1通过。证据android-4-mp3-playing.png、android-4-first-playback.log、android-4-mp3-session.txt。
- +5修复：DescriptorFile/RandomAccessFile只读适配器直接通过libc pread64读取已授权FD、lseek64取长度，不打开proc路径、不复制整首音乐、不推导真实路径。原始PFD由Kotlin外层finally关闭；适配器只借用。每次读取上限16MiB，写入拒绝。ffi2.2.0为精确直接依赖，版本未新增。NDK API29 arm64符号核对android-descriptor-symbols.txt。
- 设备停留：助手已用媒体暂停停止测试音，android-4-paused-at-stop.txt观察PAUSED；手机可能仍为+4曲库播放面板，Windows+4发布版可能仍开着。未按自动化去关闭用户前台窗口。此前用户以实体Esc结束过Computer Use；本次又收到完成收尾后停止的明确请求。
- 已有Windows证据：早前原生Debug集成测试六格式、seek/暂停/坏文件恢复/20次交替切歌通过，windows-native-playback.png已查看；20秒默认WH-1000XM3输出回环检测440Hz，windows-loopback.json/wav。不冒充+5或Release截图。+4Release已启动且无障碍文本正常，窗口截图两次超时；不重复无效截图尝试。
- 工具链：Flutter3.47.8/Dart3.13.7；空格路径native hook用本地hooks_runner1.5.0副本受限修复，原配置备份.tools/backups，官方SDK ZIP不变，本地工具依赖已改，详见TOOLCHAIN。build先enforce-lockfile、再允许按模式重建注册文件、复核lockfile；Flutter检查/测试/构建串行。NTFS junction无需修改系统开发者模式。
- 原生许可：Windows mpv v0.36.0-403-g652a1dd907 / FFmpeg n6.0；Android mpv0.35.1-dirty / FFmpeg构建6.0；FFmpeg实际LGPL3+，禁GPL/nonfree。assets/licenses/native保留文本；历史Windows完整对应源码/静态子依赖通知、Android helper未固定提交是公开再分发前缺口，不能整体称MIT，详见THIRD_PARTY。
- 样本：6种24秒原创440Hz音和坏MP3，CC0，位于artifacts/R1/fixtures并已新增到手机Music/TagMusic-R1。用户已明确反馈样本子目录授权完成（不是体验全部通过）。真实目录1365首只属于先前读取观察，不等同R2持久入库。
- 恢复入口：docs/rounds/R1.md追加记录、docs/rounds/R1-ACCEPTANCE.md的7项清单、artifacts/R1/REPORT.md。先查看目标暂停状态并等待用户明确恢复。取得新批次交互确认后才能安装+5或操作电脑/手机，再复验Android元数据、六格式实际有声、seek/暂停、坏文件恢复、通知/锁屏、重启授权和至少30次切歌句柄；未通过不得进R2。Android10/Windows11仍无实机。
