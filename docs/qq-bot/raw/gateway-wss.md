# QQ 机器人开放平台 Gateway WebSocket(WSS) 接入 完整整理

> 事实来源：**仅**使用 QQ 机器人开放平台官方文档站 `https://bot.q.qq.com/wiki` 页面正文。
> 不使用任何第三方博客、CSDN、GitHub issue 或 SDK 源码作为依据。
> 文档未提供的内容一律显式标注为「官方文档未提供」，不做推测与补全。

## 0. 本文件覆盖的官方页面清单（来源清单）

| 序号 | 页面标题（文档站内标题） | 来源 URL |
|---|---|---|
| P1 | WebSocket 方式（事件接收 / dev-prepare/event-emit/websocket） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/websocket.html |
| P2 | 通用数据结构 Payload（dev-prepare/event-emit/payload） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/payload.html |
| P3 | opcode（dev-prepare/interface-framework/opcode） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/opcode.html |
| P4 | 事件订阅与通知（dev-prepare/interface-framework/event-emit） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html |
| P5 | 接口通信基础框架（dev-prepare/interface-framework 首页） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/ |
| P6 | WebSocket 错误码（dev-prepare/error-trace/websocket） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/websocket.html |
| P7 | 错误与调试（dev-prepare/error-trace 首页） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/ |
| P8 | 获取通用 WSS 接入点（openapi/wss/url_get） | https://bot.q.qq.com/wiki/develop/api-v2/openapi/wss/url_get.html |
| P9 | 获取带分片 WSS 接入点（openapi/wss/shard_url_get） | https://bot.q.qq.com/wiki/develop/api-v2/openapi/wss/shard_url_get.html |
| P10 | 获取通用 WSS 接入点（autogen/api/gateway.get） | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/gateway.get.html |

> 补充抓取的官方页面（仅用于填补上述页面中被「引用指向」的内容，来源仍为官方站点）：
>
> | 序号 | 页面标题 | 来源 URL | 用途 |
> |---|---|---|---|
> | S1 | 使用 Websocket 接入（interface-framework/reference） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html | P1/P4 中「具体参考 gateway」所指页面；补充 token 格式的另一处官方表述 |
> | S2 | 错误与调试 / OpenAPI 错误码（openapi/error/error） | https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html | P8/P9 中「详见错误码」所指页面；含 WebSocket 错误码全表与 HTTP 状态码 |
> | S3 | API 调用指南（dev-prepare/api-call-guide） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html | 统一请求地址、鉴权方式（Authorization 头）、Content-Type 的官方表述 |

---

## 1. 总览：WSS 接入是什么（来源：P4 事件订阅与通知）

> 「当用户在QQ平台内的一些行为操作或某些接口的有异步返回通知确认机制的场景的时候，QQ 会通过"事件"的方式，通知到开发者服务器，开发者可自行根据具体事件通知来进行下一步响应。譬如用户跟机器人发消息，用户添加机器人好友，机器人被拉入群聊等等事件。」（P4）

事件接收有两种方式：**Webhook 方式** 与 **WebSocket 方式**（P4 中并列的两大节）。本文件只整理 **WebSocket(WSS) 方式**。P4 中 Webhook 相关（回调地址端口 80/443/8080/8443、签名校验、OpCode 12/13 等）仅在与 OpCode 全集表相关时保留（见第 6 章），其余不展开。

Gateway WSS 的完整生命周期（来源：P1、P4、S1 三处表述一致，按相同顺序）：

1. 调用 `GET /gateway` 或 `GET /gateway/bot` 获取 WSS 接入点地址；
2. 建立 `websocket` 长连接；
3. 连接成功后，服务端下发 **OpCode 10 Hello**（含 `heartbeat_interval`）；
4. 发送 **OpCode 2 Identify** 登录鉴权，成功后获得 `session_id`，并收到 **READY** 事件（`t = "READY"`，属于 OpCode 0 Dispatch）；
5. 按周期发送 **OpCode 1 Heartbeat**，收到 **OpCode 11 Heartbeat ACK**；
6. 连接断开后重连，发送 **OpCode 6 Resume**（携带 `session_id` 与 `seq`），补齐遗漏事件后收到 **RESUMED** 事件（`t = "RESUMED"`）。

---

## 2. `GET /gateway` —— 获取通用 WSS 接入点

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/openapi/wss/url_get.html （P8）
另见来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/gateway.get.html （P10）

### 2.1 接口定义（P8）

```
GET /gateway
```

### 2.2 功能描述（P8 逐字）

> 用于获取 WSS 接入地址，通过该地址可建立 `websocket` 长连接。

### 2.3 Content-Type（P8 逐字）

```
application/json
```

### 2.4 基础信息（P10 逐字表格）

| 字段 | 值 |
|---|---|
| HTTP URL | /gateway |
| HTTP Method | GET |
| 接口频率限制 | 2 QPM / 10 QPM burst |

### 2.5 请求示例（P10 逐字）

**获取通用WSS接入点**

```
GET /gateway
```

### 2.6 返回（P8 逐字）

> 返回一个用于连接 `websocket` 的地址。

### 2.7 响应体字段表（P10 逐字表格）

| 名称 | 类型 | 描述 |
|---|---|---|
| url | string | WebSocket 连接地址 |

### 2.8 响应示例 JSON

P8「示例 - 响应数据包」（逐字）：

```
{
  "url": "wss://api.bot.qq.com/websocket/"
}
```

P10「响应示例 - 获取WSS网关地址成功」（逐字）：

```
{
  "url": "wss://qqbot-api.example.com/websocket"
}
```

### 2.9 请求头、鉴权方式

- **请求头**：P8 与 P10 均未列出 `GET /gateway` 的请求头字段清单 ── **官方文档未提供**（该两个页面的正文中不存在「请求头 / Header」章节）。
- **鉴权方式**：P8 与 P10 均未在该页内说明鉴权方式 ── 该两页 **官方文档未提供**。
- 官方站点在另一页（S3，API 调用指南）给出了 OpenAPI 的通用鉴权方式与 Content-Type 示例（非 `/gateway` 专属）：

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

- 统一请求地址（S3 逐字）：

```
https://api.bot.qq.com
```

- 鉴权方式（S3 逐字）：

> 调用 API 时，需要将 access_token 放入请求 Header 中：

```
Authorization: QQBot {ACCESS_TOKEN}
```

- 请求示例（S3 逐字，示例为发送单聊消息，非 `/gateway`）：

```
curl -X POST 'https://api.bot.qq.com/v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/messages' \
-H 'Authorization: QQBot {ACCESS_TOKEN}' \
-H 'Content-Type: application/json; charset=utf-8' \
-d '{
 "content": "Hello World",
 "msg_type": 0,
 "msg_id": "previous_msg_id"
}'
```

> 说明：官方文档 **未提供** 「`GET /gateway` 的 Header 必填清单」这一专门表格；只提供了上述通用鉴权与 Content-Type 说明。

### 2.10 错误码（P8 逐字）

