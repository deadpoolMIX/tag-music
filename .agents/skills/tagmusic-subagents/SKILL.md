---
name: tagmusic-subagents
description: 用于 D:\.projects\Tag Musicplayer 的成果批次开发与按需协作。默认一个 developer 连续实现，批次交付前集中必要检查，优先交用户体验；普通问答不派发，不恢复暂停任务或替代设备授权。
---

# Tag Music 成果批次协作

仅用于解析后的`D:\.projects\Tag Musicplayer`及子目录，不改全局subagents。流程唯一依据[AGENTS](../../../AGENTS.md)；主协调目标/进度/授权/资源，默认一个developer连续实现并直接交main准备用户体验，反馈修复复用原执行者。主可直接维护流程文档。子Agent不再派发或联系其他聊天。

## 最小读取集合

主先恢复HANDOFF，派发时提供必要状态/授权摘要；子Agent不再默认读HANDOFF、整个阶段计划或本表所有链接。已在上下文且未变的规则不重读。仅缺必要事实或出现依赖/矛盾才定向补读。

| 角色/任务 | 读取 | 默认不读 |
|---|---|---|
| 主协调 | 本Skill；本批计划/状态及必要差异 | 全部角色正文、完整规格/原始日志 |
| 普通developer | AGENTS、本批需求/规格小节、相关代码/调用方；本Skill短交接 | roles、设备细则、完整HANDOFF/PLAN、历史/全套证据 |
| planner（确有待决） | 本批待决及[计划角色](references/roles.md#计划) | 已明确实现的重复规划/完整测试矩阵 |
| reviewer（按需） | 具体风险/差异及[审查角色](references/roles.md#独立验收与高风险审查)、对应原始证据 | 无关功能/全部报告 |
| command_runner（按需） | 明确命令包及[命令角色](references/roles.md#明确命令执行) | 整个实施计划/自行新增门禁 |
| 设备执行者 | 本批授权/操作；[设备共同要求](references/devices.md#设备批次共同要求)、采集规则及自身端小节 | 另一端细节/无关历史批次 |

## 配置与路由

[defaults.json](defaults.json)唯一保存请求配置，不是原生配置。主期望Luna/high由用户界面选择；无可信运行元数据时实际配置记“未验证”。指定配置/工具不可用须报告，不静默替换。新增岗位/Skill须用户授权。

| 工作 | 角色/配置键 |
|---|---|
| 明确小UI/文案/文档 | developer / simple；流程文档主可维护 |
| 页面组/功能链 | developer / normal |
| AGENTS列明高风险的实际变化 | developer / high_risk；需独立判断才加reviewer / high_risk |
| 具体技术/依赖待决 | planner / planner |
| 用户要求独立审查 | reviewer / acceptance；高风险或证据冲突用high_risk |
| 分担已有明确命令 | command_runner / command_runner；developer可自行执行，不强制交接 |
| 手机脚本/视觉；电脑GUI | phone_tester / phone_script或phone_visual；windows_tester / windows_gui；具体限制见设备细则 |

## 派发与资源约束

spawn显式`fork_turns: "none"`、model、reasoning_effort，task_name仅小写字母/数字/下划线。一次给目标、范围/路径所有权、必要入口@版本、本批差异、完成/验收条件、授权及资源；不灌完整聊天。

最多3个子Agent；仅有独立可并行实现、具体困难或明确风险才增派。写路径不重叠，Flutter全局串行，设备单控制者；换人/配置前确认旧执行者停写/释放，失联不等于释放。相关实现及修复优先复用；reviewer不得参与被审实现。

## 短交接

批次完成、需决策或异常时回：`交给=main；状态=实现完成；配置=无；输入=结果/差异入口@版本；注意=候选未构建、体验未测`。

配置表示接收方档位（见上表，main=无），来源核实际句柄。附必要的完成/剩余、检查/未测、候选及运行依据、入口和缺口；长批次有实质产品进展时简短更新，不逐小步交接。开发/命令/设备结果可直接回main，不默认planner/reviewer；需修复优先原执行者。

缺输入/版本不符不盲转；需授权/解锁/用户决策停相关操作。状态可用就绪/实现完成/候选就绪/检查完成/审查通过/失败/阻塞；仅实际所审范围可称审查通过，未启动不称已运行，所有完成标记都不代替用户验收。普通交接不建卡片文件，详细证据确需保存才存一次并引用。
