# 官方文档知识库

本仓库在开发过程中**逐字抓取并整理了官方 api-v2 文档**，产出两份可离线阅读的资料。
它们不是二次解读，而是原文摘录 + 明确标注的冲突项，用于在写代码前把事实钉死。

## 两份资料

- **[官方文档知识库](../official/knowledge-base.html)** —— 按主题整理：全部字段表、
  枚举、限流、错误码、事件 JSON 样例。开发时「某个字段到底怎么拼」查这一份。
- **[系统架构说明](../official/app-architecture.html)** —— 分层设计、模块职责、
  Dart 数据模型、连接状态机、目录结构。第一份的结论怎么落成代码，看这一份。

::: info 这两份资料由构建脚本复制进站点

源头在仓库的 `docs/qq-bot/`。`npm run dev` 与 `npm run build` 之前会由
`docs-site/tools/copy-official.mjs` 复制到 `docs-site/docs/public/official/`，
因此站点上的版本与仓库里的**永远是同一份内容**，不会出现两份各自漂移。
复制产物已 gitignore，不要提交副本。

:::

## 原始抓取笔记

更细的逐字笔记（含每个页面的原文、以及「官方文档未提供」的显式标注）在
[`docs/qq-bot/raw/`](https://github.com/Echoed-Abyss/Lave-develop/tree/main/docs/qq-bot/raw)：

| 文件 | 内容 |
| --- | --- |
| `gateway-wss.md` | 接入点、OpCode、生命周期、心跳、Resume、分片、关闭码 |
| `http-api-auth.md` | 鉴权、发消息、富媒体上传、频控、接口级错误码 |
| `events-intents.md` | 事件清单、intents 表、平台限制、错误码汇总 |

## 官方文档的已知问题

整理过程中发现官方文档存在若干**自相矛盾**或**明确缺失**的地方。
本项目的原则是：**照实标注，不替官方裁定**，并在代码里取保守值。

### 自相矛盾

| 位置 | 冲突内容 |
| --- | --- |
| 基础事件清单 | `event-emit.html` 列 `GUILDS`、`PUBLIC_GUILD_MESSAGES`、`GUILD_MEMBERS`；`nodesdk` 页多列了 `DIRECT_MESSAGE` |
| 单聊被动回复次数 | `overview.html` 写 4 次，`send.html` 正文写 5 次，同页更新说明写 4 次 |
| 被动消息有效期 | `send.html` 顶部写 60 分钟，字段说明写 5 分钟 |
| `GROUP_MEMBER_EVENT` | 不在 intents 清单里，却出现在多个事件页的 Intent 字段中 |
| Identify 的 token 拼法 | 字段表写 `QQBot {AccessToken}`，另一页正文写 `Bot {appid}.{app_token}` |
| 频道消息事件的 intent 归属 | `event-emit.html` 归 `GUILD_MESSAGES`，事件页标题写 `PUBLIC_GUILD_MESSAGES` |

### 明确缺失

| 缺失项 |
| --- |
| 心跳丢失的判定阈值 |
| intents 的十进制/十六进制值对照表（只有位移表达式） |
| 完整的事件 `err_code` 汇总页（分散在各接口页） |
| 压缩传输（WebSocket permessage-deflate）的相关说明 |
| C2C / GROUP_AT 事件的完整事件体字段（部分只在示例 JSON 里出现） |

## 项目遵守的底线

::: danger 只使用官方协议

本项目**禁止**引入任何逆向 QQ、抓包客户端协议、Hook、模拟登录 QQ 客户端的方案。
全部实现基于官方文档公开的 OpenAPI 与 Gateway WebSocket。

唯一边界情况是头像 CDN（`q.qlogo.cn/qqapp/{appid}/{openid}/{size}`）：
它未出现在官方文档中，但只是一张公开图片的地址，不含凭证、不涉及协议逆向。
[相关问题](https://github.com/Echoed-Abyss/Lave-develop/issues)可以讨论。

:::