> 详见[错误码](https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html)。

即 P8 本身未列出 `/gateway` 接口专属错误码，只指向官方「错误码」页（见本文件第 12 章）。**`/gateway` 的接口专属错误码：官方文档未提供。**

---

## 3. `GET /gateway/bot` —— 获取带分片 WSS 接入点

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/openapi/wss/shard_url_get.html （P9）

### 3.1 接口定义（P9 逐字）

```
GET /gateway/bot
```

### 3.2 功能描述（P9 逐字）

> 用于获取 WSS 接入地址及相关信息，通过该地址可建立 `websocket` 长连接。相关信息包括：
>
> - 建议的分片数。
>
> - 目前连接数使用情况。

### 3.3 Content-Type（P9 逐字）

```
application/json
```

### 3.4 返回字段表（P9 逐字表格）

| 字段名 | 类型 | 描述 |
|---|---|---|
| url | string | WebSocket 的连接地址 |
| shards | int | 建议的 shard 数 |
| session_start_limit | [SessionStartLimit](https://bot.q.qq.com/wiki/develop/api-v2/openapi/wss/shard_url_get.html#sessionstartlimit) | 创建 Session 限制信息 |

### 3.5 SessionStartLimit 子字段表（P9 逐字表格）

| 字段名 | 类型 | 描述 |
|---|---|---|
| total | int | 每 24 小时可创建 Session 数 |
| remaining | int | 目前还可以创建的 Session 数 |
| reset_after | int | 重置计数的剩余时间(ms) |
| max_concurrency | int | 每 5s 可以创建的 Session 数 |

### 3.6 示例 JSON（P9 逐字）

```
{
  "wss://api.bot.qq.com/websocket/",
  "shards": 9,
  "session_start_limit": {
    "total": 1000,
    "remaining": 999,
    "reset_after": 14400000,
    "max_concurrency": 1
  } }
```

> 逐字保留说明：该示例在官方文档原文中即为上述形态（首行缺少字段名 `"url":`，结尾为 `} }`），本文件按原文照录，未作修正。

### 3.7 另一处官方给出的 `/gateway/bot` 返回示例（P1、P4 逐字）

P1「分片连接 LoadBalance - 获得合适的分片数」与 P4「分片连接LoadBalance - 获得合适的分片数」中给出：

> 使用 `/gateway/bot` 接口获取网关地址的时候，会同时返回一个建议的 `shard` 数，及最大并发限制。

```
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

### 3.8 请求头、鉴权方式

- P9 页面正文中未列出 `GET /gateway/bot` 的请求头清单，也未说明鉴权方式 ── 该页 **官方文档未提供**。
- 官方站点给出的通用鉴权方式见本文件 2.9（来源 S3）。
- **建议的分片数如何使用、如何据此选择 shard 数量的具体算法** ── 官方文档仅给出「建议的分片数」描述与「分片规则」公式（见第 9 章），**未提供**由 `shards` 推导出实际应建立连接数的完整决策流程。

### 3.9 错误码（P9 逐字）

> 详见[错误码](https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html)。

即 P9 本身未列出 `/gateway/bot` 接口专属错误码。**`/gateway/bot` 的接口专属错误码：官方文档未提供。**

---

## 4. WebSocket 完整生命周期（逐字来自 P1 / P4，两页内容一致）

来源 URL（P1）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/websocket.html
来源 URL（P4）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html
来源 URL（S1）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html

### 4.1 第一步：发起连接到 Gateway

P1/P4 原文：

> 第一步先调用 [获取通用WSS 接入点] 或 [获取带分片WSS 接入点] 接口获取网关地址。
>
> 会得到一个类似下面这样的地址：

```
wss://api.bot.qq.com/websocket/
```

> 然后进行 `websocket` 长连接建立，一旦连接成功，就会返回 OpCode 10 Hello 消息。这个消息主要的内容是心跳周期，单位毫秒(milliseconds)，如下：

```json
{
  "op": 10,
  "d": {
    "heartbeat_interval": 45000
  }
}
```

（P1 原文示例此处排版为 `{"op": 10,"d": {"heartbeat_interval": 45000} } }`；P4 与 S1 原文示例为 `{"op": 10,"d": {"heartbeat_interval": 45000}}`。内容一致，此处按内容合并书写。）

S1 的同一节标题为「1.连接到 Gateway」，原文：

> 第一步先调用 [/gateway] 或 [/gateway/bot] 接口获取网关地址。 会得到一个类似下面这样的地址：

```
wss://api.bot.qq.com/websocket/
```

> 然后进行 websocket 连接，一旦连接成功，就会返回 OpCode 10 Hello 消息。这个消息主要的内容是心跳周期，单位毫秒(milliseconds)，如下：

```json
{
  "op": 10,
  "d": {
    "heartbeat_interval": 45000
  }
}
```

**约定（官方文档表述）**：
- `wss://api.bot.qq.com/websocket/` 为示例地址；实际地址以 `/gateway` 或 `/gateway/bot` 返回的 `url` 为准。
- 心跳周期 `heartbeat_interval` 的**单位为毫秒（milliseconds）**（P1/P4/S1 均明确）。
- 官方文档 **未提供** WSS 连接可用的子协议（Sec-WebSocket-Protocol）、编码格式协商、连接超时时间、重连退避策略的说明。

### 4.2 第二步：登录鉴权获得 Session（OpCode 2 Identify）

P1/P4 原文：

> `websocket` 长连接建立之后，需要进行登录鉴权，登录鉴权成功后会获得一个 session 会话 id，只有登录成功后，QQ 后台才会下发事件通知。
>
> 发送一个 OpCode 2 Identify 消息，`payload` 如下：

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

S1（使用 Websocket 接入）原文：

> 建立 websocket 连接之后，就需要进行鉴权了，需要发送一个 OpCode 2 Identify 消息，如下：

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

`d` 字段说明表（P1 逐字表格）：

