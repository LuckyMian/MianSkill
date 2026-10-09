# Battle.net WoW Web API

仅在用户开发站外网站、服务、CLI、数据同步器或明确要求 Battle.net API 时使用本参考。普通游戏内 AddOn 没有任意网络访问能力，不能直接调用这些 HTTPS 接口。

## 官方入口

- [World of Warcraft documentation](https://develop.battle.net/documentation/world-of-warcraft)
- [Game Data APIs](https://develop.battle.net/documentation/world-of-warcraft/game-data-apis)
- [Profile APIs](https://develop.battle.net/documentation/world-of-warcraft/profile-apis)
- [Getting Started](https://develop.battle.net/documentation/guides/getting-started)
- [Using OAuth](https://develop.battle.net/documentation/guides/using-oauth)

门户会重定向到 `community.developer.battle.net`；两者属于同一官方开发者门户。

## 实现前必须确认

1. 端点所属区域及主机，不能把 US、EU、KR/TW 与中国区配置混用。
2. 所需 OAuth grant、scope、token 生命周期与刷新策略。Client secret 只能放在可信服务端或安全 secret store，绝不提交仓库或打包进 WoW AddOn。
3. API namespace 是 static、dynamic 还是 profile，并与区域/版本匹配；同时传正确 `locale`。
4. HTTP 状态、重试、限流、缓存和数据缺失策略。只对幂等请求做有限的指数退避，并尊重服务端指示。
5. 用户资料端点所需的用户授权、隐私边界和最小 scope。

## 与 AddOn 协作

若产品同时包含游戏内插件和站外服务，把它们作为两个受信边界：

- AddOn 仅处理游戏公开给 UI 的数据，并通过 SavedVariables 或用户明确操作导入/导出允许的数据。
- 服务端持有 OAuth 凭据并调用 Web API。
- 不设计绕过游戏 UI API 限制、实时传输受保护战斗信息或自动化玩家操作的通道。

