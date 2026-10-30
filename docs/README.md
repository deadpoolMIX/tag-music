# 项目索引

先读 [当前交接](HANDOFF.md)，从其链接恢复当前工作。本页是导航，不要求整页读取；当前阶段、版本和阻塞只在交接维护。

## 按任务读取

| 当前需要 | 读取范围 |
|---|---|
| 继续已确认任务 | HANDOFF 指向的当前计划小节、待办及相关代码/测试 |
| 新阶段规划、产品行为决策 | [PLAN](PLAN.md) 对应目标/语义/验收章节，不读历史轮次 |
| 定位实现、修改公共接口 | 本页模块表及涉及的长期接口；沿调用关系补读依赖 |
| 构建、测试、平台或许可问题 | 本页验证入口，再按需读 TOOLCHAIN/THIRD_PARTY 和指定证据 |
| 排查历史问题 | 交接指向的具体记录/证据；只有需要时才扩大范围 |
| 用户要求交接 | 更新同一份 HANDOFF；不用另建聊天总结文件 |

文档边界：用户当前指令优先；AGENTS 定协作流程，PLAN 定产品目标，HANDOFF 定当前状态，原始记录证明过去发生过什么。发现不一致先核实，不让历史状态覆盖当前结论。

## 架构与代码定位

Flutter + Material 3 共用 UI/业务，Riverpod 组织状态，Drift/SQLite 存曲库，media_kit 播放，Android Kotlin/SAF 与 audio_service 接入平台。首版两端数据独立。下表是现有实现，不能据目录名推断后续功能已完成。

| 职责 | 代码入口 / 符号 | 相关验证 |
|---|---|---|
| 初始化、导航、设置 | [main.dart](../lib/main.dart)、[app.dart](../lib/app.dart)、[core/](../lib/core/) | `app_test`、`settings_test`、集成 `smoke_test` |
| 数据表、连接、迁移 | [database.dart](../lib/library/database.dart) / `LibraryDatabase`；`database.g.dart` 为生成文件 | `test/library_test.dart`、[schema v1 DDL](database-schema/v1.json) |
| 扫描事务、增量/失联、搜索排序 | [library_controller.dart](../lib/library/library_controller.dart) / `LibraryController` | 单元/集成 `library_test` |
| 曲库 UI、封面、输入连接 | [library_page.dart](../lib/library/library_page.dart)、[library_search.dart](../lib/library/library_search.dart) | `test/library_page_test.dart`、真机输入 |
| 播放、串行切换、媒体会话 | [playback_controller.dart](../lib/playback/playback_controller.dart) / `PlaybackController`、`TagAudioHandler`；[playback_page.dart](../lib/playback/playback_page.dart) 组装曲库 UI | `audio_handler_test`、集成 `playback_test` |
| 共用文件/元数据/FD 适配 | [documents.dart](../lib/playback/documents.dart) / `DocumentAccess`；[descriptor_file.dart](../lib/playback/descriptor_file.dart) | `documents_test`、`descriptor_file_test` |
| Android 原生桥 | [DocumentBridge.kt](../android/app/src/main/kotlin/app/tagmusic/player/DocumentBridge.kt)、[MainActivity.kt](../android/app/src/main/kotlin/app/tagmusic/player/MainActivity.kt) | 桥测试 + 真机日志/媒体会话 |
| Windows 壳、工程工具 | [windows/runner/](../windows/runner/)、[scripts/](../scripts/)、[diagnostics.dart](../lib/core/diagnostics.dart) | 原生集成、Release 运行、输出回环分列 |

定位用 `rg --files lib test integration_test`、`rg -n 'playSnapshot|LibraryController' lib test integration_test -g '!*.g.dart'`，再查 import/调用方。默认不扫生成代码、build、artifacts、SDK。`DocumentAccess` 虽在 playback 目录，已由曲库复用，不另写第二套平台访问；页面只做输入/展示与组装，不新增 SQL/FD 管理。当前跨模块 UI 组装不为整理而搬迁。

## 长期有效的接口与约束

