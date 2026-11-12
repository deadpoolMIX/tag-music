# 项目索引

先读 [当前交接](HANDOFF.md)，从其链接恢复当前工作。本页是导航，不要求整页读取；当前阶段、版本和阻塞只在交接维护。

## 按任务读取

| 当前需要 | 读取范围 |
|---|---|
| 继续已确认任务 | HANDOFF 指向的当前计划小节、待办及相关代码/测试 |
| 新阶段规划、产品行为决策 | [PLAN](PLAN.md) 对应目标/语义/验收章节，不读历史轮次 |
| 定位实现、修改公共接口 | 本页模块表及涉及的长期接口；沿调用关系补读依赖 |
| 构建、测试、平台或许可问题 | 本页验证入口，再按需读 TOOLCHAIN/THIRD_PARTY 和指定证据 |
| 追溯 R4 流程优化依据 | [本窗口省 token 复盘](rounds/R4-TOKEN-REVIEW.md)，现行规则见 AGENTS |
| 排查历史问题 | 交接指向的具体记录/证据；只有需要时才扩大范围 |
| 用户要求交接 | 更新同一份 HANDOFF；不用另建聊天总结文件 |
| 子 Agent 协作与减少主上下文读取 | [协作 Skill](../.agents/skills/tagmusic-subagents/SKILL.md)、[短交接协议](../.agents/skills/tagmusic-subagents/references/handoff.md)；主只读固定路由段，角色只读自身边界 |

文档边界：用户当前指令优先；AGENTS 定协作流程，PLAN 定产品目标，HANDOFF 定当前状态，原始记录证明过去发生过什么。发现不一致先核实，不让历史状态覆盖当前结论。

## 架构与代码定位

Flutter + Material 3 共用 UI/业务，Riverpod 组织状态，Drift/SQLite 存曲库，media_kit 播放，Android Kotlin/SAF 与 audio_service 接入平台。首版两端数据独立。下表是现有实现，不能据目录名推断后续功能已完成。

| 职责 | 代码入口 / 符号 | 相关验证 |
|---|---|---|
| 初始化、导航、设置 | [main.dart](../lib/main.dart)、[app.dart](../lib/app.dart)、[core/](../lib/core/) | `app_test`、`settings_test`、集成 `smoke_test` |
| 数据表、连接、迁移 | [database.dart](../lib/library/database.dart) / `LibraryDatabase`；`database.g.dart` 为生成文件 | `library_test`、`tag_test`、`playlist_test`、[schema v4 DDL](database-schema/v4.json) |
| 扫描事务、增量/失联、搜索排序 | [library_controller.dart](../lib/library/library_controller.dart) / `LibraryController` | 单元/集成 `library_test` |
| 曲库 UI、封面、输入连接 | [library_page.dart](../lib/library/library_page.dart)、[library_search.dart](../lib/library/library_search.dart) | `test/library_page_test.dart`、真机输入 |
| 标签关系与管理、多选操作 | [tag_repository.dart](../lib/library/tag_repository.dart)、[tags_page.dart](../lib/library/tags_page.dart)；曲库controller共用DB及状态 | `tag_test`、`tags_page_test`、设备 `tag_benchmark_test` |
| 三框组合筛选、当前规则保留 | [filter_rule.dart](../lib/library/filter_rule.dart)、[filter_repository.dart](../lib/library/filter_repository.dart)、[filter_page.dart](../lib/library/filter_page.dart)；LibraryController复用曲库/标签数据 | `filter_test`、`filter_page_test`、双端 `filter_benchmark_test` |
| 普通歌单存储、编辑、列表/队列保存 | [playlist_repository.dart](../lib/library/playlist_repository.dart)、[playlists_page.dart](../lib/library/playlists_page.dart)、[playlist_actions.dart](../lib/library/playlist_actions.dart)；LibraryController共用DB与曲库UUID | `playlist_test`、`playlists_page_test` |
| 智能规则、动态结果、删标签预览/联动 | `PlaylistRepository.createSmart/editSmart/preferences`、[smart_playlist_editor.dart](../lib/library/smart_playlist_editor.dart)、[rule_editor.dart](../lib/library/rule_editor.dart)；复用上述歌单页、TagRepository和LibraryController | `smart_playlist_test`、`smart_playlist_page_test`、`filter_page_test` |
| 播放、串行切换、媒体会话 | [playback_controller.dart](../lib/playback/playback_controller.dart) / `PlaybackController`、`TagAudioHandler`；[playback_page.dart](../lib/playback/playback_page.dart) 组装曲库 UI | `audio_handler_test`、`playback_semantics_test`（Windows进度条启用转换）、集成 `playback_test` |
| 临时队列、优先待播、四模式与随机历史 | [playback_queue.dart](../lib/playback/playback_queue.dart) / `PlaybackQueue`、`QueueSong`、`QueueEntry`；[queue_page.dart](../lib/playback/queue_page.dart) 完整队列/模式/共用播放控件，[queue_actions.dart](../lib/playback/queue_actions.dart) 各来源追加入口；播放控制器共用串行链 | `playback_queue_test`、`queue_playback_test`、`queue_page_test`；实际设备证据按HANDOFF |
| 共用文件/元数据/FD 适配 | [documents.dart](../lib/playback/documents.dart) / `DocumentAccess`；[descriptor_file.dart](../lib/playback/descriptor_file.dart) | `documents_test`、`descriptor_file_test` |
| Android 原生桥 | [DocumentBridge.kt](../android/app/src/main/kotlin/app/tagmusic/player/DocumentBridge.kt)、[MainActivity.kt](../android/app/src/main/kotlin/app/tagmusic/player/MainActivity.kt) | 桥测试 + 真机日志/媒体会话 |
| Windows 壳、工程工具 | [windows/runner/](../windows/runner/)、[scripts/](../scripts/)、[diagnostics.dart](../lib/core/diagnostics.dart) | 原生集成、Release 运行、输出回环分列 |

