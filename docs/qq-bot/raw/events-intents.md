# QQ 机器人开放平台知识库（C）
# 事件列表 / intents 掩码 / Webhook vs Gateway / 平台限制 / 错误码

> **事实来源声明**
> 本文件全部内容仅来自 QQ 机器人开放平台官方文档站 `https://bot.q.qq.com/wiki/`（含其 `develop/api-v2/`、`develop/api/`、`business/`、`changelog/`、`bot_new_product-intro/` 等官方页面）。
> 禁止第三方博客、CSDN、GitHub issue 作为来源；本文件未使用任何第三方资料。
> 抓取日期：2026-09-26。
>
> **处理原则**
> 1. 官方文档未给出的内容，一律写明「官方文档未提供」，不做推断填充。
> 2. 凡是标注「（换算）」的，是按官方文档给出的位移表达式所做的算术换算，**不是官方原文直接给出的十进制数值**。
> 3. 官方文档的原文措辞保留，包含其内部不一致之处（会在相应位置明确标注为「官方文档此处的表述」）。
> 4. JSON 样例逐字保留官方页面的样例。

---

## 目录

- [0. 本次抓取的来源页面清单](#0-本次抓取的来源页面清单)
- [1. 通用数据结构 Payload 与 OpCode](#1-通用数据结构-payload-与-opcode)
- [2. 事件订阅 intents 掩码完整对照表](#2-事件订阅-intents-掩码完整对照表)
- [3. 事件逐条整理（事件名 / 触发时机 / intents / JSON 样例 / 字段表）](#3-事件逐条整理)
- [4. 消息元素在 JSON 中的结构差异](#4-消息元素在-json-中的结构差异)
- [5. 双通道对比：Gateway WSS vs Webhook 回调](#5-双通道对比gateway-wss-vs-webhook-回调)
- [6. 平台限制与风控](#6-平台限制与风控)
- [7. 错误与调试总表](#7-错误与调试总表)
- [8. 沙箱环境与测试](#8-沙箱环境与测试)
- [9. 官方文档未提供的内容清单](#9-官方文档未提供的内容清单)

---

## 0. 本次抓取的来源页面清单

下表为本文件实际逐页抓取的官方页面（全部为 `bot.q.qq.com/wiki` 域名下页面）。

### 0.1 框架 / 通道 / 接入类

| 序号 | 页面标题 | URL |
|---|---|---|
| 1 | 事件订阅与通知（含 Webhook 方式、WebSocket 方式、Intents、分片） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html |
| 2 | Webhook 方式 | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/webhook.html |
| 3 | 使用 Websocket 接入（reference） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html |
| 4 | 启动接入（getting-started） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/getting-started.html |
| 5 | opcode | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/opcode.html |
| 6 | 安全和授权（Ed25519 签名算法, sign） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/sign.html |
| 7 | 开发说明（旧版，含沙箱域名 / 鉴权 / ID 说明） | https://bot.q.qq.com/wiki/develop/api/ |
| 8 | 介绍与接入指南（wiki 首页，含沙箱配置 7.1/7.2、消息 URL 白名单等） | https://bot.q.qq.com/wiki/ |

### 0.2 错误码 / 数据模型类

| 序号 | 页面标题 | URL |
|---|---|---|
| 9 | 错误与调试（OpenAPI 错误码 + WebSocket 错误码 + 全链路追踪） | https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html |
| 10 | 业务报错返回的数据信息(Data) | https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/data/model.html |
| 11 | WebSocket（错误码 code 与溯源） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/websocket.html |

### 0.3 事件页面（autogen/event）

| 序号 | 页面标题 | URL |
|---|---|---|
| 12 | 单聊消息事件 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/c2c_message_create.html |
| 13 | 群@机器人消息 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_at_message_create.html |
| 14 | 群消息（全量模式） | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_message_create.html |
| 15 | 单聊消息接收开启 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/c2c_msg_receive.html |
| 16 | 单聊消息接收关闭 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/c2c_msg_reject.html |
| 17 | 群聊消息接收开启 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_msg_receive.html |
| 18 | 群聊消息接收关闭 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_msg_reject.html |
| 19 | 机器人加入群聊 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_add_robot.html |
| 20 | 机器人退出群聊 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_del_robot.html |
| 21 | 群成员加入 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_member_add.html |
| 22 | 群成员退出 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_member_remove.html |
| 23 | 用户申请加群事件 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_join_request.html |
| 24 | 用户添加好友 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/friend_add.html |
| 25 | 用户删除好友 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/friend_del.html |
| 26 | 频道创建 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/guild_create.html |
| 27 | 频道更新 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/guild_update.html |
| 28 | 频道解散 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/guild_delete.html |
| 29 | 子频道创建 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/channel_create.html |
| 30 | 子频道更新 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/channel_update.html |
| 31 | 子频道删除 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/channel_delete.html |
| 32 | 互动事件 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/interaction_create.html |
| 33 | 订阅消息授权状态变更 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/subscribe_message_status.html |

### 0.4 补充页面（用于消息元素 / 频控 / 规范 / 产品限制）

| 序号 | 页面标题 | URL |
|---|---|---|
| 34 | 消息收发概述（主动/被动消息、消息类型、频率与时效、去重、撤回） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/overview.html |
| 35 | 发送消息（频控规则、单聊/群聊请求参数与错误码） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/send.html |
| 36 | 事件（send-receive/event：单聊/群聊/频道事件的精简字段表） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/event.html |
| 37 | 消息类型 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/overview.html |
| 38 | 文本消息 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/text.html |
| 39 | Markdown 消息 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/markdown.html |
| 40 | 结构化卡片消息（ARK） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/ark.html |
| 41 | 消息按钮（keyboard） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/msg-btn.html |
| 42 | 表情表态（emoji / reaction） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/emoji.html |
| 43 | 富媒体消息概述（file_type / 软硬限制 / 上传） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/rich-media.html |
| 44 | 频道消息事件（AT_MESSAGE_CREATE / MESSAGE_CREATE / DIRECT_MESSAGE_CREATE / MESSAGE_AUDIT_*） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/channel/message/event.html |
| 45 | 消息对象(Message) / 消息审核对象(MessageAudited) | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/template/model.html |
| 46 | 运营规范 | https://bot.q.qq.com/wiki/business/ |
| 47 | 文档更新日志 | https://bot.q.qq.com/wiki/changelog/ |
| 48 | QQ Bot 介绍与接入指南 | https://bot.q.qq.com/wiki/bot_new_product-intro/ |

> **说明**：任务清单中给出的 `https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_message_create.html` 页面确实存在（序号 14），官方页面标题为「群消息（全量模式）」。

---

## 1. 通用数据结构 Payload 与 OpCode

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html 、 https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html 、 https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/opcode.html

### 1.1 通用数据结构 Payload

官方原文：

> `payload` 指的是在 `webhook` 或 `websocket` 连接上传输的数据，网关的上下行消息采用的都是同一个结构，如下：

```json
{
  "id":"event_id",
  "op": 0,
  "d": {},
  "s": 42,
  "t": "GATEWAY_EVENT_NAME" }
```

> 注：以上 JSON 为官方文档原样（官方样例第 6 行 `"t": "GATEWAY_EVENT_NAME"` 后接 `}`，缩进与换行保持官方原样）。`reference.html`（Websocket 接入页）中给出的同结构样例不含 `id` 字段：

```json
{
  "op": 0,
  "d": {},
  "s": 42,
  "t": "GATEWAY_EVENT_NAME" }
```

**字段说明（官方表格）**

| 字段 | 描述 |
|---|---|
| id | 事件id |
| op | 指的是 opcode，参考连接维护 |
| s | 下行消息都会有一个序列号，标识消息的唯一性，客户端需要再发送心跳的时候，携带客户端收到的最新的 s |
| t | 代表事件类型。主要用在 op 为 0 Dispatch 的时候 |
| d | 代表事件内容，不同事件类型的事件内容格式都不同，请注意识别。主要用在 op 为 0 Dispatch 的时候 |

**reference.html 对 s / t / d 的补充原文**

> `s` 下行消息都会有一个序列号，标识消息的唯一性，客户端需要再发送心跳的时候，携带客户端收到的最新的 `s`。
> `t` 和 `d` 主要是用在 `op` 为 `0 Dispatch` 的时候，`t` 代表事件类型，`d` 代表事件内容，不同事件类型的事件内容格式都不同，请注意识别。

### 1.2 OpCode 含义

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html （OpCode 含义章节）

官方原文：所有 `opcode` 列表如下：

| **CODE** | **名称** | 接入方式 | **客户端行为** | **描述** |
|---|---|---|---|---|
| 0 | Dispatch | webhook/websocket | Receive | 服务端进行消息推送 |
| 1 | Heartbeat | websocket | Send/Receive | 客户端或服务端发送心跳 |
| 2 | Identify | websocket | Send | 客户端发送鉴权 |
| 6 | Resume | websocket | Send | 客户端恢复连接 |
| 7 | Reconnect | websocket | Receive | 服务端通知客户端重新连接 |
| 9 | Invalid Session | websocket | Receive | 当 identify 或 resume 的时候，如果参数有错，服务端会返回该消息 |
| 10 | Hello | websocket | Receive | 当客户端与网关建立 ws 连接之后，网关下发的第一条消息 |
| 11 | Heartbeat ACK | websocket | Receive/Reply | 当发送心跳成功之后，就会收到该消息 |
| 12 | HTTP Callback ACK | webhook | Reply | 仅用于 http 回调模式的回包，代表机器人收到了平台推送的数据 |
| 13 | 回调地址验证 | webhook | Receive | 开放平台对机器人服务端进行验证 |

客户端行为含义如下（官方原文）：

- `Receive` 客户端接收到服务端 `push` 的消息
- `Send` 客户端发送消息
- `Reply` 客户端接收到服务端发送的消息之后的回包（HTTP 回调模式）

**opcode.html 页面版本（对比）**

| CODE | 名称 | 客户端操作 | 描述 |
|---|---|---|---|
| 0 | Dispatch | Receive | 服务端进行消息推送 |
| 1 | Heartbeat | Send/Receive | 客户端或服务端发送心跳 |
| 2 | Identify | Send | 客户端发送鉴权 |
| 6 | Resume | Send | 客户端恢复连接 |
| 7 | Reconnect | Receive | 服务端通知客户端重新连接 |
| 9 | Invalid Session | Receive | 当identify或resume的时候，如果参数有错，服务端会返回该消息 |
| 10 | Hello | Receive | 当客户端与网关建立ws连接之后，网关下发的第一条消息 |
| 11 | Heartbeat ACK | Receive/Reply | 当发送心跳成功之后，就会收到该消息 |
| 12 | HTTP Callback ACK | Reply | 仅用于 http 回调模式的回包，代表机器人收到了平台推送的数据() |
| 13 | 回调地址验证 | Receive | 开放平台对机器人服务端进行验证 |

> 注：`opcode.html` 版本未区分「接入方式（webhook/websocket）」列；`event-emit.html` 版本含该列。两处内容一致，仅列结构不同。

### 1.3 WebSocket 时序关键报文（官方样例逐字保留）

**（1）建立连接后收到 OpCode 10 Hello**（来源：reference.html / event-emit.html）

```json
{
  "op": 10,
  "d": {
    "heartbeat_interval": 45000
  }
}
```

**（2）OpCode 2 Identify 鉴权**（来源：reference.html）

```json
{
  "op": 2,
  "d": {
    "token": "my_token",
    "intents": 513,
    "shard": [0, 4],
    "properties": {
      "$os": "linux",
      "$browser": "my_library",
      "$device": "my_library"
    }
  }
}
```

**（3）event-emit.html 版本 Identify**（注意 token 字段描述不同）

```json
{
  "op": 2,
  "d": {
    "token": "token string",
    "intents": 513,
    "shard": [0, 4],
    "properties": {
      "$os": "linux",
      "$browser": "my_library",
      "$device": "my_library"
    }
  }
}
```

| **字段** | **描述**（event-emit.html 原文） |
|---|---|
| token | 格式为"QQBot {AccessToken}" |
| intents | 是此次连接所需要接收的事件，具体可参考 **Intents** [事件订阅intents] |
| shard | 考虑到开发者事件接收时可以实现负载均衡，QQ 提供了分片逻辑，事件通知会落在不同的分片上，该参数是个拥有两个元素的数组。例如：[0,4]，代表分为四个片，当前链接是第 0 个片，业务稍后应该继续建立 `shard` 为[1,4],[2,4],[3,4]的链接，才能完整接收事件 |
| properties | 目前无实际作用，可以按照自己的实际情况填写，也可以留空 |

reference.html 对 token 的原文：

> `token` 是创建机器人的时候分配的，格式为 `Bot {appid}.{app_token}`

> **官方文档内部不一致标注**：`event-emit.html` 写 token 格式为 `"QQBot {AccessToken}"`；`reference.html` 写 token 格式为 `Bot {appid}.{app_token}`。两处表述不一致，本文件如实并列，不做裁定。

**（4）鉴权成功下发 Ready Event**（来源：reference.html / event-emit.html，两页样例一致）

```json
{
  "op": 0,
  "s": 1,
  "t": "READY",
  "d": {
    "version": 1,
    "session_id": "082ee18c-0be3-491b-9d8b-fbd95c51673a",
    "user": {
      "id": "6158788878435714165",
      "username": "群pro测试机器人",
      "bot": true
    },
    "shard": [0, 0]
  }
}
```

**（5）发送心跳**（来源：reference.html）

```json
{
  "op": 1,
  "d": 251
}
```

> 官方原文：鉴权成功之后，就需要按照周期进行心跳发送。`d` 为客户端收到的最新的消息的 `s`，如果是第一次连接，传 `null`。

**（6）心跳 ACK**

```json
{
  "op": 11
}
```

**（7）OpCode 6 Resume 恢复连接**（来源：reference.html）

```json
{
  "op": 6,
  "d": {
    "token": "my_token",
    "session_id": "session_id_i_stored",
    "seq": 1337
  }
}
```

> 官方原文：其中 `seq` 指的是在接收事件时候的 `s` 字段，我们推荐开发者在处理过事件之后记录下 `s` 这样可以在 resume 的时候传递给 websocket，websocket 会自动补发这个 seq 之后的事件。

**（8）Resumed Event**

```json
{
  "op": 0,
  "s": 2002,
  "t": "RESUMED",
  "d": ""
}
```

### 1.4 分片（Shard）机制

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

官方原文：

> 随着`bot`的增长并被添加到越来越多的频道中，事件越来越多，业务有必要对事件进行水平分割，实现负载均衡。机器人网关实现了一种用户可控制的分片方法，该方法允许跨多个网关连接拆分事件。 分片完全由用户控制，并且不需要在单独的连接之间进行状态共享。

**获得合适的分片数** —— 使用 `/gateway/bot` 接口获取网关地址时，会同时返回一个建议的 `shard` 数，及最大并发限制。官方样例：

```json
{
  "url": "wss://api.bot.qq.com/websocket",
  "shards": 1,
  "session_start_limit": {
    "total": 1000,
    "remaining": 1000,
    "reset_after": 86400000,
    "max_concurrency": 1
  }
}
```

**分片规则**（官方原文）：

> 分片是按照频道id进行哈希的，同一个频道的信息会固定从同一个链接推送。具体哈希计算规则如下：

```
shard_id = (guild_id >> 22) % num_shards
```

**最大连接数**（官方原文）：

> 每个机器人创建的连接数不能超过 `remaining` 剩余连接数

### 1.5 网关地址

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

官方原文：第一步先调用「获取通用WSS 接入点」或「获取带分片WSS 接入点」接口获取网关地址。会得到一个类似下面这样的地址：

```
wss://api.bot.qq.com/websocket/
```

### 1.6 事件权限（能否订阅 intents）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

官方原文（逐字）：

> 事件类型的订阅，是有权限控制的，除了 `GUILDS`，`PUBLIC_GUILD_MESSAGES`，`GUILD_MEMBERS` 事件是基础的事件，默认有权限订阅之外，其他的特殊事件，都需要经过申请才能够使用，如果在鉴权的时候传递了无权限的 `intents`， `websocket` 会报错，并直接关闭连接。请开发者注意订阅事件的范围需要控制在自己所需要的范围之内。
>
> 如果拥有的某个特殊事件类型的权限被取消，则在当前连接上不会报错，但是将不会收到对应的事件类型，如果重新连接，则报错，所以如果开发者的事件类型权限被取消，请及时调整监听事件代码，避免报错导致的无法连接。

> **补充（官方另一页表述）**：`https://bot.q.qq.com/wiki/develop/nodesdk/` 页面摘要中出现「除了 `GUILDS`，`PUBLIC_GUILD_MESSAGES`，`DIRECT_MESSAGE`，`GUILD_MEMBERS` 事件是基础的事件……」，与上页（event-emit.html）列举的基础事件集合（`GUILDS`、`PUBLIC_GUILD_MESSAGES`、`GUILD_MEMBERS`）不同。本文件如实并列，不裁定哪一版为准。

---

## 2. 事件订阅 intents 掩码完整对照表

### 2.1 intents 掩码表出自哪一页（重要）

**intents 的位定义（位移表达式 + 每类事件下的事件名清单）在官方文档中只出现于以下页面：**

- **`https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html`** —— 章节「事件订阅Intents」。

**官方文档是否有完整数值表？**

> **没有。** 官方文档只给出**位移表达式**（如 `GUILDS (1 << 0)`、`PUBLIC_GUILD_MESSAGES (1 << 30)`）与「该位对应哪些事件」的清单，**没有给出任何十进制/十六进制数值对照表**，也没有给出「所有 intent 汇总成一张表」的独立文档页。
> 本文件下方表格中的「数值（换算）」列，是依据官方位移表达式做的算术换算，**属于换算结果，不是官方原文数值**。官方原文对应的列为「位值（官方原文表达式）」。

### 2.2 intents 完整对照表（官方原文表达式 + 换算数值 + 对应事件）

| intent 名称 | 位值（官方原文表达式） | 数值（换算，非官方原文） | 对应事件（官方原文清单） | 备注（官方原文） |
|---|---|---|---|---|
| GUILDS | `1 << 0` | 1 | `GUILD_CREATE`（当机器人加入新guild时）<br>`GUILD_UPDATE`（当guild资料发生变更时）<br>`GUILD_DELETE`（当机器人退出guild时）<br>`CHANNEL_CREATE`（当channel被创建时）<br>`CHANNEL_UPDATE`（当channel被更新时）<br>`CHANNEL_DELETE`（当channel被删除时） | 基础事件，默认有权限订阅 |
| GUILD_MEMBERS | `1 << 1` | 2 | `GUILD_MEMBER_ADD`（当成员加入时）<br>`GUILD_MEMBER_UPDATE`（当成员资料变更时）<br>`GUILD_MEMBER_REMOVE`（当成员被移除时） | 基础事件，默认有权限订阅 |
| GUILD_MESSAGES | `1 << 9` | 512 | `MESSAGE_CREATE`（发送消息事件，代表频道内的全部消息，而不只是 at 机器人的消息。内容与 AT_MESSAGE_CREATE 相同）<br>`MESSAGE_DELETE`（删除（撤回）消息事件） | 官方原文：`// 消息事件，仅 *私域* 机器人能够设置此 intents。` |
| GUILD_MESSAGE_REACTIONS | `1 << 10` | 1024 | `MESSAGE_REACTION_ADD`（为消息添加表情表态）<br>`MESSAGE_REACTION_REMOVE`（为消息删除表情表态） | — |
| DIRECT_MESSAGE | `1 << 12` | 4096 | `DIRECT_MESSAGE_CREATE`（当收到用户发给机器人的私信消息时）<br>`DIRECT_MESSAGE_DELETE`（删除（撤回）消息事件） | — |
| GROUP_AND_C2C_EVENT | `1 << 25` | 33554432 | `C2C_MESSAGE_CREATE`（用户单聊发消息给机器人时候）<br>`FRIEND_ADD`（用户添加使用机器人）<br>`FRIEND_DEL`（用户删除机器人）<br>`C2C_MSG_REJECT`（用户在机器人资料卡手动关闭"主动消息"推送）<br>`C2C_MSG_RECEIVE`（用户在机器人资料卡手动开启"主动消息"推送开关）<br>`GROUP_AT_MESSAGE_CREATE`（用户在群里@机器人时收到的消息）<br>`GROUP_ADD_ROBOT`（机器人被添加到群聊）<br>`GROUP_DEL_ROBOT`（机器人被移出群聊）<br>`GROUP_MSG_REJECT`（群管理员主动在机器人资料页操作关闭通知）<br>`GROUP_MSG_RECEIVE`（群管理员主动在机器人资料页操作开启通知） | — |
| INTERACTION | `1 << 26` | 67108864 | `INTERACTION_CREATE`（互动事件创建时） | — |
| MESSAGE_AUDIT | `1 << 27` | 134217728 | `MESSAGE_AUDIT_PASS`（消息审核通过）<br>`MESSAGE_AUDIT_REJECT`（消息审核不通过） | — |
| FORUMS_EVENT | `1 << 28` | 268435456 | `FORUM_THREAD_CREATE`（当用户创建主题时）<br>`FORUM_THREAD_UPDATE`（当用户更新主题时）<br>`FORUM_THREAD_DELETE`（当用户删除主题时）<br>`FORUM_POST_CREATE`（当用户创建帖子时）<br>`FORUM_POST_DELETE`（当用户删除帖子时）<br>`FORUM_REPLY_CREATE`（当用户回复评论时）<br>`FORUM_REPLY_DELETE`（当用户回复评论时）<br>`FORUM_PUBLISH_AUDIT_RESULT`（当用户发表审核通过时） | 官方原文：`// 论坛事件，仅 *私域* 机器人能够设置此 intents。` |
| AUDIO_ACTION | `1 << 29` | 536870912 | `AUDIO_START`（音频开始播放时）<br>`AUDIO_FINISH`（音频播放结束时）<br>`AUDIO_ON_MIC`（上麦时）<br>`AUDIO_OFF_MIC`（下麦时） | — |
| PUBLIC_GUILD_MESSAGES | `1 << 30` | 1073741824 | `AT_MESSAGE_CREATE`（当收到@机器人的消息时）<br>`PUBLIC_MESSAGE_DELETE`（当频道的消息被删除时） | 官方原文：`// 消息事件，此为公域的消息事件`；基础事件，默认有权限订阅 |
| GROUP_MEMBER_EVENT | `1 << 24` | 16777216 | `GROUP_MEMBER_ADD`（群成员加入）<br>`GROUP_MEMBER_REMOVE`（群成员退出）<br>`GROUP_JOIN_REQUEST`（用户申请加群事件） | **官方文档内部不一致标注**：`GROUP_MEMBER_EVENT` 及其 `1<<24` 位值**未出现在** `event-emit.html` 的 intents 清单里，而是出现在各事件页（`group_member_add.html` / `group_member_remove.html` / `group_join_request.html`）的「Intent」字段中。因此 intents 清单存在两处来源不一致的情况，本文件如实并列。 |

**官方原文中的 intents 清单原文块（逐字保留，含注释格式）**

```
GUILDS (1 << 0)
 - GUILD_CREATE // 当机器人加入新guild时
 - GUILD_UPDATE // 当guild资料发生变更时
 - GUILD_DELETE // 当机器人退出guild时
 - CHANNEL_CREATE // 当channel被创建时
 - CHANNEL_UPDATE // 当channel被更新时
 - CHANNEL_DELETE // 当channel被删除时

GUILD_MEMBERS (1 << 1)
 - GUILD_MEMBER_ADD // 当成员加入时
 - GUILD_MEMBER_UPDATE // 当成员资料变更时
 - GUILD_MEMBER_REMOVE // 当成员被移除时

GUILD_MESSAGES (1 << 9) // 消息事件，仅 *私域* 机器人能够设置此 intents。
 - MESSAGE_CREATE // 发送消息事件，代表频道内的全部消息，而不只是 at 机器人的消息。内容与 AT_MESSAGE_CREATE 相同
 - MESSAGE_DELETE // 删除（撤回）消息事件

GUILD_MESSAGE_REACTIONS (1 << 10)
 - MESSAGE_REACTION_ADD // 为消息添加表情表态
 - MESSAGE_REACTION_REMOVE // 为消息删除表情表态

DIRECT_MESSAGE (1 << 12)
 - DIRECT_MESSAGE_CREATE // 当收到用户发给机器人的私信消息时
 - DIRECT_MESSAGE_DELETE // 删除（撤回）消息事件

GROUP_AND_C2C_EVENT (1 << 25)
 - C2C_MESSAGE_CREATE // 用户单聊发消息给机器人时候
 - FRIEND_ADD // 用户添加使用机器人
 - FRIEND_DEL // 用户删除机器人
 - C2C_MSG_REJECT // 用户在机器人资料卡手动关闭"主动消息"推送
 - C2C_MSG_RECEIVE // 用户在机器人资料卡手动开启"主动消息"推送开关
 - GROUP_AT_MESSAGE_CREATE // 用户在群里@机器人时收到的消息
 - GROUP_ADD_ROBOT // 机器人被添加到群聊
 - GROUP_DEL_ROBOT // 机器人被移出群聊
 - GROUP_MSG_REJECT // 群管理员主动在机器人资料页操作关闭通知
 - GROUP_MSG_RECEIVE // 群管理员主动在机器人资料页操作开启通知

INTERACTION (1 << 26)
 - INTERACTION_CREATE // 互动事件创建时

MESSAGE_AUDIT (1 << 27)
 - MESSAGE_AUDIT_PASS // 消息审核通过
 - MESSAGE_AUDIT_REJECT // 消息审核不通过

FORUMS_EVENT (1 << 28) // 论坛事件，仅 *私域* 机器人能够设置此 intents。
 - FORUM_THREAD_CREATE // 当用户创建主题时
 - FORUM_THREAD_UPDATE // 当用户更新主题时
 - FORUM_THREAD_DELETE // 当用户删除主题时
 - FORUM_POST_CREATE // 当用户创建帖子时
 - FORUM_POST_DELETE // 当用户删除帖子时
 - FORUM_REPLY_CREATE // 当用户回复评论时
 - FORUM_REPLY_DELETE // 当用户回复评论时
 - FORUM_PUBLISH_AUDIT_RESULT // 当用户发表审核通过时

AUDIO_ACTION (1 << 29)
 - AUDIO_START // 音频开始播放时
 - AUDIO_FINISH // 音频播放结束时
 - AUDIO_ON_MIC // 上麦时
 - AUDIO_OFF_MIC // 下麦时

PUBLIC_GUILD_MESSAGES (1 << 30) // 消息事件，此为公域的消息事件
 - AT_MESSAGE_CREATE // 当收到@机器人的消息时
 - PUBLIC_MESSAGE_DELETE // 当频道的消息被删除时
```

### 2.3 位运算规则与官方给出的组合示例

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

官方原文（逐字）：

> 事件的 `intents` 是一个标记位，每一位都代表不同的事件，如果需要接收某类事件，就将该位置为 `1`。
> 每个 `intents` 位代表的是一类事件，可以使用使用 `websocket` 传输的数据中的 `t` 字段的值来区分。

**官方给出的组合示例（逐字）**

> 如开发者需要接收用户 at 机器人的消息，那么就需要在 `intents` 中设置接收 `PUBLIC_GUILD_MESSAGES`。则需要先计算 `1 << 30` 的值。然后与 `0` 做位或操作，得到最终需要传递的 `intents`。
>
> 如果涉及到多个事件类型的接收，则需要将多个结果做位或操作，如：`0|1<<30|1<<1` 代表订阅 `PUBLIC_GUILD_MESSAGES` 和 `GUILD_MEMBERS` 这两类事件。

**官方给出的 intents 示例数值**

> Identify 报文样例中 `"intents": 513`（见 `reference.html` 与 `event-emit.html` 的 Identify 样例）。
> **官方文档未说明 513 具体对应哪些 intent**；按位移表达式换算为 `1<<9 | 1<<0`（即 `GUILD_MESSAGES | GUILDS`），但**该解释属于本文件换算推断，非官方原文**。

### 2.4 任务中要求核实的「群聊 + 单聊 + 频道推荐取值」

> **官方文档未提供**「群聊 + 单聊 + 频道的推荐 intents 取值组合」这一描述。
> 官方在 `event-emit.html` 中只提供了两处组合示例：
> - `1 << 30`（单一位，PUBLIC_GUILD_MESSAGES）
> - `0|1<<30|1<<1`（PUBLIC_GUILD_MESSAGES + GUILD_MEMBERS）
> 与「群聊 + 单聊」相关的 `GROUP_AND_C2C_EVENT (1 << 25)` 在官方文档中**没有给出任何组合示例**。
> 官方另有表述：**「请开发者注意订阅事件的范围需要控制在自己所需要的范围之内」**（event-emit.html 权限章节）。

---

## 3. 事件逐条整理

> 排列顺序：先单聊/群聊（亲友团场景）事件，再频道（Guild）相关事件，最后互动与订阅事件。
> 每条含：事件名(t) / 触发时机 / intents 所属 / 完整 JSON 样例（逐字保留）/ 字段说明表 / 来源 URL。

### 3.1 C2C_MESSAGE_CREATE —— 单聊消息事件

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/c2c_message_create.html

**触发时机（官方原文）**

> 用户给机器人发送单聊消息时触发。 为确保消息可达，相同 msg_id 可能重复推送，开发者需结合 msg_seq 做去重。
>
> 为确保消息可达，相同 msg_id 可能重复推送，需结合 message_scene.ext 中的 msg_idx 做去重。message_type 决定消息结构：0=纯文本，3=ARK卡片（ark_data 有值），103=引用消息（msg_elements 有值，message_scene.ext 含 ref_msg_idx）。

**事件基本信息（官方表格）**

| 字段 | 值 |
|---|---|
| 事件名 | C2C_MESSAGE_CREATE |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 消息 ID，可用于被动回复和撤回 |
| author | User | 发送者（user_openid 有值） |
| content | string | 消息文本内容 |
| timestamp | string | 消息发送时间，RFC3339 格式 |
| message_type | integer | 消息内容类型: 0=普通文本, 3=结构化卡片, 101=并行消息, 102=聊天记录, 103=引用消息 |
| message_scene | MessageScene | 消息场景上下文（含消息索引、鉴权令牌等） |
| attachments | []MessageAttachment | 消息附件（图片、文件、语音等） |
| ark_data | ARKData | 结构化卡片消息数据（message_type=3 时有值） |
| msg_elements | []MsgElement | 消息元素列表（message_type=103 引用消息时包含被引用内容） |

**User**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 用户唯一标识（OpenID 格式） |
| username | string | 用户昵称 |
| bot | boolean | 是否为机器人 |
| union_openid | string | 跨应用统一用户 OpenID（可能为空） |
| union_user_account | string | 跨应用统一用户账号（可能为空） |
| user_openid | string | 用户 OpenID（单聊场景使用） |
| member_openid | string | 群成员 OpenID（群聊场景使用） |
| member_role | string | 群内角色。member=普通成员, admin=管理员, owner=群主 |

**MessageScene**

| 名称 | 类型 | 描述 |
|---|---|---|
| source | string | 场景来源。default=默认聊天窗口 |
| ext | []string | 扩展数据列表，key=value 格式: msg_idx=消息索引, 用于引用场景 ref_msg_idx=引用的消息索引 auth_token=鉴权令牌 |

**MessageAttachment**

| 名称 | 类型 | 描述 |
|---|---|---|
| url | string | 附件下载 URL |
| filename | string | 文件名 |
| width | integer | 图片宽度（像素），非图片附件无此字段 |
| height | integer | 图片高度（像素），非图片附件无此字段 |
| size | integer | 文件大小（字节） |
| content_type | string | 附件内容类型（MIME 类型）: voice=语音消息 image/jpeg=JPEG 图片 image/png=PNG 图片 image/gif=GIF 图片 video/mp4=MP4 视频 file=群文件 |
| voice_wav_url | string | 语音消息 SILK 等转换后的 WAV 文件 URL |
| asr_refer_text | string | 语音消息 ASR 参考结果 |

**ARKData**

| 名称 | 类型 | 描述 |
|---|---|---|
| prompt | string | 卡片消息中的用户操作提示文本 |
| ark_type | string | 卡片消息类型标识: tuwen = 图文 H5（如快手分享链接） feed = 图文卡片（群相册、频道帖子、分享卡片） miniapp = 小程序（微信小程序、QQ 小程序、哔哩哔哩等） map = 位置卡片 contact_card = 好友名片 video_share = 视频分享 music_together = 一起听歌 picture = 图片 |
| ark_name | string | 卡片消息类型的中文名称，如"图文 H5"、"小程序"、"图文卡片" |
| fields | object | 卡片消息字段，常见键名: tag/tags=来源标签, title=标题, desc=描述, jump_url=跳转链接, preview=预览图, source=来源名称, source_logo=来源图标, tag_icon=标签图标, nickname=昵称, avatar=头像, address=地址 |

**MsgElement**

| 名称 | 类型 | 描述 |
|---|---|---|
| msg_idx | string | 消息元素在列表中的引用消息索引 |
| author | User | 该元素对应的消息发送者 |
| message_type | integer | 消息内容类型: 0=普通文本, 3=结构化卡片, 101=并行消息, 102=聊天记录, 103=引用消息 |
| content | string | 消息正文内容 |
| attachments | []MessageAttachment | 该元素携带的附件 |
| ark_data | ARKData | 结构化卡片消息数据（message_type=3 时有值） |
| msg_elements | []MsgElement | 嵌套消息元素列表（递归结构） |

**事件示例（官方三例，逐字保留）**

示例1：

```json
{
 "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "author": {
 "id": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "user_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "union_openid": "",
 "username": "",
 "bot": false
 },
 "content": "你好，今天有什么推荐的活动吗？",
 "message_type": 0,
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_xxxxxxxxxxxxxxx=="
 ]
 },
 "timestamp": "2026-07-21T10:00:00+08:00"
}
```

示例2：

```json
{
 "id": "ROBOT1.0_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
 "author": {
 "id": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "user_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "union_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "username": "",
 "bot": false
 },
 "content": "[卡片消息] 小程序\n摘要: [每日打卡]快来完成今日学习打卡",
 "message_type": 3,
 "ark_data": {
 "ark_type": "miniapp",
 "ark_name": "小程序",
 "prompt": "[每日打卡]快来完成今日学习打卡",
 "fields": {
 "title": "快来完成今日学习打卡",
 "source": "学习助手",
 "tag": "微信小程序",
 "preview": "https://pubminishare-30161.picsz.qpic.cn/preview_a1b2c3d4",
 "source_logo": "https://miniapp.gtimg.cn/generated-icon/app_a1b2c3d4.png",
 "tag_icon": "https://miniapp.gtimg.cn/public/miniwx.png"
 }
 },
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_yyyyyyyyyyyyyyy=="
 ]
 },
 "timestamp": "2026-07-21T10:01:00+08:00"
}
```

示例3：

```json
{
 "id": "ROBOT1.0_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
 "author": {
 "id": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "user_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "union_openid": "",
 "username": "",
 "bot": false
 },
 "content": "这个建议很有帮助，谢谢你！",
 "message_type": 103,
 "msg_elements": [
 {
 "msg_idx": "REFIDX_aaaaaaaaaaaaaaa==",
 "message_type": 103,
 "content": "每天坚持阅读半小时，一个月后你会发现自己的变化"
 }
 ],
 "message_scene": {
 "source": "default",
 "ext": [
 "ref_msg_idx=REFIDX_aaaaaaaaaaaaaaa==",
 "msg_idx=REFIDX_zzzzzzzzzzzzzzz=="
 ]
 },
 "timestamp": "2026-07-21T10:02:00+08:00"
}
```

**另一个官方版本（精简字段表）** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/event.html

| 基本 |  |
|---|---|
| intents | 1<<25 |
| 事件类型 | C2C_MESSAGE_CREATE |
| 触发场景 | 用户在单聊发送消息给机器人 |

事件字段：`id`(string，平台方消息ID，可以用于被动消息发送)、`author`(object，发送者)、`content`(string，文本消息内容)、`timestamp`(string，消息生产时间（RFC3339）)、`attachments`(object[]，富媒体文件附件，文件类型："图片，语音，视频，文件")。

author 对象：`user_openid`(string，用户 openid)。

attachment 对象（该页原文）：

| **属性** | **类型** | **说明** |
|---|---|---|
| content_type | string | 文件类型，"image/jpeg","image/png","image/gif"，"file"，"video/mp4"，"voice" |
| filename | string | 文件名称 |
| height | int | 图片高度 |
| width | int | 图片宽度 |
| size | int | 文件大小 |
| url | string | 文件链接 |
| voice_wav_url | string | 语音文件链接（wav格式） |
| asr_refer_text | string | 语音 asr 参考结果 |

该页事件示例（逐字）：

```json
{
  "author": {
      "user_openid": "E4F4AEA33253A2797FB897C50B81D7ED"
  },
  "content": "123",
  "id": "ROBOT1.0_.b6nx.CVryAO0nR58RXuU6SC.m92gc19j02qKqdm8ek!",
  "timestamp": "2023-11-06T13:37:18+08:00" }
```

> 官方补充说明（该页原文）：为了确保消息可到达，极端情况下，相同的 msg_id 的消息会有概率重复推送，当开发者在做"被动回复消息"响应业务的时候，如果开发者不对 msg_id 的回复做存储排重后的回复逻辑，很可能会回复了两条相同的消息给用户，这里我们引入了一个 `msg_seq` 的字段，便于过滤重复消息响应。

---

### 3.2 GROUP_AT_MESSAGE_CREATE —— 群@机器人消息

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_at_message_create.html

**触发时机（官方原文）**

> 用户在群里@机器人发送消息时触发。这是机器人最常接收的事件。 content 字段已自动去除@机器人的前缀。 为确保消息可达，相同 msg_id 可能重复推送，开发者需结合 msg_seq 做去重。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_AT_MESSAGE_CREATE |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 消息 ID，可用于被动回复和撤回 |
| author | User | 发送者（member_openid 有值） |
| content | string | 消息文本内容（已去除@机器人的前缀） |
| group_openid | string | 群 OpenID |
| timestamp | string | 消息发送时间，RFC3339 格式 |
| message_type | integer | 消息内容类型（同 C2C_MESSAGE_CREATE） |
| message_scene | MessageScene | 消息场景上下文 |
| attachments | []MessageAttachment | 消息附件 |
| mentions | []User | 消息中@的用户列表（不含@机器人自身） |
| ark_data | ARKData | 结构化卡片消息数据 |
| msg_elements | []MsgElement | 消息元素列表 |

其中 User / MessageScene / MessageAttachment / ARKData / MsgElement 的字段表与 3.1 节完全相同（官方页面重复给出，内容一致）。

**事件示例（官方三例，逐字保留）**

示例1：

```json
{
 "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "author": {
 "id": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "member_role": "member",
 "username": "小明",
 "bot": false
 },
 "content": " /今日天气 ",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "message_type": 0,
 "timestamp": "2026-07-21T10:00:00+08:00",
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_xxxxxxxxxxxxxxx==",
 "auth_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
 ]
 }
}
```

示例2：

```json
{
 "id": "ROBOT1.0_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
 "author": {
 "id": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "member_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "member_role": "member",
 "username": "小红",
 "bot": false
 },
 "content": " 看看这张风景照 ",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "message_type": 0,
 "timestamp": "2026-07-21T10:05:00+08:00",
 "attachments": [
 {
 "content_type": "image/jpeg",
 "filename": "photo.jpg",
 "url": "https://multimedia.nt.qq.com.cn/download?appid=xxx&fileid=xxx&rkey=xxx&spec=0",
 "width": 1920,
 "height": 1080,
 "size": 256000
 }
 ],
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_yyyyyyyyyyyyyyy==",
 "auth_token=yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
 ]
 }
}
```

示例3：

```json
{
 "id": "ROBOT1.0_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
 "author": {
 "id": "D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1",
 "member_openid": "D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1",
 "member_role": "owner",
 "username": "小华",
 "bot": false
 },
 "content": " ",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "message_type": 103,
 "timestamp": "2026-07-21T10:10:00+08:00",
 "msg_elements": [
 {
 "content": "=== 消息 1 ===\n[消息内容] 今天的学习计划已完成\n\n=== 消息 2 ===\n[消息内容] 很棒！继续保持，明天继续加油\n\n=== 消息 3 ===\n[消息内容] 好的，一起进步！"
 }
 ],
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_zzzzzzzzzzzzzzz==",
 "auth_token=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
 "ref_msg_idx=TMP_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
 ]
 }
}
```

**另一个官方版本（精简字段表）** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/event.html

| 基本 |  |
|---|---|
| intents | 1<<25 |
| 事件类型 | GROUP_AT_MESSAGE_CREATE |
| 触发场景 | 用户在群聊@机器人发送消息 |

author 对象：`member_openid`(string，用户在本群的 member_openid)、`member_role`(string，消息发送者在群内的身份，枚举值：owner、admin、member)、`bot`(bool，是否是机器人)。

该页事件示例（逐字，标注为 `// Websocket`）：

```json
// Websocket {
  "author": {
      "member_openid": "E4F4AEA33253A2797FB897C50B81D7ED"
  },
  "content": " 123",
  "group_openid": "C9F778FE6ADF9D1D1DBE395BF744A33A",
  "id": "ROBOT1.0_eBIyWnxpmSu6uLQ7u7fU0eGloKGYg4eEa737vRyKnMCgyZjKi7JLYkQ9B0VapbiY",
  "timestamp": "2023-11-06T13:37:18+08:00" }
```

---

### 3.3 GROUP_MESSAGE_CREATE —— 群消息（全量模式）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_message_create.html

**触发时机（官方原文，逐字）**

> 当机器人开启了"接收所有消息"功能后，群里的每一条消息（不限于@机器人）都会推送此事件。 各字段含义与 GROUP_AT_MESSAGE_CREATE 完全一致。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_MESSAGE_CREATE |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 消息 ID，可用于被动回复和撤回 |
| author | User | 发送者 |
| content | string | 消息文本内容（已去除@机器人的前缀） |
| group_openid | string | 群 OpenID |
| timestamp | string | 消息发送时间，RFC3339 格式 |
| message_type | integer | 消息内容类型 |
| message_scene | MessageScene | 消息场景上下文 |
| attachments | []MessageAttachment | 消息附件 |
| mentions | []User | 消息中@的用户列表 |
| ark_data | ARKData | 结构化卡片消息数据 |
| msg_elements | []MsgElement | 消息元素列表 |

**事件示例（官方三例，逐字保留）**

示例1：

```json
{
 "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "author": {
 "id": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "member_role": "member",
 "username": "小明",
 "bot": false
 },
 "content": "大家早上好呀",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "message_type": 0,
 "timestamp": "2026-07-21T08:00:00+08:00",
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_xxxxxxxxxxxxxxx==",
 "auth_token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
 ]
 }
}
```

示例2：

```json
{
 "id": "ROBOT1.0_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
 "author": {
 "id": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "member_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "member_role": "owner",
 "username": "小红",
 "bot": false
 },
 "content": "分享一张今天的风景照",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "message_type": 0,
 "timestamp": "2026-07-21T09:30:00+08:00",
 "attachments": [
 {
 "content_type": "image/jpeg",
 "filename": "photo.jpg",
 "url": "https://multimedia.nt.qq.com.cn/download?appid=xxx&fileid=xxx&rkey=xxx&spec=0",
 "width": 1920,
 "height": 1080,
 "size": 256000
 }
 ],
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_yyyyyyyyyyyyyyy==",
 "auth_token=yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
 ]
 }
}
```

示例3：

```json
{
 "id": "ROBOT1.0_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
 "author": {
 "id": "D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1",
 "member_openid": "D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1",
 "member_role": "admin",
 "username": "小华",
 "bot": false
 },
 "content": " ",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "message_type": 103,
 "timestamp": "2026-07-21T10:10:00+08:00",
 "msg_elements": [
 {
 "content": "=== 消息 1 ===\n[消息内容] 今天的学习计划已完成\n\n=== 消息 2 ===\n[消息内容] 很棒！继续保持，明天继续加油\n\n=== 消息 3 ===\n[消息内容] 好的，一起进步！"
 }
 ],
 "message_scene": {
 "source": "default",
 "ext": [
 "msg_idx=REFIDX_zzzzzzzzzzzzzzz==",
 "auth_token=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
 "ref_msg_idx=TMP_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
 ]
 }
}
```

**另一个官方版本** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/event.html

| 基本 |  |
|---|---|
| intents | 1<<25 |
| 事件类型 | GROUP_MESSAGE_CREATE |
| 触发场景 | 用户在群聊@机器人发送消息 |

该页说明原文：当群主设定允许该机器人接收群内全部消息时，机器人可接收到群内所有成员在群内的发言消息。

---

### 3.4 C2C_MSG_RECEIVE —— 单聊消息接收开启

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/c2c_msg_receive.html

**触发时机（官方原文）**

> 用户在机器人资料卡手动开启"主动消息"推送开关时触发。
>
> 用户在机器人资料卡手动开启主动消息推送开关时触发。开启后机器人可向该用户发送主动消息。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | C2C_MSG_RECEIVE |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 操作时间戳（Unix 秒） |
| openid | string | 用户 OpenID |

**事件示例（官方，逐字）**

```json
{
 "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570617
}
```

---

### 3.5 C2C_MSG_REJECT —— 单聊消息接收关闭

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/c2c_msg_reject.html

**触发时机（官方原文）**

> 用户在机器人资料卡手动关闭"主动消息"推送时触发。
>
> 用户在机器人资料卡手动关闭主动消息推送时触发。关闭后机器人无法向该用户发送主动消息。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | C2C_MSG_REJECT |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 操作时间戳（Unix 秒） |
| openid | string | 用户 OpenID |

**事件示例（官方，逐字）**

```json
{
 "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570599
}
```

---

### 3.6 GROUP_MSG_RECEIVE —— 群聊消息接收开启

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_msg_receive.html

**触发时机（官方原文）**

> 群管理员在机器人资料页操作开启通知时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_MSG_RECEIVE |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 操作时间戳（Unix 秒） |
| group_openid | string | 群 OpenID |
| op_member_openid | string | 操作群成员 OpenID |

**事件示例（官方，逐字）**

```json
{
 "timestamp": 1784276800,
 "group_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "op_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4"
}
```

---

### 3.7 GROUP_MSG_REJECT —— 群聊消息接收关闭

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_msg_reject.html

**触发时机（官方原文）**

> 群管理员在机器人资料页操作关闭通知时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_MSG_REJECT |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 操作时间戳（Unix 秒） |
| group_openid | string | 群 OpenID |
| op_member_openid | string | 操作群成员 OpenID |

**事件示例（官方，逐字）**

```json
{
 "timestamp": 1784276810,
 "group_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "op_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4"
}
```

---

### 3.8 GROUP_ADD_ROBOT —— 机器人加入群聊

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_add_robot.html

**触发时机（官方原文）**

> 机器人被添加到群聊时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_ADD_ROBOT |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 加入时间戳（Unix 秒） |
| group_openid | string | 群 OpenID |
| op_member_openid | string | 操作添加机器人进群的群成员 OpenID |

**事件示例（官方，逐字）**

```json
{
 "group_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "op_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570534
}
```

---

### 3.9 GROUP_DEL_ROBOT —— 机器人退出群聊

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_del_robot.html

**触发时机（官方原文）**

> 机器人被移出群聊时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_DEL_ROBOT |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 移除时间戳（Unix 秒） |
| group_openid | string | 群 OpenID |
| op_member_openid | string | 操作移除机器人退群的群成员 OpenID |

**事件示例（官方，逐字）**

```json
{
 "group_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "op_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570535
}
```

---

### 3.10 GROUP_MEMBER_ADD —— 群成员加入

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_member_add.html

**触发时机（官方原文）**

> 有新成员加入群聊时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_MEMBER_ADD |
| Intent | GROUP_MEMBER_EVENT (1<<24) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 事件时间戳（Unix 秒） |
| group_openid | string | 群 OpenID |
| member_openid | string | 新加入成员的 OpenID |
| user_openid | string | 新成员的用户 OpenID（跨应用统一标识，可能为空） |

**事件示例（官方，逐字）**

```json
{
 "timestamp": 1784276757,
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "member_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "user_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6"
}
```

---

### 3.11 GROUP_MEMBER_REMOVE —— 群成员退出

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_member_remove.html

**触发时机（官方原文）**

> 群成员退出或被移出群聊时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_MEMBER_REMOVE |
| Intent | GROUP_MEMBER_EVENT (1<<24) |

**事件体字段说明**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 事件时间戳（Unix 秒） |
| group_openid | string | 群 OpenID |
| member_openid | string | 退出成员的 OpenID |
| user_openid | string | 退出成员的用户 OpenID（可能为空） |

**事件示例（官方，逐字）**

```json
{
 "timestamp": 1784276759,
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "member_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6",
 "user_openid": "C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6"
}
```

---

### 3.12 GROUP_JOIN_REQUEST —— 用户申请加群事件

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/group_join_request.html

**触发时机（官方原文，逐字）**

> 用户申请加群请求触发此事件
>
> 1.只有当机器人是群管理员时才可以收到此事件。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GROUP_JOIN_REQUEST |
| Intent | GROUP_MEMBER_EVENT (1<<24) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| group_openid | string | 群OpenID |
| join_request_id | string | 申请ID,需要在申请接口回传 |
| risk_tips | string | 安全提示语；可疑消息直接返回 warning_tips；普通消息命中 sec_risk_rules 时返回 top_tips |
| union_openid | string | 用户在应用/开放平台下的统一标识（如有） |
| member_openid | string | 申请人 openid |
| username | string | 申请人昵称 |
| apply_at | string | 申请时间戳（RFC3339 格式） |
| apply_source | string | 申请来源：self_apply 主动申请，invited 被邀请 |
| invited_by | string | 邀请人 openid（apply_source=invited 时有效） |
| bot | boolean | 是否为机器人账号 |
| verify_info | VerifyInfo | 用户入群验证方式 |
| auto_approved | AutoAppproved | 自动审批通过的扩展信息, 只有在下行事件中会携带。 |

**VerifyInfo**

| 名称 | 类型 | 描述 |
|---|---|---|
| method | string | 入群验证方式：verify_message / admin_review_qa |
| verify_message | string | 验证消息内容；仅 auth_type=verify_message 时可能携带 |
| review_qa_list | []ReviewQA | 问答列表；仅 auth_type=admin_review_qa 时可能携带 |

**ReviewQA**

| 名称 | 类型 | 描述 |
|---|---|---|
| question | string | 管理员设置的问题 |
| answer | string | 申请人填写的答案 |

**AutoAppproved**

| 名称 | 类型 | 描述 |
|---|---|---|
| strategy_id | string | 自动审批通过的策略ID |

**事件示例（官方三例，逐字保留）**

示例1（用户申请入群申请）：

```json
{
 "group_openid": "30584554AA2BF4E72BD3B8F27A70339D",
 "join_request_id": "AVKiFWpdy0-q0rfCkpQFbWB9GvX7QPIe9hlsbVeO6TiurrZw1DHP0sXGnbUR4Xm79tKNpfl4zZynxeibVwwUD6h96RqiFB-4V6p5FKGXfqInOuQQSf5WwXr8lyIsn6yeaMwEI1KSuTTMBMNe6WN8bDtKg2REXTcF",
 "member_openid": "FE003FAF76C4817251FDC128A16753BB",
 "username": "痞孓小光光╮hw灰",
 "apply_at": "2026-08-05T16:21:40+08:00",
 "apply_source": "self_apply",
 "verify_info": {
 "method": "verify_message",
 "verify_message": "就快乐了"
 }
}
```

示例2（其他用户邀请用户入群）：

```json
{
 "group_openid": "30584554AA2BF4E72BD3B8F27A70339D",
 "join_request_id": "AZj4L11PQ3oFrs2xf0wyfPmJ-3ONzbTr9MZRnXCSfoGce4KkWIgaTDwtkLXJVBaPx61VW9dzQz041oPt8o-JbBSyIerWVziQp1LaxYQCoyEx8rhffLwfBp5OW1-WL5C5HNji3M9lwDfZO4h_zNT4r0lywGojY4CX",
 "member_openid": "DE538D0B23260BFEC30EA4A17C3A71B1",
 "username": "吓唬",
 "apply_at": "2026-08-05T16:36:32+08:00",
 "apply_source": "invited",
 "invited_by": "FE003FAF76C4817251FDC128A16753BB"
}
```

示例3（用户入群申请自动申请通过）：

```json
{
 "group_openid": "30584554AA2BF4E72BD3B8F27A70339D",
 "join_request_id": "AZ22mGUrkPeeNy6Fzz_raGskCnpnbdy7pIq6pME7XUgS72LOXTH4TxgzGlv3FmAGmNQAelRYYhBZYKgJUEoSgu21rSJVSdKOznbSu6FdXqXvZ10SkpI5fyE_876Va8KSbuLFbWdKa8Rh9nc_hzvZYKZT0_X1W0o4",
 "member_openid": "FE003FAF76C4817251FDC128A16753BB",
 "username": "痞孓小光光╮hw灰",
 "apply_at": "2026-08-05T17:32:52+08:00",
 "apply_source": "self_apply",
 "verify_info": {
 "method": "verify_message",
 "verify_message": "健健康康"
 },
 "auto_approved": {
 "strategy_id": "st_7c0b77d442"
 }
}
```

---

### 3.13 FRIEND_ADD —— 用户添加好友

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/friend_add.html

**触发时机（官方原文）**

> 通过传 scene_param 中的 callback_data 可区分不同来源的添加好友场景。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | FRIEND_ADD |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 添加时间戳（Unix 秒） |
| openid | string | 用户 OpenID |
| scene | integer | 加好友场景值。1000=缺省默认, 1001=网络搜索（全部tab）, 1002=网络搜索（机器人tab）, 1003=群场景, 1004=空间场景, 2001=站内分享资料页, 2002=站外分享资料页, 2003=开发者生成的分享链接（站内）, 2004=开发者生成的分享链接（站外） |
| scene_param | string | 开发者自定义的回调数据（callback_data），用于区分不同来源 |
| author | FriendAuthor | 用户信息 |
| short_code | string | 机器人分享链接的短链code |

**FriendAuthor**

| 名称 | 类型 | 描述 |
|---|---|---|
| union_openid | string | 用户统一 OpenID（跨应用标识） |

**事件示例（官方两例，逐字保留）**

示例1（用户添加好友（网络搜索场景））：

```json
{
 "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570523,
 "scene": 1001,
 "scene_param": "",
 "author": {
 "union_openid": "DB85A74E07BA08B5B44CD9ED332FCBD2"
 }
}
```

示例2（用户添加好友（开发者分享链接））：

```json
{
 "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570600,
 "scene": 2003,
 "scene_param": "callback_abc123",
 "author": {
 "union_openid": "DB85A74E07BA08B5B44CD9ED332FCBD2"
 }
}
```

---

### 3.14 FRIEND_DEL —— 用户删除好友

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/friend_del.html

**触发时机（官方原文）**

> 用户删除机器人好友时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | FRIEND_DEL |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| timestamp | integer | 删除时间戳（Unix 秒） |
| openid | string | 用户 OpenID |
| author | FriendAuthor | 用户信息 |

**FriendAuthor**

| 名称 | 类型 | 描述 |
|---|---|---|
| union_openid | string | 用户统一 OpenID（跨应用标识） |

**事件示例（官方，逐字）**

```json
{
 "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "timestamp": 1784570524
}
```

---

### 3.15 GUILD_CREATE —— 频道创建

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/guild_create.html

**触发时机（官方原文）**

> 机器人被加入到某个频道时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GUILD_CREATE |
| Intent | GUILDS (1<<0) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 频道 ID |
| name | string | 频道名称 |
| icon | string | 频道头像 URL |
| owner_id | string | 频道创建者 ID |
| member_count | integer | 频道成员数 |
| max_members | integer | 频道成员上限 |
| description | string | 频道简介 |
| joined_at | string | 加入时间，ISO8601 格式 |
| op_user_id | string | 操作人 ID |

**事件示例（官方，逐字）**

```json
{
 "id": "123456789012345678",
 "name": "技术交流频道",
 "icon": "https://thirdqq.qlogo.cn/0",
 "owner_id": "123456789012345678",
 "member_count": 100,
 "max_members": 1000,
 "description": "专注于技术分享与交流的频道",
 "joined_at": "2026-01-01T00:00:00+08:00",
 "op_user_id": "123456789012345678"
}
```

---

### 3.16 GUILD_UPDATE —— 频道更新

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/guild_update.html

**触发时机（官方原文）**

> 频道信息变更时触发。事件内容为变更后的数据。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GUILD_UPDATE |
| Intent | GUILDS (1<<0) |

**事件体字段说明**

与 GUILD_CREATE 完全相同的字段表：`id`、`name`、`icon`、`owner_id`、`member_count`、`max_members`、`description`、`joined_at`、`op_user_id`（官方页面重复给出，内容一致）。

**事件示例（官方，逐字）**

```json
{
 "id": "123456789012345678",
 "name": "更新后的频道",
 "owner_id": "123456789012345678",
 "icon": "https://thirdqq.qlogo.cn/0",
 "member_count": 12,
 "max_members": 1000,
 "description": "更新后的描述"
}
```

---

### 3.17 GUILD_DELETE —— 频道解散

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/guild_delete.html

**触发时机（官方原文）**

> 频道被解散或机器人被移除时触发。事件内容为变更前的数据。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | GUILD_DELETE |
| Intent | GUILDS (1<<0) |

**事件体字段说明**

与 GUILD_CREATE 相同的字段表（官方页面重复给出）。

**事件示例（官方，逐字）**

```json
{
 "id": "123456789012345678",
 "name": "测试频道",
 "owner_id": "123456789012345678",
 "icon": "https://thirdqq.qlogo.cn/0",
 "member_count": 10,
 "max_members": 1000,
 "description": "频道描述"
}
```

---

### 3.18 CHANNEL_CREATE —— 子频道创建

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/channel_create.html

**触发时机（官方原文）**

> 子频道被创建时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | CHANNEL_CREATE |
| Intent | GUILDS (1<<0) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 子频道 ID |
| guild_id | string | 所属频道 ID |
| name | string | 子频道名称 |
| type | integer | 子频道类型。0=文字, 2=语音, 4=分组, 10005=直播, 10006=应用, 10007=论坛 |
| sub_type | integer | 子频道子类型 |
| owner_id | string | 创建者 ID |
| op_user_id | string | 操作人 ID |

**事件示例（官方，逐字）**

```json
{
 "id": "123456",
 "guild_id": "123456789012345678",
 "name": "新子频道",
 "type": 0,
 "sub_type": 0,
 "position": 1,
 "owner_id": "123456789012345678"
}
```

> 注：官方「事件体」字段表未列出 `position`，但官方示例 JSON 中包含 `position` 字段。本文件如实保留该差异。

---

### 3.19 CHANNEL_UPDATE —— 子频道更新

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/channel_update.html

**触发时机（官方原文）**

> 子频道信息变更时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | CHANNEL_UPDATE |
| Intent | GUILDS (1<<0) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 子频道 ID |
| guild_id | string | 所属频道 ID |
| name | string | 子频道名称 |
| type | integer | 子频道类型。0=文字, 2=语音, 4=分组, 10005=直播, 10006=应用, 10007=论坛 |
| sub_type | integer | 子频道子类型 |
| owner_id | string | 创建者 ID |
| op_user_id | string | 操作人 ID |

**事件示例（官方，逐字）**

```json
{
 "id": "123456",
 "guild_id": "123456789012345678",
 "name": "更新后的子频道",
 "type": 0,
 "sub_type": 0,
 "position": 1,
 "owner_id": "123456789012345678"
}
```

---

### 3.20 CHANNEL_DELETE —— 子频道删除

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/channel_delete.html

**触发时机（官方原文）**

> 子频道被删除时触发。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | CHANNEL_DELETE |
| Intent | GUILDS (1<<0) |

**事件体字段说明（官方表格）**

与 CHANNEL_UPDATE 相同的字段表（官方页面重复给出，内容一致）。

**事件示例（官方，逐字）**

```json
{
 "id": "123456",
 "guild_id": "123456789012345678",
 "name": "被删除的子频道",
 "type": 0,
 "sub_type": 0,
 "position": 1,
 "owner_id": "123456789012345678"
}
```

---

### 3.21 INTERACTION_CREATE —— 互动事件

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/interaction_create.html

**触发时机（官方原文，逐字）**

> 用户与机器人的互动操作触发此事件，包括消息按钮点击、快捷菜单回调、消息反馈、清空会话、进出故事集、切换模型、用户/群授权等。 收到事件后需调用 PUT /interactions/{interaction_id} 接口回应，否则客户端会一直 loading 直到超时。
>
> 仅 type=11（消息按钮）和 type=12（快捷菜单）需要调用 PUT /interactions/{interaction_id} 回应；其他类型（消息反馈、清空会话、进出故事集、切换模型、授权等）无需回应。同一 interaction_id 只能回应一次，超时后失效。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | INTERACTION_CREATE |
| Intent | INTERACTION (1<<26) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 事件 ID，用于被动消息发送和互动回调 |
| type | integer | 互动类型 11 - 消息按钮回调（INLINE_KEYBOARD）：用户点击消息中的内联键盘按钮 12 - 单聊快捷菜单回调（CALLBACK_COMMAND）：用户点击单聊场景下的自定义菜单 13 - 消息反馈（MESSAGE_FEEDBACK）：用户对智能体消息进行点赞/点踩反馈 14 - 清空会话（CLEAR_SESSION）：用户清空智能体会话历史 15 - 进出故事集（IN_OUT_STORY）：用户进入或退出故事集 16 - 切换模型（SWITCH_MODEL）：用户切换智能体模型 18 - 用户授权（USER_AUTHORIZE）：用户授权事件 19 - 群授权（GROUP_AUTHORIZE）：群授权事件 20 - 群授权状态变更（GROUP_AUTHORIZE_STATUS） |
| scene | string | 事件发生场景。c2c=单聊, group=群聊, guild=频道 |
| chat_type | integer | 聊天场景。0=频道, 1=群聊, 2=单聊 |
| timestamp | string | 触发时间，RFC3339 格式 |
| guild_id | string | 频道 OpenID（仅频道场景有值） |
| channel_id | string | 子频道 OpenID（仅频道场景有值） |
| user_openid | string | 用户 OpenID（仅单聊场景有值） |
| group_openid | string | 群 OpenID（仅群聊场景有值） |
| group_member_openid | string | 群成员 OpenID（仅群聊场景有值） |
| data | InteractionData | 互动数据 |
| version | integer | 版本号，默认 1 |
| application_id | string | 机器人 AppID |

**InteractionData**

| 名称 | 类型 | 描述 |
|---|---|---|
| type | integer | 互动数据类型，与外层 type 含义一致。11=消息按钮点击, 12=快捷菜单点击, 13=消息反馈点击, 14=清空会话点击, 15=故事集点击, 16=切换模型点击 |
| resolved | InteractionResolved | 解析后的互动数据 |

**InteractionResolved**

| 名称 | 类型 | 描述 |
|---|---|---|
| button_data | string | 按钮的 data 字段值（发送消息按钮时设置）；消息反馈场景下为回调数据 |
| button_id | string | 按钮的 id 字段值（发送消息按钮时设置） |
| user_id | string | 操作用户 ID（仅频道场景有值） |
| feature_id | string | 功能 ID（仅快捷菜单有值，管理端设置） |
| message_id | string | 操作的消息 ID（频道场景为消息 OpenID；消息反馈场景为机器人消息 ID） |
| feedback_opt | string | 反馈选项（仅 type=13 消息反馈）。LIKE=点赞, UNLIKE=点踩 |
| checked | integer | 反馈选项是否选中（仅 type=13 消息反馈） |
| action | string | 操作类型（type=15 故事集：ENTER_STORY=进入, QUIT_STORY=退出；type=16 切换模型：对应操作动作） |
| message_scene | InteractionMessageScene | 消息场景信息（仅 type=13 消息反馈） |
| authorize_data | AuthorizeData | 授权数据（仅 type=18/19 用户/群授权事件） |

**InteractionMessageScene**

| 名称 | 类型 | 描述 |
|---|---|---|
| ext | []string | 扩展信息键值对列表，如 "disable_net_search=1" 表示关闭联网搜索 |

**AuthorizeData**

| 名称 | 类型 | 描述 |
|---|---|---|
| opt_scene | string | 授权操作场景。setting=资料页设置, dialog=弹窗授权 |
| scope | string | 授权范围。c2c_push=C2C 主动消息推送, group_push=群主动消息推送 |

**事件示例（官方三例，逐字保留）**

示例1（单聊消息按钮）：

```json
{
 "application_id": "1904842048",
 "chat_type": 2,
 "data": {
 "resolved": {
 "button_data": "confirm:once",
 "button_id": "allow-once"
 },
 "type": 11
 },
 "id": "1b13d569-4610-4ab9-bc51-feecc5def6d4",
 "scene": "c2c",
 "timestamp": "2026-07-20T21:53:54+08:00",
 "type": 11,
 "user_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "version": 1
}
```

示例2（群聊消息按钮）：

```json
{
 "application_id": "101984245",
 "chat_type": 1,
 "data": {
 "resolved": {
 "button_data": "eyJjb21tYW5kIjogInNhbXBsZSJ9"
 },
 "type": 11
 },
 "group_member_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "group_openid": "B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5",
 "id": "06915133-7aef-46ed-94f7-c50939e285ae",
 "scene": "group",
 "timestamp": "2026-07-20T21:53:54+08:00",
 "type": 11,
 "version": 1
}
```

示例3（用户授权）：

```json
{
 "application_id": "102057050",
 "data": {
 "resolved": {
 "authorize_data": {
 "opt_scene": "setting",
 "scope": "c2c_push"
 }
 }
 },
 "id": "c30c003e-9454-4450-8e5e-665267c088c4",
 "scene": "c2c",
 "timestamp": "2026-07-20T21:54:38+08:00",
 "type": 18,
 "user_openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "version": 1
}
```

**按钮与互动事件的关联（官方原文）** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/msg-btn.html

> 用户点击回调按钮会触发 `INTERACTION_CREATE` 事件，机器人收到事件后需调用 `PUT /interactions/{interaction_id}` 进行回应，否则客户端会一直处于 loading 状态直到超时。

---

### 3.22 SUBSCRIBE_MESSAGE_STATUS —— 订阅消息授权状态变更

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/subscribe_message_status.html

**触发时机（官方原文）**

> 用户对订阅消息模板的授权状态发生变化时触发。 可用于判断用户是否允许/拒绝接收某个订阅消息模板。

**事件基本信息**

| 字段 | 值 |
|---|---|
| 事件名 | SUBSCRIBE_MESSAGE_STATUS |
| Intent | GROUP_AND_C2C_EVENT (1<<25) |

**事件体字段说明（官方表格）**

| 名称 | 类型 | 描述 |
|---|---|---|
| group_openid | string | 群 OpenID（群订阅场景时有值） |
| openid | string | 用户 OpenID（个人订阅场景时有值） |
| result | []SubscribeMsgTemplateResult | 各模板的授权结果列表 |

**SubscribeMsgTemplateResult**

| 名称 | 类型 | 描述 |
|---|---|---|
| template_id | integer | 平台提供的订阅模板 ID |
| custom_template_id | string | 自定义订阅模板 ID |
| op | integer | 用户操作。1=允许订阅, 2=拒绝订阅 |
| subscribe_id | string | 订阅 ID，发送订阅消息时需使用 |
| subscribe_ts | integer | 订阅操作时间戳（Unix 秒） |
| update_ts | integer | 订阅状态最后更新时间戳（Unix 秒） |

**事件示例（官方，逐字）**

```json
{
 "openid": "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4",
 "result": [
 {
 "template_id": 10001,
 "custom_template_id": "tpl_abc123",
 "op": 1,
 "subscribe_id": "sub_def456",
 "subscribe_ts": 1784276820,
 "update_ts": 1784276820
 },
 {
 "template_id": 10002,
 "custom_template_id": "tpl_xyz789",
 "op": 2,
 "subscribe_id": "sub_ghi012",
 "subscribe_ts": 1784276815,
 "update_ts": 1784276820
 }
 ]
}
```

---

### 3.23 补充：频道消息事件（官方在非 autogen 页面给出，任务清单未列但属于同一事件体系）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/channel/message/event.html

#### 3.23.1 AT_MESSAGE_CREATE（intents PUBLIC_GUILD_MESSAGES）

**发送时机（官方原文）**

> - 用户发送消息，@当前机器人或回复机器人消息时
> - 为保障消息投递的速度，消息顺序我们虽然会尽量有序，但是并不保证是严格有序的，如开发者对消息顺序有严格有序的需求，可以自行缓冲消息事件之后，基于 Message.seq 进行排序

**内容**：内容为 [Message] 对象（见 3.26 节 Message 字段表）。

**示例（官方，逐字）**

```json
{
  "author": {
    "avatar": "http://thirdqq.qlogo.cn/0",
    "bot": false,
    "id": "1234",
    "username": "abc"
  },
  "channel_id": "100010",
  "content": "ndnnd",
  "guild_id": "18700000000001",
  "id": "0812345677890abcdef",
  "member": {
    "joined_at": "2021-04-12T16:34:42+08:00",
    "roles": ["1"]
  },
  "timestamp": "2021-05-20T15:14:58+08:00",
  "seq": 101 }
```

#### 3.23.2 MESSAGE_CREATE（intents PUBLIC_GUILD_MESSAGES，私域）

官方标题原文：`MESSAGE_CREATE（intents PUBLIC_GUILD_MESSAGES，私域）`

**发送时机（官方原文）**

> - 用户在文字子频道内发送的所有聊天消息（私域）
> - 为保障消息投递的速度，消息顺序我们虽然会尽量有序，但是并不保证是严格有序的，如开发者对消息顺序有严格有序的需求，可以自行缓冲消息事件之后，基于 Message.seq 进行排序

**示例（官方，逐字）**

```json
{
  "author": {
    "avatar": "http://thirdqq.qlogo.cn/0",
    "bot": false,
    "id": "1234",
    "username": "abc"
  },
  "channel_id": "100010",
  "content": "ndnnd",
  "guild_id": "18700000000001",
  "id": "0812345677890abcdef",
  "member": {
    "joined_at": "2021-04-12T16:34:42+08:00",
    "roles": ["1"]
  },
  "timestamp": "2021-05-20T15:14:58+08:00",
  "seq": 101
}
```

> **官方文档内部不一致标注**：`event-emit.html` 的 intents 清单中 `MESSAGE_CREATE` 归属 `GUILD_MESSAGES`（1<<9，私域）；而本页标题写为「MESSAGE_CREATE（intents PUBLIC_GUILD_MESSAGES，私域）」。两处表述不同，本文件如实并列。

#### 3.23.3 DIRECT_MESSAGE_CREATE（intents DIRECT_MESSAGE）

**发送时机（官方原文）**

> - 用户通过私信发消息给机器人时
> - 由于私信场景无法设置沙箱频道，目前私信事件不支持沙箱环境，开发者可以通过用户 id 白名单的方式来调试私信

**示例（官方，逐字）**

```json
{
    "author": {
        "avatar": "http://thirdqq.qlogo.cn/0",
        "bot": false,
        "id": "1234",
        "username": "abc"
    },
    "channel_id": "100010",
    "content": "ndnnd",
    "guild_id": "18700000000001",
    "id": "0812345677890abcdef",
    "member": {
        "joined_at": "2021-04-12T16:34:42+08:00",
        "roles": [
            "1"
        ]
    },
    "timestamp": "2021-05-20T15:14:58+08:00"
}
```

#### 3.23.4 MESSAGE_AUDIT_PASS / MESSAGE_AUDIT_REJECT（intents MESSAGE_AUDIT）

- **MESSAGE_AUDIT_PASS** 发送时机：消息审核通过
- **MESSAGE_AUDIT_REJECT** 发送时机：消息审核不通过
- 内容：`MessageAudited` 对象（见 3.26 节）

**示例（官方，逐字）**

```json
{
  "audit_id": "5f60b782-d134-4628-93b8-9baa4b182f48",
  "audit_time": "2022-01-04T18:05:42+08:00",
  "channel_id": "1699792",
  "create_time": "2022-01-04T18:05:42+08:00",
  "guild_id": "46646271634786417",
  "message_id": "10d0df671a1231343431313532313831383136323933383420801e280030a0cbc4013848404148f6b7d08e0650b1acf8fa05"
}
```

#### 3.23.5 MESSAGE_REACTION_ADD / MESSAGE_REACTION_REMOVE（intents GUILD_MESSAGE_REACTIONS）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/emoji.html

官方原文：

- **MESSAGE_REACTION_ADD (intents GUILD_MESSAGE_REACTIONS)** 发送时机：用户对消息进行表情表态时
- **MESSAGE_REACTION_REMOVE (intents GUILD_MESSAGE_REACTIONS)** 发送时机：用户对消息进行取消表情表态时
- 内容为 `MessageReaction` 对象

**示例（官方，逐字）**

```json
{
  "user_id": "1111222233333",
  "emoji": {
    "id": "277",
    "type": 1
  },
  "channel_id": "12345",
  "guild_id": "11110011112222",
  "target": {
    "id": "2",
    "type": 0
  } }
```

> 补充：该页面还说明「目前表情表态仅支持在频道内使用」。

#### 3.23.6 官方 intents 清单中列出、但本文件未抓到独立事件页的事件

官方 `event-emit.html` 的 intents 清单中还列出了以下事件名，但**官方文档站未提供对应的独立事件页面**（本次抓取范围内未发现），因此其完整 JSON 样例与字段说明表：**官方文档未提供**。

- `GUILD_MEMBER_ADD` / `GUILD_MEMBER_UPDATE` / `GUILD_MEMBER_REMOVE`
- `MESSAGE_DELETE`
- `DIRECT_MESSAGE_DELETE`
- `PUBLIC_MESSAGE_DELETE`
- `FORUM_THREAD_CREATE` / `FORUM_THREAD_UPDATE` / `FORUM_THREAD_DELETE` / `FORUM_POST_CREATE` / `FORUM_POST_DELETE` / `FORUM_REPLY_CREATE` / `FORUM_REPLY_DELETE` / `FORUM_PUBLISH_AUDIT_RESULT`
- `AUDIO_START` / `AUDIO_FINISH` / `AUDIO_ON_MIC` / `AUDIO_OFF_MIC`

---

### 3.24 @ 机器人的消息结构（mentions / content 前缀处理）

**结论（基于官方文档已抓取内容）**

1. **群聊场景（GROUP_AT_MESSAGE_CREATE）**
   - 官方原文：`content` 字段「**已自动去除@机器人的前缀**」（`group_at_message_create.html` 事件体字段表；页面首段亦写「content 字段已自动去除@机器人的前缀」）。
   - 官方提供 `mentions` 字段：「消息中@的用户列表（**不含@机器人自身**）」（`group_at_message_create.html` 事件体字段表）。
   - `mentions` 的元素类型为 `User`（官方标注为 `[]User`），即具备 `User` 的全部字段（`id`、`username`、`bot`、`union_openid`、`union_user_account`、`user_openid`、`member_openid`、`member_role`）。
   - **官方文档未提供**群聊 `mentions` 的 JSON 样例。
2. **群全量消息（GROUP_MESSAGE_CREATE）**
   - 官方字段表同样给出 `mentions`：「消息中@的用户列表」（`group_message_create.html`）。
3. **频道场景（AT_MESSAGE_CREATE）**
   - `Message` 对象含 `mentions` 字段：「消息中@的人」，类型为 `User` 对象数组（`server-inter/message/template/model.html`）。
   - `Message` 对象另含 `mention_everyone`：「是否是@全员消息」。
   - **官方文档未提供** `content` 中出现 `<@!id>` 形式的说明。`<@!id>` 这一表示法**未在本次抓取到的任何官方页面中出现**，因此：**官方文档未提供**。

**「去掉 at 后的内容处理」**

- 群聊（`GROUP_AT_MESSAGE_CREATE` / `GROUP_MESSAGE_CREATE`）：官方明确 `content` **已自动去除@机器人的前缀**，开发者无需自行剥离（官方原文见上）。
- 频道（`AT_MESSAGE_CREATE`）：官方 `server-inter/channel/message/event.html` 页面**未给出** `content` 是否去除 @ 前缀的说明；该页 `AT_MESSAGE_CREATE` 示例中的 `content` 为 `"ndnnd"`，无 @ 前缀。
- **官方文档未提供**：`<@!id>` 的具体替换/清洗规则、`mentions` 与 `content` 中占位符的对应关系。

---

### 3.25 官方消息对象 Message / MessageAudited 字段表（频道体系）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/template/model.html

**消息对象(Message)**

| 字段名 | 类型 | 描述 |
|---|---|---|
| id | string | 消息 id |
| channel_id | string | 子频道 id |
| guild_id | string | 频道 id |
| content | string | 消息内容 |
| timestamp | ISO8601 timestamp | 消息创建时间 |
| edited_timestamp | ISO8601 timestamp | 消息编辑时间 |
| mention_everyone | bool | 是否是@全员消息 |
| author | User 对象 | 消息创建者 |
| attachments | MessageAttachment 对象数组 | 附件 |
| embeds | MessageEmbed 对象数组 | embed |
| mentions | User 对象数组 | 消息中@的人 |
| member | Member 对象 | 消息创建者的member信息 |
| ark | MessageArk | ark消息 |
| seq | int | 用于消息间的排序，seq 在同一子频道中按从先到后的顺序递增，不同的子频道之间消息无法排序。(目前只在消息事件中有值，`2022年8月1日` 后续废弃) |
| seq_in_channel | string | 子频道消息 seq，用于消息间的排序，seq 在同一子频道中按从先到后的顺序递增，不同的子频道之间消息无法排序 |
| message_reference | MessageReference 对象 | 引用消息对象 |

**MessageEmbed**

| 字段名 | 类型 | 描述 |
|---|---|---|
| title | string | 标题 |
| prompt | string | 消息弹窗内容 |
| thumbnail | MessageEmbedThumbnail 对象 | 缩略图 |
| fields | MessageEmbedField 对象数组 | embed 字段数据 |

**MessageEmbedThumbnail**：`url`(string，图片地址)

**MessageEmbedField**：`name`(string，字段名)

**MessageAttachment（频道体系）**：`url`(string，下载地址)

> 注意：频道体系的 `MessageAttachment` 官方只列出 `url` 一个字段；而 C2C/群聊体系的 `MessageAttachment`（3.1 节）列出 `url`/`filename`/`width`/`height`/`size`/`content_type`/`voice_wav_url`/`asr_refer_text`。两套体系的 `MessageAttachment` **不是同一个结构**，官方原文如此。

**MessageArk**：`template_id`(int，ark模板id（需要先申请）)、`kv`(MessageAkrKv arkkv数组，kv值列表)

**MessageArkKv**：`key`(string)、`value`(string)、`obj`(MessageArkObj arkobj类型的数组)

**MessageArkObj**：`obj_kv`(MessageArkObjKv objkv类型的数组)

**MessageArkObjKv**：`key`(string)、`value`(string)

**MessageReference**：`message_id`(string，需要引用回复的消息 id)、`ignore_get_message_error`(bool，是否忽略获取引用消息详情错误，默认否)

**MessageMarkdown**：`template_id`(int，markdown 模板 id)、`params`(MessageMarkdownParams)、`content`(string，原生 markdown 内容,与 `template_id` 和 `params`参数互斥,参数都传值将报错。)

**MessageMarkdownParams**：`key`(string，markdown 模版 key)、`values`(string 类型的数组，markdown 模版 key 对应的 values)

**MessageDelete**：`message`(Message 对象，被删除的消息内容)、`op_user`(User 对象，执行删除操作的用户)

**消息审核对象(MessageAudited)**

| 字段名 | 类型 | 描述 |
|---|---|---|
| audit_id | string | 消息审核 id |
| message_id | string | 消息 id，只有审核通过事件才会有值 |
| guild_id | string | 频道 id |
| channel_id | string | 子频道 id |
| audit_time | ISO8601 timestamp | 消息审核时间 |
| create_time | ISO8601 timestamp | 消息创建时间 |
| seq_in_channel | string | 子频道消息 seq |

**业务报错返回的数据信息(Data)** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/data/model.html

| 字段名 | 类型 | 描述 |
|---|---|---|
| message_audit | MessageAudited 对象 | 消息审核信息，只会填充该对象的 audit_id 字段 |

---

## 4. 消息元素在 JSON 中的结构差异

### 4.1 官方「消息类型」总览

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/overview.html

官方原文：通过 `msg_type` 指定消息格式，不同的类型对应不同的内容字段和收发能力。

**发送：msg_type**

| msg_type | 类型 | 内容字段 | 说明 |
|---|---|---|---|
| 0 | 文本 | `content` | 纯文本消息 |
| 2 | Markdown | `markdown` | 支持 Markdown 语法 |
| 7 | 富媒体 | `media` | 图片/视频/语音/文件，需先上传获取 `file_info` |

> 注意：该页只列出 0/2/7；而 `send-receive/send.html` 的请求参数说明中 `msg_type` 写为「0 文本、2 markdown、3 ark、4 embed、7 media 富媒体」。两处列举不一致，本文件如实并列。

**接收：message_type**

| message_type | 含义 | 说明 |
|---|---|---|
| 0 | 普通文本 | `content` 字段携带文本内容 |
| 3 | 结构化卡片 | `ark_data` 字段携带卡片数据 |
| 103 | 引用消息 | `msg_elements` 字段携带嵌套内容 |

官方原文补充：

> 图片、视频、语音、文件等附加内容通过 `attachments` 字段携带（`content_type` 区分具体类型），不通过 `message_type` 单独表示。

> 注：`c2c_message_create.html` / `group_at_message_create.html` 的 `message_type` 字段说明中另列出 `101=并行消息, 102=聊天记录`；`type/overview.html` 的接收表未列出 101/102。两处不一致，本文件如实并列。

**各场景支持情况（官方表格）**

| 类型 | 单聊 | 群聊 | 频道 |
|---|---|---|---|
| **文本** | 收发 ✅ | 收发 ✅ | 收发 ✅ |
| **Markdown** | 发 ✅ / 收 ❌ | 收发 ✅ | 发 ✅ / 收 ❌ |
| **图片** | 收发 ✅ | 收发 ✅ | 收发 ✅ |
| **视频** | 收发 ✅ | 收发 ✅ | 收发 ✅ |
| **语音** | 收发 ✅ | 收发 ✅ | 收发 ✅ |
| **文件** | 收发 ✅ | 收发 ✅ | ❌ |
| **结构化卡片** | 发 ❌ / 收 ✅ | 发 ❌ / 收 ✅ | 发 ❌ / 收 ❌ |
| **Embed** | ❌ | ❌ | 发 ✅ / 收 ❌ |
| **表情表态** | ❌ | ❌ | 收发 ✅ |
| **引用消息** | 收 ✅ | 收 ✅ | 收 ✅ |

官方原文补充：

> - 发送侧只有 msg_type=0/2/3/7 四种（见上方表格）
> - 富媒体上传流程见 [富媒体使用说明]
> - 表情表态仅频道支持，详见 [表情表态]

**文本消息场景支持（官方表格）** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/text.html

|  | **单聊** | **群聊** | **文字子频道** | **频道私信** |
|---|---|---|---|---|
| 机器人接收 | 支持 | 支持 | 支持 | 支持 |
| 机器人发送 | 支持 | 支持 | 支持 | 支持 |

### 4.2 各元素在**事件 JSON**（接收侧）中的位置与结构

| 元素 | 在事件 JSON 中的载体 | 结构要点（官方原文） | 来源 |
|---|---|---|---|
| **text（文本）** | 顶层 `content`（string） | `message_type=0` 时 `content` 携带文本 | `type/overview.html` |
| **image（图片）** | `attachments[]` 元素 | `content_type` 为 `image/jpeg`、`image/png`、`image/gif`；带 `width`/`height`/`size`/`url`/`filename` | `c2c_message_create.html`、`group_at_message_create.html`、`send-receive/event.html` |
| **file（文件）** | `attachments[]` 元素 | `content_type` = `file`（官方注释写「群文件」） | 同上 |
| **voice（语音）** | `attachments[]` 元素 | `content_type` = `voice`；另有 `voice_wav_url`（语音消息 SILK 等转换后的 WAV 文件 URL）与 `asr_refer_text`（语音消息 ASR 参考结果） | 同上 |
| **video（视频）** | `attachments[]` 元素 | `content_type` = `video/mp4` | 同上 |
| **emoji（表情）** | 无独立事件字段 | 官方 `type/overview.html` 将「表情表态」列为仅频道支持；事件为 `MESSAGE_REACTION_ADD` / `MESSAGE_REACTION_REMOVE`，内容为 `MessageReaction` 对象（含 `emoji.id`、`emoji.type`）。**官方未在消息事件体中提供 emoji 独立字段** | `trans/emoji.html`、`type/overview.html` |
| **ark（结构化卡片）** | 顶层 `ark_data`（`message_type=3`） | `ark_data` 含 `prompt`/`ark_type`/`ark_name`/`fields`；`fields` 为 object，常见键 `tag`/`tags`/`title`/`desc`/`jump_url`/`preview`/`source`/`source_logo`/`tag_icon`/`nickname`/`avatar`/`address` | `c2c_message_create.html` |
| **markdown** | 事件侧无 `markdown` 字段 | 官方收发表：Markdown 单聊「发 ✅ / 收 ❌」、群聊「收发 ✅」、频道「发 ✅ / 收 ❌」；**官方群聊接收 Markdown 时的 JSON 字段形态：官方文档未提供** | `type/overview.html` |
| **embed** | 事件侧仅频道 `Message.embeds` | `Message.embeds` 为 `MessageEmbed` 对象数组，含 `title`/`prompt`/`thumbnail`/`fields`；收发表：Embed 仅频道「发 ✅ / 收 ❌」 | `template/model.html`、`type/overview.html` |
| **attachment** | `attachments[]` | 见下方 4.3 两套结构对比 | 多处 |
| **按钮（button）** | 接收侧为 `INTERACTION_CREATE` 事件；发送侧为 `keyboard` | 见 4.5 | `trans/msg-btn.html`、`interaction_create.html` |
| **引用消息** | 顶层 `msg_elements[]`（`message_type=103`）+ `message_scene.ext` 中的 `ref_msg_idx` | 见 3.1 / 3.2 示例 3 | `c2c_message_create.html` |

### 4.3 attachments 的 content_type / url / filename / size / width / height（重点核对）

**（A）C2C / 群聊事件体系 `MessageAttachment`（来源：`c2c_message_create.html`、`group_at_message_create.html`、`group_message_create.html`）**

| 字段 | 类型 | 描述（官方原文） |
|---|---|---|
| `url` | string | 附件下载 URL |
| `filename` | string | 文件名 |
| `width` | integer | 图片宽度（像素），**非图片附件无此字段** |
| `height` | integer | 图片高度（像素），**非图片附件无此字段** |
| `size` | integer | 文件大小（字节） |
| `content_type` | string | 附件内容类型（MIME 类型）: `voice`=语音消息 `image/jpeg`=JPEG 图片 `image/png`=PNG 图片 `image/gif`=GIF 图片 `video/mp4`=MP4 视频 `file`=群文件 |
| `voice_wav_url` | string | 语音消息 SILK 等转换后的 WAV 文件 URL |
| `asr_refer_text` | string | 语音消息 ASR 参考结果 |

**（B）`send-receive/event.html` 的 attachment 对象（字段说明措辞略有差异）**

| 属性 | 类型 | 说明（官方原文） |
|---|---|---|
| content_type | string | 文件类型，"image/jpeg","image/png","image/gif"，"file"，"video/mp4"，"voice" |
| filename | string | 文件名称 |
| height | int | 图片高度 |
| width | int | 图片宽度 |
| size | int | 文件大小 |
| url | string | 文件链接 |
| voice_wav_url | string | 语音文件链接（wav格式） |
| asr_refer_text | string | 语音 asr 参考结果 |

**（C）频道体系 `MessageAttachment`（来源：`template/model.html`）**

| 字段名 | 类型 | 描述 |
|---|---|---|
| url | string | 下载地址 |

> 对比结论（官方原文对比）：C2C/群聊体系有 `content_type`/`filename`/`width`/`height`/`size`/`voice_wav_url`/`asr_refer_text`；频道体系只列出 `url`。**频道体系是否另有 `content_type` 等字段：官方文档未提供。**

**官方 attachments JSON 样例（image/jpeg，逐字）**

```json
 "attachments": [
 {
 "content_type": "image/jpeg",
 "filename": "photo.jpg",
 "url": "https://multimedia.nt.qq.com.cn/download?appid=xxx&fileid=xxx&rkey=xxx&spec=0",
 "width": 1920,
 "height": 1080,
 "size": 256000
 }
 ],
```

> **官方文档未提供**：`attachments` 中 file（文件）、voice（语音）、video（视频）三种 `content_type` 的**完整 JSON 样例**（官方只提供了 `image/jpeg` 的样例）。

### 4.4 发消息接口中元素字段（发送侧）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/send.html

**单聊 `POST /v2/users/{openid}/messages` 请求参数（官方表格）**

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| content | string | 否 | 文本消息内容 |
| msg_type | int | 是 | 消息类型：0 文本、2 markdown、3 ark、4 embed、7 media 富媒体 |
| markdown | object | 否 | Markdown 对象 |
| keyboard | object | 否 | Keyboard 对象 |
| ark | object | 否 | Ark 对象 |
| media | object | 否 | 富媒体单聊的 file_info |
| message_reference | object | 否 | 消息引用 |
| event_id | string | 否 | 前置收到的事件 ID，用于发送被动消息，支持事件："INTERACTION_CREATE"、"C2C_MSG_RECEIVE"、"FRIEND_ADD" |
| msg_id | string | 否 | 前置收到的用户发送过来的消息 ID，用于发送被动（回复）消息 |
| msg_seq | int | 否 | 回复消息的序号，与 msg_id 联合使用，避免相同消息 id 回复重复发送，不填默认是 1。相同的 msg_id + msg_seq 重复发送会失败。 |
| is_wakeup | bool | 否 | 指明发送消息为互动召回消息，与 msg_id，event_id 互斥使用 |

**群聊 `POST /v2/groups/{group_openid}/messages` 请求参数（官方表格）**

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| content | string | 是 | 文本消息内容 |
| msg_type | int | 是 | 消息类型： 0 文本、2 markdown、3 ark 消息、4 embed、7 media 富媒体 |
| markdown | object | 否 | Markdown 对象 |
| keyboard | object | 否 | Keyboard 对象 |
| media | object | 否 | 富媒体群聊的file_info |
| ark | object | 否 | Ark 对象 |
| message_reference | object | 否 | 消息引用 |
| event_id | string | 否 | 前置收到的事件 ID，用于发送被动消息，支持事件："INTERACTION_CREATE"、"GROUP_ADD_ROBOT"、"GROUP_MSG_RECEIVE" |
| msg_id | string | 否 | 前置收到的用户发送过来的消息 ID，用于发送被动消息（回复） |
| msg_seq | int | 否 | 回复消息的序号，与 msg_id 联合使用……相同的 msg_id + msg_seq 重复发送会失败。 |

**Markdown 数据结构**（来源：`type/markdown.html`）

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| content | string | 否 | 自定义 markdown 文本内容 |
| custom_template_id | string | 否 | markdown 模版id，申请模版后获得 |
| params | Array | 否 | {key: xxx, values: xxx}，模版内变量与填充值的kv映射 |

官方「2026/04/23 能力更新说明」：单聊场景、群聊场景自定义 Markdown 消息能力已开放到所有机器人均可使用，无需单独申请 Markdown 模版，频道场景目前需要内邀开通。

**Markdown 发送示例（官方，逐字）**

```json
{
  "markdown": {
    "content": "# 标题 \n## 简介很开心 \n内容[🔗腾讯](https://www.qq.com)"
  }
}
```

**ARK 结构化卡片数据结构**（来源：`type/ark.html`）

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| template_id | int | 是 | 模板 ID，可选 23 / 24 / 37 |
| kv | kv 数组 | 是 | `[{key: "#变量#", value: "填充值"}]`，模板变量与填充值的映射 |

官方说明原文（逐字）：达到准入条件的开发者，向平台运营申请后获得权限。

官方「模板 23 — 链接+文本列表」模板格式（逐字）：

```json
{
  "app": "com.tencent.channel.robot",
  "view": "albumAddPic",
  "ver": "0.0.0.1",
  "desc": "#DESC#",
  "prompt": "[QQ小程序]#PROMPT#",
  "meta": {
    "detail": {
      "list": "#LIST#"
    }
  } }
```

官方「模板 24 — 文本+缩略图」模板格式（逐字）：

```json
{
  "app": "com.tencent.channelrobot.smallpic",
  "view": "albumAddPic",
  "ver": "0.0.0.1",
  "desc": "#DESC#",
  "prompt": "[QQ小程序]#PROMPT#",
  "meta": {
    "detail": {
      "title": "#TITLE#",
      "desc": "#METADESC#",
      "img": "#IMG#",
      "link": "#LINK#",
      "subTitle": "#SUBTITLE#"
    }
  }
}
```

官方「模板 37 — 大图」模板格式（逐字）：

```json
{
  "app": "com.tencent.imagetextbot",
  "view": "index",
  "ver": "1.0.0.11",
  "prompt": "#PROMPT#",
  "meta": {
    "robot": {
      "title": "#METATITLE#",
      "subtitle": "#METASUBTITLE#",
      "cover": "#METACOVER#",
      "jump_url": "#METAURL#"
    }
  }
}
```

**富媒体（media / file_info）**（来源：`rich-media.html`）

| file_type | 类型 | 格式 | 软限制 | 硬限制 |
|---|---|---|---|---|
| 1 | 图片 | png / jpg | 20 MB | 200 MB |
| 2 | 视频 | mp4 | 30 MB | 200 MB |
| 3 | 语音 | silk | 20 MB | 200 MB |
| 4 | 文件 | - | 200 MB | 200 MB |

> 官方原文：超过软限制会降级为文件类型上传，超过硬限制会报错。

官方 `msg_type=7` 发送示例（逐字）：

```json
POST /v2/users/{user_openid}/messages
{
  "msg_type": 7,
  "media": {
    "file_info": "{上一步返回的 file_info}"
  }
}
```

官方 URL 上传示例（逐字）：

```json
POST /v2/users/{user_openid}/files
{
 "file_type": 1,
 "url": "https://example.com/image.png"
}
```

官方原文补充：

> 富媒体消息支持发送图片、视频、语音、文件等类型，需先将文件上传获取 `file_info`，再通过发消息接口（`msg_type=7`）携带 `media.file_info` 发送。
> `file_info` 有有效期（`ttl`），过期后需重新上传。
> `md5_10m`（文件前 10002432 字节，约 9.54 MB 的 MD5）可用于秒传判断，避免重复上传。
> 分片大小默认 5MB，并发数、重试策略由服务端在 `upload_config` 中下发。
> 单聊和群聊的文件上传接口相互独立，上传的文件不能跨场景使用。

### 4.5 按钮（keyboard）数据结构

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/msg-btn.html

官方原文：在 markdown 消息的基础上，支持消息最底部挂载按钮。

**发送方式（官方原文 + 样例逐字）**

【申请使用】按钮模版，按钮模版暂时不支持使用变量填充。

```json
{
    "keyboard": {
        "id": "123" // 申请模版后获得
    } }
```

【内邀开通】自定义按钮

```json
{
    "keyboard": {
        "content": {
            "rows": [
                {"buttons": [{button}, {button}, {button}, {button}, {button}]},
                {"buttons": [{button}, {button}, {button}, {button}, {button}]},
                {"buttons": [{button}, {button}, {button}, {button}, {button}]},
                {"buttons": [{button}, {button}, {button}, {button}, {button}]},
                {"buttons": [{button}, {button}, {button}, {button}, {button}]},
            ] // 自定义按钮内容，最多可以发送5行按钮，每一行最多5个按钮。
        }
    } }
```

**button 字段说明（官方表格）**

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| id | string | 否 | 按钮ID：在一个keyboard消息内设置唯一 |
| render_data.label | string | 是 | 按钮上的文字 |
| render_data.visited_label | string | 是 | 点击后按钮的上文字 |
| render_data.style | int | 是 | 按钮样式：0 灰色线框，1 蓝色线框 |
| action.type | int | 是 | 设置 0 跳转按钮：http 或 小程序 客户端识别 scheme，设置 1 回调按钮：回调后台接口, data 传给后台，设置 2 指令按钮：自动在输入框插入 @bot data |
| action.permission.type | int | 是 | 0 指定用户可操作，1 仅管理者可操作，2 所有人可操作，3 指定身份组可操作（仅频道可用） |
| action.permission.specify_user_ids | array | 否 | 有权限的用户 id 的列表 |
| action.permission.specify_role_ids | array | 否 | 有权限的身份组 id 的列表（仅频道可用） |
| action.data | string | 是 | 操作相关的数据 |
| action.reply | bool | 否 | 指令按钮可用，指令是否带引用回复本消息，默认 false。支持版本 8983 |
| action.enter | bool | 否 | 指令按钮可用，点击按钮后直接自动发送 data，默认 false。支持版本 8983 |
| action.anchor | int | 否 | 本字段仅在指令按钮下有效，设置后后会忽略 action.enter 配置。设置为 1 时 ，点击按钮自动唤起启手Q选图器，其他值暂无效果。（仅支持手机端版本 8983+ 的单聊场景，桌面端不支持） |
| action.click_limit | int | 否 | 【已弃用】可操作点击的次数，默认不限 |
| action.at_bot_show_channel_list | bool | 否 | 【已弃用】指令按钮可用，弹出子频道选择器，默认 false |
| action.unsupport_tips | string | 是 | 客户端不支持本action的时候，弹出的toast文案 |

官方完整示例（逐字）：

```json
{
  "rows": [
    {
      "buttons": [
        {
          "id": "1",
          "render_data": {
            "label": "⬅️上一页",
            "visited_label": "⬅️上一页"
          },
          "action": {
            "type": 1,
            "permission": {
              "type": 1,
              "specify_role_ids": [
                "1",
                "2",
                "3"
              ]
            },
            "click_limit": 10,
            "unsupport_tips": "兼容文本",
            "data": "data",
            "at_bot_show_channel_list": true
          }
        },
        {
          "id": "2",
          "render_data": {
            "label": "➡️下一页",
            "visited_label": "➡️下一页"
          },
          "action": {
            "type": 1,
            "permission": {
              "type": 1,
              "specify_role_ids": [
                "1",
                "2",
                "3"
              ]
            },
            "click_limit": 10,
            "unsupport_tips": "兼容文本",
            "data": "data",
            "at_bot_show_channel_list": true
          }
        }
      ]
    },
    {
      "buttons": [
        {
          "id": "3",
          "render_data": {
            "label": "📅 打卡（5）",
            "visited_label": "📅 打卡（5）"
          },
          "action": {
            "type": 1,
            "permission": {
              "type": 1,
              "specify_role_ids": [
                "1",
                "2",
                "3"
              ]
            },
            "click_limit": 10,
            "unsupport_tips": "兼容文本",
            "data": "data",
            "at_bot_show_channel_list": true
          }
        }
      ]
    }
  ] }
```

### 4.6 官方文档未提供的消息元素相关内容

- `emoji` 在**消息事件体**中的独立字段/结构：**官方文档未提供**（表情表态仅以 `MessageReaction` 事件形式出现，且仅频道支持）。
- 群聊接收 Markdown 消息时事件 JSON 中的 `markdown` 字段形态：**官方文档未提供**。
- `attachments` 中 `file` / `voice` / `video` 三种 `content_type` 的完整 JSON 样例：**官方文档未提供**。
- `msg_type=4 embed` 的发送请求体结构（仅列出字段名 `embeds` / `msg_type`，无独立字段说明页）：**官方文档未提供**（本次抓取范围内）。

---

## 5. 双通道对比：Gateway WSS vs Webhook 回调

### 5.1 官方对两种接入方式的定位（产品介绍页原文）

**来源**：https://bot.q.qq.com/wiki/bot_new_product-intro/ （8.1 事件与回调方式选择）

官方原文（逐字）：

> 点击「事件订阅与回调地址」，配置接收平台事件回调通知的方式，可切换 WebSocket 与 Webhook 连接方式。
>
> 👉**提示** ：切换后立刻生效，请谨慎操作，避免影响在线服务。
>
> **WebSocket** ：不依赖公网服务器部署，适合个人单机使用，需维护长连接。如果你是想用于连接 OpenClaw 等类似 AI Agent 服务，在 AI 服务提供方没有明确说明和指引的前提下，选用 WebSocket 即可。
>
> **Webhook** ：事件推送至你配置的 HTTPS 服务上，适合提供公开服务的机器人使用，运维更可靠。

**来源**：https://bot.q.qq.com/wiki/bot_new_product-intro/ （核心亮点）

官方原文（逐字）：

> **高效** ：支持WebSocket、WebHook回调连接方式灵活切换，可帮助开发者实现机器人快速开发迭代。

### 5.2 官方对两种方式的能力/行为差异说明

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

官方原文（逐字）：

> QQ机器人开放平台支持通过使用HTTP接口接收事件。开发者可通过[管理端]设定回调地址，监听事件等。
>
> 目前回调地址允许配置的端口号为： 80、443、8080、8443。

> 第一步先调用 [获取通用WSS 接入点] 或 [获取带分片WSS 接入点] 接口获取网关地址。
>
> 然后进行 `websocket` 长连接建立，一旦连接成功，就会返回 [OpCode 10 Hello] 消息。

**官方 OpCode 的「接入方式」对比（原文，见 1.2 节表格）**

| CODE | 名称 | 接入方式 | 客户端行为 | 描述 |
|---|---|---|---|---|
| 0 | Dispatch | webhook/websocket | Receive | 服务端进行消息推送 |
| 1 | Heartbeat | websocket | Send/Receive | 客户端或服务端发送心跳 |
| 2 | Identify | websocket | Send | 客户端发送鉴权 |
| 6 | Resume | websocket | Send | 客户端恢复连接 |
| 7 | Reconnect | websocket | Receive | 服务端通知客户端重新连接 |
| 9 | Invalid Session | websocket | Receive | 当 identify 或 resume 的时候，如果参数有错，服务端会返回该消息 |
| 10 | Hello | websocket | Receive | 当客户端与网关建立 ws 连接之后，网关下发的第一条消息 |
| 11 | Heartbeat ACK | websocket | Receive/Reply | 当发送心跳成功之后，就会收到该消息 |
| 12 | HTTP Callback ACK | webhook | Reply | 仅用于 http 回调模式的回包，代表机器人收到了平台推送的数据 |
| 13 | 回调地址验证 | webhook | Receive | 开放平台对机器人服务端进行验证 |

> 官方原文对客户端行为的定义：
> `Receive` 客户端接收到服务端 `push` 的消息；`Send` 客户端发送消息；`Reply` 客户端接收到服务端发送的消息之后的回包（HTTP 回调模式）。

**关键差异点（基于官方 OpCode 表）**

| 维度 | Gateway WSS | Webhook 回调 |
|---|---|---|
| 连接发起方向 | 客户端主动连腾讯网关（官方：`wss://api.bot.qq.com/websocket/`） | 腾讯推送到开发者公网后端（官方：「事件推送至你配置的 HTTPS 服务上」） |
| 专有 OpCode | 1/2/6/7/9/10/11（Heartbeat、Identify、Resume、Reconnect、Invalid Session、Hello、Heartbeat ACK） | 12（HTTP Callback ACK，回包）、13（回调地址验证） |
| 是否需心跳 | 需要（OpCode 1 Heartbeat，周期由 OpCode 10 Hello 的 `heartbeat_interval` 给定，官方样例 45000 毫秒） | 官方文档未提供心跳机制说明 |
| 是否需鉴权报文 | 需要（OpCode 2 Identify） | 官方文档未提供（通过回调地址验证 + 签名校验） |
| 断线补发机制 | 有（OpCode 6 Resume + `seq`，恢复后补发遗漏事件，随后下发 RESUMED） | 官方文档未提供 |
| 分片（Shard） | 支持（`shard` 参数 + `/gateway/bot` 返回建议分片数 + 分片哈希规则） | 官方文档未提供 |
| 鉴权/签名 | token（Identify 报文 `token` 字段） | Ed25519 签名校验（HTTP Header `X-Signature-Ed25519` + `X-Signature-Timestamp` + Body） |
| 回调地址端口限制 | 不适用 | 官方原文：允许配置的端口号为：80、443、8080、8443 |
| 配置入口 | 官方：管理端「事件订阅与回调地址」，可切换 WebSocket 与 Webhook | 同左 |
| 适用场景（官方原文） | 不依赖公网服务器部署，适合个人单机使用，需维护长连接；连接 AI Agent 服务时若无明确指引，选用 WebSocket 即可 | 事件推送至你配置的 HTTPS 服务上，适合提供公开服务的机器人使用，运维更可靠 |

> **官方文档未提供**：
> - Webhook 模式下的事件去重 / 重推策略说明（Gateway 侧官方给出了 `s`/`seq` 补发与 4009/4006 等重试语义）。
> - Webhook 模式的分片能力说明。
> - 两种模式在**事件类型覆盖范围**上是否存在差异的说明（官方文档未提供「某事件仅 WSS 可用」或「某事件仅 Webhook 可用」的表述）。

### 5.3 Webhook 的配置与鉴权（官方原文）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html 、 https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/webhook.html

**配置要求（官方原文）**

> 开发者需要提供一个HTTPS回调地址。并选定监听的事件类型。开放平台会将事件通过回调的方式推送给机器人。
>
> 目前回调地址允许配置的端口号为： 80、443、8080、8443。

**回调地址验证（OpCode 13）**

请求结构（Payload.d）：

| **字段** | **描述** |
|---|---|
| plain_token | 需要计算签名的字符串 |
| event_ts | 计算签名使用时间戳 |

返回结果：

| **字段** | **描述** |
|---|---|
| plain_token | 需要计算签名的字符串 |
| signature | 签名 |

官方计算过程（golang，逐字保留）：

```go
func handleValidation(rw http.ResponseWriter, r *http.Request, botSecret string) {
	httpBody, err := io.ReadAll(r.Body)
	if err != nil {
		log.Println("read http body err", err)
		return
	}
	payload := &Payload{}
	if err = json.Unmarshal(httpBody, payload); err != nil {
		log.Println("parse http payload err", err)
		return
	}
	validationPayload := &ValidationRequest{}
	if 	err = json.Unmarshal(payload.Data, validationPayload);err != nil {
		log.Println("parse http payload failed:", err)
		return
	}
	seed := botSecret
	for len(seed) < ed25519.SeedSize {
		seed = strings.Repeat(seed, 2)
	}
	seed = seed[:ed25519.SeedSize]
	reader := strings.NewReader(seed)
	// GenerateKey 方法会返回公钥、私钥，这里只需要私钥进行签名生成不需要返回公钥
	_, privateKey, err := ed25519.GenerateKey(reader)
	if err != nil {
		log.Println("ed25519 generate key failed:", err)
		return
	}
	var msg bytes.Buffer
	msg.WriteString(validationPayload.EventTs)
	msg.WriteString(validationPayload.PlainToken)
	signature := hex.EncodeToString(ed25519.Sign(privateKey, msg.Bytes()))
	if err != nil {
		log.Println("generate signature failed:", err)
		return
	}
	rspBytes, err := json.Marshal(
		&ValidationResponse{
			PlainToken: validationPayload.PlainToken,
			Signature: signature,
		})
	if err != nil {
		log.Println("handle validation failed:", err)
		return
	}
	rw.Write(rspBytes)
}
```

官方示例（逐字）：

```text
appid: 11111111
secret: DG5g3B4j9X2KOErG
```

```text
回调验证请求：
headers: User-Agent:[QQBot-Callback] X-Bot-Appid:[11111111]
body: {"d":{"plain_token":"Arq0D5A61EgUu4OxUvOp","event_ts":"1725442341"},"op":13},
```

```text
机器人应返回：
body: {"plain_token": "Arq0D5A61EgUu4OxUvOp","signature": "87befc99c42c651b3aac0278e71ada338433ae26fcb24307bdc5ad38c1adc2d01bcfcadc0842edac85e85205028a1132afe09280305f13aa6909ffc2d652c706"}
```

**回调请求签名校验（Ed25519）** —— 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/sign.html

官方原文（逐字）：

> 开发者需要对每一次回调请求，根据回调中的签名等信息验证请求者身份，避免安全隐患。目前签名算法使用Ed25519。
>
> 开发者平台的 Bot Secret 用于加密签名字符串和服务器端验证签名字符串的密钥。用户必须严格保管安全凭证，避免泄露。

**1. 签名验证参数（官方表格）**

| 字段名 | 说明 | 参考值 |
|---|---|---|
| X-Signature-Ed25519 | HTTP Header 中透传 Signature | 3ecd***（64字节） |
| X-Signature-Timestamp | HTTP Header 透传的签名时间戳 | 1636373772 |
| HTTP Body | HTTP 请求中 Body 值 | {"msg":"hello"} |

**2. 验证签名过程（官方 go 代码逐字）**

```go
  // 根据botSecret进行repeat操作后得到seed值计算出公钥
 seed := botSecret
 for len(seed) < ed25519.SeedSize {
 seed = strings.Repeat(seed, 2)
  }
 rand := strings.NewReader(seed[:ed25519.SeedSize])
 publicKey, privateKey, err := ed25519.GenerateKey(rand)
```

```go
  // 取HTTP header中X-Signature-Ed25519(进行hex解码)并校验 
 signature := req.Header.Get("X-Signature-Ed25519")
  if signature == "" {
    return false
  }
 sig, err := hex.DecodeString(signature)
  if err != nil {
    return false
  }
  if len(sig) != ed25519.SignatureSize || sig[63]&224 != 0 {
    return false
  }
```

```go
    // 取HTTP header中 X-Signature-Timestamp 并校验
 timestamp := req.Header.Get("X-Signature-Timestamp")
  if timestamp == "" {
    return false
  }
 httpBody, err := io.ReadAll(req.Body)
  if err != nil {
    return false
  }
  // 按照timestamp+Body顺序组成签名体
  var msg bytes.Buffer
 msg.WriteString(timestamp)
 msg.Write(httpBody)
  if err != nil {
    return false
  }
```

```go
 ed25519.Verify(publicKey, msg.Bytes(), sig)
```

官方 DEMO（逐字）：

```text
【输入】
secret: naOC0ocQE3shWLAfffVLB1rhYPG7
seed: naOC0ocQE3shWLAfffVLB1rhYPG7naOC
【输出】
publicKey: [215 195 98 254 120 174 248 31 242 50 135 180 147 98 139 93 176 42 60 79 227 11 33 94 77 25 96 155 93 118 103 58]
privateKey: [110 97 79 67 48 111 99 81 69 51 115 104 87 76 65 102 102 102 86 76 66 49 114 104 89 80 71 55 110 97 79 67 215 195 98 254 120 174 248 31 242 50 135 180 147 98 139 93 176 42 60 79 227 11 33 94 77 25 96 155 93 118 103 58]
```

```text
【输入】
secret: naOC0ocQE3shWLAfffVLB1rhYPG7
body: { "op": 0,"d": {}, "t": "GATEWAY_EVENT_NAME"}
timestamp: 1725442341

【输出】
sig: 865ad13a61752ca65e26bde6676459cd36cf1be609375b37bd62af366e1dc25a8dc789ba7f14e017ada3d554c671a911bfdf075ba54835b23391d509579ed002
```

### 5.4 Gateway WSS 的配置与鉴权（官方原文）

见 1.3 节时序报文与 1.4 节分片机制。要点：

- 先调用 `/gateway` 或 `/gateway/bot` 获取网关地址（官方样例 `wss://api.bot.qq.com/websocket/`）。
- 连接成功 → 收 OpCode 10 Hello（`heartbeat_interval`）。
- 发 OpCode 2 Identify（`token` / `intents` / `shard` / `properties`）。
- 按周期发 OpCode 1 Heartbeat，收 OpCode 11 Heartbeat ACK。
- 断线重连发 OpCode 6 Resume（`token` / `session_id` / `seq`），补发后收 RESUMED。

### 5.5 开发基础设置中的其它通道相关限制

**来源**：https://bot.q.qq.com/wiki/bot_new_product-intro/ （8.2 服务器 IP 白名单）

官方原文（逐字）：

> IP 白名单支持添加、删除，仅支持单个 IPv4，暂不支持 CIDR 网段。
>
> **温馨提示**
> 未设置 IP 白名单时，所有请求来源 IP 都会被调用，建议至少添加一条以提升安全性。
> 设置白名单后，仅白名单地址允许调通机器人 OpenAPI，支持最多 50 个 IP 地址。（原文为：「未设置 IP 白名单时，所有请求来源 IP 都会被允许调用，建议至少添加一条以提升安全性。设置白名单后，仅白名单地址允许调通机器人 OpenAPI，支持最多 50 个 IP 地址。」）

**来源**：https://bot.q.qq.com/wiki/develop/api/ （旧版开发说明）

官方原文：

> # 接口域名
> 正式环境： https://api.sgroup.qq.com/
> 沙箱环境： https://sandbox.api.sgroup.qq.com 沙箱环境只会收到测试频道的事件，且调用openapi仅能操作测试频道
>
> # 加密
> 只支持 HTTPS 以及 WSS。不支持不安全的 HTTP 与 WS。

---

## 6. 平台限制与风控

### 6.1 消息频控与主动/被动消息规则

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/overview.html

**主动消息与被动消息（官方表格）**

| 类型 | 特征 | 说明 |
|---|---|---|
| 主动消息 | 无任何条件 | 机器人主动触达用户，用户可在客户端关闭「允许主动发送」开关，关闭后主动消息将发送失败 |
| 互动召回消息 | `is_wakeup=true` | 用户主动与机器人对话之后每个周期内可下发 1 条召回消息 |
| 被动消息（回复用户） | 携带 `msg_id` | 对用户消息的回复 |
| 被动消息（响应事件） | 携带 `event_id` | 对事件的回复 |

**被动消息有效期与可回复次数（官方表格）**

| 场景 | 有效期 | 每条消息可回复次数 |
|---|---|---|
| 单聊 | 60 分钟 | 4 次 |
| 群聊 | 5 分钟 | 5 次 |
| 频道 | 5 分钟 | - |

**主动消息频控 —— 单聊（官方表格）**

| 认证类型 | 场景 | Bot 维度频控 | 单关系维度频控 | 每日上限 |
|---|---|---|---|---|
| 企业认证 | 单聊 | 10/qps | 20/qpm | 1000 条/用户 |
| 个人认证 | 单聊 | 10/qps | 20/qpm | 1000 条/用户 |
| 未认证 | 单聊 | 5/qps & 30/qpm | 20/qpm | 1000 条/用户 |

**主动消息频控 —— 群聊（官方表格）**

| 认证类型 | 场景 | Bot 维度频控 | 单关系维度频控 | 每日上限 |
|---|---|---|---|---|
| 企业认证 | 群 | 60/qpm | 20/qpm | 1000 条/群 |
| 个人认证 | 群 | 60/qpm | 20/qpm | 1000 条/群 |
| 未认证 | 群 | 30/qpm | 20/qpm | 1000 条/群 |

**互动召回消息（官方原文）**

> 在用户主动与机器人对话之后，机器人在未来 30 天内可下发互动召回消息给用户（消息类型与当前机器人拥有的消息类型权限一致），每个周期内可下发一条。分别为：当天、1 - 3 天、3 - 7 天、7 - 30 天，合计：4 个周期。在发消息接口中使用 is_wakeup 字段声明使用该能力。

**文字子频道（官方原文）**

> - 主动消息在频道主或管理设置了情况下，按设置的数量进行限频。在未设置的情况遵循如下限制:
>     - 主动推送消息，默认每天往每个子频道可推送的消息数是 20 条，超过会被限制。
>     - 主动推送消息在每个频道中，每天可以往 2 个子频道推送消息。超过后会被限制。
> - 不论主动消息还是被动消息，在一个子频道中，每秒 最多可发送 5 条 消息。
> - 被动回复消息有效期为 5 分钟，超时会发送失败。
> - 发送消息接口要求机器人接口需要连接到 WebSocket 上保持在线状态
> - 有关主动消息审核，可以通过 事件订阅 Intents 中审核事件 MESSAGE_AUDIT 返回 MessageAudited 对象获取结果。

**频道私信（官方原文）**

> - 私信场景下，每个机器人每天可以对一个用户发 2 条 主动消息。
> - 私信场景下，每个机器人每天累计可以发 200 条 主动消息。
> - 被动回复消息有效期为 5 分钟，超时会发送失败。

**消息去重（官方原文）**

> 相同 `msg_id` 可能多次推送，请结合 `msg_seq` 去重。被动回复时，相同的 `msg_id + msg_seq` 重复发送会失败，可递增 `msg_seq` 实现对同一消息的多次回复。

**撤回消息（官方原文）**

> 机器人可撤回自己发送的消息（发送超过 **2 分钟** 不可撤回）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/send.html

官方原文（逐字，注意该页同时保留了新旧两套口径）：

> 2026/06/22 主动推送能力更新说明
> 群场景主动推送消息能力于 2026/06/22 全量开放，当群主主动打开【机器人主动在群聊内发言】设置项后，机器人可对该群下发主动推动消息。
> 整体频控规则如下：
> - 机器人账号维度的限频规则，企业认证开发者：60 qpm、个人认证开发者：60 qpm、未认证：30 qpm
> - 单群（机器人发给某个群）维度的频控：20 qpm
> 若超频调用接口，平台返回相关超频错误信息。
>
> 2026/03/05 能力更新说明
> 沙箱环境内，机器人发送消息不受频控策略影响。
>
> 2026/01/10 能力更新说明
> 单聊场景新增互动召回消息能力，在用户主动与机器人对话之后，机器人在未来 30 天内可下发互动召回消息给用户（消息类型与当前机器人拥有的消息类型权限一致），每个周期内可下发一条。分别为：当天、1 - 3 天、3 - 7 天、7 - 30 天，合计：4 个周期，C2C发消息接口新增 is_wakeup 字段使用该能力，同时被动消息（回复类）由 `60 分钟 5 次` 调整为 `60 分钟 4 次` 。
>
> 注意
> 主动推送能力于 2025 年 4 月 21 日起不再提供，接口调用时会收到错误信息。 公告信息：[【关于QQ机器人消息推送策略调整通知】]
>
> 说明
> 发送消息分为，主动推送与被动回复，主动消息和被动消息在不同的场景下，发送的频次有不同的规则。 发送消息的接口有`4`个场景：QQ单聊、QQ群聊、文字子频道、频道私信
>
> 主动消息与被动消息说明： QQ 用户可以在 QQ 客户端主动设置是否接收机器人发送的主动消息，如果设置了关闭，主动消息一律发送失败。
>
> - 单聊
>     - 主动消息每月 `4 条`，超额会发送失败。（例如：给相同用户每月最多发 4 条）
>     - 被动消息（回复类）有效时间为 `60 分钟`，每个消息最多回复 `5 次`，超时或超频会发送（回复）失败；
>     - 互动召回消息：当用户主动与机器人对话之后每个的周期内可下发 1 条召回消息。周期分别为：当天、1 - 3 天、3 - 7 天、7 - 30 天。在用户隔天发消息给机器人后，周期都会按天维度往后重新计算。
> - 群聊
>     - 主动消息每月 `4 条`，超额会发送失败。（例如：给相同群每月最多发 4 条）
>     - 被动消息（回复类）有效时间为 `5 分钟`，每个消息最多回复 `5 次`，超时或超频会发送（发送/回复）失败；
> - 文字子频道
>     - 主动消息在频道主或管理设置了情况下，按设置的数量进行限频。在未设置的情况遵循如下限制:
>         - 主动推送消息，默认每天往每个子频道可推送的消息数是 `20` 条，超过会被限制。
>         - 主动推送消息在每个频道中，每天可以往 `2` 个子频道推送消息。超过后会被限制。
>     - 不论主动消息还是被动消息，在一个子频道中，`每秒` 最多可发送 `5 条` 消息。
>     - 被动回复消息有效期为 `5 分钟`，超时会发送失败。
>     - 发送消息接口要求机器人接口需要连接到 `WebSocket` 上保持在线状态
>     - 有关主动消息审核，可以通过 `事件订阅 Intents` 中审核事件 `MESSAGE_AUDIT` 返回 `MessageAudited` 对象获取结果。
> - 频道私信
>     - 私信场景下，每个机器人每天可以对一个用户发 `2 条` 主动消息。
>     - 私信场景下，每个机器人每天累计可以发 `200 条` 主动消息。
>     - 被动回复消息有效期为 `5 分钟`，超时会发送失败。
>
> 发送的消息内容包含 URL 的说明：
> 如开发者需要在消息内容发送含有 url 信息的消息，请现在 q.qq.com 后台-开发设置-消息URL配置 预先配置，否则会发送失败。 调用发消息 http 接口的 timeout 建议设置最低为 5 秒，避免出现实际消息已发送成功，但没接收到同步的结果返回。

> **官方文档内部不一致标注**：`overview.html` 写单聊被动消息「60 分钟 / 4 次」、群聊「5 分钟 / 5 次」；`send.html` 正文写单聊被动消息「60 分钟 / 5 次」（同时其 2026/01/10 更新说明又写「由 60 分钟 5 次 调整为 60 分钟 4 次」）、群聊「5 分钟 / 5 次」；`overview.html` 群聊主动消息每日上限为「1000 条/群」，`send.html` 写「主动消息每月 4 条」。三处口径不一致，本文件如实并列，不裁定。

**常见发送错误码（官方表格）**

| code | message | 说明 |
|---|---|---|
| 22009 | msg limit exceed | 消息发送超频 |
| 304082 | upload media info fail | 富媒体资源拉取失败，请重试 |
| 304083 | convert media info fail | 富媒体资源拉取失败，请重试 |

### 6.2 单聊与群聊权限 / 能力差异（官方表格汇总）

| 维度 | 单聊 | 群聊 | 频道 |
|---|---|---|---|
| 文件（富媒体） | 收发 ✅ | 收发 ✅ | ❌ |
| Markdown | 发 ✅ / 收 ❌ | 收发 ✅ | 发 ✅ / 收 ❌ |
| 结构化卡片 | 发 ❌ / 收 ✅ | 发 ❌ / 收 ✅ | 发 ❌ / 收 ❌ |
| Embed | ❌ | ❌ | 发 ✅ / 收 ❌ |
| 表情表态 | ❌ | ❌ | 收发 ✅ |
| 消息上传接口 | `/v2/users/{user_openid}/files` | `/v2/groups/{group_openid}/files` | 官方文档未提供 |
| 文件跨场景 | 官方原文：单聊和群聊的文件上传接口相互独立，上传的文件不能跨场景使用 | 同左 | 同左 |
| 被动消息有效期 | 60 分钟（overview 口径） | 5 分钟 | 5 分钟 |
| 主动消息每日上限 | 1000 条/用户 | 1000 条/群 | 每个子频道 20 条/天、每频道 2 个子频道/天 |
| 发送被动消息可用的 `event_id` | "INTERACTION_CREATE"、"C2C_MSG_RECEIVE"、"FRIEND_ADD" | "INTERACTION_CREATE"、"GROUP_ADD_ROBOT"、"GROUP_MSG_RECEIVE" | 官方文档未提供 |

> 来源：`type/overview.html`、`overview.html`、`send.html`、`rich-media.html`。

### 6.3 群场景特殊能力

- **接收全量消息**：官方原文（`group_message_create.html`）——「当机器人开启了"接收所有消息"功能后，群里的每一条消息（不限于@机器人）都会推送此事件」；`send-receive/event.html` ——「当群主设定允许该机器人接收群内全部消息时，机器人可接收到群内所有成员在群内的发言消息」。
- **主动在群内发言**：官方原文（`send.html`）——「群场景主动推送消息能力于 2026/06/22 全量开放，当群主主动打开【机器人主动在群聊内发言】设置项后，机器人可对该群下发主动推动消息」。
- **群管理员专属事件**：官方原文（`group_join_request.html`）——「1.只有当机器人是群管理员时才可以收到此事件」。

### 6.4 认证身份带来的能力差异（个人 / 企业 / 未认证）

**来源**：https://bot.q.qq.com/wiki/bot_new_product-intro/ （5.1 服务范围修改）

官方原文（逐字）：

> **未认证** ：机器人仅管理员使用，可添加到管理员作为群主的群内。
>
> **个人认证** ：可设置为公开使用，机器人进群数量添加上限为 500 个。
>
> **企业认证** ：场景均可设置为公开被使用的服务范围。

**来源**：https://bot.q.qq.com/wiki/ （介绍与接入指南，第 7 章 开发场景选择）

官方表格：

| 认证身份 | QQ频道 | QQ群 | 消息列表单聊 |
|---|---|---|---|
| 企业开发者 | ✅ | ✅ | ✅ |
| 个人开发者 | ✅ | ✅ | ✅ |

**来源**：https://bot.q.qq.com/wiki/ （第 2/3 章）

官方原文（逐字）：

> 企业主体入驻开发者，除默认开通的能力外，后续其他接口能力申请上，企业开发者与个人开发者也存在差异。

> 个人主体入驻的开发者，相比企业主体，在后续其他接口能力申请上，企业开发者与个人开发者会存在差异。

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/send.html

官方频控原文（逐字）：机器人账号维度的限频规则，企业认证开发者：60 qpm、个人认证开发者：60 qpm、未认证：30 qpm。

> **官方文档未提供**：「个人开发者 / 未上架机器人不能使用的具体能力清单」这一独立文档。官方仅以「存在差异」「需要申请」「达到准入条件」等表述描述，未给出逐项清单。
> 官方提到「需要向平台申请 / 内邀 / 达到准入条件」的能力（原文）包括：
> - ARK 结构化卡片：官方原文「达到准入条件的开发者，向平台运营申请后获得权限。」
> - 自定义 Markdown（频道场景）：官方原文「频道场景目前需要内邀开通。」
> - 自定义按钮：官方原文「【内邀开通】自定义按钮」
> - 特殊事件类型订阅：官方原文「其他的特殊事件，都需要经过申请才能够使用」

### 6.5 未上架 / 下架 / 封禁的运行时表现

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html （WebSocket 错误码）

| 值 | 含义 | 是否可以重试 RESUME | 是否可以重试 IDENTIFY |
|---|---|---|---|
| 4914 | 机器人已下架,只允许连接沙箱环境,请断开连接,检验当前连接环境 | 否 | 否 |
| 4915 | 机器人已封禁,不允许连接,请断开连接,申请解封后再连接 | 否 | 否 |

官方处理逻辑原文：

> - 4009 可以重新发起 resume
> - 4914，4915 不可以连接，请联系官方解封
> - 其他错误，请重新发起 identify

**HTTP 侧封禁相关错误码（官方原文）**

| 值 | 含义 |
|---|---|
| 11254 | ErrorInterfaceForbidden 应用接口被封禁，该机器人虽然获得了该接口权限，但是被封禁了。 |
| 11265 | ErrorRobotHasBaned 机器人已经被封禁 |

**HTTP 侧风控/打击相关错误码（官方原文，节选与风控强相关项）**

| 值 | 含义 |
|---|---|
| 1100100 | 安全打击：消息被限频 |
| 1100101 | 安全打击：内容涉及敏感，请返回修改 |
| 1100102 | 安全打击：抱歉，暂未获得新功能体验资格 |
| 1100103 | 安全打击 |
| 1100104 | 安全打击：该群已失效或当前群已不存在 |
| 1100308 | 触发频道内限频 |
| 1100300 | 系统内部错误 |
| 1100301 | 调用方不是群成员 |
| 1100302 | 获取指定频道名称失败 |
| 1100303 | 主页频道非管理员不允许发消息 |
| 1100304 | @次数鉴权失败 |
| 1100305 | TinyId 转换 Uin 失败 |
| 1100306 | 非私有频道成员 |
| 1100307 | 非白名单应用子频道 |
| 1100499 | 其他错误 |
| 3300006 | 安全打击（属「编辑消息错误」段） |

### 6.6 违规处理规则（运营规范）

**来源**：https://bot.q.qq.com/wiki/business/

官方原文（逐字，总则）：

> 如果我们认为你的 QQ 机器人违反了我们的条款、相关平台规则或法律法规，或对 QQ 、 QQ 机器人开放平台造成了影响，则 QQ 有权对你的 QQ 机器人采取 **强制措施** ，包括但不限于 **限制你的** **QQ** **机器人访问平台功能** 、 **封禁** **QQ** **机器人** 、 **要求删除数据** 、 **终止协议等** 。

**5.1 内容安全（官方原文）**

> - **违规内容 ：** QQ 机器人涉及未设置过滤违法、违规等不当信息内容的机制。建议调用内容安全检测接口校验文本/图片是否含有敏感内容，提升信息安全防护能力，降低被恶意利用导致传播恶意内容的风险。
> - **处罚规则 ：** 一经发现将根据违规程度对该 QQ 机器人帐号封禁搜索，添加能力，直至下架处理。

**5.2 刷量行为**

> - **违规内容：** 不得存在恶意刷票、刷粉、刷单等行为。包括但不限于通过第三方技术、工具等进行刷票、刷粉、刷单等行为或为上述行为提供工具或服务。
> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人采取相应的处理措施直至封号处理。

**5.3 网赚行为**

> - **违规内容：** 存在自行或协助他人以拟人程序、利诱其他用户参与、转发、下载或委托刷单平台等方式的行为。如：诱导转发内容获取利益，包括但不限于现金、礼品、积分等；诱导下载 APP 或使用 APP 获取收益等。（对于有其他主要功能的 QQ 机器人，分享获利只是活动促销手段的，不视为网赚）。
> - **处罚规则：** 一经发现将对该 QQ 机器人帐号进行封号处理。

**5.4 外挂行为**

> - **违规内容：** 未经腾讯书面许可，不得使用或推荐、介绍使用插件、外挂或其他违规第三方工具、服务接入本服务和相关系统。如：售卖或宣传外挂类游戏软件、辅助性破解功能软件等。
> - **处罚规则：** 帐号仅售卖或宣传外挂软件、无其他功能的 QQ 机器人，将被永久封号。

**5.5 侵犯名誉/商誉/隐私/肖像行为**

> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人侵权名称、头像等违规内容清空直至下架处理。

**5.6 侵犯知识产权行为**

> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人侵权内容清空直至下架处理。

**5.7 多级分销经营行为**

> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人进行限制功能直至主体封禁处理，并有权拒绝再向该主体提供服务。

**5.8 互推行为**

> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人采取限制功能直至封号处理。

**5.9 欺诈行为**

> - **处罚规则：** 一经发现将对该 QQ 机器人帐号封号处理。

**5.10 收集用户个人信息的行为**

> - **处罚规则：** 经发现将封禁该 QQ 机器人帐号相应接口权限，视情节严重进行下架直至封号处理。

**5.11 混淆行为**

> - **处罚规则：** 一经发现将对该 QQ 机器人帐号封号处理。

**5.12 滥用接口能力行为**

> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人的接口能力进行封禁，直至封号处理。

**5.13 过度营销行为**

> - **处罚规则：** 一经发现将根据违规程度对该 QQ 机器人帐号进行更新消息接口能力封禁或封号下架处理。

**6.1 违反国家法律法规禁止的内容**

> - **处罚规则：** 违法违规类帐号一经发现将进行永久封号处理。

**6.2 色情低俗内容**

> - **处罚规则 ：** 一经发现将根据违规程度对该 QQ 机器人采取相应的处理措施。

**6.3 垃圾广告**

> - **处理规则：** 一经发现将对该 QQ 机器人帐号进行封号处理。

**注册提交 / 基本信息 / 功能设置 / 主体 / 技术实现等其他规范要点（官方原文）**

> **（1）** 不允许批量注册、重复提交大量相似的 QQ 机器人。
> **（2）** 不允许相同问题或同类型问题，拒不修改反复提审。
> **（3）** 未经腾讯公司授权的情况下， QQ 机器人的添加，必须是免费的，不得设置付费添加。
> **（4）** 完成注册后，如帐号长期未登录， QQ 机器人可能被终止使用，终止使用后注册所使用的邮箱、身份证、 QQ 号等信息可能将被取消注册状态。

### 6.7 平台其它量化限制（官方原文）

| 项目 | 限制 | 来源 |
|---|---|---|
| 回调地址 | 上限为 10 条 | https://bot.q.qq.com/wiki/ （8.2 回调地址） |
| 消息 URL 白名单 | 域名上限为 20 条，每年可修改 50 次；域名需提前进行 ICP 备案，并通过域名校验才可报备成功 | https://bot.q.qq.com/wiki/ （8.3） |
| 机器人基本信息修改 | 每月可修改 5 次 | https://bot.q.qq.com/wiki/ （第 6 章 基础信息设置） |
| IP 白名单 | 仅支持单个 IPv4，暂不支持 CIDR 网段；支持最多 50 个 IP 地址 | https://bot.q.qq.com/wiki/bot_new_product-intro/ （8.2） |
| 内部体验号码 | 支持添加 20 个用户号码 | https://bot.q.qq.com/wiki/bot_new_product-intro/ （8.3） |
| 沙箱频道/群成员数 | 不可大于 20 人 | https://bot.q.qq.com/wiki/ （7.1 配置沙箱环境） |
| 网关连接数 | 每个机器人创建的连接数不能超过 `remaining` 剩余连接数 | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html |
| 按钮数量 | 最多可以发送5行按钮，每一行最多5个按钮 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/msg-btn.html |
| 富媒体文件 | 图片 软 20MB / 硬 200MB；视频 软 30MB / 硬 200MB；语音 软 20MB / 硬 200MB；文件 软 200MB / 硬 200MB | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/rich-media.html |
| 撤回窗口 | 发送超过 2 分钟不可撤回 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/overview.html |
| 日程（频道） | 每天只能创建 10 个日程 | 错误码 302012 |
| 私密子频道关联人数 | 私密子频道关联的人数到达上限（错误码 301004，未给出具体数值） | 错误码 301004 |

---

## 7. 错误与调试总表

### 7.1 错误码体系说明与全链路追踪

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html

官方原文（逐字）：

> 错误码分为两部分：
> - http 状态码
> - http body 返回的 json 中的 err_code

官方示例（逐字）：

```json
{
  "err_code": 40034005,
  "message": "回复消息msg_id已过期",
  "trace_id": "4a8a61565b909f199b1ec169fdd6f49e" }
```

**全链路追踪（官方原文）**

> 平台的链路追踪 `TraceID` 可通过两种方式获取：
> - **HTTP 响应头** ：`X-Tps-trace-ID` 字段
> - **响应 Body** ：返回体中的 `trace_id` 字段
>
> 如果开发者有无法自行定位的问题，需要找平台协助时，可提取该 ID 提交给平台方，方便查询相关日志。

### 7.2 HTTP 状态码（官方表格）

| 值 | 含义 |
|---|---|
| 200 | 成功 |
| 204 | 成功，但是无包体，一般用于删除操作 |
| 201,202 | 异步操作成功，虽然说成功，但是会返回一个 error body，需要特殊处理 |
| 401 | 认证失败 |
| 404 | 未找到 API |
| 405 | http method 不允许 |
| 429 | 频率限制 |
| 500 | 处理失败 |
| 504 | 处理失败 |

### 7.3 HTTP body 中的公共错误码（官方全表）

官方原文：以下为所有接口通用的公共错误码。各接口特有的错误码请查阅具体接口文档中的「错误码」章节。

**账号 / 频道 / 权限类（10001 ~ 11306）**

| 值 | 含义 |
|---|---|
| 10001 | UnknownAccount 账号异常 |
| 10003 | UnknownChannel 子频道异常 |
| 10004 | UnknownGuild 频道异常 |
| 11281 | ErrorCheckAdminFailed 检查是否是管理员失败，系统错误，一般重试一次会好，最多只能重试一次 |
| 11282 | ErrorCheckAdminNotPass 检查是否是管理员未通过，该接口需要管理员权限，但是用户在添加机器人的时候并未授予该权限，属于逻辑错误，可以提示用户进行授权 |
| 11251 | ErrorWrongAppid 参数中的 appid 错误，开发者填的 token 错误，appid 无法识别 |
| 11252 | ErrorCheckAppPrivilegeFailed 检查应用权限失败，系统错误，一般重试一次会好，最多只能重试一次 |
| 11253 | ErrorCheckAppPrivilegeNotPass 检查应用权限不通过，该机器人应用未获得调用该接口的权限，需要向平台申请 |
| 11254 | ErrorInterfaceForbidden 应用接口被封禁，该机器人虽然获得了该接口权限，但是被封禁了。 |
| 11261 | ErrorWrongAppid 参数中缺少 appid，同 11251 |
| 11262 | ErrorCheckRobot 当前接口不支持使用机器人 Bot Token 调用 |
| 11263 | ErrorCheckGuildAuth 检查频道权限失败，系统错误，一般重试一次会好，最多只能重试一次 |
| 11264 | ErrorGuildAuthNotPass 检查小站权限未通过，管理员添加机器人的时候未授予该接口权限，属于逻辑错误，可提示用户进行授权，如果已经给予授权，请检查传递的 guild id 是否正确 |
| 11265 | ErrorRobotHasBaned 机器人已经被封禁 |
| 11241 | ErrorWrongToken 参数中缺少 token |
| 11242 | ErrorCheckTokenFailed 校验 token 失败，系统错误，一般重试一次会好，最多只能重试一次 |
| 11243 | ErrorCheckTokenNotPass 校验 token 未通过，用户填充的 token 错误，需要开发者进行检查 |
| 11273 | ErrorCheckUserAuth 检查用户权限失败，当前接口不支持使用 Bearer Token 调用 |
| 11274 | ErrorUserAuthNotPass 检查用户权限未通过，用户 OAuth 授权时未给与该接口权限，可提示用户重新进行授权 |
| 11275 | ErrorWrongAppid 无 appid ，同 11251 |
| 11301 | ErrorGetHTTPHeader HTTP Header 无效 |
| 11302 | ErrorGetHeaderUIN HTTP Header 无效 |
| 11303 | ErrorGetNick 获取昵称失败 |
| 11304 | ErrorGetAvatar 获取头像失败 |
| 11305 | ErrorGetGuildID 获取频道 ID 失败 |
| 11306 | ErrorGetGuildInfo 获取频道信息失败 |

**通用请求类（12001 ~ 20028）**

| 值 | 含义 |
|---|---|
| 12001 | ReplaceIDFailed 替换 id 失败 |
| 12002 | RequestInvalid 请求体错误 |
| 12003 | ResponseInvalid 回包错误 |
| 20028 | ChannelHitWriteRateLimit 子频道消息触发限频 |

**消息类（50006 ~ 50057）**

| 值 | 含义 |
|---|---|
| 50006 | CannotSendEmptyMessage 消息为空 |
| 50035 | InvalidFormBody form-data 内容异常 |
| 50037 | 带有markdown消息只支持 markdown 或者 keyboard 组合 |
| 50038 | 非同频道同子频道 |
| 50039 | 获取消息失败 |
| 50040 | 消息模版类型错误 |
| 50041 | markdown 有空值 |
| 50042 | markdown 列表长达最大值 |
| 50043 | guild_id 转换失败 |
| 50045 | 不能回复机器人自己产生的消息 |
| 50046 | 非 at 机器人消息 |
| 50047 | 非机器人产生的消息 或者 at 机器人消息 |
| 50048 | message id 不能为空 |
| 50049 | 只能修改含有 keyboard 元素的消息 |
| 50050 | 修改消息时，keyboard 元素不能为空 |
| 50051 | 只能修改机器人自己发送的消息 |
| 50053 | 修改消息错误 |
| 50054 | markdown 模版参数错误 |
| 50055 | 无效的 markdown content |
| 50056 | 不允许发送 markdown content |
| 50057 | markdown 参数只支持原生语法或者模版二选一 |

**子频道权限错误（301000 ~ 301099 / 301000 ~ 301007）**

| 值 | 含义 |
|---|---|
| 301000~301099 | 子频道权限错误 |
| 301000 | 参数错误 |
| 301001 | 查询频道信息错误 |
| 301002 | 查询子频道权限错误 |
| 301003 | 修改子频道权限错误 |
| 301004 | 私密子频道关联的人数到达上限 |
| 301005 | 调用 Rpc 服务失败 |
| 301006 | 非群成员没有查询权限 |
| 301007 | 参数超过数量限制 |

**日程错误（302000 ~ 302024）**

| 值 | 含义 |
|---|---|
| 302000 | 参数错误 |
| 302001 | 查询频道信息错误 |
| 302002 | 查询日程列表失败 |
| 302003 | 查询日程失败 |
| 302004 | 修改日程失败 |
| 302005 | 删除日程失败 |
| 302006 | 创建日程失败 |
| 302007 | 获取创建者信息失败 |
| 302008 | 子频道 ID 不能为空 |
| 302009 | 频道系统错误，请联系客服 |
| 302010 | 暂无修改日程权限 |
| 302011 | 日程活动已被删除 |
| 302012 | 每天只能创建 10 个日程，明天再来吧！ |
| 302013 | 创建日程触发安全打击 |
| 302014 | 日程持续时间超过 7 天，请重新选择 |
| 302015 | 开始时间不能早于当前时间 |
| 302016 | 结束时间不能早于开始时间 |
| 302017 | Schedule 对象为空 |
| 302018 | 参数类型转换失败 |
| 302019 | 调用下游失败，请联系客服 |
| 302020 | 日程内容违规、账号违规 |
| 302021 | 频道内当日新增活动达上限 |
| 302022 | 不能绑定非当前频道的子频道 |
| 302023 | 开始时跳转不可绑定日程子频道 |
| 302024 | 绑定的子频道不存在 |

**消息发送 / 消息组件错误（304003 ~ 304052）**

| 值 | 含义 |
|---|---|
| 304003 | URL_NOT_ALLOWED url 未报备 |
| 304004 | ARK_NOT_ALLOWED 没有发 ark 消息权限 |
| 304005 | EMBED_LIMIT embed 长度超限 |
| 304006 | SERVER_CONFIG 后台配置错误 |
| 304007 | GET_GUILD 查询频道异常 |
| 304008 | GET_BOT 查询机器人异常 |
| 304009 | GET_CHENNAL 查询子频道异常 |
| 304010 | CHANGE_IMAGE_URL 图片转存错误 |
| 304011 | NO_TEMPLATE 模板不存在 |
| 304012 | GET_TEMPLATE 取模板错误 |
| 304014 | TEMPLATE_PRIVILEGE 没有模板权限 |
| 304016 | SEND_ERROR 发消息错误 |
| 304017 | UPLOAD_IMAGE 图片上传错误 |
| 304018 | SESSION_NOT_EXIST 机器人没连上 gateway |
| 304019 | AT_EVERYONE_TIMES @全体成员 次数超限 |
| 304020 | FILE_SIZE 文件大小超限 |
| 304021 | GET_FILE 下载文件错误 |
| 304022 | PUSH_TIME 推送消息时间限制 |
| 304023 | PUSH_MSG_ASYNC_OK 推送消息异步调用成功, 等待人工审核 |
| 304024 | REPLY_MSG_ASYNC_OK 回复消息异步调用成功, 等待人工审核 |
| 304025 | BEAT 消息被打击 |
| 304026 | MSG_ID 回复的消息 id 错误 |
| 304027 | MSG_EXPIRE 回复的消息过期 |
| 304028 | MSG_PROTECT 非 At 当前用户的消息不允许回复 |
| 304029 | CORPUS_ERROR 调语料服务错误 |
| 304030 | CORPUS_NOT_MATCH 语料不匹配 |
| 304031 | 私信已关闭 |
| 304032 | 私信不存在 |
| 304033 | 拉私信错误 |
| 304034 | 不是私信成员 |
| 304035 | 推送消息超过子频道数量限制 |
| 304036 | 没有 markdown 模板的权限 |
| 304037 | 没有发消息按钮组件的权限 |
| 304038 | 消息按钮组件不存在 |
| 304039 | 消息按钮组件解析错误 |
| 304040 | 消息按钮组件消息内容错误 |
| 304044 | 取消息设置错误 |
| 304045 | 子频道主动消息数限频 |
| 304046 | 不允许在此子频道发主动消息 |
| 304047 | 主动消息推送超过限制的子频道数 |
| 304048 | 不允许在此频道发主动消息 |
| 304049 | 私信主动消息数限频 |
| 304050 | 私信主动消息总量限频 |
| 304051 | 消息设置引导请求构造错误 |
| 304052 | 发消息设置引导超频 |

**撤回消息错误（306001 ~ 306006）**

| 值 | 含义 |
|---|---|
| 306001 | param invalid 撤回消息参数错误 |
| 306002 | msgid error 消息 id 错误 |
| 306003 | fail to get message 获取消息错误(可重试) |
| 306004 | no permission to delete message 没有撤回此消息的权限 |
| 306005 | retract message error 消息撤回失败(可重试) |
| 306006 | fail to get channel 获取子频道失败(可重试) |

**公告错误（501000 ~ 501999 / 501001 ~ 501020）**

| 值 | 含义 |
|---|---|
| 501000~501999 | 公告错误 |
| 501001 | 参数校验失败 |
| 501002 | 创建子频道公告失败(可重试) |
| 501003 | 删除子频道公告失败(可重试) |
| 501004 | 获取频道信息失败(可重试) |
| 501005 | MessageID 错误 |
| 501006 | 创建频道全局公告失败(可重试) |
| 501007 | 删除频道全局公告失败(可重试) |
| 501008 | MessageID 不存在 |
| 501009 | MessageID 解析失败 |
| 501010 | 此条消息非子频道内消息 |
| 501011 | 创建精华消息失败(可重试) |
| 501012 | 删除精华消息失败(可重试) |
| 501013 | 精华消息超过最大数量 |
| 501014 | 安全打击 |
| 501015 | 此消息不允许设置 |
| 501016 | 频道公告子频道推荐超过最大数量 |
| 501017 | 非频道主或管理员 |
| 501018 | 推荐子频道 ID 无效 |
| 501019 | 公告类型错误 |
| 501020 | 创建推荐子频道类型频道公告失败 |

**禁言相关错误（502000 ~ 502099 / 502001 ~ 502010）**

| 值 | 含义 |
|---|---|
| 502000~502099 | 禁言相关错误 |
| 502001 | 频道 id 无效 |
| 502002 | 频道 id 为空 |
| 502003 | 用户 id 无效 |
| 502004 | 用户 id 为空 |
| 502005 | timestamp 不合法 |
| 502006 | timestamp 无效 |
| 502007 | 参数转换错误 |
| 502008 | rpc 调用失败 |
| 502009 | 安全打击 |
| 502010 | 请求头错误 |

**论坛/帖子错误（503001 ~ 503020）**

| 值 | 含义 |
|---|---|
| 503001 | 频道 id 无效 |
| 503002 | 频道 id 为空 |
| 503003 | 获取子频道信息失败 |
| 503004 | 超出发布帖子的频次限制 |
| 503005 | 帖子标题为空 |
| 503006 | 帖子内容为空 |
| 503007 | 帖子ID为空 |
| 503008 | 获取X-Uin失败 |
| 503009 | 帖子ID无效或不合法 |
| 503010 | 通过Uin获取TinyID失败 |
| 503011 | 帖子ID里面的时间戳无效或不合法 |
| 503012 | 帖子不存在或已删除 |
| 503013 | 服务器内部错误 |
| 503014 | 帖子JSON内容解析失败 |
| 503015 | 帖子内容转换失败 |
| 503016 | 链接数量超过限制 |
| 503017 | 字数超过限制 |
| 503018 | 图片数量超过限制 |
| 503019 | 视频数量超过限制 |
| 503020 | 标题长度超过限制 |

**消息频率相关错误（504000 ~ 504999 / 504001 ~ 504004）**

| 值 | 含义 |
|---|---|
| 504000~504999 | 消息频率相关错误 |
| 504001 | 请求参数无效错误 |
| 504002 | 获取 HTTP 头失败 |
| 504003 | 获取 BOT UIN 错误 |
| 504004 | 获取消息频率设置信息错误 |

**频道权限错误（610000 ~ 619999 / 610001 ~ 610014）**

| 值 | 含义 |
|---|---|
| 610000-619999 | 频道权限错误 ~~ |
| 610001 | 获取频道 ID 失败 |
| 610002 | 获取 HTTP 头失败 |
| 610003 | 获取机器人号码失败 |
| 610004 | 获取机器人角色失败 |
| 610005 | 获取机器人角色内部错误 |
| 610006 | 拉取机器人权限列表失败 |
| 610007 | 机器人不在频道内 |
| 610008 | 无效参数 |
| 610009 | 获取 API 接口详情失败 |
| 610010 | API 接口已授权 |
| 610011 | 获取机器人信息失败 |
| 610012 | 限频失败 |
| 610013 | 已限频 |
| 610014 | api 授权链接发送失败 |

**表情表态错误（620001 ~ 620007）**

| 值 | 含义 |
|---|---|
| 620001-629999 | 表情表态错误 |
| 620001 | 表情表态无效参数 |
| 620002 | 已经达到表情反应的类型数量上限 |
| 620003 | 已经设置过该表情表态 |
| 620004 | 没有设置过该表情表态 |
| 620005 | 没有权限设置表情表态 |
| 620006 | 操作限频 |
| 620007 | 表情表态操作失败，请重试 |

**互动回调数据更新（630001 ~ 630007）**

| 值 | 含义 |
|---|---|
| 630001-639999 | 互动回调数据更新 |
| 630001 | 互动回调数据更新无效参数 |
| 630002 | 互动回调数据更新获取AppID失败 |
| 630003 | 互动回调数据AppID不匹配 |
| 630004 | 互动回调数据更新内部存储错误 |
| 630005 | 互动回调数据更新内部存储读取错误 |
| 630006 | 互动回调数据更新读取请求AppID失败 |
| 630007 | 互动回调数据太大 |

**发消息错误（1000000 ~ 2999999；1100100 ~ 1100499）**

| 值 | 含义 |
|---|---|
| 1000000~2999999 | 发消息错误 |
| 1100100 | 安全打击：消息被限频 |
| 1100101 | 安全打击：内容涉及敏感，请返回修改 |
| 1100102 | 安全打击：抱歉，暂未获得新功能体验资格 |
| 1100103 | 安全打击 |
| 1100104 | 安全打击：该群已失效或当前群已不存在 |
| 1100300 | 系统内部错误 |
| 1100301 | 调用方不是群成员 |
| 1100302 | 获取指定频道名称失败 |
| 1100303 | 主页频道非管理员不允许发消息 |
| 1100304 | @次数鉴权失败 |
| 1100305 | TinyId 转换 Uin 失败 |
| 1100306 | 非私有频道成员 |
| 1100307 | 非白名单应用子频道 |
| 1100308 | 触发频道内限频 |
| 1100499 | 其他错误 |

**编辑消息错误（3000000 ~ 3999999；3300006）**

| 值 | 含义 |
|---|---|
| 3000000~3999999 | 编辑消息错误 |
| 3300006 | 安全打击 |

> **官方文档未提供**：完整的 `err_code` 与 `message`（英文标识）对照以 JSON 结构形式给出的清单；官方仅以上表形式列出「值 / 含义」。此外，各接口特有错误码（如 22009、304082、304083 出现在 `send.html`；40034005 出现在错误示例中）分散在各接口页，官方未提供汇总页。本文件的 6.1 节与 7.6 节已收录抓取到的接口特有错误码。

### 7.4 WebSocket 错误码全表

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html 与 https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/websocket.html （两页表格内容一致）

| 值 | 含义 | 是否可以重试 RESUME | 是否可以重试 IDENTIFY |
|---|---|---|---|
| 4001 | 无效的 opcode | 否 | 否 |
| 4002 | 无效的 payload | 否 | 否 |
| 4007 | seq 错误 | 否 | **是** |
| 4006 | 无效的 session id，无法继续 resume，请 identify | 否 | **是** |
| 4008 | 发送 payload 过快，请重新连接，并遵守连接后返回的频控信息 | **是** | **是** |
| 4009 | 连接过期，请重连并执行 resume 进行重新连接 | **是** | **是** |
| 4010 | 无效的 shard | 否 | 否 |
| 4011 | 连接需要处理的 guild 过多，请进行合理的分片 | 否 | 否 |
| 4012 | 无效的 version | 否 | 否 |
| 4013 | 无效的 intent | 否 | 否 |
| 4014 | intent 无权限 | 否 | 否 |
| 4900~4913 | 内部错误，请重连 | 否 | **是** |
| 4914 | 机器人已下架,只允许连接沙箱环境,请断开连接,检验当前连接环境 | 否 | 否 |
| 4915 | 机器人已封禁,不允许连接,请断开连接,申请解封后再连接 | 否 | 否 |

> 注：`error-trace/websocket.html` 页面中 4014 出现了两次（表格中重复一行「4014 | intent 无权限 | 否 | 否」）；`openapi/error/error.html` 只出现一次。本文件如实说明。

**官方给出的简单处理逻辑（两页原文一致）**

> - 4009 可以重新发起 resume
> - 4914，4915 不可以连接，请联系官方解封
> - 其他错误，请重新发起 identify

**按错误码的重试建议（依据官方表格「是否可以重试」列整理）**

| 错误码 | 建议动作（依据官方表格列） |
|---|---|
| 4008 / 4009 | 可 RESUME，也可 IDENTIFY |
| 4007 / 4006 | 不可 RESUME，可 IDENTIFY |
| 4900~4913 | 不可 RESUME，可 IDENTIFY |
| 4001 / 4002 / 4010 / 4011 / 4012 / 4013 / 4014 | RESUME 与 IDENTIFY 均不可 |
| 4914 / 4915 | 均不可，官方原文：「4914，4915 不可以连接，请联系官方解封」 |

> **官方文档未提供**：错误码的关闭帧（WebSocket Close Frame）具体格式、错误码与 `op` 报文的对应关系、`4008` 的频控具体阈值数值。

### 7.5 错误溯源（error-trace）页面说明

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/websocket.html

该页仅包含「错误码 code」表格（内容与 7.4 节一致）与「针对 WebSocket 错误码的简单处理逻辑」两条内容，**未提供**错误回溯/请求重放的额外机制说明。

### 7.6 接口特有错误码（抓取到的部分）

| code | message | 说明 | 来源 |
|---|---|---|---|
| 40034005 | 回复消息msg_id已过期 | 官方错误码示例中出现的 err_code | openapi/error/error.html |
| 22009 | msg limit exceed | 消息发送超频 | send-receive/send.html |
| 304082 | upload media info fail | 富媒体资源拉取失败，请重试 | send-receive/send.html |
| 304083 | convert media info fail | 富媒体资源拉取失败，请重试 | send-receive/send.html |

### 7.7 鉴权相关（Access Token / Token）

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/getting-started.html

官方原文（逐字）：

> 注册创建机器人后：获得的开发机器人接入票据 `AppID` `AppSecret`

| 名称 | 描述 | 备注 |
|---|---|---|
| AppID | 机器人 ID | 必须使用 |
| AppSecret | 机器人密钥 | 用于请求签名的密钥 |

> Token 的鉴权方式已废弃，请使用更安全的 `Access Token` 鉴权方式。

**来源**：https://bot.q.qq.com/wiki/develop/api/ （旧版，含 Token 格式说明）

官方原文：

> # 票据
> 申请机器人通过后，平台将会下发三个票据。具体描述如下：
> - bot_app_id 用于识别一个机器人的 id
> - bot_secret 用于在 oauth 场景进行请求签名的密钥
> - bot_token 机器人token，用于以机器人身份调用 openapi，格式为 `${app_id}.${random_str}`
>
> # OPENAPI 鉴权方式
> 使用在 HTTP 上添加 Authorization头来进行鉴权。支持两种类型的 TOKEN
> # Bot Token
> 使用申请机器人时平台返回的机器人 appID + token 拼接而成。此时，所有的操作都是以机器人身份来完成的。
> `Authorization: Bot 100000.Cl2FMQZnCjm1XVW7vRze4b7Cq4se7kKWs`
> # Bearer Token
> 使用 OAUTH2.0 接口，通过一次性 CODE 换取的代表用户登录态的 Token。此时所有的操作都是以授权用户的身份来完成的。
> `Authorization: Bearer CZhtkLDpNYXgPH9Ml6shqh2OwykChw`

**来源**：https://bot.q.qq.com/wiki/develop/api/ （ID 与数据格式说明）

官方原文：

> # ID 描述
> 协议中返回的用户ID，频道ID，子频道ID，均是 UINT64 类型的数字。
> 由于返回在 JSON 中，JS 解析 JSON 中的大数的时候会造成精度丢失所以在返回中都用字符串来返回。
>
> # 数据格式
> 目前仅支持返回 JSON 格式数据

### 7.8 文档更新日志（changelog）

**来源**：https://bot.q.qq.com/wiki/changelog/

> **官方说明**：该 `changelog` 页面为**研发/SDK 变更日志**（内容为 botpy、bot-docs 仓库的 commit 记录），**不是产品能力变更公告**。
> 页面条目形如：`feat: 完善ws事件中Message数据的构建`、`docs: 更新消息推送限制描述` 等，日期范围为 2021-12-19 ~ 2022-06-17。
> 页面中与「限制」相关的条目仅有：**「docs: 更新消息推送限制描述」**（2022-01-02），未展开具体内容。
> 因此：**任务要求的「平台限制变更历史」在 `changelog` 页中未提供**；产品能力变更说明实际位于各功能页顶部的「能力更新说明」段落（例如 `send.html` 的 2026/06/22、2026/03/05、2026/01/10 三条）。
> 页面最后更新时间为 `9/22/2026, 2:12:57 PM`。

---

## 8. 沙箱环境与测试

### 8.1 沙箱环境配置（官方原文）

**来源**：https://bot.q.qq.com/wiki/ （介绍与接入指南 · 7.1 配置沙箱环境）

官方原文（逐字）：

> 建议开发者根据实际的需要，选择在不同场景开发机器人，完成对应场景的沙箱环境配置。配置沙箱后，开发者可在「功能配置」、「使用范围与人员」页面解锁相应场景的配置能力。
>
> 沙箱频道仅可设置当前用户为频道主/管理员的频道、沙箱群仅可设置当前用户为群主/群管理员的群，且沙箱频道成员、沙箱群成员不可大于 `20` 人。

**温馨提示（官方原文）**

> （1）配置沙箱群/频道，需要先在QQ客户端创建符合沙箱要求的QQ群/QQ频道；
> （2）在频道场景，机器人仍然保留「公域」/「私域」机器人的区分，设置为公域机器人保存确认后不可切换为私域机器人，但在「使用范围与人员」可设置公域机器人的允许添加范围："全部用户可添加"/"仅白名单用户可添加"；
> （3）配置沙箱频道/群后，机器人会出现在沙箱频道/沙箱群的机器人列表当中。

### 8.2 添加机器人至沙箱环境（官方原文）

**来源**：https://bot.q.qq.com/wiki/ （7.2 添加机器人至沙箱环境）

官方原文：

> 配置好沙箱环境后，可通过机器人资料卡将测试机器人添加进沙箱频道/沙箱群/沙箱账号，沙箱群/沙箱频道也可通过群/频道设置页的机器人列表添加机器人。

- **7.2.1 添加到沙箱频道**
  - 方法一：移动端点击沙箱频道封面图-->选择「机器人」进入商店页-->点击添加测试机器人
  - 方法二：移动端登陆管理员QQ号-->扫描管理端频道机器人二维码-->打开机器人资料卡-->添加至频道-->选择配置好的沙箱频道-->确认添加
  - 官方温馨提示：二维码可在「使用范围与人员」页面扫描。
  - **【进入私信沙箱】**（官方原文）：沙箱频道添加好测试机器人后，已经配置沙箱私信账号的QQ号，从沙箱频道打开机器人资料卡，选择私信，即进入私信沙箱环境
  - 官方温馨提示：当账号在「沙箱配置」-「在频道私信配置」完成配置后，该账号从任意渠道进入该机器人的频道私信窗口，拉到的该机器人指令面板、基础信息资料等内容均为沙箱环境信息。
- **7.2.2 添加到沙箱群**
  - 方法一：移动端点击沙箱群"设置"-->选择「群机器人」进入商店页-->点击添加测试机器人
  - 方法二：移动端登陆管理员QQ号-->扫描管理端QQ群和消息列表机器人二维码-->打开机器人web资料卡-->点击「添加到机器人」-->跳转到native资料卡-->分享到沙箱群-->打开native资料卡-->点击「添加到本群」-->选择配置好的沙箱群-->授权确认添加
- **7.2.3 添加到沙箱账号消息列表**
  - 移动端登陆管理员QQ号-->扫描管理端QQ群和消息列表机器人二维码-->打开机器人资料卡-->点击"发消息"-->授权确认添加-->进入消息列表开启沙箱单聊对话

### 8.3 沙箱环境的接口域名与行为差异

**来源**：https://bot.q.qq.com/wiki/develop/api/

官方原文：

> # 接口域名
> 正式环境： https://api.sgroup.qq.com/
> 沙箱环境： https://sandbox.api.sgroup.qq.com 沙箱环境只会收到测试频道的事件，且调用openapi仅能操作测试频道

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/send-receive/send.html

官方原文（逐字）：

> 2026/03/05 能力更新说明
> 沙箱环境内，机器人发送消息不受频控策略影响。

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/autogen/event/direct_message.html 相关的私信说明（实际出现在 `server-inter/channel/message/event.html` 与 `server-inter/message/send-receive/event.html`）

官方原文：

> 由于私信场景无法设置沙箱频道，目前私信事件不支持沙箱环境，开发者可以通过用户 id 白名单的方式来调试私信

### 8.4 沙箱相关的错误码

**来源**：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html

| 值 | 含义 |
|---|---|
| 4914 | 机器人已下架,只允许连接沙箱环境,请断开连接,检验当前连接环境 |

### 8.5 内部体验号码（非沙箱，但属测试手段）

**来源**：https://bot.q.qq.com/wiki/bot_new_product-intro/ （8.3 内部体验号码）

官方原文（逐字）：

> 支持添加 20 个用户号码用于内部开发与内邀体验的场景；配置后不受服务范围的设置影响，可测试体验机器人的对话能力。

### 8.6 沙箱环境相关：官方文档未提供

- 沙箱环境与正式环境的 **OpenAPI 域名在 `api-v2` 文档中的对应说明**：`develop/api-v2/` 系列页面中未出现沙箱域名，仅在旧版 `develop/api/` 页面给出 `https://sandbox.api.sgroup.qq.com`。**官方文档未提供** `api-v2` 版的沙箱域名表。
- 沙箱环境的 **WSS 网关地址**：**官方文档未提供**。
- 沙箱环境的 **事件推送（Webhook）配置方式**与正式环境的差异：**官方文档未提供**。

---

## 9. 官方文档未提供的内容清单

本节汇总任务中出现、但官方文档未提供（或未在本次抓取范围内找到）的内容。全部标注为「官方文档未提供」。

### 9.1 关于 intents

| 项目 | 状态 |
|---|---|
| intents 掩码表所在页面 | **已定位**：`https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html` 的「事件订阅Intents」章节 |
| 是否有完整数值表（十进制/十六进制） | **官方文档未提供**。官方仅给出位移表达式（`1 << N`）与对应事件名清单 |
| 群聊 + 单聊 + 频道的「推荐取值组合」 | **官方文档未提供**。官方只给出 `1 << 30` 与 `0|1<<30|1<<1` 两个示例 |
| `Identify` 中 `"intents": 513` 的具体含义 | **官方文档未提供**（官方样例只给数值，未解释对应的 intent） |
| `GROUP_MEMBER_EVENT (1<<24)` 出现在 intents 总清单中 | **官方文档未提供**。该 intent 只出现在各事件页，未出现在 `event-emit.html` 的 intents 清单中 |
| GUILD_MEMBER_* 系列事件的 JSON 样例与字段表 | **官方文档未提供**（仅在 intents 清单中列出事件名） |
| FORUM_* / AUDIO_* 系列事件的 JSON 样例与字段表 | **官方文档未提供**（仅在 intents 清单中列出事件名） |
| MESSAGE_DELETE / DIRECT_MESSAGE_DELETE / PUBLIC_MESSAGE_DELETE 的 JSON 样例与字段表 | **官方文档未提供**（仅在 intents 清单中列出事件名） |

### 9.2 关于事件

| 项目 | 状态 |
|---|---|
| `content` 中 `<@!id>` 形式的说明 | **官方文档未提供**。本次抓取的全部官方页面中未出现 `<@!id>` 这一表示法 |
| 群聊 `mentions` 数组的 JSON 样例 | **官方文档未提供**（只有字段表：`mentions | []User | 消息中@的用户列表（不含@机器人自身）`） |
| `mentions` 与 `content` 中占位符的对应/清洗规则 | **官方文档未提供** |
| 频道 `AT_MESSAGE_CREATE` 的 `content` 是否去除 @ 前缀 | **官方文档未提供** |
| `message_type=101`（并行消息）/ `102`（聊天记录）的完整结构与 JSON 样例 | **官方文档未提供**（仅在 `message_type` 字段说明中列出枚举名） |
| `msg_elements` 的完整递归结构示例（含 `author`/`attachments`/`ark_data` 嵌套） | **官方文档未提供**（官方示例 3 只给出 `msg_idx`/`message_type`/`content` 三个键） |
| `message_scene.ext` 中 `auth_token` 的用途与校验方式 | **官方文档未提供**（`ext` 字段说明仅写「auth_token=鉴权令牌」） |
| 群聊接收 Markdown 时的 JSON 字段形态 | **官方文档未提供** |
| `attachments` 中 `file` / `voice` / `video` 三种 `content_type` 的完整 JSON 样例 | **官方文档未提供**（仅提供 `image/jpeg` 样例） |
| `emoji` 在消息事件体中的独立字段结构 | **官方文档未提供** |
| `SUBSCRIBE_MESSAGE_STATUS` 事件的更完整说明（订阅消息模板的申请方式等） | **官方文档未提供**（本次抓取范围内） |

### 9.3 关于双通道

| 项目 | 状态 |
|---|---|
| Webhook 模式的心跳机制 | **官方文档未提供** |
| Webhook 模式的断线补发/去重策略 | **官方文档未提供** |
| Webhook 模式的分片能力 | **官方文档未提供** |
| 两种模式在事件类型覆盖范围上的差异 | **官方文档未提供** |
| Webhook 回调的重试策略（超时时间、重试次数） | **官方文档未提供** |
| Webhook 的 IP 来源地址段（用于防火墙放行） | **官方文档未提供** |

### 9.4 关于平台限制与风控

| 项目 | 状态 |
|---|---|
| 「个人开发者/未上架机器人不能使用的具体能力清单」 | **官方文档未提供**（官方仅有「存在差异」「需要申请」「达到准入条件」等概括表述） |
| 未上架机器人（非下架、非封禁）的运行时行为 | **官方文档未提供**（只有 4914「机器人已下架」） |
| 违规处罚的「违规等级 / 分数 / 申诉流程」细则 | **官方文档未提供**（运营规范只给出各类违规的处罚规则，未给出分级与申诉流程） |
| 个人认证「进群数量上限 500 个」的配套说明（如是否含沙箱群、统计口径） | **官方文档未提供** |
| 消息发送超频的具体阈值触发点（如 qpm 的计算窗口） | **官方文档未提供**（官方只给出 qpm/qps 数值） |
| `changelog` 页中的「平台限制变更历史」 | **官方文档未提供**（该页为研发/SDK commit 日志，与产品限制无关） |

### 9.5 关于错误码

| 项目 | 状态 |
|---|---|
| 错误码与 `err_code` 的 JSON 结构化总表 | **官方文档未提供**（官方只给「值 / 含义」表格） |
| 各接口特有错误码的汇总页 | **官方文档未提供**（分散在各接口页） |
| WebSocket 错误码的关闭帧格式 | **官方文档未提供** |
| WebSocket `4008` 的频控具体阈值 | **官方文档未提供** |
| `12001~12003`、`500xx` 等错误码的重试建议 | **官方文档未提供**（只有 `112xx`、`30600x`、`5010xx` 等部分条目写有「一般重试一次会好」「可重试」） |

### 9.6 关于沙箱

| 项目 | 状态 |
|---|---|
| `api-v2` 版沙箱 OpenAPI 域名 | **官方文档未提供**（仅 `develop/api/` 给出 `https://sandbox.api.sgroup.qq.com`） |
| 沙箱环境 WSS 网关地址 | **官方文档未提供** |
| 沙箱环境的 Webhook 配置差异 | **官方文档未提供** |

### 9.7 其它

| 项目 | 状态 |
|---|---|
| `GROUP_MESSAGE_CREATE`（全量模式）的开通入口与条件 | 官方仅有「当机器人开启了"接收所有消息"功能后」/「当群主设定允许该机器人接收群内全部消息时」的表述，**开通入口的具体路径：官方文档未提供** |
| `risk_tips` 中 `warning_tips` / `top_tips` / `sec_risk_rules` 的具体规则 | **官方文档未提供**（只有字段说明中的短语） |
| `SubscribeMsgTemplateResult.template_id` 的平台模板 ID 清单 | **官方文档未提供** |
| `FRIEND_ADD` 中 `short_code` 的获取方式 | **官方文档未提供**（只有字段名与描述「机器人分享链接的短链code」） |

---

## 附：本文件的自检说明

1. **intents 掩码表的位置**：位于 `https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html`。
2. **是否存在完整数值表**：**不存在**。官方只给出 `1 << N` 位移表达式，本文件在 2.2 节给出的十进制数值已全部标注「（换算，非官方原文）」。
3. **任务清单中的页面全部抓到**：清单共 30 个 URL，已全部抓取（其中 `group_message_create.html` 确认存在并已抓取）。此外为满足「消息元素结构差异」「主动/被动消息规则」「封禁规范」「消息类型限制」等要求，额外抓取 19 个官方页面（见 0.4 节）。
4. **官方文档内部不一致处**已在正文中以「官方文档内部不一致标注」明确标出，未做主观裁定：
   - Identify 报文 `token` 格式（`QQBot {AccessToken}` vs `Bot {appid}.{app_token}`）
   - WebSocket 基础事件集合（是否含 `DIRECT_MESSAGE`）
   - `MESSAGE_CREATE` 的 intent 归属（`GUILD_MESSAGES` vs `PUBLIC_GUILD_MESSAGES`）
   - 单聊被动消息「4 次」vs「5 次」、群聊主动消息「1000 条/群/天」vs「每月 4 条」
   - `msg_type` 枚举（0/2/7 vs 0/2/3/4/7）
   - `message_type` 枚举（0/3/103 vs 0/3/101/102/103）
   - `CHANNEL_*` 示例中的 `position` 字段未列入字段表
   - `error-trace/websocket.html` 中 4014 重复列出
   - `send.html`「2026/03/05 沙箱不受频控」与 `2025/04/21 主动推送能力不再提供」两条能力说明并存
5. **全文未引用任何第三方来源**。

（文件结束）
