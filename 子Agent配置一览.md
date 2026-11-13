# 子 Agent 配置一览（仅供用户查阅）

> 本文是给用户看的展示快照，不是模型工作指令、恢复入口或配置来源。模型默认不读取；仅用户明确要求查看或更新本文时读取。

配置快照时间：2026-11-14 00:21（北京时间）。

以下是角色与执行档位，不代表这些子Agent当前正在运行；同一developer可按任务使用不同档位。

| 名称 | 角色 | 配置键 | 任务 | 模型 | 思考档位 |
|---|---|---|---|---|---|
| 计划助手 | `planner` | `planner` | 仅在目标/依赖待决、拆分或技术困难时协助规划；已有明确计划不重复调用 | `gpt-6.1-sol` | `medium` |
| 开发助手：明确小改 | `developer` | `simple` | 位置、做法、结果都明确的文案或机械小改，无需业务判断 | `gpt-6-luna` | `high` |
| 开发助手：普通开发 | `developer` | `normal` | 规格明确的页面、相似页面组、已有结构复用及局部修复；普通开发默认 | `gpt-6.1-terra` | `medium` |
| 开发助手：复杂交互 | `developer` | `complex` | 影响范围清楚，但局部状态或交互需要更多推敲 | `gpt-6.1-terra` | `high` |
| 开发助手：复杂业务/高风险 | `developer` | `high_risk` | 复杂依赖、业务链，或数据迁移、持久身份、SAF、播放并发等实际风险变化 | `gpt-6.1-sol` | `medium` |
| 命令执行助手 | `command_runner` | `command_runner` | 分担已有明确命令，记录退出码与原始输出；不自行新增检查任务 | `gpt-6-luna` | `high` |
| 审查助手：普通独立审查 | `reviewer` | `acceptance` | 按用户要求独立审查指定范围；普通开发不默认安排 | `gpt-6.1-terra` | `high` |
| 审查助手：具体风险/证据冲突 | `reviewer` | `high_risk` | 需要独立判断的明确风险或关键证据冲突；不自动扩大范围 | `gpt-6.1-sol` | `medium` |
| 手机测试助手：明确脚本 | `phone_tester` | `phone_script` | 在当批授权范围内执行明确ADB脚本与断言；人工测试只读观察 | `gpt-6-luna` | `high` |
| 手机测试助手：视觉操作 | `phone_tester` | `phone_visual` | 在当批授权范围内处理复杂手机界面定位和操作 | `gpt-6.1-terra` | `high` |
| 电脑测试助手 | `windows_tester` | `windows_gui` | 在当批授权范围内通过Windows MCP操作电脑界面；人工测试不代输入 | `gpt-6.1-terra` | `high` |
| 共同例外档（不是新角色） | `developer / planner / reviewer` | `sol_high` | 仅有具体未解决难点、现有证据和升档理由时由主Agent决定启用；不因高风险标签或一次失败自动升级 | `gpt-6.1-sol` | `high` |

主Agent按整批任务决定分配，普通开发默认一个developer连续负责，不按表中所有角色建立流水线。表内模型是请求配置，不代表已验证每个执行者的实际模型。

配置与路由以[defaults.json](.agents/skills/tagmusic-subagents/defaults.json)及[协作Skill](.agents/skills/tagmusic-subagents/SKILL.md)为准；本展示表不触发额外角色、测试、审查或设备操作。
