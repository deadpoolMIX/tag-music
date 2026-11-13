# 检查与构建命令参考

仅本批需要检查、构建或排错时查对应入口；不是待执行清单，不因入口存在而全跑。

## 验证入口与维护

- `& ./scripts/check.ps1 -Round R6`（PowerShell 7）：依赖恢复、格式、analyze、全套单元/widget及R6工具/报告审计测试；准备固定曲库/封面/LRC样本并输出既有曲库/标签/筛选/队列主机基准。这是可选完整入口，按具体批次需要选用，不是体验候选前置条件。R6应用变更的当前计划与未测范围见[当轮计划](rounds/R6.md)；不含原生集成、双端构建、手机验收，不代表真实万首文件或设备Release性能。
- 候选参数：`scripts/build.ps1 -Target all -BuildNumber <新构建号> -Round <当前阶段>`；`verify-apk.ps1` 显式传 `-Version/-BuildNumbers/-Round`；`verify-packages.py` 传 `--version/--build/--round`，当前音频基线另传 `--native-reference-round R1`。隔离性能包用同一审计入口另传`--android-archive <APK> --windows-archive <ZIP> --output <新审计.json>`；报告拒绝覆盖，SQLite剥离复核文件按构建号区分。须在下一次Android构建覆盖merged原生输入前审计本批包。示意值须取实际 pubspec/交接。
- 手动 Flutter 先 `. ./scripts/env.ps1`，再 `& ./scripts/restore.ps1 -Round R6`。所有 Flutter 检查/测试/构建串行，避免共享注册文件互改。按功能批次交付前集中必要检查，不默认全量回归或完整 check；具体范围见 [PLAN §4](PLAN.md#4-验证与质量门禁)。
- check在R1～R6按阶段准备样本，SQLite包审计分支在R2～R6启用；R6的固定封面/LRC、性能采样契约及未测边界见[R6测量契约](rounds/R6-SPEC.md#七固定样本与测量入口契约)。后续阶段Plan先核对覆盖，不能把skip当通过。脚本默认参数及Android播放/卡片脚本仍有R1路径/样本假设，使用前核对，显式传当前参数。
- 固定日志名重跑前保留旧失败证据到同轮构建号/问题子目录，候选不复用构建号覆盖。`install-android.ps1` 还会启动应用与抓日志，须取得涵盖这些操作的本批交互确认。
- 独立设备性能包（R3标签/R4三框）：`& ./scripts/build-filter-benchmark.ps1 -Target all -BenchmarkBuildNumber <新测试编号>`，双端Release模式；Android独立ID `app.tagmusic.player.benchmark`、临时合成库，Windows单列打包并内置JSON报告出口；脚本只构建审计，不安装运行。正式APK安装从artifacts取包，不能从最新build/app输出推定候选身份。R4使用`integration_test/filter_benchmark_test.dart`，报告实际规则重算/搜索排序，初次加载单列，不计真实文件扫描或UI渲染。Android完整分段日志用 `python scripts/audit-filter-benchmark.py <本批日志> --report <新报告.json> --audit <新审计.json>` 恢复并复核六场景；缺段/重复/截断拒绝，勿用摘要替代原始数据。
- R5隔离性能入口：[build-queue-benchmark.ps1](../scripts/build-queue-benchmark.ps1)的`-Target all -BenchmarkBuildNumber <新编号>`只构建，复用独立Android ID并写入构建号/revision；Windows单列ZIP和报告路径，运行须当批授权。[queue_benchmark_test.dart](../integration_test/queue_benchmark_test.dart)共用[test/support/queue_benchmark.dart](../test/support/queue_benchmark.dart)，10000条目替换/批量加/删当前与非当前/反向重排/切入随机及跨轮构建各5次预热+20样本，逐次校验成员/独立ID/当前/FIFO；只计状态机操作，排除准备、校验、UI和播放FD。普通歌单11000输入去重为10000的保存/加载含事务等待、另计，不套队列阈值。
- R5报告用[审计脚本](../scripts/audit-queue-benchmark.py)校验：`python scripts/audit-queue-benchmark.py <本批源文件> --input-format log --platform android --build <编号> --revision <包内revision> --report <新完整报告.json> --audit <新审计.json>`；Windows原始JSON用`--input-format json --platform windows`。默认要求Release身份；主机调试结果须显式`--mode debug --build 0 --revision host-test`，不冒充设备通过。源/报告/审计必须不同，输出文件必须未存在；共用[分段恢复器](../scripts/benchmark_report.py)拒绝缺段/重复/乱序/截断，独立复算数量、顺序校验值和P95；实际逐次完整成员断言在包内。报告审计故障注入在[scripts/test_benchmark_audits.py](../scripts/test_benchmark_audits.py)。
- 仅文档改动验 diff、链接/事实/改动范围，不重建应用。改公共接口先查调用方/已有实现并验证，避免重复功能或闲置抽象。临时修复记录原因、范围、验证与撤除条件；改模块/接口/命令同步对应长期文档。
