# 日常维护交接

R0～R9 开发计划已收尾。后续按日常使用反馈做定向修补。

- **当前版本** 本地 `main` 对应 [GitHub 公开仓库](https://github.com/deadpoolMIX/tag-music)，原创代码采用 0BSD 许可。个人版 `0.9.0` 的包内 revision 为 `3b5bc4a`。Windows 98、Android 正式 99 和原子随身听 100 保存在原 Release 草稿和本地 [output](../output/)。[公开 Release](https://github.com/deadpoolMIX/tag-music/releases/tag/v0.9.0-source) 提供源码下载。
- **当前状态** 手机播放页左滑进入歌词，歌词页右滑返回。普通和沉浸模式的双向切换共用淡入淡出动画，封面长按可查看原图。静态检查及三包版本、签名、原生文件和哈希核对已完成。见 [R9 验证归档](../artifacts/R9/)。
- **验收** 本批未安装或运行，待用户体验两种模式下的双向切换。用户已确认上一批局域网同步功能完成，旧库覆盖升级、同步冲突、缺失歌曲补扫和旧备份自动匹配没有逐项验收记录。局域网同步入口与实现见 [架构](ARCHITECTURE.md#局域网同步与备份匹配)。既有真机回归及公开发行缺口见 [R9 交付记录](rounds/R9.md#用户验收与保留事项)。
- **维护** 按反馈定位相关代码，集中验证，按规则交付三包。定位代码查[架构](ARCHITECTURE.md)，打包查[构建命令](VERIFICATION.md)，工具链或签名故障查[环境](TOOLCHAIN.md)，许可变更查[第三方许可](THIRD_PARTY.md)。
- **历史** 曲库迁移相关看 [R8 记录](rounds/R8.md)。其余阶段资料仅在追溯具体决策时从[计划的历史入口](PLAN.md#历史查询)查阅。
