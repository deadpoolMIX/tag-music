# 当前交接

更新：2026-10-30 13:07 北京时间。**R2 开发中**。R1 已双端通过（0.2.0+9）；本对话仅推进R2本地音乐库。R2候选0.3.0+10完成双端自动检查、构建和本批设备验证，但用户发现Android搜索框不能弹输入法/粘贴，**未通过验收**。0.3.0+11输入修复候选已双端构建和包审计通过，等待新批次设备确认；未进R3。

## 源码、版本与产物

- 应用源码本地提交38564fe（2026-10-30 13:03），当前pubspec 0.3.0+11。+10/+11包内revision仍为构建时3ac86b6-dirty，不改写成后来的提交号。提交前检查无密钥/产物；无远程仓库。
- +10 APK：artifacts/R2/tag-music-0.3.0+10.apk，SHA256 07fe5ff6c3cf17ead523226d77cddf300cce0c4aad7a7edfe10f541a49cf6a6d。
- +10 Windows ZIP：artifacts/R2/tag-music-windows-0.3.0+10.zip，SHA256 481f1fd951f1b46723f99f0d06d8319e0ffd40aad94a98bbb09056613cfdf48e。
- +11双端构建/签名/包审计完成（build-all-11.json、package-audit-11.json、verify-apk-11.log）；APK SHA256 593118cf8b6909e6b7fedd29c1151c2a01c9abe7ce5a74ea0fb0211cebbfe6d3，Windows ZIP SHA256 3a715da8351621f9213e7ed8e37172cb81812cf99a4e50ef6a2747ef092cc733。37项运行源码匹配source-manifest-11.json，source-comparison-11.txt；AOT包含新输入诊断标记runtime-markers-11.json。不能把+10手机结果冒充+11通过。
- 手机已原签名覆盖安装+10，固定ID app.tagmusic.player，首次安装时间2026-10-29 20:14:50不变，深色与R1两个目录授权保留，新增用户授权Download/TagMusic-R2。手机当前16首。+11未安装。

## R2 已实施

- Drift/SQLite schema v1，UUID歌曲与多根目录位置关联；Windows规范化路径/Android provider document ID去重，重叠根目录不重复；相同音频在不同位置保留不同记录。
- 可取消递归扫描、按大小/修改时间增量读取、坏文件隔离；按根目录完整扫描后事务提交，取消/失败保留旧数据；失联保留及原位置恢复。
- 曲库搜索/四种排序/升降序/失联过滤，当前歌曲内嵌封面按需读取/96px解码缓存；播放使用独立不可变快照，不随搜索或扫描变化。Android搜索在+10真机失败，不能称完整可用。
- R1目录书签迁入数据库，首次手动扫描建立曲库，之后启动读取持久库且不自动播放。没有R5队列/进度恢复，也没有R3标签/R4规则/歌单。

## 检查与运行证据

- 格式、analyze --fatal-infos、31项测试通过（check-release.log、check-11.log）。包含UUID/重叠/增量/取消/失败保留/事务回滚/失联/重开/真实六格式只读/坏文件/封面/SAF游标finally及小屏搜索快照。schema v1实际SQLite DDL基线docs/database-schema/v1.json，并验证user_version/外键/基线。独立Dart CLI schema导出遇空格路径hook问题，未扩大SDK补丁。
- library-benchmark.json：一万首合成Windows数据库的搜索排序P95约28ms；真实文件扫描另测，不能当一万真实文件或手机性能。SQL绑定实际包sqlite3 3.5.2，包内引擎3.53.4。
- +10双端release、同证书/ID/API29、音频原生库R1基线/8许可文本、SQLite官方原件哈希及独立NDK strip变换审计通过。package-audit-10.json、upgrade-certificate.json、source-manifest-10.json。Windows原生Debug测试会重新生成模式专用GeneratedPluginRegistrant.java，不把这个自动文件误认为应用源码改变。
- Windows+10原生Debug集成通过9个真实位置/重叠/增量/封面/搜索不改9曲快照/数据库重开，截图windows10/windows-library.png已查看；12秒默认WH-1000XM3输出回环12/12秒检测440Hz，output-loopback.json/wav。测试进程已退出。R1已知Release完整UI播放/截图工具限制保留，本轮没有反复重试该失败路径。
- Android+10：旧目录无需新授权恢复7首、新目录9首，总16；重复9首扫描只重读坏文件1首。实际封面/中文媒体会话PLAYING/非零进度。进程重启PID变化后16首保留、NONE且不播放。仅改本批测试WAV扩展名后失联记录保留，隐藏失联15/16，复原恢复16；9个文件SHA256不变。Music扫描截图已读591首时取消，旧16首保留。phone-*.json、XML、截图、android-10-final.log。

## 用户反馈、失败与下一步

- 用户明确反馈+10不能弹输入法、不能粘贴，搜索验收失败；其他已测试项目正常。完整记录docs/rounds/R2.md；手机清单docs/rounds/R2-ACCEPTANCE.md。不能把“其他正常”扩为搜索通过或搜索期间播放通过。
- 两次自动输入失败后已报告并停重试，用户手测也失败；同一问题计数不因+11清零。**后续搜索复验由用户手测**，助手分析修复/安装抓日志。+11已有独立状态搜索框/显式controller和focus/search动作/清空按钮/输入诊断；widget真正tap连接及键盘缩小时连接保持通过，但尚无真机修复结论。
- 本批+10设备输入已结束，电脑/手机可正常使用，无测试/采集/播放任务运行。新安装/前台运行/手机输入批次必须再次交互确认；本轮用户尚未授权+11设备操作。后台编辑/检查/构建可继续。
- 下一步：经新批次交互确认覆盖+11并运行相关Windows回归，手机搜索只给用户简短步骤（弹键盘、flac 3/16、无结果、粘贴/清空、播放中搜索），由用户反馈后判定。若仍失败，继续日志定位，禁止自动重复同一搜索测试。
- 保留边界：授权撤销真机、其他设备/Android10/Windows11、手机一万首性能及Release完整UI验证尚未执行。音频LGPL完整对应源码/子依赖通知的公开再分发缺口仍留R9，见THIRD_PARTY。R2未验收，不进入R3。

## 13:07 候选保全复核

37项运行源码和+11双端包SHA256仍与构建快照一致，工作区干净，未发现Windows测试进程。上一批已结束，新+11交互确认仍未收到明确答复；未安装、未启动前台应用、未输入手机，不把自动目标续行当设备授权。下一步仍为确认该批操作后安装并由用户手测搜索。
