# 架构与长期接口

仅定位实现、修改相关接口时读对应小节，不是恢复必读材料。

## 架构与代码定位

Flutter + Material 3 共用 UI/业务，Riverpod 组织状态，Drift/SQLite 存曲库，media_kit 播放，Android Kotlin/SAF 与 audio_service 接入平台。首版两端数据独立。下表是现有实现，不能据目录名推断后续功能已完成。

| 职责 | 代码入口 / 符号 | 相关验证 |
|---|---|---|
| 初始化、导航、设置 | [main.dart](../lib/main.dart)、[app.dart](../lib/app.dart)、[core/](../lib/core/)；R6 已实现七入口壳层与页面状态保留 | `app_test`、`settings_test`、集成 `smoke_test`；当前R6进度见[当轮计划](rounds/R6.md) |
| 数据表、连接、迁移 | [database.dart](../lib/library/database.dart) / `LibraryDatabase`；`database.g.dart` 为生成文件 | `library_test`、`tag_test`、`playlist_test`、[schema v4 DDL](database-schema/v4.json) |
| 扫描事务、增量/失联、搜索排序 | [library_controller.dart](../lib/library/library_controller.dart) / `LibraryController`；R6 新增独立全库搜索和修改时间排序，兼容要求见[R6 §2B/2C](rounds/R6-SPEC.md#2b公共排序与持久兼容) | 单元/集成 `library_test`、`r6_library_sort_test`、`library_search_test`；R6状态见[当轮计划](rounds/R6.md) |
| 曲库 UI、共享歌曲行、封面、输入连接 | [library_page.dart](../lib/library/library_page.dart)、[song_list.dart](../lib/library/song_list.dart)、[library_search_page.dart](../lib/library/library_search_page.dart)、[library_search.dart](../lib/library/library_search.dart)、[track_cover.dart](../lib/library/track_cover.dart)；R6顺序2仍未验收 | `test/library_page_test.dart`、`r6_song_list_test`、`library_search_test`；真机输入另需当批授权 |
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
