# 文档索引

恢复先读[当前交接](HANDOFF.md)。本页只定位，不要求读完所有链接；按任务选择一个入口，再定位小节，不递归通读。

## 按任务读取

| 任务 | 最小入口；扩大读取的条件 |
|---|---|
| 继续R6 | [R6当前计划](rounds/R6.md)的进度、当批安排与缺口；只读其指向的本批规格小节 |
| 新阶段/产品行为决策 | [PLAN](PLAN.md)对应阶段/产品语义；需要操作Goal才读[细则](WORKFLOW.md#goal-状态) |
| 定位实现/改公共接口 | [模块定位](ARCHITECTURE.md#架构与代码定位)，涉及持久/播放语义才补[长期接口](ARCHITECTURE.md#长期有效的接口与约束)及调用方 |
| 检查/构建/排错 | [命令参考](VERIFICATION.md)对应入口；环境问题读[TOOLCHAIN](TOOLCHAIN.md)，依赖/许可变化读[THIRD_PARTY](THIRD_PARTY.md) |
| 派发子Agent | [Skill读取矩阵](../.agents/skills/tagmusic-subagents/SKILL.md#最小读取集合)；按角色，不加载整套引用 |
| 准备设备批次 | [设备细则](../.agents/skills/tagmusic-subagents/references/devices.md)的共同要求及对应端；先确认授权 |
| 排查历史问题 | HANDOFF指定的具体证据；有依赖或矛盾才扩大，默认不读历史轮次/原始输出 |
| 交接/压缩 | 更新同一份HANDOFF；准备压缩时读[细则](WORKFLOW.md#压缩与交接)，不另建总结 |

## 文档各司其职

| 维护位置 | 唯一职责 |
|---|---|
| [AGENTS](../AGENTS.md) | 通用开发/读取/授权/停止/记录规则 |
| [协作Skill](../.agents/skills/tagmusic-subagents/SKILL.md) | 配置、角色最小读取、派发与短交接 |
| [PLAN](PLAN.md) | 产品边界及R0～R9阶段目标 |
| [HANDOFF](HANDOFF.md) | 当前状态、候选、授权、下一步和必要证据入口 |
| `rounds/Rxx.md` | 当前批次计划、进度和缺口；R6详细规格独立在[R6-SPEC](rounds/R6-SPEC.md) |
| `rounds/Rxx-ACCEPTANCE.md` | 正式验收结论/证据入口；原始输出唯一归`artifacts/Rxx/` |
| [开发日志](开发日志.md) | 每批一行完成摘要，不作恢复依据、不默认读取 |
| [架构](ARCHITECTURE.md)/[命令](VERIFICATION.md) | 长期接口与可选命令参考，不维护当前阶段状态 |
| 历史`rounds/R0～R5*`、[R4复盘](rounds/R4-TOKEN-REVIEW.md)、[原始计划](archive/PLAN.original.md) | 仅追溯；不作为当前规范、不默认读取 |

用户指令优先；历史状态不覆盖当前事实。默认搜索限定相关目录，排除`.tools/`、`build/`、`.dart_tool/`、`artifacts/`和生成文件；只有已知证据/工具问题才定向进入。文件数量不作为读取任务清单。

## 架构与代码定位

已移至[模块定位](ARCHITECTURE.md#架构与代码定位)。

## 长期有效的接口与约束

已移至[长期接口](ARCHITECTURE.md#长期有效的接口与约束)。

## 验证入口与维护

已移至[命令参考](VERIFICATION.md#验证入口与维护)，仅需要时读取。
