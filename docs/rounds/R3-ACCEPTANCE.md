# R3 手机验收结果

正式候选 **0.4.0+12 / bcf31d5**，vivo V2309A；用户选择Codex测试，另选允许独立Release性能包。覆盖安装保留数据，未卸载/清空正式App。用户于2026-10-30 21:00明确“确认R3验收通过”，**最终验收通过**；下列证据边界保留。

证据统一位于 `artifacts/R3/android12/run-20261030-2040/`，results.json通过17项断言；主Agent已审阅关键截图、XML和日志。

| 编号/本批操作与预期 | 结果及证据 |
|---|---|
| 1 升级后数据、版本与主题保留 | 安装+12成功，firstInstallTime仍2026-10-29 20:14:50；设置0.4.0+12、1374首、深色主题。没有手机正式库UUID逐行比较 |
| 2 创建及重名拒绝 | 创建R3PhoneA与rock；ROCK被拒，已有标签保留。ADB带首尾空白输入不可靠，因此手机去空白未验；单元及Windows人工已有覆盖 |
| 3 单曲多标签及改名 | rock改为R3PhoneB；首曲两标签均1/1，标签页各1首。见single-two-tags、counts-single及renamed-B |
| 4 跨搜索选择与批量增删 | Brooklyn搜索勾选首曲后改搜Elaine仍选1，再选另一首共2；A/B均1/2→2/2，移除B后0/2；关联列表核对两首文件名。见selected-two、batch-added、batch-removed-B、associated-two |
| 5 删除提示、取消与确认 | A提示影响2首，取消保留2，确认后只剩B；收尾删除B两关联后标签页为空、曲库1374首。见delete-impact-two、delete-cancelled、deleted-A、tags-cleaned |
| 6 播放独立性及重启保留 | 播放首曲时给另一首添加B，截图同曲0:39→0:51；PID12816→18873，重开B有2关联且1374首，启动日志idle/playing=false、无播放器栏。完整业务队列不能由媒体会话证明，另由已有不可变队列widget断言验证 |

独立性能App `app.tagmusic.player.benchmark` Release构建1：临时万首库/一标签全关联，5次预热后20样本，P95 **19,607 μs（19.607ms）**，目标≤1s。benchmark.log记录All tests passed，benchmark-result.json独立重算一致；不是实际万首文件扫描或R4复杂规则测量。

批次结束：测试App已卸载，仅正式App保留；测试标签清理，正式曲库页1374首、无播放，采集停止。输入法候选提交与一次UIA无法idle的工具问题保留原证据，分别改用确认键提交和新截图定位；不原样重试。输入手感、中文组合体验、听感需用户判断；本批没有失联模拟，单元测试覆盖失联标签保留。