| **字段** | **描述** |
|---|---|
| token | 格式为 "QQBot {AccessToken}" |
| intents | 是此次连接所需要接收的事件，具体可参考 [事件订阅 Intents](https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/payload.html#%E4%BA%8B%E4%BB%B6%E8%AE%A2%E9%98%85-intents) |
| shard | 考虑到开发者事件接收时可以实现负载均衡，QQ 提供了分片逻辑，事件通知会落在不同的分片上，该参数是个拥有两个元素的数组。例如：`[0,4]`，代表分为四个片，当前链接是第 0 个片，业务稍后应该继续建立 `shard` 为 `[1,4]`, `[2,4]`, `[3,4]` 的链接，才能完整接收事件，更多详细的内容可以参考 [Shard 机制](https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/websocket.html#%E5%88%86%E7%89%87%E8%BF%9E%E6%8E%A5-loadbalance)。若无需分片，使用 `[0, 1]` 即可。 |
| properties | 目前无实际作用，可以按照自己的实际情况填写，也可以留空 |

P4 同一表格（逐字，字段描述与 P1 一致，链接指向不同锚点）：

| **字段** | **描述** |
|---|---|
| token | 格式为"QQBot {AccessToken}" |
| intents | 是此次连接所需要接收的事件，具体可参考 **Intents** [事件订阅intents] |
| shard | 考虑到开发者事件接收时可以实现负载均衡，QQ 提供了分片逻辑，事件通知会落在不同的分片上，该参数是个拥有两个元素的数组。例如：[0,4]，代表分为四个片，当前链接是第 0 个片，业务稍后应该继续建立 `shard` 为[1,4],[2,4],[3,4]的链接，才能完整接收事件，更多详细的内容可以参考 **Shard** [Shard机制] |
| properties | 目前无实际作用，可以按照自己的实际情况填写，也可以留空 |

> **token 格式的官方表述存在两种写法，均逐字保留**：
> - P1 / P4 表：`格式为 "QQBot {AccessToken}"`
> - S1 正文：`token` 是创建机器人的时候分配的，格式为 `Bot {appid}.{app_token}`
> - 两处来源 URL 不同（见本章来源清单），官方文档未指明以哪个为准 ── **两种格式的取舍关系：官方文档未提供明确说明。**
> - Identify 时 `token` 是否必填：P1/P4/S1 的 `d` 字段表均未标注「必填/可选」列 ── **必填/可选标注：官方文档未提供**（从示例结构与描述看为需要提供，但官方文档无「必填」字样）。

鉴权成功之后下发 READY 事件（P1/P4/S1 逐字）：

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

READY 事件 `d` 结构说明（字段级表格）：**官方文档未提供**（P1/P4/S1 均只给上述 JSON 示例，未给出 `version` / `session_id` / `user` / `shard` 的字段表）。

### 4.3 第三步：发送心跳 Ack（OpCode 1 / OpCode 11）

P1/P4 原文：

> 鉴权成功之后，就需要按照周期进行心跳发送。d 为客户端收到的最新的消息的 s，如果是首次连接，d 为传 null，`payload` 如下：

```json
{
  "op": 1,
  "d": 251
}
```

> 心跳发送成功之后会收到 OpCode 11 Heartbeat ACK 消息，`payload` 如下：

```json
{
  "op": 11
}
```

S1「3.发送心跳」原文：

> 鉴权成功之后，就需要按照周期进行心跳发送。`d`为客户端收到的最新的消息的`s`，如果是第一次连接，传`null`。

```json
{
  "op": 1,
  "d": 251
}
```

> 心跳发送成功之后会收到 OpCode 11 Heartbeat ACK 消息，如下：

```json
{
  "op": 11
}
```

### 4.4 第四步：恢复登录态 Session（OpCode 6 Resume）

P1/P4 原文：

> 有很多原因可能会导致 `websocket` 长连接断开，断开之后短时间内重连会补发中间遗漏的事件，以保障业务逻辑的正确性。断开重连 gateway 后不需要发送重新登录 OpCode 2 Identify 请求。在连接到 `Gateway` 之后，需要发送 OpCode 6 Resume 消息，`payload` 如下：

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

> 其中 `seq` 指的是在接收事件时候的 `s` 字段，我们推荐开发者在处理过事件之后记录下 `s` 这样可以在 `resume` 的时候传递给 `websocket`，`websocket` 会自动补发这个 seq 之后的事件。
>
> 恢复成功之后，就开始补发遗漏事件，所有事件补发完成之后，会下发一个 `Resumed Event`，`payload` 如下：

```json
{
  "op": 0,
  "s": 2002,
  "t": "RESUMED",
  "d": ""
}
```

S1「4.恢复连接」原文：

> 有很多原因都会导致连接断开，断开之后短时间内重连会补发中间遗漏的事件，以保障业务逻辑的正确性。断开重连不需要发送`Identify`请求。在连接到 Gateway 之后，需要发送 Opcode 6 Resume 消息，结构如下：

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

> 其中 `seq` 指的是在接收事件时候的 `s` 字段，我们推荐开发者在处理过事件之后记录下 `s` 这样可以在 resume 的时候传递给 websocket，websocket 会自动补发这个 seq 之后的事件。
>
> 恢复成功之后，就开始补发遗漏事件，所有事件补发完成之后，会下发一个 `Resumed Event`，结构如下：

```json
{
  "op": 0,
  "s": 2002,
  "t": "RESUMED",
  "d": ""
}
```

**Resume `d` 的字段级表格（含必填/可选标注）：官方文档未提供。**
官方文档仅给出上述 JSON 结构（`token` / `session_id` / `seq` 三个键）与 `seq` 的文字说明，**未提供** `token`、`session_id`、`seq` 的独立字段表与「必填/可选」列。

---

## 5. OpCode 全集表格（按来源分别逐字保留）

### 5.1 P2 来源表（含「接入方式」列）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/payload.html

> 所有 `opcode` 列表如下：

| **CODE** | **名称** | **接入方式** | **客户端行为** | **描述** |
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

客户端行为含义如下（P2 逐字）：

- `Receive` 客户端接收到服务端 `push` 的消息
- `Send` 客户端发送消息
- `Reply` 客户端接收到服务端发送的消息之后的回包（HTTP 回调模式）

### 5.2 P3 来源表（opcode 页，列为「客户端操作」）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/opcode.html

> 所有opcode列表如下：

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

客户端操作含义如下（P3 逐字）：

- `Receive` 客户端接收到服务端 push 的消息
- `Send` 客户端发送消息
- `Reply` 客户端接收到服务端发送的消息之后的回包（HTTP 回调模式）

### 5.3 P4 来源表（与 P2 完全一致，逐字保留）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

| **CODE** | **名称** | **接入方式** | **客户端行为** | **描述** |
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

### 5.4 OpCode 汇总（本组官方页面出现过的取值全集）

本组官方页面中出现过的 OpCode 取值共 **10 个**：`0`、`1`、`2`、`6`、`7`、`9`、`10`、`11`、`12`、`13`。

- 其中与 **websocket** 相关的：`0`、`1`、`2`、`6`、`7`、`9`、`10`、`11`。
- 其中标注为 **webhook** 才有的：`12`（HTTP Callback ACK，Reply）、`13`（回调地址验证，Receive）。
- 官方文档中 **未出现** 的常见 OpCode（如 `3`、`4`、`5`、`8`）── **官方文档未提供对应定义**。

各 OpCode 的进一步细节覆盖情况：

| OpCode | 官方文档提供的内容 |
|---|---|
| 0 Dispatch | 表格定义 + 通用 payload 结构 + READY / RESUMED 示例（P1/P2/P3/P4/S1） |
| 1 Heartbeat | 表格定义 + 示例 `{"op":1,"d":251}` + `d` 语义说明（P1/P3/P4/S1） |
| 2 Identify | 表格定义 + 完整 `d` 示例 + `d` 字段表（P1/P3/P4/S1） |
| 6 Resume | 表格定义 + 完整 `d` 示例 + `seq` 说明（P1/P3/P4/S1） |
| 7 Reconnect | 仅表格定义（「服务端通知客户端重新连接」）；**`d` 结构、触发条件、客户端处理后该做什么：官方文档未提供** |
| 9 Invalid Session | 仅表格定义（「当 identify 或 resume 的时候，如果参数有错，服务端会返回该消息」）；**`d` 结构、是否可重试的判定规则：官方文档未提供**（错误码表中的 4006/4007 等给了 RESUME/IDENTIFY 可否重试，但未与 Op9 的 `d` 字段绑定说明） |
| 10 Hello | 表格定义 + 示例 `{"op":10,"d":{"heartbeat_interval":45000}}` |
| 11 Heartbeat ACK | 表格定义 + 示例 `{"op":11}` |
| 12 HTTP Callback ACK | 仅表格定义（webhook） |
| 13 回调地址验证 | 仅表格定义（webhook）；P4 另有回调地址验证的 `plain_token`/`event_ts`/`signature` 表与 golang 示例 |

---

## 6. 通用数据结构 Payload（Dispatch 事件包结构）

### 6.1 P2 / P4 逐字：通用数据结构

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/payload.html （P2）
来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html （P4）

P2 原文：

> `payload` 指的是在 `webhook` 或 `websocket` 连接上传输的数据，网关的上下行消息采用的都是同一个结构，如下：

```json
{
  "id":"event_id",
  "op": 0,
  "d": {},
  "s": 42,
  "t": "GATEWAY_EVENT_NAME" }
```

P2 字段表（逐字）：

| 字段 | 描述 |
|---|---|
| id | 事件id |
| op | 指的是 opcode，参考连接维护 |
| s | 下行消息都会有一个序列号，标识消息的唯一性，客户端需要再发送心跳的时候，携带客户端收到的最新的 s |
| t | 代表事件类型。主要用在 op 为 0 Dispatch 的时候 |
| d | 代表事件内容，不同事件类型的事件内容格式都不同，请注意识别。主要用在 op 为 0 Dispatch 的时候 |

P4 同一结构（逐字）：

```json
{
  "id":"event_id",
  "op": 0,
  "d": {},
  "s": 42,
  "t": "GATEWAY_EVENT_NAME" }
```

P4 字段表（逐字，与 P2 一致）：

| 字段 | 描述 |
|---|---|
| id | 事件id |
| op | 指的是 opcode，参考连接维护 |
| s | 下行消息都会有一个序列号，标识消息的唯一性，客户端需要再发送心跳的时候，携带客户端收到的最新的s |
| t | 代表事件类型。主要用在op为 0 Dispatch 的时候 |
| d | 代表事件内容，不同事件类型的事件内容格式都不同，请注意识别。主要用在op为 0 Dispatch 的时候 |

### 6.2 S1 来源的 payload 说明（逐字）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html

> payload 指的是在 websocket 连接上传输的数据，网关的上下行消息采用的都是同一个结构，如下：

```json
{
  "op": 0,
  "d": {},
  "s": 42,
  "t": "GATEWAY_EVENT_NAME" }
```

> `op` 指的是 opcode，全部 opcode 列表参考 opcode。
>
> `s` 下行消息都会有一个序列号，标识消息的唯一性，客户端需要再发送心跳的时候，携带客户端收到的最新的`s`。
>
> `t`和`d` 主要是用在`op`为 `0 Dispatch` 的时候，`t` 代表事件类型，`d` 代表事件内容，不同事件类型的事件内容格式都不同，请注意识别。

> 注：S1 该示例中未出现 `id` 字段，与 P2/P4 的示例不同（P2/P4 含 `"id":"event_id"`）。官方文档未说明该差异原因 ── **`id` 字段是否必填、是否为所有下行消息共有：官方文档未提供明确结论**。

### 6.3 Dispatch 事件包字段语义小结（完全依据官方文档）

- `op`：opcode；`op = 0` 时为 Dispatch（服务端进行消息推送）。（P2/P3/P4）
- `d`：事件内容，不同事件类型的事件内容格式都不同；**主要用在 `op` 为 0 Dispatch 的时候**。（P2/P4）
- `s`：下行消息的序列号，标识消息的唯一性；客户端再发送心跳的时候，携带客户端收到的最新的 `s`。（P2/P4）
- `t`：代表事件类型；**主要用在 `op` 为 0 Dispatch 的时候**；可用 `t` 字段的值来区分不同 intents 位代表的事件。（P2/P4）
- `id`：事件 id。（P2/P4）

### 6.4 Dispatch 事件的 `t` 全量清单

Dispatch 事件的 `t` 取值清单官方文档放在「事件订阅 Intents」一章（每个 intents 位下逐条列出，见本文件第 11 章）。READY 与 RESUMED 是两个特殊 Dispatch 事件名（P1/P4/S1）。

### 6.5 压缩传输（zlib 等）

- 在本组官方页面（P1–P10、S1–S3）中，**未出现** 任何关于 `zlib`、`deflate`、`compress`、`inflate` 的表述。
- 在官方页面给出的 payload 示例中，**未出现** `compress` 字段。
- 因此：**WSS 压缩传输（zlib / deflate / transport compression）相关内容：官方文档未提供。**

---

## 7. 心跳机制（Heartbeat）

来源 URL（P1）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/websocket.html
来源 URL（P4）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html
来源 URL（S1）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html
来源 URL（P2/P3）：payload / opcode 页面

官方文档明确给出的要点（逐字/原文归纳）：

1. **heartbeat_interval 的来源与单位**
   - 连接成功后收到的 **OpCode 10 Hello** 消息「主要的内容是心跳周期，单位毫秒(milliseconds)」。（P1/P4/S1）
   - 示例值：`45000`（即示例中为 45000 毫秒）。

2. **心跳包的发送时机**
   - 「鉴权成功之后，就需要按照周期进行心跳发送。」（P1/P4/S1）
   - 即：在 Identify 鉴权成功（收到 READY）之后开始按周期发送。

3. **心跳包内容**
   - `op = 1`，`d` 为客户端收到的最新的消息的 `s`；**如果是首次连接（第一次连接），`d` 传 `null`**。（P1/P4/S1）
   - 示例：

```json
{
  "op": 1,
  "d": 251
}
```

4. **OpCode 11 Heartbeat ACK 判定**
   - 「心跳发送成功之后会收到 OpCode 11 Heartbeat ACK 消息」，`payload` 为：

```json
{
  "op": 11
}
```

   （P1/P4/S1）
   - OpCode 表定义：`11 | Heartbeat ACK | websocket | Receive/Reply | 当发送心跳成功之后，就会收到该消息`。（P2/P3/P4）

5. **心跳与 seq（`d` 传上次 `s`）的关系**
   - 「`s` 下行消息都会有一个序列号，标识消息的唯一性，**客户端需要再发送心跳的时候，携带客户端收到的最新的 `s`**。」（P2/P4）
   - 「`d` 为客户端收到的最新的消息的 `s`，如果是首次连接，`d` 为传 `null`。」（P1/P4/S1）
   - 即：心跳包 `d` = 最近一次收到的下行消息的 `s`；首次连接时 `d = null`。

6. **心跳丢失 / zombie connection 处理**
   - 关于「心跳丢失（未收到 ACK）后的处理」「zombie connection（僵尸连接）的判定与关闭」「多少毫秒未收到 ACK 判定为断线」等内容，本组官方页面（P1–P10、S1–S3）中 **均未出现**。
   - 因此：**心跳丢失判定阈值与 zombie connection 处理机制：官方文档未提供。**
   - 官方文档仅提供与连接失效相关的错误码（如 `4009 连接过期，请重连并执行 resume 进行重新连接`，见第 12 章），但**未说明其与心跳丢失的对应关系**。

7. **心跳周期调整 / 服务端主动心跳**
   - OpCode 1 的官方定义为「客户端或服务端发送心跳」（Send/Receive），即服务端也**可能**发送心跳；但**服务端主动发送心跳时的触发条件、`d` 内容、客户端应如何回包：官方文档未提供**。

---

## 8. Session 与 seq

来源 URL：P1 / P4 / S1 / P2 / P3 / P6 / S2

官方文档明确给出的内容：

1. **session_id 的来源**
   - 「`websocket` 长连接建立之后，需要进行登录鉴权，登录鉴权成功后会获得一个 session 会话 id，只有登录成功后，QQ 后台才会下发事件通知。」（P1/P4）
   - 即 `session_id` 通过 Identify（OpCode 2）登录鉴权成功后获得，出现在 **READY 事件的 `d.session_id`** 中。（P1/P4/S1 的 READY 示例：`"session_id": "082ee18c-0be3-491b-9d8b-fbd95c51673a"`）

2. **seq 的来源与语义**
   - Resume 的 `seq`「指的是在接收事件时候的 `s` 字段」。（P1/P4/S1）
   - 「我们推荐开发者在处理过事件之后记录下 `s` 这样可以在 `resume` 的时候传递给 `websocket`，`websocket` 会自动补发这个 seq 之后的事件。」（P1/P4/S1）

3. **`s` 的自增规则细节**
   - 官方文档仅说明：`s` 是「下行消息都会有一个序列号，标识消息的唯一性」（P2/P4），以及心跳时携带「客户端收到的最新的 `s`」（P2/P4）。
   - READY 示例中 `s = 1`，RESUMED 示例中 `s = 2002`（P1/P4/S1）。
   - **`s` 是否严格从 1 开始、是否严格 +1 递增、是否与 shard 有关、断线期间是否连续：官方文档未提供。**

4. **Resume 的条件（何时可以 Resume）**
   - 「有很多原因可能会导致 `websocket` 长连接断开，断开之后短时间内重连会补发中间遗漏的事件，以保障业务逻辑的正确性。断开重连 gateway 后不需要发送重新登录 OpCode 2 Identify 请求。在连接到 `Gateway` 之后，需要发送 OpCode 6 Resume 消息」。（P1/P4）
   - 因此 Resume 的前提是：**已经过 Identify 并持有 `session_id` 与可用的 `seq`**（来自 READY / 事件流的 `s`），且连接是在「短时间内」断开。
   - **「短时间内」的具体时长阈值 / session 的有效期：官方文档未提供。**
   - 错误码表中允许 RESUME 的情形（P1/P4/P6/S2）：`4008`（可以 RESUME）、`4009`（可以 RESUME）；「4009 可以重新发起 resume」。

5. **何时必须重新 Identify（必须重新鉴权）**
   - 官方错误码表「是否可以重试 IDENTIFY = 是」的行，表示这些场景下应重新发起 identify（P1/P4/P6/S2）：
     - `4007` seq 错误
     - `4006` 无效的 session id，无法继续 resume，请 identify
     - `4008` 发送 payload 过快，请重新连接，并遵守连接后返回的频控信息
     - `4009` 连接过期，请重连并执行 resume 进行重新连接
     - `4900~4913` 内部错误，请重连
   - 「针对 WebSocket 错误码的简单处理逻辑」（逐字，P1/P6/S2）：
     - 4009 可以重新发起 resume
     - 4914，4915 不可以连接，请联系官方解封
     - 其他错误，请重新发起 identify

6. **Resume 失败处理**
   - 若 Resume 失败（例如 `4006 无效的 session id，无法继续 resume，请 identify`、`4007 seq 错误`），错误码表标注「是否可以重试 IDENTIFY = 是」，即需重新 Identify。（P1/P4/P6/S2）
   - **Resume 失败时是否/如何收到 OpCode 9 Invalid Session、客户端收到 Op9 后的标准处理步骤：官方文档未提供。**
   - **同一 `session_id` 可 Resume 的次数上限、并发限制：官方文档未提供。**

7. **Session 创建限额**
   - 来自 `/gateway/bot` 的 `session_start_limit`（P9 逐字表）：

| 字段名 | 类型 | 描述 |
|---|---|---|
| total | int | 每 24 小时可创建 Session 数 |
| remaining | int | 目前还可以创建的 Session 数 |
| reset_after | int | 重置计数的剩余时间(ms) |
| max_concurrency | int | 每 5s 可以创建的 Session 数 |

   - 「最大连接数」（P1/P4 逐字）：每个机器人创建的连接数不能超过 `remaining` 剩余连接数。

---

## 9. Shard 分片机制与 max_concurrency

来源 URL（P1）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/websocket.html
来源 URL（P4）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html
来源 URL（P9）：https://bot.q.qq.com/wiki/develop/api-v2/openapi/wss/shard_url_get.html

### 9.1 分片连接 LoadBalance（P1/P4 逐字）

> 随着 bot 的增长并被添加到越来越多的频道中，事件越来越多，业务有必要对事件进行水平分割，实现负载均衡。机器人网关实现了一种用户可控制的分片方法，该方法允许跨多个网关连接拆分事件。分片完全由用户控制，并且不需要在单独的连接之间进行状态共享。
>
> 要在连接上启用分片，需要在建立连接的时候指定分片参数，具体参考 [gateway](https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/reference.html)

（P4 版本措辞：`随着`bot`的增长并被添加到越来越多的频道中……需要在建立连接的时候指定分片参数，具体参考[gateway]`，语义一致。）

### 9.2 获得合适的分片数（P1/P4 逐字）

> 使用 `/gateway/bot` 接口获取网关地址的时候，会同时返回一个建议的 `shard` 数，及最大并发限制。

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

### 9.3 分片规则（P1/P4 逐字）

> 分片是按照频道 id 进行哈希的，同一个频道的信息会固定从同一个链接推送。具体哈希计算规则如下：

```
shard_id = (guild_id >> 22) % num_shards
```

### 9.4 最大连接数（P1/P4 逐字）

> 每个机器人创建的连接数不能超过 `remaining` 剩余连接数。

### 9.5 shard 参数在 Identify 中的用法（P1/P4/S1 逐字）

> `shard` 考虑到开发者事件接收时可以实现负载均衡，QQ 提供了分片逻辑，事件通知会落在不同的分片上，该参数是个拥有两个元素的数组。例如：`[0,4]`，代表分为四个片，当前链接是第 0 个片，业务稍后应该继续建立 `shard` 为 `[1,4]`, `[2,4]`, `[3,4]` 的链接，才能完整接收事件……**若无需分片，使用 `[0, 1]` 即可。**

### 9.6 max_concurrency 的出现位置与含义

- `max_concurrency` 出现在 `/gateway/bot` 返回的 `session_start_limit` 中，官方描述为「**每 5s 可以创建的 Session 数**」（P9 逐字）。
- P1/P4 在「获得合适的分片数」一节中把 `session_start_limit` 描述为「**最大并发限制**」。
- **`max_concurrency` 在建立连接时的具体节流/排队实现细节（例如必须按 5s 间隔逐个建立连接、是否可并发发起）：官方文档未提供。**

### 9.7 分片相关的其他细节

- **分片与 intents 的关系、分片下 READY/RESUMED 的表现、每个分片独立 session_id 还是共享：官方文档未提供。**
- **`shard` 两个元素中第二元素（总数）必须等于 `/gateway/bot` 返回的 `shards` 建议值吗：官方文档未提供明确要求**（文档仅描述「建议的 shard 数」与示例）。
- 分片相关的错误码：`4010 无效的 shard`（不可 RESUME、不可 IDENTIFY，见第 12 章）、`4011 连接需要处理的 guild 过多，请进行合理的分片`（不可 RESUME、不可 IDENTIFY）。

---

## 10. Identify / Resume 的完整 `d` 结构汇总

### 10.1 Identify（OpCode 2，客户端 → 服务端）

官方文档给出的完整 `d` 结构（P1/P4 示例）：

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

（S1 示例中 `"token": "my_token"`，其余相同。）

| 字段 | 类型 | 描述（官方原文） | 必填/可选 |
|---|---|---|---|
| token | 官方文档未标注类型 | 格式为 "QQBot {AccessToken}"（P1/P4）；S1 表述为「是创建机器人的时候分配的，格式为 `Bot {appid}.{app_token}`」 | **官方文档未提供**（无「必填」标注） |
| intents | 官方文档未标注类型 | 是此次连接所需要接收的事件，具体可参考「事件订阅 Intents」 | **官方文档未提供** |
| shard | 数组（描述为「拥有两个元素的数组」） | 分片参数，例如 `[0,4]` 代表分为四个片，当前链接是第 0 个片；无需分片使用 `[0, 1]` | **官方文档未提供**（描述中「若无需分片，使用 `[0, 1]` 即可」暗示可分片场景下需填） |
| properties | 对象（示例） | 目前无实际作用，可以按照自己的实际情况填写，也可以留空 | 「可以留空」（即可选） |
| properties.$os | 字符串（示例值 `"linux"`） | 官方文档未单独说明 `$os` 的含义 | **官方文档未提供** |
| properties.$browser | 字符串（示例值 `"my_library"`） | 官方文档未单独说明 `$browser` 的含义 | **官方文档未提供** |
| properties.$device | 字符串（示例值 `"my_library"`） | 官方文档未单独说明 `$device` 的含义 | **官方文档未提供** |

> 关于 `properties`（`$os` / `$browser` / `$device`）：官方文档仅说明「目前无实际作用，可以按照自己的实际情况填写，也可以留空」，**未提供** 三个子字段各自的类型约束、取值范围、是否必须同时出现的说明。（P1/P4/S1）

### 10.2 Resume（OpCode 6，客户端 → 服务端）

官方文档给出的完整 `d` 结构（P1/P4/S1 示例）：

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

| 字段 | 类型 | 描述（官方原文） | 必填/可选 |
|---|---|---|---|
| token | 官方文档未标注类型 | 官方文档在 Resume 章节**未对 `token` 作文字描述**（仅出现在示例中）；Identify 章节描述为 `格式为 "QQBot {AccessToken}"` / `Bot {appid}.{app_token}` | **官方文档未提供** |
| session_id | 官方文档未标注类型 | 官方文档在 Resume 章节**未对 `session_id` 作文字描述**；仅说明 Identify 鉴权成功后会获得一个 session 会话 id（READY 的 `d.session_id`） | **官方文档未提供** |
| seq | 官方文档未标注类型（示例为数字 `1337`） | `seq` 指的是在接收事件时候的 `s` 字段；推荐开发者处理过事件之后记录下 `s`，在 resume 时传递给 websocket，websocket 会自动补发这个 seq 之后的事件 | **官方文档未提供** |

### 10.3 服务端 → 客户端的三个关键下行包（逐字）

- OpCode 10 Hello（P1/P4/S1）：

```json
{
  "op": 10,
  "d": {
    "heartbeat_interval": 45000
  }
}
```

- OpCode 11 Heartbeat ACK（P1/P4/S1）：

```json
{
  "op": 11
}
```

- READY（OpCode 0 Dispatch，`t = "READY"`）（P1/P4/S1）：

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

- RESUMED（OpCode 0 Dispatch，`t = "RESUMED"`）（P1/P4/S1）：

```json
{
  "op": 0,
  "s": 2002,
  "t": "RESUMED",
  "d": ""
}
```

---

## 11. Intents：本组页面出现的取值 / 掩码信息

来源 URL（P2）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/payload.html
来源 URL（P4）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/event-emit.html

### 11.1 说明（P2/P4 逐字）

> 事件的 `intents` 是一个标记位，每一位都代表不同的事件，如果需要接收某类事件，就将该位置为 `1`。
>
> 每个 `intents` 位代表的是一类事件，可以使用 `websocket` 传输的数据中的 `t` 字段的值来区分。
>
> 事件和位移的关系如下：

### 11.2 事件与位移关系（P2/P4 逐字全量）

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
 - GROUP_MSG_RECEIVE // 群管理员在机器人资料页操作开启通知

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

### 11.3 掩码取值表（依据官方「1 << n」表述换算整理）

> 说明：下表左列为官方文档逐字给出的位移表达式，右列 10 进制/16 进制为按该表达式换算的结果（换算过程完全依据官方给出的表达式，未引入外部资料）。intents 的最终取值 = 所需事件对应位做位或（官方文档在下节「举例」中明确了位或运算方式）。

| 事件类别 | 官方位移表达式 | 换算（十进制） | 换算（十六进制） | 官方备注 |
|---|---|---|---|---|
| GUILDS | 1 << 0 | 1 | 0x1 | — |
| GUILD_MEMBERS | 1 << 1 | 2 | 0x2 | — |
| GUILD_MESSAGES | 1 << 9 | 512 | 0x200 | 消息事件，仅 **私域** 机器人能够设置此 intents |
| GUILD_MESSAGE_REACTIONS | 1 << 10 | 1024 | 0x400 | — |
| DIRECT_MESSAGE | 1 << 12 | 4096 | 0x1000 | — |
| GROUP_AND_C2C_EVENT | 1 << 25 | 33554432 | 0x2000000 | — |
| INTERACTION | 1 << 26 | 67108864 | 0x4000000 | — |
| MESSAGE_AUDIT | 1 << 27 | 134217728 | 0x8000000 | — |
| FORUMS_EVENT | 1 << 28 | 268435456 | 0x10000000 | 论坛事件，仅 **私域** 机器人能够设置此 intents |
| AUDIO_ACTION | 1 << 29 | 536870912 | 0x20000000 | — |
| PUBLIC_GUILD_MESSAGES | 1 << 30 | 1073741824 | 0x40000000 | 消息事件，此为公域的消息事件 |

> 官方文档中 **未出现** 的位移位（本组页面中无对应类别）：`1 << 2` ~ `1 << 8`、`1 << 11`、`1 << 13` ~ `1 << 24`、`1 << 31` 及以上 ── **这些位的含义与掩码：官方文档未提供。**
> 官方文档 **未给出** 任何 intents 类别的「预设名称组合值」。示例中出现过的 intents 具体数值只有 Identify 示例里的 `513`（P1/P4/S1）与文本说明 `0|1<<30|1<<1`（P2/P4）。

### 11.4 举例（P2/P4 逐字）

> 如开发者需要接收用户 at 机器人的消息，那么就需要在 `intents` 中设置接收 `PUBLIC_GUILD_MESSAGES`。则需要先计算 `1 << 30` 的值。然后与 `0` 做位或操作，得到最终需要传递的 `intents`。
>
> 如果涉及到多个事件类型的接收，则需要将多个结果做位或操作，如：`0|1<<30|1<<1` 代表订阅 `PUBLIC_GUILD_MESSAGES` 和 `GUILD_MEMBERS` 这两类事件。

### 11.5 权限（P2/P4 逐字）

> 事件类型的订阅，是有权限控制的，除了 `GUILDS`，`PUBLIC_GUILD_MESSAGES`，`GUILD_MEMBERS` 事件是基础的事件，默认有权限订阅之外，其他的特殊事件，都需要经过申请才能够使用，如果在鉴权的时候传递了无权限的 `intents`，`websocket` 会报错，并直接关闭连接。请开发者注意订阅事件的范围需要控制在自己所需要的范围之内。
>
> 如果拥有的某个特殊事件类型的权限被取消，则在当前连接上不会报错，但是将不会收到对应的事件类型，如果重新连接，则报错，所以如果开发者的事件类型权限被取消，请及时调整监听事件代码，避免报错导致的无法连接。

对应的错误码：`4013 无效的 intent`、`4014 intent 无权限`（见第 12 章）。

---

## 12. WSS 错误码 / 关闭码全表（逐条保留「是否可 RESUME / 是否可 IDENTIFY」）

来源 URL（P1）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/websocket.html
来源 URL（P6）：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/websocket.html
来源 URL（S2）：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html

### 12.1 WebSocket 错误码表（P1 逐字原表）

> P1 章节标题为「WebSocket 错误码」。

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
| 4914 | 机器人已下架，只允许连接沙箱环境，请断开连接，检验当前连接环境 | 否 | 否 |
| 4915 | 机器人已封禁，不允许连接，请断开连接，申请解封后再连接 | 否 | 否 |

> 注意：P1 原表中的行序为 4007 在 4006 之前，本表按原序逐字保留。

### 12.2 错误码简单处理逻辑（P1/P6/S2 逐字）

> 针对 WebSocket 错误码的简单处理逻辑：
>
> - 4009 可以重新发起 resume
>
> - 4914，4915 不可以连接，请联系官方解封
>
> - 其他错误，请重新发起 identify

### 12.3 P6 页面原表（逐字，含文档中的重复行）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/websocket.html

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
| 4014 | intent 无权限 | 否 | 否 |
| 4900~4913 | 内部错误，请重连 | 否 | **是** |
| 4914 | 机器人已下架,只允许连接沙箱环境,请断开连接,检验当前连接环境 | 否 | 否 |
| 4915 | 机器人已封禁,不允许连接,请断开连接,申请解封后再连接 | 否 | 否 |

> 注：P6 原表存在 `4014 intent 无权限` 连续重复两行，本文件按原文逐字保留该重复。
> 注：P6 中 4914 / 4915 的文案使用半角逗号（`,`），P1 使用全角逗号（`，`）；本文件分别按各自来源逐字保留。

### 12.4 S2 页面原表（逐字）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html

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

### 12.5 表中未出现但任务提及的关闭码

- 任务清单中提到的 `4003`、`4004`、`4005`：在本组官方页面（P1、P6、S2）的 WebSocket 错误码表中 **均未出现** ── **4003 / 4004 / 4005 的含义：官方文档未提供。**
- 官方表中实际出现的关闭码为：`4001`、`4002`、`4006`、`4007`、`4008`、`4009`、`4010`、`4011`、`4012`、`4013`、`4014`、`4900~4913`、`4914`、`4915`。**`4003`~`4005` 缺失**，即官方文档在该段编号上不连续。
- 本组官方页面 **未提供** 「WebSocket 关闭码（close code）」与「错误码」的区分说明，也未提供标准 WebSocket 关闭码（1000/1001 等）的解释 ── **标准关闭码：官方文档未提供。**

### 12.6 参考的 HTTP 状态码（与 WSS 无直接关系，但为 P8/P9「错误码」页所指内容）

来源 URL（S2）：https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html

> 错误码分为两部分：
>
> - http 状态码
>
> - http body 返回的 json 中的 err_code

```json
{
  "err_code": 40034005,
  "message": "回复消息msg_id已过期",
  "trace_id": "4a8a61565b909f199b1ec169fdd6f49e" }
```

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

> S2 该页同时包含「公共错误码」完整表（10001、10003、10004、11241～11282、11301～11306、12001～12003、20028、50006、50035～50057、301000～301007、302000～302024、304003～304052、306001～306006、501000～501020、502001～502010、503001～503020、504001～504004、610001～610014、620001～620007、630001～630007、1000000~2999999、1100100～1100499、3000000~3999999、3300006 等）。因该表面向 OpenAPI 而非 WSS 独占，本文件不逐条复制；如需完整内容请参见来源 URL。其中与 gateway 相关的两条值得注意：
>
> | 值 | 含义 |
> |---|---|
> | 304018 | SESSION_NOT_EXIST 机器人没连上 gateway |
> | 11265 | ErrorRobotHasBaned 机器人已经被封禁 （与 WSS 关闭码 4915 语义相关，但官方文档未声明二者关系） |

### 12.7 全链路追踪（P7 逐字）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/error-trace/

P7 原文：

> ## 错误码
>
> ## 有关 traceID
>
> 在 openapi 的返回 http 头上，有一个 `X-Tps-trace-ID` 自定义头部，是平台的链路追踪 ID，如果开发者有无法自己定位的问题，需要找平台协助的时候，可以提取这个 ID，提交给平台方。
>
> 方便查询相关日志。

> 说明：P7（错误与调试首页）本身 **未包含** 任何错误码表格，仅包含「错误码」标题（无内容）与「有关 traceID」正文。S3 中给出了同一信息的另一种表述：
>
> > 平台的链路追踪 `TraceID` 可通过两种方式获取：
> >
> > - **HTTP 响应头** ：`X-Tps-trace-ID` 字段
> > - **响应 Body** ：返回体中的 `trace_id` 字段

---

## 13. 接口通信基础框架首页（P5）

来源 URL：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/

P5 页面正文全文（逐字）：

> ## 接口通信基础框架
>
> 接口通信基础框架，BOT 开发者对接 QQ 机器人开放平台提供的接口能力，开发出一款让普通 QQ 用户可用的机器人。

> 说明：P5 页面 **仅包含上述引言**，无任何子页面链接清单之外的正文内容 ── 该页 **未提供** WSS 相关的任何字段、表格、示例或规则。

---

## 14. 官方文档未提供的内容清单（汇总）

以下条目在任务要求覆盖的范围内，但在本组官方页面（P1–P10）以及为填补「引用指向」而抓取的补充官方页面（S1–S3）中 **均未出现**，故标注为「官方文档未提供」：

1. **`GET /gateway` 的专属请求头清单**（Header 字段列表、是否必需 `Authorization`）── 未提供（只有 S3 的通用鉴权说明）。
2. **`GET /gateway/bot` 的专属请求头清单** ── 未提供。
3. **`GET /gateway` / `GET /gateway/bot` 的专属错误码** ── 未提供，两页均只写「详见错误码」并指向官方错误码页。
4. **`GET /gateway/bot` 的接口频率限制** ── 未提供（仅 P10 给出了 `GET /gateway` 的「2 QPM / 10 QPM burst」）。
5. **`GET /gateway/bot` 在 autogen 接口文档中的独立页面**（同 P10 形式）── 本组页面中未提供对应页面（P10 仅为 `gateway.get`）。
6. **WSS 连接层面的协议细节**：Sec-WebSocket-Protocol 子协议协商、消息编码格式、连接超时、握手超时、重连退避算法 ── 未提供。
7. **压缩传输**：zlib / deflate / transport compression / `compress` 字段 ── 未提供；本组页面中未出现任何压缩相关内容。
8. **心跳丢失判定阈值**（例如多少毫秒/多少次未收到 Op11 即判定断线）── 未提供。
9. **zombie connection（僵尸连接）的定义与处理流程** ── 未提供；本组页面中未出现「zombie」一词。
10. **服务端主动发送心跳（OpCode 1）的条件与 `d` 内容** ── 未提供（OpCode 1 定义为 `Send/Receive`，但无进一步说明）。
11. **OpCode 3 / 4 / 5 / 8 的定义** ── 未提供（官方表中不存在这些取值）。
12. **OpCode 7 Reconnect 的 `d` 结构、触发条件、客户端应执行的动作** ── 未提供（仅表格一句话定义）。
13. **OpCode 9 Invalid Session 的 `d` 结构、客户端标准处理步骤** ── 未提供（仅表格一句话定义）。
14. **`s`（seq）的自增规则细节**：是否从 1 起、步长是否为 1、断线期间是否连续、是否按 shard 独立编号 ── 未提供。
15. **`session_id` 的有效期 / Resume 的「短时间内」具体时限 / 单 session 可 Resume 次数上限** ── 未提供。
16. **READY 事件 `d` 字段表**（`version`、`session_id`、`user.id`、`user.username`、`user.bot`、`shard` 的类型与含义）── 未提供字段表，仅有 JSON 示例。
17. **`user.bot` 之外的用户其他字段、`version` 的取值含义** ── 未提供。
18. **Identify `d` 与 Resume `d` 各字段的显式「必填/可选」标注** ── 未提供（无法从官方文档得到字段级必填结论；仅 `properties` 有「可以留空」的文字）。
19. **`token` 格式以哪一处为准**（P1/P4 的 `QQBot {AccessToken}` vs S1 的 `Bot {appid}.{app_token}`）── 官方文档未提供统一说明。
20. **`properties.$os` / `$browser` / `$device` 各自的类型、取值范围、默认值** ── 未提供（仅「目前无实际作用」）。
21. **intents 中未出现的位（1<<2 ~ 1<<8、1<<11、1<<13 ~ 1<<24、1<<31 及以上）的含义** ── 未提供。
22. **intents 的「预设组合值」/ 官方推荐组合** ── 未提供（仅有 `0|1<<30|1<<1` 这类手工位或示例）。
23. **`max_concurrency` 的实际节流实现方式**（是否必须串行建连、5s 窗口如何滑动）── 未提供。
24. **shard 总数与 `/gateway/bot` 返回 `shards` 的关系是否强制**、**每个 shard 是否独立 `session_id`**、**分片与 READY/RESUMED 的关系** ── 未提供。
25. **错误码 4003 / 4004 / 4005 的含义** ── 未提供（官方表中的关闭码不连续）。
26. **标准 WebSocket 关闭码（1000、1001 等）与业务错误码的区分** ── 未提供。
27. **重连后的补发上限 / 补发事件数量上限 / 补发超时** ── 未提供。
28. **`GET /gateway/bot` 返回 `shards` 建议值的计算依据** ── 未提供。
29. **P9 示例 JSON 的格式错误是否有更正版本** ── 未提供（官方页面原文即缺少 `"url":` 字段名）。

---

## 附：各页面文档站显示的「上次更新」时间（用于版本核对）

| 页面 | 官方显示的上次更新时间 |
|---|---|
| P1 WebSocket 方式（event-emit/websocket） | 7/30/2026, 10:21:27 PM |
| P2 通用数据结构（event-emit/payload） | 7/21/2026, 9:50:42 PM |
| P3 opcode | 9/12/2024, 9:12:52 PM |
| P4 事件订阅与通知（interface-framework/event-emit） | 9/11/2026, 6:09:37 PM |
| P5 接口通信基础框架首页 | 5/20/2026, 8:38:10 PM |
| P6 WebSocket 错误码（error-trace/websocket） | 7/21/2026, 9:50:42 PM |
| P7 错误与调试首页（error-trace） | 12/20/2023, 4:46:30 PM |
| P8 获取通用 WSS 接入点（openapi/wss/url_get） | 7/30/2026, 10:21:27 PM |
| P9 获取带分片 WSS 接入点（openapi/wss/shard_url_get） | 7/30/2026, 10:21:27 PM |
| P10 autogen/api/gateway.get | 7/22/2026, 6:23:09 PM |
| S1 interface-framework/reference | 7/30/2026, 10:21:27 PM |
| S2 openapi/error/error | 7/21/2026, 9:50:42 PM |
| S3 api-call-guide | 9/17/2026, 11:37:24 AM |
