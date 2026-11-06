# Tag Music

Windows / Android 本地音乐播放器，Flutter + Material 3。原创代码 MIT，第三方许可独立保留。

协作规则：[AGENTS](AGENTS.md)。新对话先读 [当前交接](docs/HANDOFF.md)，沿其链接恢复当前计划；[项目索引](docs/README.md) 按任务查阅，不必通读所有文档。产品目标见 [PLAN](docs/PLAN.md)。

日常续行只需说：

> 继续当前阶段，按项目交接恢复。

新阶段用Plan模式确认目标、依赖与验收，再以阶段Goal推进；阶段内由Codex自主拆分、验证和建立Git检查点。你负责关键决策与验收、额度观察、压缩及换对话。设备/前台操作仍须本批交互确认。

## 临时提问怎么选模型

以 Plus 限额内完成更多工作为目标。平时两三个零碎问题，默认 **Luna High**；按问题难度选择，不按问题数量升级。

| 你要问什么 | 建议 |
|---|---|
| 查进度/待办、解释术语、整理反馈、明确的小问题 | Luna High |
| 比较方案、取舍测试、调整阶段顺序、一般开发讨论 | Sol Medium |
| 跨模块故障、数据迁移/安全、异步竞态、正式代码审查 | Sol High |

同一轮混有难题时按最难的一项选择；简单问题不必用 Sol High。回答须按需核对项目文件，查不到就说明，不能猜。以上是提问建议，不自动改变开发配置；电脑界面测试仍按 AGENTS 使用 Terra High。

模块/验证入口在项目索引，环境与签名见 [TOOLCHAIN](docs/TOOLCHAIN.md)，许可见 [THIRD_PARTY](docs/THIRD_PARTY.md)。产物 `artifacts/Rxx/`、SDK `.tools/`、密钥 `.secrets/` 均不提交Git；候选不复用构建号覆盖。

完成摘要见 [开发日志](docs/开发日志.md)，原始计划在 `docs/archive/PLAN.original.md`，仅作历史依据。