定位用 `rg --files lib test integration_test`、`rg -n 'playSongs|LibraryController' lib test integration_test -g '!*.g.dart'`，再查 import/调用方。默认不扫生成代码、build、artifacts、SDK。`DocumentAccess` 虽在 playback 目录，已由曲库复用，不另写第二套平台访问；页面只做输入/展示与组装，不新增 SQL/FD 管理。当前跨模块 UI 组装不为整理而搬迁。

## 长期有效的接口与约束

- 产品完整语义见 [PLAN §1～2](PLAN.md#2-技术结构与关键行为)。音乐只读、标签仅入库；Android 保留 SAF URI/授权，不转真实路径；Windows 仅软件内操作和后台播放，不做 SMTC、系统媒体键、托盘播放按钮。
- **曲库已实现**：`Songs.id` 是 UUID，根目录/`SongLocations` 关联位置。重叠根目录按位置去重，异位置同内容不合并；单根完整成功才事务提交，取消/授权失败保留旧数据，失联/重现保持 UUID。后续标签/歌单用歌曲 ID，不能把路径当永久 ID。
- **数据库迁移**：当前schema v4；v1/v2/v3直接升v4，在同一事务补齐标签/当前筛选/歌单表，失败回滚，未知升级抛错。变表即升版本并验证旧库数据、外键及中途失败。[v1.json](database-schema/v1.json)、[v2.json](database-schema/v2.json)、[v3.json](database-schema/v3.json)、[v4.json](database-schema/v4.json)是实际SQLite DDL基线，不覆盖，也不是Drift CLI schema JSON。
- **普通歌单接口**：`PlaylistRepository.create/add/remove/reorder/rename/delete`与`LibraryController`对应封装；歌曲UUID去重保留首次顺序，失联关联保留，成员/排序事务改写。名称trim/小写键跨两类唯一，`PlaylistSongs`保存普通歌曲及顺序；不保存队列。界面列表/完整队列保存先固定源快照，搜索中不重排，播放复用`playSongs`。
- **智能歌单接口**：`createSmart/editSmart`事务保存版本化`FilterRule`及排序/方向，检查标签存在；`preferences`严格解码，未知版本或排序不降级。`LibraryController.playlistTracks`对智能种类按最新可用曲库/标签重算排序，不保存搜索词和固定成员；共用`RuleEditor`，草稿不改当前筛选。损坏规则须明确确认重建，保存才替换。
- **删标签联动**：`tagDeletionEffects`预览当前筛选及全部受影响智能歌单的框和可用数量变化；任一规则无法读取时阻止预览/删除。`TagRepository.delete`在同一事务清标签/关联、当前规则和全部智能引用；末项失败全部回滚。Controller先等当前筛选写完，事务后一起发布标签与歌单，已有播放快照不变。
- **资源生命周期已实现**：切歌/通知操作串行，停止旧曲后关闭应用持有的播放 FD 再开新曲；元数据只读借用 FD、finally 释放，不靠 GC。业务万首队列只为当前与有限预取建立播放对象/句柄。
- **R5播放接口**：`playSongs(List<QueueSong>, target)`接收歌曲UUID及文件信息快照，每个`QueueEntry`另有UUID；来源变更不改队列。`LibraryController.resolveSong`在打开前按歌曲UUID取有效位置；`ProbeTrack`仅作文件访问对象。旧`playSnapshot`已移除，目录技术探测仍使用独立transient locator，不能作为业务身份。
- **R5状态边界**：优先待播只消费一次、完整条目保留；四种互斥模式共用状态机。2026-11-02用户取消队列/进度恢复，冷启动空队列、默认随机、不出声。歌单存储及阶段进度见[R5计划](rounds/R5.md#r5-当前执行计划)和HANDOFF。
- **队列界面接口**：空队列也可打开完整列表和模式选择；条目按独立ID显示/点播/移除，`selectEntry(entryId)`在串行执行时定位，陈旧ID不点错歌曲。追加默认FIFO，手动拖动可改变队列及待播相对顺序，随机本轮顺序不重洗；清空须确认，保存完整队列按显示顺序首次去重。`QueueAddButton`固定按下时的来源快照，只添加可用歌曲；曲库/普通歌单多选含跨搜索项并保持来源排序，添加不切换当前歌曲。
- **标签已实现**：扁平多标签引用歌曲UUID，名称trim/小写唯一键；批量关系事务、删除级联与数量确认，多选按UUID跨搜索保留，不改变播放快照；R3验收见[R3验收记录](rounds/R3-ACCEPTANCE.md)。R4新增版本化三框配置及删除标签时事务移除规则引用；R5歌单按当前计划演进，R8备份/整体回滚仍为后续阶段。
- 固定 ID/签名、锁定依赖、本机受限补丁见 [TOOLCHAIN](TOOLCHAIN.md)；实际原生库与再分发来源缺口见 [THIRD_PARTY](THIRD_PARTY.md)。相关变更即核对，不等 R9 从零处理。

## 验证入口与维护

- `& ./scripts/check.ps1 -Round R5`（PowerShell 7）：依赖恢复、格式、analyze、全套单元/widget及7项Python报告审计测试；准备真实合成音频/封面样本，并输出曲库/标签/筛选/队列主机基准。不含原生集成、双端构建、手机验收，不代表真实万首文件或设备Release性能。
- 候选参数：`scripts/build.ps1 -Target all -BuildNumber <新构建号> -Round <当前阶段>`；`verify-apk.ps1` 显式传 `-Version/-BuildNumbers/-Round`；`verify-packages.py` 传 `--version/--build/--round`，当前音频基线另传 `--native-reference-round R1`。隔离性能包用同一审计入口另传`--android-archive <APK> --windows-archive <ZIP> --output <新审计.json>`；报告拒绝覆盖，SQLite剥离复核文件按构建号区分。须在下一次Android构建覆盖merged原生输入前审计本批包。示意值须取实际 pubspec/交接。
- 手动 Flutter 先 `. ./scripts/env.ps1`，再 `& ./scripts/restore.ps1 -Round R5`。所有 Flutter 检查/测试/构建串行，避免共享注册文件互改。按模块表先做相关回归，候选/阶段收口完整验证，具体门禁见 [PLAN §4](PLAN.md#4-验证与质量门禁)。
- check在R1～R6按阶段准备样本，SQLite包审计分支在R2～R6启用；R6的固定封面/LRC、性能采样契约及未测边界见[R6顺序1](rounds/R6.md#七顺序1固定样本与测量入口2026-11-12)。后续阶段Plan先核对覆盖，不能把skip当通过。脚本默认参数及Android播放/卡片脚本仍有R1路径/样本假设，使用前核对，显式传当前参数。
- 固定日志名重跑前保留旧失败证据到同轮构建号/问题子目录，候选不复用构建号覆盖。`install-android.ps1` 还会启动应用与抓日志，须取得涵盖这些操作的本批交互确认。
- 独立设备性能包（R3标签/R4三框）：`& ./scripts/build-filter-benchmark.ps1 -Target all -BenchmarkBuildNumber <新测试编号>`，双端Release模式；Android独立ID `app.tagmusic.player.benchmark`、临时合成库，Windows单列打包并内置JSON报告出口；脚本只构建审计，不安装运行。正式APK安装从artifacts取包，不能从最新build/app输出推定候选身份。R4使用`integration_test/filter_benchmark_test.dart`，报告实际规则重算/搜索排序，初次加载单列，不计真实文件扫描或UI渲染。Android完整分段日志用 `python scripts/audit-filter-benchmark.py <本批日志> --report <新报告.json> --audit <新审计.json>` 恢复并复核六场景；缺段/重复/截断拒绝，勿用摘要替代原始数据。
- R5隔离性能入口：[build-queue-benchmark.ps1](../scripts/build-queue-benchmark.ps1)的`-Target all -BenchmarkBuildNumber <新编号>`只构建，复用独立Android ID并写入构建号/revision；Windows单列ZIP和报告路径，运行须当批授权。[queue_benchmark_test.dart](../integration_test/queue_benchmark_test.dart)共用[test/support/queue_benchmark.dart](../test/support/queue_benchmark.dart)，10000条目替换/批量加/删当前与非当前/反向重排/切入随机及跨轮构建各5次预热+20样本，逐次校验成员/独立ID/当前/FIFO；只计状态机操作，排除准备、校验、UI和播放FD。普通歌单11000输入去重为10000的保存/加载含事务等待、另计，不套队列阈值。
- R5报告用[审计脚本](../scripts/audit-queue-benchmark.py)校验：`python scripts/audit-queue-benchmark.py <本批源文件> --input-format log --platform android --build <编号> --revision <包内revision> --report <新完整报告.json> --audit <新审计.json>`；Windows原始JSON用`--input-format json --platform windows`。默认要求Release身份；主机调试结果须显式`--mode debug --build 0 --revision host-test`，不冒充设备通过。源/报告/审计必须不同，输出文件必须未存在；共用[分段恢复器](../scripts/benchmark_report.py)拒绝缺段/重复/乱序/截断，独立复算数量、顺序校验值和P95；实际逐次完整成员断言在包内。报告审计故障注入在[scripts/test_benchmark_audits.py](../scripts/test_benchmark_audits.py)。
- 仅文档改动验 diff、链接/事实/改动范围，不重建应用。改公共接口先查调用方/已有实现并验证，避免重复功能或闲置抽象。临时修复记录原因、范围、验证与撤除条件；改模块/接口/命令同步对应长期文档。

## 文档各司其职

| 文档 | 职责 / 读取时机 |
|---|---|
| [AGENTS](../AGENTS.md) | 协作、阶段/Goal、验证责任、失败与交接规则 |
| 本索引 | 架构/模块/长期接口，按上述任务路由读取 |
| [PLAN](PLAN.md) | 产品边界、R0～R9 及跨阶段验证；阶段启动/相关规则时读 |
| [HANDOFF](HANDOFF.md) | 唯一当前状态和入口，每次结束/中断前更新；详细验收结论引用验收记录 |
| `rounds/Rxx.md` / `Rxx-ACCEPTANCE.md` | 当轮计划及技术记录 / 详细验收结论与证据索引；手机清单5～8项，历史按依赖读 |
| [开发日志](开发日志.md) | 每次收口一句已完成摘要，不作恢复依据、不默认通读 |
| [TOOLCHAIN](TOOLCHAIN.md) / [THIRD_PARTY](THIRD_PARTY.md) | 环境/补丁及许可，相关任务读 |
| [原始计划](archive/PLAN.original.md) | 原件保留，仅溯源时读 |

历史入口（非必读）：[R0](rounds/R0.md)/[验收](rounds/R0-ACCEPTANCE.md)、[R1](rounds/R1.md)/[验收](rounds/R1-ACCEPTANCE.md)、[R2](rounds/R2.md)/[验收](rounds/R2-ACCEPTANCE.md)、[R3](rounds/R3.md)/[验收](rounds/R3-ACCEPTANCE.md)、[R4](rounds/R4.md)/[验收](rounds/R4-ACCEPTANCE.md)；[R5](rounds/R5.md)/[验收记录](rounds/R5-ACCEPTANCE.md)。历史旧路径按本索引/Git定位，不改写原始失败记录。

当前阶段入口：[R6：日常界面重构、LRC 歌词与睡眠定时](rounds/R6.md)，状态与授权以HANDOFF为准。