- 产品完整语义见 [PLAN §1～2](PLAN.md#2-技术结构与关键行为)。音乐只读、标签仅入库；Android 保留 SAF URI/授权，不转真实路径；Windows 仅软件内操作和后台播放，不做 SMTC、系统媒体键、托盘播放按钮。
- **曲库已实现**：`Songs.id` 是 UUID，根目录/`SongLocations` 关联位置。重叠根目录按位置去重，异位置同内容不合并；单根完整成功才事务提交，取消/授权失败保留旧数据，失联/重现保持 UUID。后续标签/歌单用歌曲 ID，不能把路径当永久 ID。
- **迁移已开始**：R3 当前 schema v2，v1→v2 显式创建标签及关系表；未知升级抛错。变表即升版本并验证旧库数据、外键及失败处理。[v1.json](database-schema/v1.json) 和 [v2.json](database-schema/v2.json) 是实际 SQLite DDL 基线，不覆盖，也不是 Drift CLI schema JSON。
- **资源生命周期已实现**：切歌/通知操作串行，停止旧曲后关闭应用持有的播放 FD 再开新曲；元数据只读借用 FD、finally 释放，不靠 GC。业务万首队列只为当前与有限预取建立播放对象/句柄。
- **R2→R5 边界**：点击播放是不可变快照，搜索/扫描不改播放；当前 `ProbeTrack` 仍用 location/name，R5 要接稳定歌曲 ID 后做持久队列/进度恢复，重启默认暂停。
- **R3 开发中**：扁平多标签与歌曲 UUID 关系已接入，是否验收见 HANDOFF。R4 版本化规则树及删标签影响、R5 普通/智能歌单和队列、R8 版本化管理数据备份/整体回滚仍属未来接口。
- 固定 ID/签名、锁定依赖、本机受限补丁见 [TOOLCHAIN](TOOLCHAIN.md)；实际原生库与再分发来源缺口见 [THIRD_PARTY](THIRD_PARTY.md)。相关变更即核对，不等 R9 从零处理。

## 验证入口与维护

- `& ./scripts/check.ps1 -Round R3`（PowerShell 7）：依赖恢复、格式、analyze、全套单元/widget；不含原生集成、双端构建、手机验收。R3 准备曲库样本及万首合成标签基准，不代表手机/真实万首文件。
- 候选参数：`scripts/build.ps1 -Target all -BuildNumber <新构建号> -Round <当前阶段>`；`verify-apk.ps1` 显式传 `-Version/-BuildNumbers/-Round`；`verify-packages.py` 传 `--version/--build/--round`，当前音频基线另传 `--native-reference-round R1`。示意值须取实际 pubspec/交接。
- 手动 Flutter 先 `. ./scripts/env.ps1`，再 `& ./scripts/restore.ps1 -Round R3`。所有 Flutter 检查/测试/构建串行，避免共享注册文件互改。按模块表先做相关回归，候选/阶段收口完整验证，具体门禁见 [PLAN §4](PLAN.md#4-验证与质量门禁)。
- 现有 check 在 R1～R3 按阶段准备样本，SQLite 包审计分支在 R2/R3 启用；后续阶段 Plan 要先核对覆盖，不能把 skip 当通过。脚本默认参数及 Android 播放/卡片脚本仍有 R1 路径/样本假设，使用前核对，显式传当前参数。
- 固定日志名重跑前保留旧失败证据到同轮构建号/问题子目录，候选不复用构建号覆盖。`install-android.ps1` 还会启动应用与抓日志，须取得涵盖这些操作的本批交互确认。
- 仅文档改动验 diff、链接/事实/改动范围，不重建应用。改公共接口先查调用方/已有实现并验证，避免重复功能或闲置抽象。临时修复记录原因、范围、验证与撤除条件；改模块/接口/命令同步对应长期文档。

## 文档各司其职

| 文档 | 职责 / 读取时机 |
|---|---|
| [AGENTS](../AGENTS.md) | 协作、阶段/Goal、验证责任、失败与交接规则 |
| 本索引 | 架构/模块/长期接口，按上述任务路由读取 |
| [PLAN](PLAN.md) | 产品边界、R0～R9 及跨阶段验证；阶段启动/相关规则时读 |
| [HANDOFF](HANDOFF.md) | 唯一当前快照，每次结束/中断前更新，不堆旧状态 |
| `rounds/Rxx.md` / `Rxx-ACCEPTANCE.md` | 顶部为当前计划；下方追加证据，另附5～8项手机清单；历史按依赖读 |
| [开发日志](开发日志.md) | 给人看的已完成摘要，不作恢复依据、不默认通读 |
| [TOOLCHAIN](TOOLCHAIN.md) / [THIRD_PARTY](THIRD_PARTY.md) | 环境/补丁及许可，相关任务读 |
| [原始计划](archive/PLAN.original.md) | 原件保留，仅溯源时读 |

历史入口（非必读）：[R0](rounds/R0.md)/[验收](rounds/R0-ACCEPTANCE.md)、[R1](rounds/R1.md)/[验收](rounds/R1-ACCEPTANCE.md)、[R2](rounds/R2.md)/[验收](rounds/R2-ACCEPTANCE.md)；当前 [R3](rounds/R3.md)/[验收](rounds/R3-ACCEPTANCE.md)。历史旧路径按本索引/Git 定位，不改写原始失败记录。
