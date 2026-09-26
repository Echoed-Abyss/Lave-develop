# QQ 机器人开放平台｜鉴权体系 + 消息类 HTTP API 全量整理

> **唯一事实来源**：QQ 机器人开放平台官方文档站 `https://bot.q.qq.com/wiki`。本文只使用官方文档内容，不含第三方博客 / CSDN / GitHub issue / SDK 源码。
> **抓取日期**：2026-09-26
> **编排原则**：逐字保留官方字段表（字段名 / 类型 / 描述 / 必填）、JSON 请求与响应样例、错误码表、频率限制数字；每个章节标注来源 URL；官方文档未提供的内容统一写作「官方文档未提供」。

---

## 目录

- [0. 页面清单与抓取状态](#0-页面清单与抓取状态)
- [1. 鉴权体系](#1-鉴权体系)
  - [1.1 接入票据：AppID / AppSecret / Token（已弃用）](#11-接入票据appid--appsecret--token已弃用)
  - [1.2 访问凭证类型（access_token）](#12-访问凭证类型access_token)
  - [1.3 获取 access_token（POST /app/getAppAccessToken）](#13-获取-access_tokenpost-appgetappaccesstoken)
  - [1.4 凭证有效期与刷新](#14-凭证有效期与刷新)
  - [1.5 使用访问凭证（Authorization 请求头）](#15-使用访问凭证authorization-请求头)
  - [1.6 接口调用与鉴权（api-use）](#16-接口调用与鉴权api-use)
  - [1.7 AccessToken 与已废弃 Token 的区别](#17-accesstoken-与已废弃-token-的区别)
  - [1.8 AppID + AppSecret 在 oauth 场景的用途](#18-appid--appsecret-在-oauth-场景的用途)
- [2. API 使用规范](#2-api-使用规范)
  - [2.1 统一请求地址](#21-统一请求地址)
  - [2.2 鉴权方式](#22-鉴权方式)
  - [2.3 请求示例](#23-请求示例)
  - [2.4 响应结构](#24-响应结构)
  - [2.5 唯一身份机制（openid）](#25-唯一身份机制openid)
  - [2.6 全链路追踪](#26-全链路追踪)
  - [2.7 HTTP 状态码](#27-http-状态码)
  - [2.8 公共错误码](#28-公共错误码)
  - [2.9 Content-Type / User-Agent / X-Union-Appid 等特殊请求头](#29-content-type--user-agent--x-union-appid-等特殊请求头)
  - [2.10 签名（sign）机制：Ed25519 回调验签](#210-签名sign机制ed25519-回调验签)
- [3. 消息收发概述](#3-消息收发概述)
- [4. 单聊 C2C 发消息 POST /v2/users/{openid}/messages](#4-单聊-c2c-发消息-post-v2usersopenidmessages)
- [5. 群聊 GROUP_AT_MESSAGE_CREATE 回复 POST /v2/groups/{group_openid}/messages](#5-群聊-group_at_message_create-回复-post-v2groupsgroup_openidmessages)
- [6. 流式消息 POST /v2/users/{openid}/stream_messages](#6-流式消息-post-v2usersopenidstream_messages)
- [7. 消息撤回 DELETE](#7-消息撤回-delete)
- [8. 富媒体 / 文件上传（三段式 + 预上传）](#8-富媒体--文件上传三段式--预上传)
- [9. 消息类型与富文本](#9-消息类型与富文本)
- [10. 频率限制与时效规则汇总](#10-频率限制与时效规则汇总)
- [11. 本组涉及的 HTTP 错误码全表](#11-本组涉及的-http-错误码全表)
- [12. 官方文档未提供的内容清单](#12-官方文档未提供的内容清单)

---

## 0. 页面清单与抓取状态

| # | 页面 | URL | 状态 |
|---|---|---|---|
| 1 | 获取访问凭证 | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/access-token.html | 已抓取 |
| 2 | API 调用指南 | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html | 已抓取 |
| 3 | 接口调用与鉴权 | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/api-use.html | 已抓取 |
| 4 | 安全和授权（sign） | https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/sign.html | 已抓取 |
| 5 | 发送群聊消息 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_messages.post.html | 已抓取 |
| 6 | 发送单聊消息 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_messages.post.html | 已抓取 |
| 7 | 撤回群聊消息 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_messages_message_id.delete.html | 已抓取 |
| 8 | 撤回单聊消息 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_messages_message_id.delete.html | 已抓取 |
| 9 | 流式发送单聊消息 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_stream_messages.post.html | 已抓取 |
| 10 | 单聊富媒体上传 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_files.post.html | 已抓取 |
| 11 | 群聊富媒体上传 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_files.post.html | 已抓取 |
| 12 | 群聊富媒体预上传 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_id_upload_prepare.post.html | 已抓取 |
| 13 | 群聊分片上传完成 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_id_upload_part_finish.post.html | 已抓取 |
| 14 | 单聊富媒体预上传 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_id_upload_prepare.post.html | 已抓取 |
| 15 | 单聊分片上传完成 | https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_id_upload_part_finish.post.html | 已抓取 |
| 16 | 消息收发概述 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/overview.html | 已抓取 |
| 17 | 富媒体消息概述 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/rich-media.html | 已抓取 |
| 18 | 消息类型（总览） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/overview.html | 已抓取 |
| 19 | Markdown 消息 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/markdown.html | 已抓取 |
| 20 | 结构化卡片消息（ARK） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/ark.html | 已抓取 |
| 21 | Embed 消息 | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/embed.html | 已抓取 |
| 22 | 表情表态（Emoji） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/emoji.html | 已抓取 |
| 23 | 消息按钮（msg-btn） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/msg-btn.html | 已抓取 |
| 24 | 文本交互（text-chain） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/text-chain.html | 已抓取 |
| 25 | 消息对象模型（model） | https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/template/model.html | 已抓取 |
| 附 | 启动接入（AppID/AppSecret/Token 已弃用 说明） | https://bot.q.qq.com/wiki/develop/api-v2/ | 已抓取（补充） |

---

## 1. 鉴权体系

### 1.1 接入票据：AppID / AppSecret / Token（已弃用）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/

注册创建机器人后：获得的开发机器人接入票据 `AppID` `AppSecret`

| 名称 | 描述 | 备注 |
|---|---|---|
| AppID | 机器人 ID | 必须使用 |
| AppSecret | 机器人密钥 | 用于在 `oauth` 场景进行请求签名的密钥 |
| Token(已弃用) | 机器人 Token | 可用于调用开放接口的鉴权。 |

> 原文重要提示：**Token 的鉴权方式已废弃，请使用更安全的 `Access Token` 鉴权方式。**

补充（同页）：QQ 机器人：一个机器人可以被添加到 `群聊/频道` 内互动对话，QQ 用户也可以直接跟机器人 `单独对话`。注册地址：QQ 开放平台官网 `https://q.qq.com/#/`。

---

### 1.2 访问凭证类型（access_token）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/access-token.html

QQ 机器人开放平台提供以下类型的访问凭证：

| 凭证类型 | 是否需要用户授权 | 说明 |
|---|---|---|
| access_token | 否 | 机器人身份调用 API 时使用的凭证，可读写的数据范围由机器人的权限范围决定。适用于机器人主动发消息、管理群聊等场景。 |

---

### 1.3 获取 access_token（POST /app/getAppAccessToken）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/access-token.html
> 同内容亦见：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/api-use.html

#### 请求（基础信息）

| 基本 |  |
|---|---|
| HTTP URL | https://api.bot.qq.com/app/getAppAccessToken |
| HTTP Method | POST |

> 注：任务描述中提及的 `GET /app/getAppAccessToken`，官方文档标注的方法为 **POST**；官方文档未提供 GET 方式。

#### 请求参数

| **属性** | **类型** | **必填** | **说明** |
|---|---|---|---|
| appId | string | 是 | 在开放平台管理端上获得。 |
| clientSecret | string | 是 | 在开放平台管理端上获得。 |

#### 返回参数

**成功响应**

| **属性** | **类型** | **说明** |
|---|---|---|
| access_token | string | 获取到的凭证。 |
| expires_in | number | 凭证有效时间，单位：秒。目前是 7200 秒之内的值。 |

**失败响应**

| **属性** | **类型** | **说明** |
|---|---|---|
| code | number | 错误码，取值见下方「业务错误码」。 |
| message | string | 错误信息，仅用于人工排查，内容可能随时调整。 |

> 注意（官方原文）：该接口的业务错误通过响应体的 `code` 返回，即使调用失败，HTTP 返回码仍为 `200`。请优先依据 `code` 判断请求是否成功，不要只依赖 HTTP 返回码；也不要依据 `message` 判定错误类型。详见下方「错误返回码」。

#### 错误码（业务错误码）

| **错误码** | **错误信息** | **排查指南** |
|---|---|---|
| 100001 | Too many requests | 请求过于频繁，请降低调用频率后重试 |
| 100007 | appid invalid | AppID 无效，或机器人状态不正常（被封禁或已删除），请检查 AppID 是否正确以及机器人状态 |
| 100016 | invalid appid or secret | AppID 或 ClientSecret 不正确，请检查传入的 appId 和 clientSecret 是否与开放平台管理端一致 |
| 10004 | 机器人不存在 | AppID 对应的机器人不存在，请确认 AppID 是否正确 |

#### 调用示例

```
curl --location 'https://api.bot.qq.com/app/getAppAccessToken' \
--header 'Content-Type: application/json' \
--data '{
 "appId": "APPID",
 "clientSecret": "CLIENTSECRET"
}'
```

#### 返回示例

**成功**

```
{
  "access_token": "ACCESS_TOKEN",
  "expires_in": "7200"
}
```

**失败**

```
{
  "code": 100007,
  "message": "appid invalid"
}
```

> 另注：在 `api-use.html` 中该接口的「错误码」小节只给出一张表：`| 错误码 | 错误码取值 |` → `| 0 | ok |`，与 `access-token.html` 的业务错误码表并存，两处均为官方文档原文。

---

### 1.4 凭证有效期与刷新

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/access-token.html

目前 `access_token` 生命周期默认 `7200` 秒（2 小时），开发者需要在过期后自行刷新 `access_token`，保证调用链路权限正常。

- 每次请求不会刷新新的 `access_token`，在有效期内重复获取会返回相同的值
- 在上一个 `access_token` 接近过期时间 `60` 秒内，获取 `access_token` 时，会获得一个新的 `access_token`，老的 `access_token` 在这个 `60` 秒内仍然有效
- 建议开发者在服务端设置定时刷新凭证的业务逻辑，以防止过期

（`api-use.html` 中「其他说明」表述一致：生命周期默认 `7200` 秒；过期前 `60` 秒内再次获取时返回新 token，老 token 在 `60` 秒内仍有效。）

---

### 1.5 使用访问凭证（Authorization 请求头）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/access-token.html

在每次调用 OpenAPI 开放接口时，需要在 HTTP 请求头中引入 `access_token` 进行调用权限验证。

**请求头**：

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| Authorization | string | 是 | 格式值：`QQBot ACCESS_TOKEN` |

**示例**：

```
curl --location 'https://api.bot.qq.com/users/@me' \
--header 'Authorization: QQBot ACCESS_TOKEN'
```

> 注意（官方原文）：为了安全考虑，请勿在应用前端使用访问凭证。请在应用服务端发起 API 访问请求。

**关于前缀拼写的官方原文对照（逐字）**：

| 出处 | 原文写法 |
|---|---|
| access-token.html 请求头表 | `QQBot ACCESS_TOKEN` |
| access-token.html 示例 | `--header 'Authorization: QQBot ACCESS_TOKEN'` |
| api-call-guide.html 鉴权方式 | `Authorization: QQBot {ACCESS_TOKEN}` |
| api-call-guide.html 请求示例 | `-H 'Authorization: QQBot {ACCESS_TOKEN}'` |
| api-use.html 请求头表 | 格式值："QQBot ACCESS_TOKEN" |
| api-use.html 示例 | `"Authorization": "QQBot {ACCESS_TOKEN}"` |

即：前缀固定为 **`QQBot`**（大写 Q、大写 B、其余小写，其后一个空格），再拼接 access_token。

---

### 1.6 接口调用与鉴权（api-use）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/api-use.html

> 原文说明：`QQ 机器人` 服务端开放的 `openapi` 接口，均使用 `https` 方式进行调用，通过 `AccessToken` 机制实现对 `openapi` 接口调用的鉴权。

**统一地址**

```
https://api.bot.qq.com
```

**请求头**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| Authorization | string | 是 | 格式值："QQBot ACCESS_TOKEN" |

**示例**

```
{
  "headers": {
    "Authorization": "QQBot {ACCESS_TOKEN}"
  }
}
```

获取调用凭证的请求 / 请求参数 / 返回参数 / 调用示例同 [1.3](#13-获取-access_tokenpost-appgetappaccesstoken)；该页「错误码」为 `| 0 | ok |`。

---

### 1.7 AccessToken 与已废弃 Token 的区别

官方文档可比对说明如下（均为原文）：

| 维度 | Access Token（推荐） | Token（已弃用） |
|---|---|---|
| 官方出处 | access-token.html、api-use.html | https://bot.q.qq.com/wiki/develop/api-v2/ 「接入票据」表 |
| 定位 | 「机器人身份调用 API 时使用的凭证，可读写的数据范围由机器人的权限范围决定」 | 「机器人 Token」「可用于调用开放接口的鉴权」 |
| 获取方式 | 通过 `POST https://api.bot.qq.com/app/getAppAccessToken` 用 appId + clientSecret 换取 | 注册创建机器人后在管理端直接获得 |
| 有效期 | 默认 7200 秒，需自行刷新；过期前 60 秒内可换新 | 官方文档未提供 |
| 使用位置 | HTTP Header：`Authorization: QQBot ACCESS_TOKEN` | 官方文档未提供（仅说明「可用于调用开放接口的鉴权」） |
| 官方态度 | 推荐使用 | 原文：「Token 的鉴权方式已废弃，请使用更安全的 `Access Token` 鉴权方式。」 |

相关旁证（api-call-guide.html 公共错误码，原文）：
- `11262` = `ErrorCheckRobot` 当前接口不支持使用机器人 Bot Token 调用
- `11273` = `ErrorCheckUserAuth` 检查用户权限失败，当前接口不支持使用 Bearer Token 调用

> 说明：官方文档没有给出「AccessToken vs 已废弃 Token」的逐项对照表；上表为对官方原文的归纳，未新增任何官方未陈述的事实。其它差异项（如已废弃 Token 的具体格式、刷新机制）标注为「官方文档未提供」。

---

### 1.8 AppID + AppSecret 在 oauth 场景的用途

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/ （「接入票据」表）

官方原文：
- `AppID` 描述为「机器人 ID」，备注「必须使用」
- `AppSecret` 描述为「机器人密钥」，备注「**用于在 `oauth` 场景进行请求签名的密钥**」
- `Token(已弃用)` 描述为「机器人 Token」，备注「可用于调用开放接口的鉴权」，并提示「Token 的鉴权方式已废弃，请使用更安全的 `Access Token` 鉴权方式。」

在本组抓取的 25 个页面中，**未出现** OAuth 授权码流程（如 authorize / token 端点）、`AppSecret` 参与 oauth 签名的具体算法与签名步骤、OAuth scope 列表等内容 → 该部分标注为「官方文档未提供」。

另据 sign.html：开发者平台用于加密签名字符串和服务器端验证签名字符串的密钥称为 **Bot Secret**（原文：「开发者平台的 Bot Secret 用于加密签名字符串和服务器端验证签名字符串的密钥。用户必须严格保管安全凭证，避免泄露。」）。

---

## 2. API 使用规范

### 2.1 统一请求地址

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html
> 同见：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/api-use.html

QQ 机器人开放平台提供了基于 HTTPS 协议的 OpenAPI 接口，开发者可以通过这些接口实现消息收发、群聊管理、频道管理等功能。

```
https://api.bot.qq.com
```

> 关于 `https://api.sgroup.qq.com` 域名：在本组抓取的官方页面中**未出现**该域名，官方给出的统一请求地址为 `https://api.bot.qq.com` → `https://api.sgroup.qq.com` 标注为「官方文档未提供」（本组页面范围内）。

### 2.2 鉴权方式

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

调用 API 时，需要将 access_token 放入请求 Header 中：

```
Authorization: QQBot {ACCESS_TOKEN}
```

### 2.3 请求示例

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

以发送单聊消息为例：

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

> 由上示例可知，官方文档使用的请求 `Content-Type` 为 `application/json; charset=utf-8`。

### 2.4 响应结构

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

API 调用成功时，响应体直接返回业务数据；调用失败时，响应体包含 `err_code`、`message` 等错误信息：

- **err_code**：错误码。成功时为 0
- **message**：错误信息
- **trace_id**：链路追踪 ID，用于问题排查

**成功响应示例**：

```
{
  "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "timestamp": "2026-07-21T10:30:00+08:00"
}
```

**失败响应示例**：

```
{
  "err_code": 40034005,
  "message": "回复消息msg_id已过期",
  "trace_id": "4a8a61565b909f199b1ec169fdd6f49e"
}
```

> 注意（官方原文）：请不要依据 `message` 来判定一个请求是否失败，`message` 可能会随时调整，建议根据 `err_code` 判断请求是否失败。

### 2.5 唯一身份机制（openid）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

不同的 `bot(AppID)` 获取到的用户 `openid`，群 `openid`，频道 `openid` 均不相同，若跨业务有关联用户身份需求，后续提供跨 `AppID` 绑定后，使用类似 `unionid` 的机制打通身份。

举例：

- 不同 `bot` 在单聊场景，获取到的用户唯一识别 `openid` 不一样，称为 `user_openid`
- 不同 `bot` 在群聊场景，获取到的群唯一识别号 `openid` 不一样，称为 `group_openid`
- `bot` 在群聊场景，获取到用户在群内的唯一识别号，称为 `member_openid`

### 2.6 全链路追踪

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

平台的链路追踪 `TraceID` 可通过两种方式获取：

- **HTTP 响应头**：`X-Tps-trace-ID` 字段
- **响应 Body**：返回体中的 `trace_id` 字段

如果开发者有无法自行定位的问题，需要找平台协助时，可提取该 ID 提交给平台方，方便查询相关日志。

### 2.7 HTTP 状态码

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

| 值 | 含义 |
|---|---|
| 200 | 成功 |
| 204 | 成功，但是无包体，一般用于删除操作 |
| 201, 202 | 异步操作成功，虽然说成功，但是会返回一个 error body，需要特殊处理 |
| 401 | 认证失败 |
| 404 | 未找到 API |
| 405 | HTTP Method 不允许 |
| 429 | 频率限制 |
| 500 | 处理失败 |
| 504 | 处理失败 |

### 2.8 公共错误码

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html

以下为所有接口通用的公共错误码。各接口特有的错误码请查阅具体接口文档中的「错误码」章节。

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
| 11254 | ErrorInterfaceForbidden 应用接口被封禁，该机器人虽然获得了该接口权限，但是被封禁了 |
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
| 11275 | ErrorWrongAppid 无 appid，同 11251 |
| 11301 | ErrorGetHTTPHeader HTTP Header 无效 |
| 11302 | ErrorGetHeaderUIN HTTP Header 无效 |
| 11303 | ErrorGetNick 获取昵称失败 |
| 11304 | ErrorGetAvatar 获取头像失败 |
| 11305 | ErrorGetGuildID 获取频道 ID 失败 |
| 11306 | ErrorGetGuildInfo 获取频道信息失败 |
| 12001 | ReplaceIDFailed 替换 id 失败 |
| 12002 | RequestInvalid 请求体错误 |
| 12003 | ResponseInvalid 回包错误 |
| 20028 | ChannelHitWriteRateLimit 子频道消息触发限频 |
| 50006 | CannotSendEmptyMessage 消息为空 |
| 50035 | InvalidFormBody form-data 内容异常 |
| 50037 | 带有 markdown 消息只支持 markdown 或者 keyboard 组合 |
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
| 301000~301099 | 子频道权限错误 |
| 301000 | 参数错误 |
| 301001 | 查询频道信息错误 |
| 301002 | 查询子频道权限错误 |
| 301003 | 修改子频道权限错误 |
| 301004 | 私密子频道关联的人数到达上限 |
| 301005 | 调用 Rpc 服务失败 |
| 301006 | 非群成员没有查询权限 |
| 301007 | 参数超过数量限制 |
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
| 304023 | PUSH_MSG_ASYNC_OK 推送消息异步调用成功，等待人工审核 |
| 304024 | REPLY_MSG_ASYNC_OK 回复消息异步调用成功，等待人工审核 |
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
| 306001 | param invalid 撤回消息参数错误 |
| 306002 | msgid error 消息 id 错误 |
| 306003 | fail to get message 获取消息错误(可重试) |
| 306004 | no permission to delete message 没有撤回此消息的权限 |
| 306005 | retract message error 消息撤回失败(可重试) |
| 306006 | fail to get channel 获取子频道失败(可重试) |
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
| 504000~504999 | 消息频率相关错误 |
| 504001 | 请求参数无效错误 |
| 504002 | 获取 HTTP 头失败 |
| 504003 | 获取 BOT UIN 错误 |
| 504004 | 获取消息频率设置信息错误 |
| 610000-619999 | 频道权限错误 |
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
| 620001-629999 | 表情表态错误 |
| 620001 | 表情表态无效参数 |
| 620002 | 已经达到表情反应的类型数量上限 |
| 620003 | 已经设置过该表情表态 |
| 620004 | 没有设置过该表情表态 |
| 620005 | 没有权限设置表情表态 |
| 620006 | 操作限频 |
| 620007 | 表情表态操作失败，请重试 |
| 630001-639999 | 互动回调数据更新 |
| 630001 | 互动回调数据更新无效参数 |
| 630002 | 互动回调数据更新获取AppID失败 |
| 630003 | 互动回调数据AppID不匹配 |
| 630004 | 互动回调数据更新内部存储错误 |
| 630005 | 互动回调数据更新内部存储读取错误 |
| 630006 | 互动回调数据更新读取请求AppID失败 |
| 630007 | 互动回调数据太大 |
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
| 3000000~3999999 | 编辑消息错误 |
| 3300006 | 安全打击 |

### 2.9 Content-Type / User-Agent / X-Union-Appid 等特殊请求头

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/api-call-guide.html 、https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/api-use.html 、https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/embed.html

| 请求头 | 官方文档是否给出 | 说明（原文） |
|---|---|---|
| `Authorization` | 是 | 必填，格式值 `QQBot ACCESS_TOKEN` |
| `Content-Type` | 是 | 调用示例中使用 `Content-Type: application/json; charset=utf-8`（api-call-guide.html 请求示例）；Embed 消息文档「Content-Type」小节写 `application/json` |
| `X-Tps-trace-ID` | 是（响应头） | 「HTTP 响应头：`X-Tps-trace-ID` 字段」用于全链路追踪 |
| `X-Signature-Ed25519` | 是（回调请求头） | 回调验签用，见 [2.10](#210-签名sign机制ed25519-回调验签) |
| `X-Signature-Timestamp` | 是（回调请求头） | 回调验签用，见 [2.10](#210-签名sign机制ed25519-回调验签) |
| `User-Agent` | 否 | 在本组抓取的官方页面中**未出现**任何 User-Agent 约定 → 「官方文档未提供」 |
| `X-Union-Appid` | 否 | 在本组抓取的官方页面中**未出现**该请求头 → 「官方文档未提供」 |
| `X-Uin` | 仅提及 | 仅在公共错误码文本中出现 `503008 获取X-Uin失败`，无请求头用法说明 |

### 2.10 签名（sign）机制：Ed25519 回调验签

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/interface-framework/sign.html

开发者需要对每一次回调请求，根据回调中的签名等信息验证请求者身份，避免安全隐患。目前签名算法使用 **Ed25519**。

#### 安全凭证

开发者平台的 Bot Secret 用于加密签名字符串和服务器端验证签名字符串的密钥。用户必须严格保管安全凭证，避免泄露。

#### 验证签名

**1. 签名验证参数**

| 字段名 | 说明 | 参考值 |
|---|---|---|
| X-Signature-Ed25519 | HTTP Header 中透传 Signature | 3ecd***（64字节） |
| X-Signature-Timestamp | HTTP Header 透传的签名时间戳 | 1636373772 |
| HTTP Body | HTTP 请求中 Body 值 | {"msg":"hello"} |

**2. 验证签名过程**

以下代码以 Go 语言为例，引用 `crypto/ed25519` 包实现 `Ed25519` 算法。

- 根据开发者平台的 Bot Secret 值进行 repeat 操作得到签名 32 字节的 seed，根据 seed 调用 Ed25519 算法生成 32 字节公钥

```
  // 根据botSecret进行repeat操作后得到seed值计算出公钥
 seed := botSecret
 for len(seed) < ed25519.SeedSize {
 seed = strings.Repeat(seed, 2)
  }
 rand := strings.NewReader(seed[:ed25519.SeedSize])
 publicKey, privateKey, err := ed25519.GenerateKey(rand)
```

DEMO

```
【输入】
secret: naOC0ocQE3shWLAfffVLB1rhYPG7
seed: naOC0ocQE3shWLAfffVLB1rhYPG7naOC
【输出】
publicKey: [215 195 98 254 120 174 248 31 242 50 135 180 147 98 139 93 176 42 60 79 227 11 33 94 77 25 96 155 93 118 103 58]
privateKey: [110 97 79 67 48 111 99 81 69 51 115 104 87 76 65 102 102 102 86 76 66 49 114 104 89 80 71 55 110 97 79 67 215 195 98 254 120 174 248 31 242 50 135 180 147 98 139 93 176 42 60 79 227 11 33 94 77 25 96 155 93 118 103 58]
```

- 获取 HTTP Header 中 X-Signature-Ed25519 的值进行 hex（十六进制解码）操作后的得到 Signature 并进行校验

```
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

- 获取 HTTP Header 中 X-Signature-Timestamp 的和 HTTP Body 的值按照 timestamp+body 顺序进行组合成签名体 msg

```
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

- 根据公钥、Signature、签名体调用 Ed25519 算法进行验证

```
 ed25519.Verify(publicKey, msg.Bytes(), sig)
```

DEMO

```
【输入】
secret: naOC0ocQE3shWLAfffVLB1rhYPG7
body: { "op": 0,"d": {}, "t": "GATEWAY_EVENT_NAME"}
timestamp: 1725442341

【输出】
sig: 865ad13a61752ca65e26bde6676459cd36cf1be609375b37bd62af366e1dc25a8dc789ba7f14e017ada3d554c671a911bfdf075ba54835b23391d509579ed002
```

> 结论：官方文档给出的 sign 机制是**回调请求验签**（Ed25519），不是「调用 OpenAPI 时对请求体做 sign 签名」。调用 OpenAPI 请求体签名另有机制 → 本组页面未提供 → 「官方文档未提供」。

---

## 3. 消息收发概述

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/overview.html

机器人可在 QQ 单聊、群聊、频道三种场景下收发消息。本页介绍基础概念与通用规则，具体接口与事件请参考对应子分类。

### 3.1 收发场景

| 场景 | 发送消息 | 接收事件 |
|---|---|---|
| QQ 单聊 | 发送单聊消息 / 流式消息 | C2C_MESSAGE_CREATE |
| QQ 群聊 | 发送群消息 | GROUP_AT_MESSAGE_CREATE / GROUP_MESSAGE_CREATE |
| 频道 | 发送子频道消息 / 频道私信 | 频道消息事件 |

### 3.2 对话场景图示

说明：机器人可以被添加各种聊天场景下。

| 单聊 | 群聊 | 文字子频道 | 频道私信 |
|---|---|---|---|
| （官方配图：https://aka.doubaocdn.com/s/CRiWn8DHJI） | （官方配图：https://aka.doubaocdn.com/s/ojn54Lz0dc） | （官方配图：https://aka.doubaocdn.com/s/wcJyw0mV7W） | （官方配图：https://aka.doubaocdn.com/s/hs67mGve5g） |

### 3.3 主动消息与被动消息

| 类型 | 特征 | 说明 |
|---|---|---|
| 主动消息 | 无任何条件 | 机器人主动触达用户，用户可在客户端关闭「允许主动发送」开关，关闭后主动消息将发送失败 |
| 互动召回消息 | `is_wakeup=true` | 用户主动与机器人对话之后每个周期内可下发 1 条召回消息 |
| 被动消息（回复用户） | 携带 `msg_id` | 对用户消息的回复 |
| 被动消息（响应事件） | 携带 `event_id` | 对事件的回复 |

### 3.4 消息类型

通过 `msg_type` 指定消息内容格式：

| msg_type | 类型 | 内容字段 | 发送 | 接收 |
|---|---|---|---|---|
| 0 | 文本 | `content` | ✅ | ✅ |
| 2 | Markdown | `markdown` | ✅ | - |
| 7 | 富媒体 | `media`（需先上传文件获取 `file_info`） | ✅ | ✅ |

除上述之外，响应中还可能收到图片、视频、语音、表情、卡片等类型，详见「消息类型」。

### 3.5 富媒体消息

图片、视频、语音、文件等富媒体需先上传获取 `file_info`，再通过发消息接口（`msg_type=7`）携带 `media.file_info` 发送。

上传方式：

- **分片上传**：推荐使用，无需开发者提供公网 CDN 地址，参考分片上传流程
- **整文件上传**：单聊上传 / 群聊上传
- `file_info` 有时效性（`ttl`），过期需重新上传。
- 单聊和群聊的文件上传接口不互通。

### 3.6 频率与时效规则

**被动消息**

| 场景 | 有效期 | 每条消息可回复次数 |
|---|---|---|
| 单聊 | 60 分钟 | 4 次 |
| 群聊 | 5 分钟 | 5 次 |
| 频道 | 5 分钟 | - |

**主动消息**

主动消息与被动消息说明：QQ 用户可以在 QQ 客户端主动设置是否接收机器人发送的主动消息，如果设置了关闭，主动消息一律发送失败。

*单聊* — 主动消息发送频率限制（HTTP接口）

| 认证类型 | 场景 | Bot 维度频控 | 单关系维度频控 | 每日上限 |
|---|---|---|---|---|
| 企业认证 | 单聊 | 10/qps | 20/qpm | 1000 条/用户 |
| 个人认证 | 单聊 | 10/qps | 20/qpm | 1000 条/用户 |
| 未认证 | 单聊 | 5/qps & 30/qpm | 20/qpm | 1000 条/用户 |

- 互动召回消息：在用户主动与机器人对话之后，机器人在未来 30 天内可下发互动召回消息给用户（消息类型与当前机器人拥有的消息类型权限一致），每个周期内可下发一条。分别为：当天、1 - 3 天、3 - 7 天、7 - 30 天，合计：4 个周期。在发消息接口中使用 is_wakeup 字段声明使用该能力。

*群聊* — 主动消息发送频率限制（HTTP接口）

| 认证类型 | 场景 | Bot 维度频控 | 单关系维度频控 | 每日上限 |
|---|---|---|---|---|
| 企业认证 | 群 | 60/qpm | 20/qpm | 1000 条/群 |
| 个人认证 | 群 | 60/qpm | 20/qpm | 1000 条/群 |
| 未认证 | 群 | 30/qpm | 20/qpm | 1000 条/群 |

*文字子频道*

- 主动消息在频道主或管理设置了情况下，按设置的数量进行限频。在未设置的情况遵循如下限制：
  - 主动推送消息，默认每天往每个子频道可推送的消息数是 20 条，超过会被限制。
  - 主动推送消息在每个频道中，每天可以往 2 个子频道推送消息。超过后会被限制。
- 不论主动消息还是被动消息，在一个子频道中，每秒**最多可发送 5 条**消息。
- 被动回复消息有效期为 5 分钟，超时会发送失败。
- 发送消息接口要求机器人接口需要连接到 WebSocket 上保持在线状态。
- 有关主动消息审核，可以通过事件订阅 Intents 中审核事件 MESSAGE_AUDIT 返回 MessageAudited 对象获取结果。

*频道私信*

- 私信场景下，每个机器人每天可以对一个用户发 **2 条**主动消息。
- 私信场景下，每个机器人每天累计可以发 **200 条**主动消息。
- 被动回复消息有效期为 5 分钟，超时会发送失败。

### 3.7 消息去重

相同 `msg_id` 可能多次推送，请结合 `msg_seq` 去重。被动回复时，相同的 `msg_id + msg_seq` 重复发送会失败，可递增 `msg_seq` 实现对同一消息的多次回复。

### 3.8 撤回消息

机器人可撤回自己发送的消息（发送超过 **2 分钟** 不可撤回）：

- 撤回单聊消息
- 撤回群聊消息
- 撤回频道消息 / 撤回频道私信

---

## 4. 单聊 C2C 发消息 POST /v2/users/{openid}/messages

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_messages.post.html

### 4.1 接口说明与频控（官方原文）

向指定用户发送私聊消息。

- 被动消息有效时间 **60 分钟**，每个消息最多回复 **4 次**
- 主动消息频控规则：
  - Bot 维度（发送方）：企业认证/个人身份证认证 **10/qps**；未认证 **5/qps** 且 **30/qpm**
  - 单关系维度（接收方）：**20/qpm**，每个好友 1 天最多接收 **1000** 条
- 互动召回消息：在用户主动与机器人对话之后，机器人在未来 30 天内可下发互动召回消息给用户（消息类型与当前机器人拥有的消息类型权限一致），每个周期内可下发一条。分别为：当天、1 - 3 天、3 - 7 天、7 - 30 天，合计：4 个周期。在发消息接口中使用 is_wakeup 字段声明使用该能力。

### 4.2 基础信息

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/users/{user_openid}/messages |
| HTTP Method | POST |
| 接口频率限制 | 100 QPS，包括主动、被动等所有消息类型 |

### 4.3 路径参数

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| user_openid | string | 是 | 用户 OpenID |

### 4.4 请求体

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| msg_type | integer | 否 | 消息类型。决定哪个内容字段生效: 0=纯文本(content) 2=Markdown(markdown) 6=输入中状态（input_notify) 7=富媒体(media) |
| content | string | 否 | 文本内容。msg_type=0 时为全文 注意: 传了 markdown 后此字段必须为空 |
| markdown | MessageMarkdown | 否 | Markdown 消息。msg_type=2 时必填 注意: 填写此字段后 content/ark 必须全为空 |
| keyboard | Keyboard | 否 | 内嵌键盘。短形式只传 id，长形式传 content.rows |
| msg_id | string | 否 | 被动回复的消息 ID。从 C2C_MESSAGE_CREATE 等事件的 d.id 获取，5 分钟内有效 |
| event_id | string | 否 | 被动回复的事件 ID。从事件最外层的id获取。与 msg_id 二选一，支持事件："INTERACTION_CREATE"、"C2C_MSG_RECEIVE"、"FRIEND_ADD" |
| msg_seq | integer | 否 | 回复消息的序号，与 msg_id 联合使用，避免相同消息 id 回复重复发送，不填默认是 1。相同的 msg_id + msg_seq 重复发送会失败。 |
| media | MediaInfo | 否 | 富媒体消息。msg_type=7 时填写，file_info 来自 /v2/users/{user_openid}/files |
| message_reference | MessageReference | 否 | 引用回复。填写后以引用形式展示，关联上下文 |
| is_wakeup | boolean | 否 | 指明发送消息为互动召回消息，与 msg_id，event_id 互斥使用 |
| input_notify | InputNotify | 否 | 输入中状态，msg_type=6时使用 |

**MessageMarkdown**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| template_id | integer | 否 | 【已废弃】平台 Markdown 模板 ID。使用模板时填写，非模板不传 |
| content | string | 否 | Markdown 内容。支持的格式参考文档：Markdown |
| custom_template_id | string | 否 | 【已废弃】自定义模板 ID，与 template_id 二选一 |
| force_verify_image_resource | boolean | 否 | 是否校验图片转存结果，当为true时，如果出现图片转存失败，则会返回错误，消息不会发送。 默认为false |

**Keyboard**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| id | string | 否 | 内嵌键盘模板 ID。使用平台预设模板时填写此字段 |
| content | KeyboardContent | 否 | 自定义键盘布局。与 id 互斥，用于自定义按钮 |

**KeyboardContent**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| rows | [][Row] | 否 | 按钮行列表 |

**Row**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| buttons | [][Button] | 否 | 行内按钮，从左到右排列 |

**Button**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| id | string | 否 | 按钮 ID。同一键盘内唯一 |
| render_data | RenderData | 否 | 按钮渲染 |
| action | Action | 否 | 按钮点击行为 |
| group_id | string | 否 | 分组ID, 同一分组内有一个按钮操作后, 其它按钮则变灰不可点击 注意:只有当action.type = 1 时才有效 |

**RenderData**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| label | string | 否 | 按钮文字，最多 10 字符 |
| visited_label | string | 否 | 点击后文字，不传则保持不变 |
| style | integer | 否 | 0：灰色线框，1：蓝色线框 3: 白色背景+红色字体, 4:蓝色背景+白色字体 |

**Action**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| type | integer | 否 | 0：跳转按钮：http 或 小程序 1：回调按钮：回调后台接口, data 传给后台， 2：指令按钮：自动在输入框插入 @bot data |
| permission | Permission | 否 | 操作权限 |
| data | string | 否 | 回调数据。type=1/2 时必填 |
| click_limit | integer | 否 | 【已废弃】可点击次数限制。0=无限 |
| unsupport_tips | string | 否 | 版本过低时提示文案 |
| enter | boolean | 否 | 指令按钮可用，点击按钮后直接自动发送 data，仅单聊可用，默认 false。支持版本 8983 |
| reply | boolean | 否 | 指令按钮可用，指令是否带引用回复本消息，默认 false。支持版本 8983 |
| anchor | integer | 否 | 本字段仅在指令按钮下有效，设置后后会忽略 action.enter 配置。 设置为 1 时 ，点击按钮自动唤起启手Q选图器，其他值暂无效果。 （仅支持手机端版本 8983+ 的单聊场景，桌面端不支持） |
| modal | Modal | 否 | 用户点击二次确认操作 |

**Permission**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| type | integer | 否 | 0=指定用户, 1=管理员, 2=所有人 |
| specify_user_ids | []string | 否 | 有权限的用户 id 的列表 |
| specify_role_ids | []string | 否 | 有权限的身份组 id 的列表（仅频道可用） |

**Modal**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| content | string | 否 | 二次确认的提示文本,如果不为空则会进行二次确认. 注意:最多40个字符, 不能有URL |
| confirm_text | string | 否 | 二次确认提示确认按钮中展示的文字,可以为空, 默认为"确认" 注意:最多4个字符 |
| cancel_text | string | 否 | 二次确认提示取消按钮中的文字,可以为空,默认为"取消" 注意:最多4个字符 |

**MediaInfo**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| file_info | string | 否 | 文件数据。来自文件上传接口返回值 |

**MessageReference**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| message_id | string | 否 | 被引用消息 ID，例如REFIDX_xxxxxx <br>- 非机器人发的消息，从消息事件的`MessageScene`的`ext`数组，`msg_idx`字段中获取 <br>- 机器人自己发的消息，从发消息请求响应`ext_info.ref_idx`获取 |

**InputNotify**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| input_type | integer | 否 | 填1 |
| input_second | integer | 否 | 状态持续时间，最长60s |

> 关于「content 为 JSON 字符串时的字段（text/attachments/ark/markdown/embed/media/image/emoji）」：本单聊接口的官方请求体**不含**此类复合 content 字段；官方在该接口面向上提供的是平铺字段 `content`（纯文本）+ `markdown` + `media` + `keyboard`。任务清单中所述「content 内含 text/attachments/ark/markdown/embed/media/image/emoji 的 JSON 字符串」结构，在本次抓取的本接口官方文档中**未出现** → 该结构标注为「官方文档未提供」（相关子类型定义另见第 9 章 ark / embed / message_type 接收结构）。

### 4.5 请求示例

**文本消息 (msg_type=0)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/messages
{
 "content": "你好，欢迎使用机器人助手！",
 "msg_type": 0,
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "msg_seq": 1
}
```

**Markdown 消息 (msg_type=2)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/messages
{
 "msg_type": 2,
 "markdown": {
 "content": "# 今日推荐\n\n**精选文章**\n> 知识就是力量，学习永无止境\n\n[点击查看详情](https://example.com)"
 },
 "keyboard": {
 "id": "1070001"
 },
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "msg_seq": 1
}
```

**输入状态通知 (msg_type=6)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/messages
{
 "msg_type": 6,
 "input_notify": {
 "input_type": 1,
 "input_second": 60
 },
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "msg_seq": 1
}
```

**富媒体消息 (msg_type=7)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/messages
{
 "msg_type": 7,
 "media": {
 "file_info": "AE86C5D3F0E14B238C656C0F6DD1D0479C"
 },
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "msg_seq": 1
}
```

### 4.6 响应体

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 消息 ID，可用于后续撤回 |
| timestamp | string | 发送时间，RFC3339 东八区 |
| ext_info | MessageExtInfo | 扩展信息 |

**MessageExtInfo**

| 名称 | 类型 | 描述 |
|---|---|---|
| ref_idx | string | 引用消息索引。对应消息时间ext里的msg_idx与ref_msg_idx |

### 4.7 响应示例

**消息发送成功**

```
{
  "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "timestamp": "2026-07-21T10:30:00+08:00"
}
```

**消息发送成功（含扩展信息）**

```
{
  "id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "timestamp": "2026-07-21T10:30:00+08:00",
  "ext_info": {
    "ref_idx": "REFIDX_xxxxxxxxxxxxxxxxxxxx=="
  }
}
```

### 4.8 错误码

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 22006 | 消息类型与内容不匹配 | 请检查msg_type与content是否对应 |
| 50059 | 输入类型错误 | 请检查输入类型 |
| 304004 | 无权限使用该ARK模板 | 请先申请ARK模板权限 |
| 304061 | 消息内容无效 | 请检查消息格式是否符合要求 |
| 304062 | 订阅按钮数量达到上限 | 请减少按钮数量 |
| 304064 | 订阅消息未授权 | 请先引导用户授权订阅消息 |
| 304080 | 文件信息无效 | 请检查文件信息格式是否正确 |
| 304103 | 消息ID已过期，不能回复 | 请在收到消息后尽快回复 |
| 340067 | 获取机器人信息失败 | 请检查机器人状态 |
| 40034004 | 富媒体信息转存失败 | 请重试 |
| 40034005 | 回复消息msg_id已过期 | 请在收到消息后尽快回复 |
| 40034006 | 消息内容违规 | 请修改消息内容后重试 |
| 40034008 | markdown参数有空值 | 请确保所有Markdown参数都有值 |
| 40034009 | markdown参数有换行符 | 请移除Markdown参数中的换行符 |
| 40034010 | 模版参数中不能含有markdown语法 | 请使用纯文本参数，不要包含Markdown语法 |
| 40034011 | 无效的markdown内容 | 请检查Markdown语法是否正确 |
| 40034024 | 请求参数msg_id无效或越权 | 请检查msg_id是否正确 |
| 40034025 | 请求参数event_id无效 | 请检查event_id是否正确 |
| 40034026 | 请求参数event_id已过期 | 请在收到事件后尽快回复 |
| 40034027 | 该事件不支持回复消息 | 请确认事件类型是否支持回复 |
| 40034029 | 内联键盘行/列超限 | 请减少键盘按钮数量 |
| 40034100 | 主动消息发送超过频控限制 | 请降低发送频率或等待配额恢复 |
| 40034105 | 主动消息发送失败，无权限 | 请检查机器人权限设置 |
| 40034106 | 消息不支持该指令类型 | 请检查消息指令类型 |
| 40034108 | 指令参数长度超限 | 请缩短指令参数 |
| 40034109 | 指令参数解析失败 | 请检查指令参数格式 |
| 40034122 | 召回消息已达区间上限 | 召回消息已达上限，无法继续召回 |
| 40034123 | 不支持召回消息 | 该消息不支持召回操作 |
| 40034124 | markdown消息参数错误 | 请检查Markdown参数格式 |
| 40034127 | 无markdown模板权限 | 请先申请Markdown模板权限 |
| 40034128 | 被动回复时间或次数超限 | 请在收到事件后尽快回复 |
| 40054004 | 无好友关系 | 请先添加好友后再发送私信 |
| 40054005 | 消息被去重 | 请确保每次请求使用不同的msgseq值 |
| 40054006 | 验证好友关系失败 | 请重试 |
| 40054007 | 消息长度超限 | 请缩短消息内容 |
| 40054013 | 用户拒收消息 | 用户已拒收消息，无法发送 |
| 40054016 | 机器人已下线 | 请检查机器人状态 |
| 40054018 | 消息过长或异常 | 请缩短消息内容 |
| 50055002 | 消息发送异常，请稍后重试 | 请稍后重试 |

---

## 5. 群聊 GROUP_AT_MESSAGE_CREATE 回复 POST /v2/groups/{group_openid}/messages

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_messages.post.html

### 5.1 接口说明与频控（官方原文）

向指定群发送消息。支持文本/Markdown/富媒体等类型，可附带内嵌键盘。 注意: 群消息不支持流式参数。

- 被动消息有效时间 **5 分钟**，每个消息最多回复 **5 次**
- 主动消息频控规则
  - Bot 维度（发送方）：企业认证/个人身份证认证 **60/qpm**；未认证 **30/qpm**
  - 单关系维度（接收方）：**20/qpm**，每个群 1 天最多接收 **1000** 条

### 5.2 基础信息

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/groups/{group_openid}/messages |
| HTTP Method | POST |
| 接口频率限制 | 100 QPS |

### 5.3 路径参数

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| group_openid | string | 是 | 群 OpenID |

### 5.4 请求体

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| msg_type | integer | 否 | 消息类型。决定哪个内容字段生效: 0=纯文本(content) 2=Markdown(markdown) 7=富媒体(media) |
| content | string | 否 | 文本内容。msg_type=0 时为全文 注意: 传了 markdown 后此字段必须为空 |
| markdown | MessageMarkdown | 否 | Markdown 消息。msg_type=2 时必填 注意: 填写此字段后 content/ark 必须全为空 |
| keyboard | Keyboard | 否 | 内嵌键盘。短形式只传 id，长形式传 content.rows |
| msg_id | string | 否 | 被动回复的消息 ID。从 GROUP_AT_MESSAGE_CREATE 等事件的 d.id 获取，5 分钟内有效 |
| event_id | string | 否 | 被动回复的事件 ID。从事件最外层的id获取。与 msg_id 二选一，支持事件："INTERACTION_CREATE"、"GROUP_ADD_ROBOT"、"GROUP_MSG_RECEIVE" |
| msg_seq | integer | 否 | 回复消息的序号，与 msg_id 联合使用，避免相同消息 id 回复重复发送，不填默认是 1。相同的 msg_id + msg_seq 重复发送会失败。 |
| media | MediaInfo | 否 | 富媒体消息。msg_type=7 时填写，file_info 来自 /v2/groups/{group_openid}/files |
| message_reference | MessageReference | 否 | 引用回复。填写后以引用形式展示，关联上下文 |

**MessageMarkdown**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| template_id | integer | 否 | 【已废弃】平台 Markdown 模板 ID。使用模板时填写，非模板不传 |
| content | string | 否 | Markdown 内容。支持的格式参考文档：Markdown |
| custom_template_id | string | 否 | 【已废弃】自定义模板 ID，与 template_id 二选一 |
| force_verify_image_resource | boolean | 否 | 是否校验图片转存结果，当为true时，如果出现图片转存失败，则会返回错误，消息不会发送。 默认为false |

**Keyboard**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| id | string | 否 | 内嵌键盘模板 ID。使用平台预设模板时填写此字段 |
| content | KeyboardContent | 否 | 自定义键盘布局。与 id 互斥，用于自定义按钮 |

**KeyboardContent**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| rows | [][Row] | 否 | 按钮行列表 |

**Row**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| buttons | [][Button] | 否 | 行内按钮，从左到右排列 |

**Button**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| id | string | 否 | 按钮 ID。同一键盘内唯一 |
| render_data | RenderData | 否 | 按钮渲染 |
| action | Action | 否 | 按钮点击行为 |
| group_id | string | 否 | 分组ID, 同一分组内有一个按钮操作后, 其它按钮则变灰不可点击 注意:只有当action.type = 1 时才有效 |

**RenderData**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| label | string | 否 | 按钮文字，最多 10 字符 |
| visited_label | string | 否 | 点击后文字，不传则保持不变 |
| style | integer | 否 | 0：灰色线框，1：蓝色线框 3: 白色背景+红色字体, 4:蓝色背景+白色字体 |

**Action**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| type | integer | 否 | 0：跳转按钮：http 或 小程序 1：回调按钮：回调后台接口, data 传给后台， 2：指令按钮：自动在输入框插入 @bot data |
| permission | Permission | 否 | 操作权限 |
| data | string | 否 | 回调数据。type=1/2 时必填 |
| click_limit | integer | 否 | 【已废弃】可点击次数限制。0=无限 |
| unsupport_tips | string | 否 | 版本过低时提示文案 |
| enter | boolean | 否 | 指令按钮可用，点击按钮后直接自动发送 data，仅单聊可用，默认 false。支持版本 8983 |
| reply | boolean | 否 | 指令按钮可用，指令是否带引用回复本消息，默认 false。支持版本 8983 |
| anchor | integer | 否 | 本字段仅在指令按钮下有效，设置后后会忽略 action.enter 配置。 设置为 1 时 ，点击按钮自动唤起启手Q选图器，其他值暂无效果。 （仅支持手机端版本 8983+ 的单聊场景，桌面端不支持） |
| modal | Modal | 否 | 用户点击二次确认操作 |

**Permission**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| type | integer | 否 | 0=指定用户, 1=管理员, 2=所有人 |
| specify_user_ids | []string | 否 | 有权限的用户 id 的列表 |
| specify_role_ids | []string | 否 | 有权限的身份组 id 的列表（仅频道可用） |

**Modal**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| content | string | 否 | 二次确认的提示文本,如果不为空则会进行二次确认. 注意:最多40个字符, 不能有URL |
| confirm_text | string | 否 | 二次确认提示确认按钮中展示的文字,可以为空, 默认为"确认" 注意:最多4个字符 |
| cancel_text | string | 否 | 二次确认提示取消按钮中的文字,可以为空,默认为"取消" 注意:最多4个字符 |

**MediaInfo**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| file_info | string | 否 | 文件数据。来自文件上传接口返回值 |

**MessageReference**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| message_id | string | 否 | 被引用消息 ID，例如REFIDX_xxxxxx <br>- 非机器人发的消息，从消息事件的MessageScene的ext数组，msg_idx字段中获取 <br>- 机器人自己发的消息，从发消息请求响应ext_info.ref_idx获取 |

### 5.5 请求示例

**文本消息 (msg_type=0)**

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/messages
{
  "msg_type": 0,
  "content": "欢迎使用本群助手，有什么可以帮你的吗？",
  "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "msg_seq": 1
}
```

**Markdown + 键盘消息 (msg_type=2)**

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/messages
{
  "msg_type": 2,
  "markdown": {
    "content": "## 每日签到\n\n今日签到成功！获得 **50** 积分\n连续签到 **7** 天"
  },
  "keyboard": {
    "content": {
      "rows": [
        {
          "buttons": [
            {
              "id": "btn_signin",
              "render_data": {
                "label": "签到",
                "style": 1
              },
              "action": {
                "type": 2,
                "permission": {
                  "type": 2
                },
                "data": "/签到",
                "enter": true
              }
            }
          ]
        }
      ]
    }
  },
  "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "msg_seq": 1
}
```

**富媒体消息 (msg_type=7)**

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/messages
{
  "msg_type": 7,
  "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "msg_seq": 2,
  "media": {
    "file_info": "AE86C5D3F0E14B238C656C0F6DD1D0479C"
  },
  "message_reference": {
    "message_id": "ROBOT1.0_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
  }
}
```

### 5.6 响应体

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 消息 ID，可用于后续撤回 |
| timestamp | string | 发送时间，RFC3339 东八区 |
| ext_info | MessageExtInfo | 扩展信息 |

**MessageExtInfo**

| 名称 | 类型 | 描述 |
|---|---|---|
| ref_idx | string | 引用消息索引。对应消息时间ext里的msg_idx与ref_msg_idx |

### 5.7 响应示例

**发送成功**

```
{
  "id": "ROBOT1.0_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
  "timestamp": "2026-07-21T10:00:00+08:00",
  "ext_info": {
    "ref_idx": "REFIDX_xxxxxxxxxxxxxxx=="
  }
}
```

### 5.8 错误码

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 22006 | 消息类型与内容不匹配 | 请检查msg_type与content是否对应 |
| 304004 | 无权限使用该ARK模板 | 请先申请ARK模板权限 |
| 304036 | 无Markdown模板权限 | 请先申请Markdown模板权限 |
| 304061 | 消息内容无效 | 请检查消息格式是否符合要求 |
| 304064 | 订阅消息未授权 | 请先引导用户授权订阅消息 |
| 304080 | 文件信息无效 | 请检查文件信息格式是否正确 |
| 304103 | 消息ID已过期，不能回复 | 请在收到消息后尽快回复 |
| 305007 | 键盘样式参数错误 | 请检查keyboard参数 |
| 340069 | 消息类型无效 | 请检查msg_type取值 |
| 40034004 | 富媒体信息转存失败 | 请重试 |
| 40034005 | 回复消息msg_id已过期 | 请在收到消息后尽快回复 |
| 40034006 | 消息内容违规 | 请修改消息内容后重试 |
| 40034008 | markdown参数有空值 | 请确保所有Markdown参数都有值 |
| 40034009 | markdown参数有换行符 | 请移除Markdown参数中的换行符 |
| 40034010 | 模版参数中不能含有markdown语法 | 请使用纯文本参数，不要包含Markdown语法 |
| 40034011 | 无效的markdown内容 | 请检查Markdown语法是否正确 |
| 40034024 | 请求参数msg_id无效或越权 | 请检查msg_id是否正确 |
| 40034025 | 请求参数event_id无效 | 请检查event_id是否正确 |
| 40034026 | 请求参数event_id已过期 | 请在收到事件后尽快回复 |
| 40034027 | 该事件不支持回复消息 | 请确认事件类型是否支持回复 |
| 40034029 | 内联键盘行/列超限 | 请减少键盘按钮数量 |
| 40034100 | 主动消息发送超过频控限制 | 请降低发送频率或等待配额恢复 |
| 40034101 | 机器人非群成员 | 请先将机器人加入群聊 |
| 40034105 | 主动消息发送失败，无权限 | 请检查机器人权限设置 |
| 40034106 | 消息不支持该指令类型 | 请检查消息指令类型 |
| 40034108 | 指令参数长度超限 | 请缩短指令参数 |
| 40034109 | 指令参数解析失败 | 请检查指令参数格式 |
| 40034124 | markdown消息参数错误 | 请检查Markdown参数格式 |
| 40034127 | 无markdown模板权限 | 请先申请Markdown模板权限 |
| 40034128 | 被动回复时间或次数超限 | 请在收到事件后尽快回复 |
| 40054002 | 机器人被禁言 | 请等待解禁后再发送 |
| 40054003 | 机器人不是群成员 | 请先将机器人加入群聊 |
| 40054005 | 消息被去重 | 请确保每次请求使用不同的msgseq值 |
| 40054007 | 消息长度超限 | 请缩短消息内容 |
| 40054010 | 不允许发送URL | 请移除消息中的URL |
| 40054016 | 机器人已下线 | 请检查机器人状态 |
| 50055001 | 消息发送异常，请稍后重试 | 请稍后重试 |
| 50055006 | ARK消息发送异常，请稍后重试 | 请稍后重试 |

> 关于 `GROUP_AT_MESSAGE_CREATE` 事件本体（事件字段结构）：不在本组页面清单内 → 事件体字段标注为「官方文档未提供」；本页只覆盖「回复该事件」所需的 `msg_id`（从事件 `d.id` 获取）与 `event_id`（从事件最外层 `id` 获取）用法。

---

## 6. 流式消息 POST /v2/users/{openid}/stream_messages

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_stream_messages.post.html

### 6.1 接口说明（官方原文）

流式分批发送单聊消息。每个分片使用相同 stream_msg_id， index 从0递增。支持 markdown 内容格式。

### 6.2 基础信息

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/users/{user_openid}/stream_messages |
| HTTP Method | POST |
| 接口频率限制 | 50 QPS |

### 6.3 路径参数

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| user_openid | string | 是 | （官方描述为空） |

### 6.4 请求体

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| input_mode | string | 否 | 输入模式。 append（默认）：ContentRaw 拼接到 Pending。 replace：ContentRaw 为当前全量正文，须以上游已下发前缀 SentContent 开头；合并后 Pending 仅存未下发后缀。 |
| input_state | integer | 否 | 输入状态。1=生成中，10=生成结束 |
| index | integer | 否 | 分片序号，从0递增 |
| content_type | string | 否 | 内容格式类型 text: 文本消息 markdown：MarkDown消息 |
| content_raw | string | 否 | Markdown 格式的文本内容 |
| event_id | string | 否 | 被动回复事件ID（与 msg_id 二选一） |
| msg_id | string | 否 | 被动回复消息ID（与 event_id 二选一） |
| stream_msg_id | string | 否 | 流式消息ID。第一条由服务端生成并返回，后续分片需携带上一分片返回的 id |
| msg_seq | integer | 否 | 消息序号，用于去重 |
| is_wakeup | boolean | 否 | 是否为召回消息。true 时不校验 msg_id/event_id 有效期 |

### 6.5 请求示例

**首片消息 (input_state=1, index=0)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/stream_messages
{
 "input_mode": "replace",
 "input_state": 1,
 "index": 0,
 "content_type": "markdown",
 "content_raw": "正在生成回答，请稍候",
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "msg_seq": 1
}
```

**续片消息 (input_state=1, index=1)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/stream_messages
{
 "input_mode": "replace",
 "input_state": 1,
 "index": 1,
 "content_type": "markdown",
 "content_raw": "正在生成回答，请稍候。目前已完成大部分内容",
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "stream_msg_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
 "msg_seq": 1
}
```

**结束片消息 (input_state=10)**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/stream_messages
{
 "input_mode": "replace",
 "input_state": 10,
 "index": 2,
 "content_type": "markdown",
 "content_raw": "正在生成回答，请稍候。目前已完成全部内容，以下是最终结果。",
 "msg_id": "ROBOT1.0_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 "stream_msg_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
 "msg_seq": 1
}
```

### 6.6 响应体

| 名称 | 类型 | 描述 |
|---|---|---|
| id | string | 消息ID。首条返回 stream_msg_id，用于后续分片 |
| timestamp | string | 消息发送时间，RFC3339 格式 |
| ext_info | MessageExtInfo | 扩展信息。ref_idx: 引用消息索引 扩展信息 |
| remain_msg_len | integer | 流式消息剩余长度（字符数） |

**MessageExtInfo**

| 名称 | 类型 | 描述 |
|---|---|---|
| ref_idx | string | 引用消息索引。对应消息时间ext里的msg_idx与ref_msg_idx |

### 6.7 响应示例

**首片响应（返回 stream_msg_id）**

```
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "timestamp": "2026-07-21T10:00:00+08:00",
  "ext_info": {
    "ref_idx": "REFIDX_xxxxxxxxxxxxxxx=="
  }
}
```

**续片/结束片响应**

```
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "timestamp": "2026-07-21T10:00:01+08:00",
  "ext_info": {
    "ref_idx": "REFIDX_xxxxxxxxxxxxxxx=="
  }
}
```

### 6.8 错误码

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 40007 | 已下发内容前缀不可修改 | 请保持已下发内容前缀一致 |
| 50001 | 服务内部错误 | 请稍后重试 |
| 50002 | 频率限制 | 请降低调用频率 |

### 6.9 发送节奏限制

官方文档在本页给出的节奏相关事实：
- 接口频率限制：**50 QPS**
- 错误码 `50002 频率限制 → 请降低调用频率`
- 分片规则：「每个分片使用相同 stream_msg_id，index 从0递增」
- `input_mode` 语义：`replace` 模式下「ContentRaw 为当前全量正文，须以上游已下发前缀 SentContent 开头」；违反时报 `40007 已下发内容前缀不可修改`
- 响应含 `remain_msg_len`（流式消息剩余长度，字符数）

> 关于「每条消息之间的最小间隔毫秒数 / 每秒最多下发多少片 / 切片最大字符数」等具体节奏数值：官方文档本页**未给出** → 「官方文档未提供」。

---

## 7. 消息撤回 DELETE

### 7.1 撤回单聊消息

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_messages_message_id.delete.html

撤回机器人发送给当前用户的消息。发送超过 2 分钟的消息不可撤回。 成功返回 HTTP 200，无响应体。

- 发送超出 **2 分钟** 的消息不可撤回

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/users/{user_openid}/messages/{message_id} |
| HTTP Method | DELETE |
| 接口频率限制 | 10 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| user_openid | string | 是 | 用户 OpenID |
| message_id | string | 是 | 消息 ID |

**请求示例**

```
DELETE /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/messages/0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
```

**响应**：无

**响应示例**

```
{}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 306009 | 用户openid无效 | 请检查user_openid是否正确 |
| 40061001 | 请求参数无效 | 请检查请求参数格式 |
| 40061002 | 请求参数msgid无效 | 请检查msgid格式是否正确 |
| 40064004 | 已超出消息撤回时限 | 消息发送超过2分钟后不可撤回 |

### 7.2 撤回群聊消息

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_messages_message_id.delete.html

撤回群消息。发送超过 2 分钟的消息不可撤回。 成功返回 HTTP 200，无响应体。

- 发送超出 **2 分钟** 的消息不可撤回。
- 机器人如果是群管理员，可以撤回机器人自己的消息以及普通群成员的消息，群成员的消息ID从群消息事件`GROUP_AT_MESSAGE_CREATE`或`GROUP_MESSAGE_CREATE`里，`d.id`这个字段中获取。
- 机器人如果是普通成员，只能撤回机器人自己发送的消息，消息ID可以从消息发送接口响应里获取。

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/groups/{group_openid}/messages/{message_id} |
| HTTP Method | DELETE |
| 接口频率限制 | 10 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| group_openid | string | 是 | 群 OpenID |
| message_id | string | 是 | 消息 ID |

**请求示例**

```
DELETE /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/messages/0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
```

**响应**：无

**响应示例**

```
{}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 40061001 | 请求参数无效 | 请检查请求参数格式 |
| 40062003 | 无操作权限 | 请检查机器人是否有操作权限，机器人是否为群管理员或者发消息的用户是否为普通用户 |
| 40064004 | 已超出消息撤回时限 | 消息发送超过2分钟后不可撤回 |
| 50065001 | 消息撤回失败，请稍后重试 | 请稍后重试 |

### 7.3 撤回限制条件汇总

| 场景 | 时限 | 最小频率限制 | 权限条件 |
|---|---|---|---|
| 单聊 | 发送超过 2 分钟不可撤回 | 10 QPS | 撤回机器人发送给当前用户的消息 |
| 群聊 | 发送超过 2 分钟不可撤回 | 10 QPS | 群管理员：可撤回机器人自己的消息 + 普通群成员的消息；普通成员：只能撤回机器人自己发送的消息 |

---

## 8. 富媒体 / 文件上传（三段式 + 预上传）

### 8.0 富媒体消息概述

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/rich-media.html

富媒体消息支持发送图片、视频、语音、文件等类型，需先将文件上传获取 `file_info`，再通过发消息接口（`msg_type=7`）携带 `media.file_info` 发送。

**支持的消息类型**

| 图片 | 语音 | 视频 | 文件 |
|---|---|---|---|
| 支持 jpg/png/gif/webp/bmp 格式，发送后直接展示图片 | 支持 silk/mp3/wav/ogg 格式，发送后展示语音条 | 支持 mp4 格式，发送后展示视频封面可播放 | 支持任意格式，发送后展示文件卡片可下载 |

（官方配图：图片 https://aka.doubaocdn.com/s/6ru6m7FjKX ；语音 https://aka.doubaocdn.com/s/A6Sw9g8vKd ；视频 https://aka.doubaocdn.com/s/OuDZjgTV0i ；文件 https://aka.doubaocdn.com/s/3ys4PlEAwH ）

**文件类型与限制**

| file_type | 类型 | 格式 | 软限制 | 硬限制 |
|---|---|---|---|---|
| 1 | 图片 | png / jpg | 20 MB | 200 MB |
| 2 | 视频 | mp4 | 30 MB | 200 MB |
| 3 | 语音 | silk | 20 MB | 200 MB |
| 4 | 文件 | - | 200 MB | 200 MB |

超过软限制会降级为文件类型上传，超过硬限制会报错。

**上传方式**

整文件上传使用单聊上传 / 群聊上传接口，直接传入文件 URL；文件较大时使用分片上传，参考单聊预上传开始分片流程。

**分片上传（推荐）** — 适用于大文件或本地文件。分四步完成：

```
1. 预上传
 调用 upload_prepare，传入文件信息和校验值
 → 获取 upload_id + block_size + 各分片预签名 URL

2. 分片 PUT
 按 block_size 将文件分片，逐片 HTTP PUT 到对应的预签名 URL

3. 确认分片
 每片 PUT 成功后调用 upload_part_finish，通知服务端该分片完成

4. 完成合并
 全部分片完成后，携带 upload_id 调用上传接口
 → 返回 file_info
```

流程图（原文）：

```
 upload_prepare 分片 PUT + part_finish 上传接口（合并）
┌──────────────┐ ┌─────────────────────────┐ ┌──────────────────┐
│ 获取 │ │ for each chunk: │ │ POST .../files │
│ upload_id │───▶│ PUT → presigned_url │───▶│ { upload_id } │
│ block_size │ │ POST → part_finish │ │ → file_info │
│ presigned │ └─────────────────────────┘ └──────────────────┘
│ URLs │
└──────────────┘
```

**URL 上传** — 适用于文件已在公网可访问的场景，直接传入文件 URL，平台自动下载转存。

```
POST /v2/users/{user_openid}/files
{
 "file_type": 1,
 "url": "https://example.com/image.png"
}
```

返回 `file_info`，即可用于发消息。

**使用 file_info 发送**

获取 `file_info` 后，在发消息接口中设置 `msg_type=7`，将 `file_info` 填入 `media` 字段：

```
POST /v2/users/{user_openid}/messages
{
  "msg_type": 7,
  "media": {
    "file_info": "{上一步返回的 file_info}"
  }
}
```

`srv_send_msg=true` 可在上传的同时直接发送，跳过单独调用发消息接口这一步，但会占用主动消息频次。

**单聊与群聊隔离** — 单聊和群聊的文件上传接口相互独立，上传的文件不能跨场景使用：

| 场景 | 上传接口 |
|---|---|
| 单聊 | `/v2/users/{user_openid}/files` |
| 群聊 | `/v2/groups/{group_openid}/files` |

对应的预上传和分片接口也需使用同场景的端点。

**注意事项**

- `file_info` 有有效期（`ttl`），过期后需重新上传。
- `md5_10m`（文件前 10002432 字节，约 9.54 MB 的 MD5）可用于秒传判断，避免重复上传。
- 分片大小默认 5MB，并发数、重试策略由服务端在 `upload_config` 中下发。
- 上传接口超时建议设为 ≥ 5 秒。

---

### 8.1 单聊富媒体上传 POST /v2/users/{user_openid}/files

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_openid_files.post.html

上传图片/视频/语音到单聊，返回 file_info 用于发送消息接口的 media 字段。 用单聊接口上传的文件仅能发送到单聊。 文件类型与大小限制:

- 1=图片(png/jpg): 软限制 20MB, 硬限制 200MB
- 2=视频(mp4): 软限制 30MB, 硬限制 200MB
- 3=语音(silk): 软限制 20MB, 硬限制 200MB
- 4=文件: 软限制 200MB, 硬限制 200MB 超过软限制会降级为文件类型上传，超过硬限制会报错。

支持两种上传方式：

1. URL 上传：传入 url，平台下载转存
2. 分片上传合并：先通过 upload_prepare + upload_part_finish 完成分片上传，再携带 upload_id 调用本接口完成合并

推荐使用分片上传，流程如下：

1. 调用 upload_prepare 获取 upload_id、block_size 和各分片预签名 URL
2. 按 block_size 将文件分片，逐片 HTTP PUT 到对应的预签名 URL
3. 每片 PUT 成功后调用 upload_part_finish 通知服务端该分片完成
4. 全部分片完成后，携带 upload_id 调用本接口完成合并，返回 file_info

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/users/{user_openid}/files |
| HTTP Method | POST |
| 接口频率限制 | 50 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| user_openid | string | 是 | 用户 OpenID |

**请求体**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| file_type | integer | 否 | 媒体类型。1=图片, 2=视频, 3=语音, 4=文件 图片支持 png/jpg，视频支持 mp4，语音支持 silk |
| url | string | 否 | 媒体资源的 URL，需以 http 开头，平台会下载并转存 分片上传合并时可为空 |
| srv_send_msg | boolean | 否 | true=直接发送消息并占用主动消息频次，返回中包含消息 ID false=仅返回 file_info，用于后续发送消息接口的 media 字段 |
| file_name | string | 否 | 文件名（可选） |
| upload_id | string | 否 | 分片上传任务 ID。来自 UploadPrepare 响应的 upload_id， 传入后走分片上传合并路径，url 可为空 |

**请求示例**

URL 上传图片：

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/files
{
 "file_type": 1,
 "url": "https://example.com/image.png",
 "srv_send_msg": false
}
```

分片上传合并：

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/files
{
 "file_type": 2,
 "srv_send_msg": false,
 "file_name": "video.mp4",
 "upload_id": "upload_a1b2c3d4e5f6"
}
```

**响应体**

| 名称 | 类型 | 描述 |
|---|---|---|
| file_uuid | string | 文件唯一 ID |
| file_info | string | 文件信息，用于发送消息接口的 media.file_info 字段。 内部为序列化的二进制数据，开发者无需解析，直接透传即可 |
| ttl | integer | file_info 有效期（秒）。到期后需重新上传。 0 表示可长期使用 |
| id | string | 发送消息的唯一 ID。仅 srv_send_msg=true 时返回 |
| raw_url | string | 文件下载链接（COS 预签名 GET URL），有效期与 ttl 一致 仅分片上传合并（upload_id 路径）且 file_type 为图片/视频/语音时返回； URL 直传和文件类型(file_type=4)不返回此字段 |

**响应示例**

```
{
  "file_uuid": "uuid_a1b2c3d4e5f6",
  "file_info": "AE86C5D3F0E14B238C656C0F6DD1D0479C",
  "ttl": 300
}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 大文件分片上传中 BDH 通道异常，请重试 |
| 40093002 | 超过今天发送文件容量上限 | 请明天再试或减少文件大小 |

---

### 8.2 群聊富媒体上传 POST /v2/groups/{group_openid}/files

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_openid_files.post.html

上传图片/视频/语音到群聊，返回 file_info 用于发送消息接口的 media 字段。 srv_send_msg=true 时直接发送消息并占用主动消息频次；false 时仅返回 file_info。 用群接口上传的文件仅能发送到群聊。 文件类型与大小限制:

- 1=图片(png/jpg): 软限制 20MB, 硬限制 200MB
- 2=视频(mp4): 软限制 30MB, 硬限制 200MB
- 3=语音(silk): 软限制 20MB, 硬限制 200MB
- 4=文件: 软限制 200MB, 硬限制 200MB 超过软限制会降级为文件类型上传，超过硬限制会报错。

支持两种上传方式（URL 上传 / 分片上传合并），推荐使用分片上传，流程同单聊。

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/groups/{group_openid}/files |
| HTTP Method | POST |
| 接口频率限制 | 50 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| group_openid | string | 是 | 群 OpenID |

**请求体**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| file_type | integer | 否 | 媒体类型。1=图片, 2=视频, 3=语音, 4=文件 图片支持 png/jpg，视频支持 mp4，语音支持 silk |
| url | string | 否 | 媒体资源的 URL，需以 http 开头，平台会下载并转存 分片上传合并时可为空 |
| srv_send_msg | boolean | 否 | true=直接发送消息并占用主动消息频次，返回中包含消息 ID false=仅返回 file_info，用于后续发送消息接口的 media 字段 |
| file_name | string | 否 | 文件名（可选） |
| upload_id | string | 否 | 分片上传任务 ID。来自 UploadPrepare 响应的 upload_id， 传入后走分片上传合并路径，url 可为空 |

**请求示例**

URL 上传图片：

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/files
{
 "file_type": 1,
 "url": "https://example.com/image.png",
 "srv_send_msg": false
}
```

分片上传合并：

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/files
{
 "file_type": 2,
 "srv_send_msg": false,
 "file_name": "video.mp4",
 "upload_id": "upload_a1b2c3d4e5f6"
}
```

**响应体**

| 名称 | 类型 | 描述 |
|---|---|---|
| file_uuid | string | 文件唯一 ID |
| file_info | string | 文件信息，用于发送消息接口的 media.file_info 字段。 内部为序列化的二进制数据，开发者无需解析，直接透传即可 |
| ttl | integer | file_info 有效期（秒）。到期后需重新上传。 0 表示可长期使用 |
| id | string | 发送消息的唯一 ID。仅 srv_send_msg=true 时返回 |
| raw_url | string | 文件下载链接（COS 预签名 GET URL），有效期与 ttl 一致 仅分片上传合并（upload_id 路径）且 file_type 为图片/视频/语音时返回； URL 直传和文件类型(file_type=4)不返回此字段 |

**响应示例**

```
{
  "file_uuid": "uuid_a1b2c3d4e5f6",
  "file_info": "AE86C5D3F0E14B238C656C0F6DD1D0479C",
  "ttl": 300
}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 大文件分片上传中 BDH 通道异常，请重试 |
| 40093002 | 超过今天发送文件容量上限 | 请明天再试或减少文件大小 |

---

### 8.3 群聊富媒体预上传 POST /v2/groups/{group_id}/upload_prepare

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_id_upload_prepare.post.html

大文件分片上传前的准备工作。返回 upload_id、分片预签名 URL 和上传配置。 后续将文件按 block_size 分片，逐片 PUT 到预签名 URL，每片完成后调用分片完成接口。

大文件分片上传第一步。传入文件大小、MD5/SHA1 校验值，服务端返回 upload_id 和各分片预签名 URL。

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/groups/{group_id}/upload_prepare |
| HTTP Method | POST |
| 接口频率限制 | 10 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| group_id | string | 是 | 群 OpenID |

**请求体**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| file_type | integer | 是 | 业务类型。1=图片, 2=视频, 3=语音, 4=文件 图片软限制 20MB, 视频软限制 30MB, 语音软限制 20MB, 文件软限制 200MB 超过软限制降级为文件类型，超过 200MB 硬限制报错 |
| file_size | string | 是 | 文件大小（字节） |
| file_name | string | 是 | 文件名 |
| md5 | string | 是 | 整个文件的 MD5 校验值 |
| sha1 | string | 是 | 整个文件的 SHA1 校验值 |
| md5_10m | string | 是 | 文件前 10002432 字节（约 10MB）的 MD5 校验值 |

**请求示例**

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/upload_prepare
{
 "file_type": 2,
 "file_size": "31457280",
 "file_name": "demo.mp4",
 "md5": "d41d8cd98f00b204e9800998ecf8427e",
 "sha1": "da39a3ee5e6b4b0d3255bfef95601890afd80709",
 "md5_10m": "c4d8c5f3a2b1e0f9a8b7c6d5e4f3a2b1"
}
```

**响应体**

| 名称 | 类型 | 描述 |
|---|---|---|
| upload_id | string | 上传任务 ID，后续分片上传和完成合并时需携带 |
| block_size | string | 分块大小（字节），默认 5MB。客户端按此大小对文件分片 |
| parts | [][UploadPart] | 分片列表，每个分片包含一个预签名上传 URL |
| upload_config | UploadConfig | 上传配置，由后台下发控制客户端上传行为 |

**UploadPart**

| 名称 | 类型 | 描述 |
|---|---|---|
| index | integer | 分片序号，从 0 开始 |
| presigned_url | string | 预签名上传 URL，客户端通过 HTTP PUT 将分片数据上传到此 URL |
| block_size | string | 该分块的大小（字节） |

**UploadConfig**

| 名称 | 类型 | 描述 |
|---|---|---|
| concurrency | integer | 上传并发数，默认 1 |
| retry_timeout | integer | 重试超时时间（秒），默认 300（5分钟） |
| retry_delay | integer | 重试延迟（秒），默认 1 |

**响应示例**

```
{
  "upload_id": "upload_a1b2c3d4e5f6",
  "block_size": "10485760",
  "parts": [
    {
      "index": 0,
      "presigned_url": "https://cos.example.com/upload?partNumber=1&sign=aaa",
      "block_size": "10485760"
    },
    {
      "index": 1,
      "presigned_url": "https://cos.example.com/upload?partNumber=2&sign=bbb",
      "block_size": "10485760"
    },
    {
      "index": 2,
      "presigned_url": "https://cos.example.com/upload?partNumber=3&sign=ccc",
      "block_size": "10485760"
    }
  ],
  "upload_config": {
    "concurrency": 1,
    "retry_timeout": 300,
    "retry_delay": 1
  }
}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 申请上传失败，请重试 |

---

### 8.4 群聊分片上传完成 POST /v2/groups/{group_id}/upload_part_finish

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_groups_group_id_upload_part_finish.post.html

通知服务端某个分片已上传完成。需在每片 PUT 成功后调用。全部分片完成后，用 upload_id 作为 MediaUpload 的 upload_id 字段调一次上传接口完成合并。

分片上传第二步。每个分片 PUT 到预签名 URL 成功后调用，通知服务端该分片已上传完成。 全部分片完成后，携带 upload_id 调用 /v2/groups/{group_openid}/files 完成合并。

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/groups/{group_id}/upload_part_finish |
| HTTP Method | POST |
| 接口频率限制 | 10 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| group_id | string | 是 | 群 OpenID |

**请求体**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| upload_id | string | 否 | 上传任务 ID，来自预上传响应 |
| part_index | integer | 否 | 分片序号，对应 UploadPart.index |
| block_size | string | 否 | 该分块的实际大小（字节） |
| md5 | string | 否 | 该分片的 MD5 校验值 |

**请求示例**

```
POST /v2/groups/B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5/upload_part_finish
{
 "upload_id": "upload_a1b2c3d4e5f6",
 "part_index": 0,
 "block_size": "10485760",
 "md5": "c4d8c5f3a2b1e0f9a8b7c6d5e4f3a2b1"
}
```

**响应**：无

**响应示例**

```
{}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 分片转存 BDH 通道异常，请重试 |
| 40093002 | 超过今天发送文件容量上限 | 请明天再试或减少文件大小 |

---

### 8.5 单聊富媒体预上传 POST /v2/users/{user_id}/upload_prepare

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_id_upload_prepare.post.html

单聊大文件分片上传前的准备工作。返回 upload_id、分片预签名 URL 和上传配置。 后续将文件按 block_size 分片，逐片 PUT 到预签名 URL，每片完成后调用分片完成接口。

大文件分片上传第一步。传入文件大小、MD5/SHA1 校验值，服务端返回 upload_id 和各分片预签名 URL。

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/users/{user_id}/upload_prepare |
| HTTP Method | POST |
| 接口频率限制 | 10 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| user_id | string | 是 | 用户 OpenID |

**请求体**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| file_type | integer | 是 | 业务类型。1=图片, 2=视频, 3=语音, 4=文件 |
| file_size | string | 是 | 文件大小（字节） |
| file_name | string | 是 | 文件名 |
| md5 | string | 是 | 整个文件的 MD5 |
| sha1 | string | 是 | 整个文件的 SHA1 |
| md5_10m | string | 是 | 文件前 10002432 字节（约 10MB）的 MD5 校验值 |

**请求示例**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/upload_prepare
{
 "file_type": 2,
 "file_size": "31457280",
 "file_name": "demo.mp4",
 "md5": "d41d8cd98f00b204e9800998ecf8427e",
 "sha1": "da39a3ee5e6b4b0d3255bfef95601890afd80709",
 "md5_10m": "c4d8c5f3a2b1e0f9a8b7c6d5e4f3a2b1"
}
```

**响应体**

| 名称 | 类型 | 描述 |
|---|---|---|
| upload_id | string | 上传任务 ID，后续分片上传和完成合并时需携带 |
| block_size | string | 分块大小（字节），默认 5MB。客户端按此大小对文件分片 |
| parts | [][UploadPart] | 分片列表，每个分片包含一个预签名上传 URL |
| upload_config | UploadConfig | 上传配置，由后台下发控制客户端上传行为 |

**UploadPart**

| 名称 | 类型 | 描述 |
|---|---|---|
| index | integer | 分片序号，从 0 开始 |
| presigned_url | string | 预签名上传 URL，客户端通过 HTTP PUT 将分片数据上传到此 URL |
| block_size | string | 该分块的大小（字节） |

**UploadConfig**

| 名称 | 类型 | 描述 |
|---|---|---|
| concurrency | integer | 上传并发数，默认 1 |
| retry_timeout | integer | 重试超时时间（秒），默认 300（5分钟） |
| retry_delay | integer | 重试延迟（秒），默认 1 |

**响应示例**

```
{
  "upload_id": "upload_a1b2c3d4e5f6",
  "block_size": "10485760",
  "parts": [
    {
      "index": 0,
      "presigned_url": "https://cos.example.com/upload?partNumber=1&sign=aaa",
      "block_size": "10485760"
    },
    {
      "index": 1,
      "presigned_url": "https://cos.example.com/upload?partNumber=2&sign=bbb",
      "block_size": "10485760"
    },
    {
      "index": 2,
      "presigned_url": "https://cos.example.com/upload?partNumber=3&sign=ccc",
      "block_size": "10485760"
    }
  ],
  "upload_config": {
    "concurrency": 1,
    "retry_timeout": 300,
    "retry_delay": 1
  }
}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 申请上传失败，请重试 |

---

### 8.6 单聊分片上传完成 POST /v2/users/{user_id}/upload_part_finish

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/autogen/api/v2_users_user_id_upload_part_finish.post.html

通知服务端某个分片已上传完成。全部分片完成后，用 upload_id 作为 MediaUpload 的 upload_id 字段调一次上传接口完成合并。

分片上传第二步。每个分片 PUT 到预签名 URL 成功后调用，通知服务端该分片已上传完成。 全部分片完成后，携带 upload_id 调用 /v2/users/{user_openid}/files 完成合并。

**基础信息**

| 字段 | 值 |
|---|---|
| HTTP URL | /v2/users/{user_id}/upload_part_finish |
| HTTP Method | POST |
| 接口频率限制 | 10 QPS |

**路径参数**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| user_id | string | 是 | 用户 OpenID |

**请求体**

| 名称 | 类型 | 必填 | 描述 |
|---|---|---|---|
| upload_id | string | 否 | 上传任务 ID |
| part_index | integer | 否 | 分片序号 |
| block_size | string | 否 | 分块大小（字节） |
| md5 | string | 否 | 分片 MD5 |

**请求示例**

```
POST /v2/users/A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4/upload_part_finish
{
 "upload_id": "upload_a1b2c3d4e5f6",
 "part_index": 0,
 "block_size": "10485760",
 "md5": "c4d8c5f3a2b1e0f9a8b7c6d5e4f3a2b1"
}
```

**响应**：无

**响应示例**

```
{}
```

**错误码**

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 分片转存 BDH 通道异常，请重试 |
| 40093002 | 超过今天发送文件容量上限 | 请明天再试或减少文件大小 |

### 8.7 三段式/分片上传字段速查

| 步骤 | 端点 | 关键入参 | 关键出参 |
|---|---|---|---|
| ① 预上传 | POST `/v2/users/{user_id}/upload_prepare`、POST `/v2/groups/{group_id}/upload_prepare` | file_type、file_size、file_name、md5、sha1、md5_10m | upload_id、block_size、parts[].index/presigned_url/block_size、upload_config.concurrency/retry_timeout/retry_delay |
| ② 分片 PUT | （预签名 URL，HTTP PUT，非 OpenAPI） | 分片二进制数据 | — |
| ③ 分片确认 | POST `/v2/users/{user_id}/upload_part_finish`、POST `/v2/groups/{group_id}/upload_part_finish` | upload_id、part_index、block_size、md5 | 无（`{}`） |
| ④ 合并 | POST `/v2/users/{user_openid}/files`、POST `/v2/groups/{group_openid}/files` | file_type、srv_send_msg、file_name、upload_id（url 可为空） | file_uuid、file_info、ttl，可选 id / raw_url |

> 注：`file_data` 字段（直接在请求体内传文件二进制）在本组抓取的上传接口官方请求体中**未出现**（官方只支持 URL 上传与分片上传合并两条路径）→ 「file_data 直传」标注为「官方文档未提供」。

---

## 9. 消息类型与富文本

### 9.1 消息类型总览（发送 msg_type / 接收 message_type）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/overview.html

通过 `msg_type` 指定消息格式，不同的类型对应不同的内容字段和收发能力。

**发送：msg_type**

| msg_type | 类型 | 内容字段 | 说明 |
|---|---|---|---|
| 0 | 文本 | `content` | 纯文本消息 |
| 2 | Markdown | `markdown` | 支持 Markdown 语法，详见 Markdown 消息 |
| 7 | 富媒体 | `media` | 图片/视频/语音/文件，需先上传获取 `file_info` |

**接收：message_type**

收到用户消息时，事件体中的 `message_type` 表示消息内容类型：

| message_type | 含义 | 说明 |
|---|---|---|
| 0 | 普通文本 | `content` 字段携带文本内容 |
| 3 | 结构化卡片 | `ark_data` 字段携带卡片数据 |
| 103 | 引用消息 | `msg_elements` 字段携带嵌套内容 |

图片、视频、语音、文件等附加内容通过 `attachments` 字段携带（`content_type` 区分具体类型），不通过 `message_type` 单独表示。

**各场景支持情况**

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

- 发送侧只有 msg_type=0/2/3/7 四种（见上方表格）
- 富媒体上传流程见富媒体使用说明
- 表情表态仅频道支持，详见表情表态

---

### 9.2 Markdown 消息

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/markdown.html

2026/04/23 能力更新说明：单聊场景、群聊场景自定义 Markdown 消息能力已开放到所有机器人均可使用，无需单独申请 Markdown 模版，频道场景目前需要内邀开通。

#### 支持格式（白名单语法，逐字）

标题：

```
# 一号标题
## 二号标题
正文
```

文字样式：

```
**加粗**
__下划线加粗__
_斜体_
*星号斜体*
***加粗斜体***
~~删除线~~
```

链接：

```
欢迎来到：[🔗腾讯网](https://www.qq.com) 
文档可以访问<https://doc.qq.com>
```

图片（对于 markdown 消息内的图片资源，请使用可在公网访问的资源 url，开放平台会下载转存该资源）：

```
![text #208px #320px](https://resource5-1255303497.cos.ap-guangzhou.myqcloud.com/abcmouse_word_watch/markdown/building.png)
```

有序列表：

```
# 有序列表
1. 新人降落桃源岛的欢迎仪式
2. 阳光准则助力建设有温度的频道
3. 岛民分享吹水纳凉
```

无序列表：

```
# 无序列表
- 新人降落桃源岛的欢迎仪式
- 阳光准则助力建设有温度的频道
- 岛民分享吹水纳凉
```

列表嵌套：

```
# 有序列表标题
1. 嵌套一层
 - 列表前是普通文本，则需要在列表前用空行隔开，否则无法识别
 - 如果是段落标签比如标题，则无需用空行隔开
2. 嵌套二层
 1. 我是有序列表，二级列表前面需要空4个空格
 2. 无序列表和有序列表可以相互嵌套，但是不建议无限制嵌套。
```

块引用：

```
> 青青子衿，悠悠我心，但为君故，沉吟至今
> 四月维夏，六月徂暑。先祖匪人，胡宁忍予
> 秋日凄凄，百卉具腓。乱离瘼矣，爰其适归？
诗经《小雅》
```

水平分割线：

```
这是段落1
***
这是段落2
```

换多行：

```
第一行

第二行

\u200B
\u200B
第三行
```

#### 发送方式

自定义 markdown 消息使用示例：

```
{
  "markdown": {
    "content": "# 标题 \n## 简介很开心 \n内容[🔗腾讯](https://www.qq.com)"
  }
}
```

markdown 模版消息的使用示例：

```
// 模版例子

#{{.title}}

![img#618px #249px]({{.image}})

*{{.para1}}
*{{.para2}}

## {{.desc}}

{{.content}}[{{.link_introduction}}]({{.link}})

// 发送case
{
	"markdown": {
		"custom_template_id": "101993071_1658748972",
		"params": [{
				"key": "title",
				"values": ["标题"]
			},
			{
				"key": "image",
				"values": [
					"https://resource5-1255303497.cos.ap-guangzhou.myqcloud.com/abcmouse_word_watch/other/mkd_img.png"
				]
			},
			{
				"key": "para1",
				"values": ["段落1"]
			},
			{
				"key": "para2",
				"values": ["段落2"]
			},
			{
				"key": "desc",
				"values": ["简介"]
			},
			{
				"key": "content",
				"values": ["在这个子频道非常开心"]
			},
			{
				"key": "link_introduction",
				"values": ["链接介绍"]
			},
			{
				"key": "link",
				"values": ["https://www.qq.com"]
			}
		]
	}
}
```

#### 数据结构与协议

消息发送 markdown 字段值是一个 json object，具体字段如下：

| **属性** | **类型** | **必填** | **说明** |
|---|---|---|---|
| content | string | 否 | 自定义 markdown 文本内容 |
| custom_template_id | string | 否 | markdown 模版id，申请模版后获得 |
| params | Array | 否 | {key: xxx, values: xxx}，模版内变量与填充值的kv映射 |

> 关于 emoji（表情）在 markdown 中的嵌入语法：官方将「表情」归入「文本交互（text-chain）」能力（见 9.7），`<emoji:id>` 仅频道可用；markdown 本身的白名单语法列表中**未**单列 emoji 语法。

---

### 9.3 结构化卡片消息（ARK）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/ark.html

说明：达到准入条件的开发者，向平台运营申请后获得权限。

#### 发送方式

选择合适的 结构化卡片消息（ARK） 模板，将模板变量以 key-value 对填充后发送。每个模板定义了自己的变量（`#XXX#`），变量类型可以是字符串、数组、URL 等。

**数据结构** — 消息发送接口中 `ark` 字段的结构：

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| template_id | int | 是 | 模板 ID，可选 23 / 24 / 37 |
| kv | kv 数组 | 是 | `[{key: "#变量#", value: "填充值"}]`，模板变量与填充值的映射 |

当变量类型为数组时，kv 元素使用 `obj` 嵌套数组结构：

```
{
  "key": "#LIST#",
  "obj": [
    {
      "obj_kv": [
        { "key": "desc", "value": "文本" },
        { "key": "link", "value": "https://..." }
      ]
    }
  ]
}
```

**请求示例**

```
{
  "ark": {
    "template_id": 23,
    "kv": [
      { "key": "#DESC#", "value": "机器人订阅消息" },
      { "key": "#PROMPT#", "value": "XX机器人" },
      { "key": "#TITLE#", "value": "XX机器人消息" },
      { "key": "#META_URL#", "value": "http://domain.com/" },
      {
        "key": "#META_LIST#",
        "obj": [
          {
            "obj_kv": [
              { "key": "name", "value": "aaa" },
              { "key": "age", "value": "3" }
            ]
          },
          {
            "obj_kv": [
              { "key": "name", "value": "bbb" },
              { "key": "age", "value": "4" }
            ]
          }
        ]
      }
    ]
  }
}
```

#### 模板 23 — 链接+文本列表

模板 id = 23。

模板格式：

```
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
  }
}
```

字段说明：

| 变量 | 类型 | 描述 |
|---|---|---|
| #DESC# | string | 描述 |
| #PROMPT# | string | 提示消息 |
| #LIST# | array | 文本列表，每个元素为 `{desc, link}` |

**#LIST# 元素结构**：

| 字段 | 类型 | 描述 |
|---|---|---|
| desc | string | 文本内容 |
| link | string | 跳转链接（需提前报备），不填则仅显示文本 |

请求示例：

```
{
  "ark": {
    "template_id": 23,
    "kv": [
      { "key": "#DESC#", "value": "descaaaaaa" },
      { "key": "#PROMPT#", "value": "promptaaaa" },
      {
        "key": "#LIST#",
        "obj": [
          { "obj_kv": [{ "key": "desc", "value": "需求标题：UI问题解决" }] },
          { "obj_kv": [{ "key": "desc", "value": "当前状态\"体验中\"点击下列动作直接扭转状态到：" }] },
          {
            "obj_kv": [
              { "key": "desc", "value": "已评审" },
              { "key": "link", "value": "https://qun.qq.com" }
            ]
          },
          {
            "obj_kv": [
              { "key": "desc", "value": "已排期" },
              { "key": "link", "value": "https://qun.qq.com" }
            ]
          },
          {
            "obj_kv": [
              { "key": "desc", "value": "开发中" },
              { "key": "link", "value": "https://qun.qq.com" }
            ]
          },
          {
            "obj_kv": [
              { "key": "desc", "value": "增量测试中" },
              { "key": "link", "value": "https://qun.qq.com" }
            ]
          },
          { "obj_kv": [{ "key": "desc", "value": "请关注" }] }
        ]
      }
    ]
  }
}
```

#### 模板 24 — 文本+缩略图

模板 id = 24。

模板格式：

```
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

字段说明：

| 变量 | 类型 | 描述 |
|---|---|---|
| #DESC# | string | 描述 |
| #PROMPT# | string | 提示文本 |
| #TITLE# | string | 标题 |
| #METADESC# | string | 详情描述 |
| #IMG# | string | 图片链接 |
| #LINK# | string | 跳转链接 |
| #SUBTITLE# | string | 来源 |

请求示例：

```
{
  "ark": {
    "template_id": 24,
    "kv": [
      { "key": "#DESC#", "value": "..." },
      { "key": "#PROMPT#", "value": "通知信息" },
      { "key": "#TITLE#", "value": "标题" },
      { "key": "#METADESC#", "value": "Meta描述" },
      { "key": "#IMG#", "value": "https://pub.idqqimg.com/pc/misc/files/20190820/2f4e70ae3355ece23d161cf5334d4fc1jzjfmtep.png" },
      { "key": "#LINK#", "value": "https://qq.com" },
      { "key": "#SUBTITLE#", "value": "子标题" }
    ]
  }
}
```

#### 模板 37 — 大图

模板 id = 37。

模板格式：

```
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

字段说明：

| 变量 | 类型 | 描述 |
|---|---|---|
| #PROMPT# | string | 提示消息 |
| #METATITLE# | string | 标题 |
| #METASUBTITLE# | string | 子标题 |
| #METACOVER# | string | 大图，尺寸 975×540 |
| #METAURL# | string | 跳转链接 |

请求示例：

```
{
  "ark": {
    "template_id": 37,
    "kv": [
      { "key": "#PROMPT#", "value": "通知提醒" },
      { "key": "#METATITLE#", "value": "标题" },
      { "key": "#METASUBTITLE#", "value": "子标题" },
      { "key": "#METACOVER#", "value": "https://vfiles.gtimg.cn/vupload/20211029/bf0ed01635493790634.jpg" },
      { "key": "#METAURL#", "value": "https://qq.com" }
    ]
  }
}
```

---

### 9.4 Embed 消息

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/type/embed.html

|  | **单聊** | **群聊** | **文字子频道** | **频道私信** |
|---|---|---|---|---|
| 机器人接收 | - | - | - | - |
| 机器人发送 | 不支持 | 不支持 | 支持 | 支持 |

样式：（官方配图：https://aka.doubaocdn.com/s/UnVFi6BbjX ）

**Content-Type**

```
application/json
```

**参数**

| 字段名 | 类型 | 描述 |
|---|---|---|
| embed | MessageEmbed | embed 消息详情 |

- 其中 embed.thumbnail 为选填，没有缩略图的可以不填。
- embed.fields.name 为文本。

**返回**：返回 Message 对象。

**错误码**：详见错误码（官方指向 https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html ）。

**示例**

请求数据包：

```
{
  "embed": {
    "title": "标题",
    "prompt": "消息通知",
    "thumbnail": {
      "url": "xxxxxx"
    },
    "fields": [
      {
        "name": "当前等级：黄金"
      },
      {
        "name": "之前等级：白银"
      },
      {
        "name": "😁继续努力"
      }
    ]
  }
}
```

返回包：

```
{
  "id": "xxxxxx",
  "channel_id": "xxxxxx",
  "guild_id": "xxxxxx",
  "timestamp": "2021-12-07T15:24:54+08:00",
  "tts": false,
  "mention_everyone": false,
  "author": {
    "id": "xxxxxx",
    "username": "abc",
    "avatar": "",
    "bot": true
  },
  "embeds": [
    {
      "title": "标题",
      "prompt": "xxxx",
      "description": "",
      "thumbnail": {
        "url": "xxxxxx"
      },
      "fields": [
        {
          "name": "当前等级：黄金"
        },
        {
          "name": "之前等级：白银"
        },
        {
          "name": "😁继续努力"
        }
      ]
    }
  ],
  "pinned": false,
  "type": 0,
  "flags": 0
}
```

> Embed 的深层字段（MessageEmbed / MessageEmbedThumbnail / MessageEmbedField）定义见 9.8「消息对象模型」。

---

### 9.5 表情表态（Emoji）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/emoji.html

说明：目前表情表态仅支持在频道内使用。

#### 9.5.1 机器人发表表情表态

**接口**

```
PUT /channels/{channel_id}/messages/{message_id}/reactions/{type}/{id}
```

**功能描述**：对消息 `message_id` 进行表情表态

**参数**

| 字段名 | 类型 | 描述 |
|---|---|---|
| channel_id | string | 子频道ID |
| message_id | string | 消息ID |
| type | int | 表情类型，参考 EmojiType |
| id | string | 表情ID，参考 Emoji 列表 |

**返回**：成功返回 HTTP 状态码 `204`。

**错误码**：详见错误码。

**示例**

```
PUT /channels/1013531/messages/08c095b7ba8ed4abd7e00110cbd83f3841489aa2bd9006/reactions/1/203
```

#### 9.5.2 删除机器人发表的表情表态

**接口**

```
DELETE /channels/{channel_id}/messages/{message_id}/reactions/{type}/{id}
```

**功能描述**：删除自己对消息 `message_id` 的表情表态

**参数**

| 字段名 | 类型 | 描述 |
|---|---|---|
| channel_id | string | 子频道ID |
| message_id | string | 消息ID |
| type | int | 表情类型，参考 EmojiType |
| id | string | 表情ID，参考 Emoji 列表 |

**返回**：成功返回 HTTP 状态码 `204`。

**示例**

```
DELETE /channels/1013531/messages/08c095b7ba8ed4abd7e00110cbd83f3841489aa2bd9006/reactions/1/203
```

#### 9.5.3 获取消息表情表态的用户列表

**接口**

```
GET /channels/{channel_id}/messages/{message_id}/reactions/{type}/{id}?cookie={cookie}&limit={limit}
```

**功能描述**：拉取对消息 `message_id` 指定表情表态的用户列表

**Path 参数**

| 字段名 | 类型 | 描述 |
|---|---|---|
| channel_id | string | 子频道ID |
| message_id | string | 消息ID |
| type | int | 表情类型，参考 EmojiType |
| id | string | 表情ID，参考 Emoji 列表 |

**Query 参数**

| 字段名 | 类型 | 描述 |
|---|---|---|
| cookie | string | 上次请求返回的cookie，第一次请求无需填写 |
| limit | int | 每次拉取数量，默认20，最多50，只在第一次请求时设置 |

**返回**

| 字段名 | 类型 | 描述 |
|---|---|---|
| users | array | 用户对象，参考 User，会返回 id, username, avatar |
| cookie | string | 分页参数，用于拉取下一页 |
| is_end | bool | 是否已拉取完成到最后一页，true代表完成 |

**示例**

请求数据包：

```
GET /channels/1013531/messages/08c095b7ba8ed4abd7e00110cbd83f3841489aa2bd9006/reactions/1/203?cookie=&limit=20
```

返回数据包：

```
{
    "users": [
        {
            "id": "1158788878435714165",
            "username": "频道机器人",
            "avatar": "http://thirdqq.qlogo.cn/g?b=oidb&k=T2qBkyqicopYXA5mn0lBkqA&s=0&t=1635736336"
        }
    ],
    "cookie":"1_2",
    "is_end": false
}
```

#### 9.5.4 事件

**用户发表** — 基本概况：用户对消息进行表情表态时，触发事件通知。

- `MESSAGE_REACTION_ADD`（intents `GUILD_MESSAGE_REACTIONS`）
  - 发送时机：用户对消息进行表情表态时
- `MESSAGE_REACTION_REMOVE`（intents `GUILD_MESSAGE_REACTIONS`）
  - 发送时机：用户对消息进行取消表情表态时
  - 内容：内容为 MessageReaction 对象

示例：

```
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
  }
}
```

> 说明：EmojiType 取值表、Emoji 列表（系统表情 id 全集）在官方文档中指向 `openapi/emoji/model.html`，该页不在本组页面清单内 → **EmojiType 数值表与 Emoji 完整 id 列表标注为「官方文档未提供」（本组页面范围内）**。

---

### 9.6 消息按钮（msg-btn）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/msg-btn.html

说明：在 markdown 消息的基础上，支持消息最底部挂载按钮。

#### 发送方式

【申请使用】按钮模版，按钮模版暂时不支持使用变量填充。

```
{
    "keyboard": {
        "id": "123" // 申请模版后获得
    }
}
```

【内邀开通】自定义按钮

```
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
    }
}
```

#### 数据结构与协议

消息发送接口 keyboard 字段值是一个 Json Object {}，rows 数组的每个元素表示每一行按钮。每个 button 是一个 Json Object，具体字段如下：

| **属性** | **类型** | **必填** | **说明** |
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

示例：

```
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
  ]
}
```

#### 相关事件与接口

用户点击回调按钮会触发 `INTERACTION_CREATE` 事件，机器人收到事件后需调用 `PUT /interactions/{interaction_id}` 进行回应，否则客户端会一直处于 loading 状态直到超时。

- 事件详情：INTERACTION_CREATE
- 回应接口：`PUT /interactions/{interaction_id}`

> **按钮权限对照小结**（依据上表原文）：
> - 发消息接口 `Keyboard.Button.action.permission.type`：`0=指定用户, 1=管理员, 2=所有人`（单聊/群聊接口表）
> - 频道按钮文档 `action.permission.type`：`0 指定用户可操作，1 仅管理者可操作，2 所有人可操作，3 指定身份组可操作（仅频道可用）`
> - 两处对 type=3（指定身份组）的可见性说明不同，均为官方原文，差异已如实保留。

---

### 9.7 文本交互（text-chain）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/trans/text-chain.html

说明：QQBot 提供文本消息的交互能力，当开发者使用指定的格式发送消息，用户即可在消息体上进行点击交互操作，例如@某人，跳转链接等。

#### 9.7.1 使用 @ 能力

说明：群聊&文字子频道，支持含有文本文字的消息类型，如：文本消息、图文消息、markdown 消息。

**1. @某人｜群聊、文字子频道可用**

- 嵌入文本使用格式：`<qqbot-at-user id="" />` 协议：`<@userid>` 即将弃用，请使用上述最新格式。
- 客户端展示为：@用户 标签

**2. @全部成员｜仅在文字子频道可用**

- 嵌入文本使用格式：`<qqbot-at-everyone />` 协议：`@everyone` 即将弃用，请使用上述最新格式。
- 客户端展示为：@全部成员 标签，需要机器人拥有发送 @全部成员 消息的权限，

#### 9.7.2 指令操作

目前仅在 markdown 支持。

**1. 回车指令格式（点击后，文本直接发送）**

嵌入文本使用格式：`<qqbot-cmd-enter text="xxx" />`

客户端展示为：/回车指令 用户可点击的标签，群聊和文字子频道不支持该能力。

- `text` 用户点击后直接发送的文本，参数必填，最大限制 100 字符，传值时需要 urlencode。

**2. 参数指令格式（点击后，文本插入输入框，用户自行编辑发送）**

嵌入文本使用格式：`<qqbot-cmd-input text="xxx" show="xxx" reference="false" />`

客户端展示为：/参数指令 用户可点击的标签

- `text` 用户点击后插入输入框的文本，参数必填，最大限制 100 字符，传值时需要 urlencode。
- `show` 用户在消息内看到的文本，参数选填，默认取 text 值，最大限制 100 字符，传值时需要 urlencode。
- `reference` 插入输入框时是否带消息原文回复引用，参数选填，默认为 `false`，填入 `true` 时则带引用回复到输入框中。

#### 9.7.3 跳转子频道

仅频道可用。

嵌入文本使用格式：`<#channel_id>`

客户端展示为：#XXX文字子频道 标签，点击可以跳转至子频道，仅支持当前频道内的子频道。

#### 9.7.4 表情

仅频道可用，解析为系统表情。 具体表情 id 参考 Emoji 列表。

嵌入文本使用格式：`<emoji:id>`

- 仅支持 `type = 1` 的系统表情。
- `type = 2` 的 emoji 表情直接按字符串填写即可。

#### 9.7.5 text-chain 转换规则速查

| 能力 | 嵌入文本格式（新） | 旧协议 | 生效场景 | 客户端展示 |
|---|---|---|---|---|
| @某人 | `<qqbot-at-user id="" />` | `<@userid>`（即将弃用） | 群聊、文字子频道 | @用户 标签 |
| @全部成员 | `<qqbot-at-everyone />` | `@everyone`（即将弃用） | 仅文字子频道 | @全部成员 标签（需权限） |
| 回车指令 | `<qqbot-cmd-enter text="xxx" />` | — | 仅 markdown；群聊/文字子频道不支持 | /回车指令 标签 |
| 参数指令 | `<qqbot-cmd-input text="xxx" show="xxx" reference="false" />` | — | 仅 markdown | /参数指令 标签 |
| 跳转子频道 | `<#channel_id>` | — | 仅频道 | #XXX文字子频道 标签 |
| 表情 | `<emoji:id>` | — | 仅频道 | 系统表情（type=1） |

---

### 9.8 消息对象模型（model）

> 来源：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/template/model.html

#### 消息对象(Message)

**Message**

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
| ark | MessageArk ark消息对象 | ark消息 |
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

**MessageEmbedThumbnail**

| 字段名 | 类型 | 描述 |
|---|---|---|
| url | string | 图片地址 |

**MessageEmbedField**

| 字段名 | 类型 | 描述 |
|---|---|---|
| name | string | 字段名 |

**MessageAttachment**

| 字段名 | 类型 | 描述 |
|---|---|---|
| url | string | 下载地址 |

**MessageArk**

| 字段名 | 类型 | 描述 |
|---|---|---|
| template_id | int | ark模板id（需要先申请） |
| kv | MessageAkrKv arkkv数组 | kv值列表 |

**MessageArkKv**

| 字段名 | 类型 | 描述 |
|---|---|---|
| key | string | key |
| value | string | value |
| obj | MessageArkObj arkobj类型的数组 | ark obj类型的列表 |

**MessageArkObj**

| 字段名 | 类型 | 描述 |
|---|---|---|
| obj_kv | MessageArkObjKv objkv类型的数组 | ark objkv列表 |

**MessageArkObjKv**

| 字段名 | 类型 | 描述 |
|---|---|---|
| key | string | key |
| value | string | value |

**MessageReference**

| 字段名 | 类型 | 描述 |
|---|---|---|
| message_id | string | 需要引用回复的消息 id |
| ignore_get_message_error | bool | 是否忽略获取引用消息详情错误，默认否 |

**MessageMarkdown**

| 字段名 | 类型 | 描述 |
|---|---|---|
| template_id | int | markdown 模板 id |
| params | MessageMarkdownParams | markdown 模板模板参数 |
| content | string | 原生 markdown 内容,与 `template_id` 和 `params`参数互斥,参数都传值将报错。 |

**MessageMarkdownParams**

| 字段名 | 类型 | 描述 |
|---|---|---|
| key | string | markdown 模版 key |
| values | string 类型的数组 | markdown 模版 key 对应的 values ，列表长度大小为 `1` 代表单 value 值，长度大于1则为列表类型的参数 values 传参数 |

**MessageDelete**

| 字段名 | 类型 | 描述 |
|---|---|---|
| message | Message 对象 | 被删除的消息内容 |
| op_user | User 对象 | 执行删除操作的用户 |

#### 消息审核对象(MessageAudited)

**MessageAudited**

| 字段名 | 类型 | 描述 |
|---|---|---|
| audit_id | string | 消息审核 id |
| message_id | string | 消息 id，只有审核通过事件才会有值 |
| guild_id | string | 频道 id |
| channel_id | string | 子频道 id |
| audit_time | ISO8601 timestamp | 消息审核时间 |
| create_time | ISO8601 timestamp | 消息创建时间 |
| seq_in_channel | string | 子频道消息 seq，用于消息间的排序，seq 在同一子频道中按从先到后的顺序递增，不同的子频道之间消息无法排序 |

---

## 10. 频率限制与时效规则汇总

### 10.1 接口级 QPS 限制（官方原文数字）

| 接口 | 方法 | 路径 | 接口频率限制 | 来源 |
|---|---|---|---|---|
| 获取 access_token | POST | /app/getAppAccessToken | 官方文档未给出 QPS 数字（仅给出错误码 100001 Too many requests） | access-token.html |
| 发送单聊消息 | POST | /v2/users/{user_openid}/messages | 100 QPS，包括主动、被动等所有消息类型 | users_messages.post |
| 流式发送单聊消息 | POST | /v2/users/{user_openid}/stream_messages | 50 QPS | stream_messages.post |
| 发送群聊消息 | POST | /v2/groups/{group_openid}/messages | 100 QPS | groups_messages.post |
| 撤回单聊消息 | DELETE | /v2/users/{user_openid}/messages/{message_id} | 10 QPS | users delete |
| 撤回群聊消息 | DELETE | /v2/groups/{group_openid}/messages/{message_id} | 10 QPS | groups delete |
| 单聊富媒体上传 | POST | /v2/users/{user_openid}/files | 50 QPS | users_files.post |
| 群聊富媒体上传 | POST | /v2/groups/{group_openid}/files | 50 QPS | groups_files.post |
| 单聊富媒体预上传 | POST | /v2/users/{user_id}/upload_prepare | 10 QPS | users prepare |
| 单聊分片上传完成 | POST | /v2/users/{user_id}/upload_part_finish | 10 QPS | users part_finish |
| 群聊富媒体预上传 | POST | /v2/groups/{group_id}/upload_prepare | 10 QPS | groups prepare |
| 群聊分片上传完成 | POST | /v2/groups/{group_id}/upload_part_finish | 10 QPS | groups part_finish |

### 10.2 被动回复：时间窗口与次数上限

| 场景 | 有效期 | 每个消息最多回复次数 | 来源 |
|---|---|---|---|
| 单聊（C2C） | **60 分钟** | **4 次** | users_messages.post / overview.html |
| 群聊（GROUP_AT_MESSAGE_CREATE） | **5 分钟** | **5 次** | groups_messages.post / overview.html |
| 文字子频道 | 5 分钟 | - | overview.html |
| 频道私信 | 5 分钟 | - | overview.html |

> 补充（单聊接口文档原文）：`msg_id` 从 C2C_MESSAGE_CREATE 等事件的 d.id 获取，**5 分钟内有效**；群聊接口文档原文：`msg_id` 从 GROUP_AT_MESSAGE_CREATE 等事件的 d.id 获取，**5 分钟内有效**。
> 即：单聊「被动消息有效时间 60 分钟」（接口页顶部说明）与「msg_id 5 分钟内有效」（字段说明）两处数字均出现在官方文档中，二者口径不同，已如实并列，不做推断。

### 10.3 `msg_seq` 用法

> 来源：单聊/群聊发送接口请求体 + https://bot.q.qq.com/wiki/develop/api-v2/server-inter/message/overview.html

- 官方字段说明（逐字）：`msg_seq` = 回复消息的序号，与 `msg_id` 联合使用，避免相同消息 id 回复重复发送，不填默认是 1。相同的 `msg_id` + `msg_seq` 重复发送会失败。
- 官方机制说明（逐字）：相同 `msg_id` 可能多次推送，请结合 `msg_seq` 去重。被动回复时，相同的 `msg_id + msg_seq` 重复发送会失败，可递增 `msg_seq` 实现对同一消息的多次回复。
- 相关错误码：`40054005 消息被去重 → 请确保每次请求使用不同的msgseq值`。

### 10.4 主动消息频控（群、单聊）

| 场景 | 认证类型 | Bot 维度频控 | 单关系维度频控 | 每日上限 |
|---|---|---|---|---|
| 单聊 | 企业认证 | 10/qps | 20/qpm | 1000 条/用户 |
| 单聊 | 个人认证 | 10/qps | 20/qpm | 1000 条/用户 |
| 单聊 | 未认证 | 5/qps & 30/qpm | 20/qpm | 1000 条/用户 |
| 群 | 企业认证 | 60/qpm | 20/qpm | 1000 条/群 |
| 群 | 个人认证 | 60/qpm | 20/qpm | 1000 条/群 |
| 群 | 未认证 | 30/qpm | 20/qpm | 1000 条/群 |

> 单聊接口页顶部另有一处表述（原文）：Bot 维度（发送方）企业认证/个人身份证认证 10/qps；未认证 5/qps 且 30/qpm。单关系维度（接收方）20/qpm，每个好友 1 天最多接收 1000 条。
> 群聊接口页顶部另有一处表述（原文）：Bot 维度（发送方）企业认证/个人身份证认证 60/qpm；未认证 30/qpm。单关系维度（接收方）20/qpm，每个群 1 天最多接收 1000 条。

### 10.5 互动召回消息

- 触发条件：在用户主动与机器人对话之后
- 时间范围：未来 30 天内
- 周期划分：当天、1 - 3 天、3 - 7 天、7 - 30 天，合计 **4 个周期**
- 每周期可下发 **1 条**
- 声明字段：`is_wakeup`
- 消息类型：与当前机器人拥有的消息类型权限一致
- 相关错误码：`40034122 召回消息已达区间上限`、`40034123 不支持召回消息`
- 流式接口补充：`is_wakeup=true` 时**不校验 msg_id/event_id 有效期**

### 10.6 富媒体文件限制

| file_type | 类型 | 格式（上传接口） | 软限制 | 硬限制 | 说明 |
|---|---|---|---|---|---|
| 1 | 图片 | png / jpg | 20 MB | 200 MB | 富媒体概述页展示支持 jpg/png/gif/webp/bmp |
| 2 | 视频 | mp4 | 30 MB | 200 MB | — |
| 3 | 语音 | silk | 20 MB | 200 MB | 富媒体概述页展示支持 silk/mp3/wav/ogg |
| 4 | 文件 | - | 200 MB | 200 MB | 任意格式 |

- 超过软限制会降级为文件类型上传，超过硬限制会报错
- 分片大小默认 5MB（预上传返回 `block_size` 示例为 10485760 字节 = 10MB）
- `upload_config`：concurrency 默认 1；retry_timeout 默认 300 秒；retry_delay 默认 1 秒
- `md5_10m` = 文件前 **10002432** 字节的 MD5（富媒体概述页备注约 9.54 MB）
- 上传接口超时建议设为 ≥ 5 秒
- 每日文件容量：错误码 `40093002 超过今天发送文件容量上限`（官方未给出具体容量数字）

### 10.7 其它限制数字

| 项 | 数值 | 来源 |
|---|---|---|
| access_token 生命周期 | 默认 7200 秒（2 小时） | access-token.html |
| access_token 提前换新窗口 | 过期前 60 秒内 | access-token.html |
| 消息撤回时限 | 发送超过 2 分钟不可撤回 | delete 接口页 |
| 文字子频道发送频率 | 每秒最多 5 条 | overview.html |
| 文字子频道主动推送 | 每天每个子频道 20 条；每个频道每天 2 个子频道 | overview.html |
| 频道私信主动消息 | 每人每天 2 条；每天累计 200 条 | overview.html |
| 按钮最大规模 | 最多 5 行，每行最多 5 个按钮 | msg-btn.html |
| 按钮 label | 最多 10 字符 | 单聊/群聊接口表 |
| 指令参数 text/show | 最大 100 字符，需 urlencode | text-chain.html |
| Modal content | 最多 40 个字符，不能有 URL | 单聊/群聊接口表 |
| Modal confirm_text / cancel_text | 最多 4 个字符 | 单聊/群聊接口表 |
| input_notify.input_second | 状态持续时间，最长 60s | 单聊接口表 |
| Ark 模板 #METACOVER# 大图尺寸 | 975×540 | ark.html |
| Emoji 表态用户列表 limit | 默认 20，最多 50 | emoji.html |

---

## 11. 本组涉及的 HTTP 错误码全表

### 11.1 HTTP 状态码（通用）

| 值 | 含义 |
|---|---|
| 200 | 成功 |
| 204 | 成功，但是无包体，一般用于删除操作 |
| 201, 202 | 异步操作成功，虽然说成功，但是会返回一个 error body，需要特殊处理 |
| 401 | 认证失败 |
| 404 | 未找到 API |
| 405 | HTTP Method 不允许 |
| 429 | 频率限制 |
| 500 | 处理失败 |
| 504 | 处理失败 |

### 11.2 公共错误码（api-call-guide.html 全量，逐字）

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
| 11254 | ErrorInterfaceForbidden 应用接口被封禁，该机器人虽然获得了该接口权限，但是被封禁了 |
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
| 11275 | ErrorWrongAppid 无 appid，同 11251 |
| 11301 | ErrorGetHTTPHeader HTTP Header 无效 |
| 11302 | ErrorGetHeaderUIN HTTP Header 无效 |
| 11303 | ErrorGetNick 获取昵称失败 |
| 11304 | ErrorGetAvatar 获取头像失败 |
| 11305 | ErrorGetGuildID 获取频道 ID 失败 |
| 11306 | ErrorGetGuildInfo 获取频道信息失败 |
| 12001 | ReplaceIDFailed 替换 id 失败 |
| 12002 | RequestInvalid 请求体错误 |
| 12003 | ResponseInvalid 回包错误 |
| 20028 | ChannelHitWriteRateLimit 子频道消息触发限频 |
| 50006 | CannotSendEmptyMessage 消息为空 |
| 50035 | InvalidFormBody form-data 内容异常 |
| 50037 | 带有 markdown 消息只支持 markdown 或者 keyboard 组合 |
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
| 301000~301099 | 子频道权限错误 |
| 301000 | 参数错误 |
| 301001 | 查询频道信息错误 |
| 301002 | 查询子频道权限错误 |
| 301003 | 修改子频道权限错误 |
| 301004 | 私密子频道关联的人数到达上限 |
| 301005 | 调用 Rpc 服务失败 |
| 301006 | 非群成员没有查询权限 |
| 301007 | 参数超过数量限制 |
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
| 304023 | PUSH_MSG_ASYNC_OK 推送消息异步调用成功，等待人工审核 |
| 304024 | REPLY_MSG_ASYNC_OK 回复消息异步调用成功，等待人工审核 |
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
| 306001 | param invalid 撤回消息参数错误 |
| 306002 | msgid error 消息 id 错误 |
| 306003 | fail to get message 获取消息错误(可重试) |
| 306004 | no permission to delete message 没有撤回此消息的权限 |
| 306005 | retract message error 消息撤回失败(可重试) |
| 306006 | fail to get channel 获取子频道失败(可重试) |
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
| 504000~504999 | 消息频率相关错误 |
| 504001 | 请求参数无效错误 |
| 504002 | 获取 HTTP 头失败 |
| 504003 | 获取 BOT UIN 错误 |
| 504004 | 获取消息频率设置信息错误 |
| 610000-619999 | 频道权限错误 |
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
| 620001-629999 | 表情表态错误 |
| 620001 | 表情表态无效参数 |
| 620002 | 已经达到表情反应的类型数量上限 |
| 620003 | 已经设置过该表情表态 |
| 620004 | 没有设置过该表情表态 |
| 620005 | 没有权限设置表情表态 |
| 620006 | 操作限频 |
| 620007 | 表情表态操作失败，请重试 |
| 630001-639999 | 互动回调数据更新 |
| 630001 | 互动回调数据更新无效参数 |
| 630002 | 互动回调数据更新获取AppID失败 |
| 630003 | 互动回调数据AppID不匹配 |
| 630004 | 互动回调数据更新内部存储错误 |
| 630005 | 互动回调数据更新内部存储读取错误 |
| 630006 | 互动回调数据更新读取请求AppID失败 |
| 630007 | 互动回调数据太大 |
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
| 3000000~3999999 | 编辑消息错误 |
| 3300006 | 安全打击 |

### 11.3 access_token 接口业务错误码

| 错误码 | 错误信息 | 排查指南 |
|---|---|---|
| 100001 | Too many requests | 请求过于频繁，请降低调用频率后重试 |
| 100007 | appid invalid | AppID 无效，或机器人状态不正常（被封禁或已删除），请检查 AppID 是否正确以及机器人状态 |
| 100016 | invalid appid or secret | AppID 或 ClientSecret 不正确，请检查传入的 appId 和 clientSecret 是否与开放平台管理端一致 |
| 10004 | 机器人不存在 | AppID 对应的机器人不存在，请确认 AppID 是否正确 |

（另有 api-use.html 给出的极简错误码表：`0 = ok`。）

### 11.4 发送单聊消息 错误码（逐字）

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 22006 | 消息类型与内容不匹配 | 请检查msg_type与content是否对应 |
| 50059 | 输入类型错误 | 请检查输入类型 |
| 304004 | 无权限使用该ARK模板 | 请先申请ARK模板权限 |
| 304061 | 消息内容无效 | 请检查消息格式是否符合要求 |
| 304062 | 订阅按钮数量达到上限 | 请减少按钮数量 |
| 304064 | 订阅消息未授权 | 请先引导用户授权订阅消息 |
| 304080 | 文件信息无效 | 请检查文件信息格式是否正确 |
| 304103 | 消息ID已过期，不能回复 | 请在收到消息后尽快回复 |
| 340067 | 获取机器人信息失败 | 请检查机器人状态 |
| 40034004 | 富媒体信息转存失败 | 请重试 |
| 40034005 | 回复消息msg_id已过期 | 请在收到消息后尽快回复 |
| 40034006 | 消息内容违规 | 请修改消息内容后重试 |
| 40034008 | markdown参数有空值 | 请确保所有Markdown参数都有值 |
| 40034009 | markdown参数有换行符 | 请移除Markdown参数中的换行符 |
| 40034010 | 模版参数中不能含有markdown语法 | 请使用纯文本参数，不要包含Markdown语法 |
| 40034011 | 无效的markdown内容 | 请检查Markdown语法是否正确 |
| 40034024 | 请求参数msg_id无效或越权 | 请检查msg_id是否正确 |
| 40034025 | 请求参数event_id无效 | 请检查event_id是否正确 |
| 40034026 | 请求参数event_id已过期 | 请在收到事件后尽快回复 |
| 40034027 | 该事件不支持回复消息 | 请确认事件类型是否支持回复 |
| 40034029 | 内联键盘行/列超限 | 请减少键盘按钮数量 |
| 40034100 | 主动消息发送超过频控限制 | 请降低发送频率或等待配额恢复 |
| 40034105 | 主动消息发送失败，无权限 | 请检查机器人权限设置 |
| 40034106 | 消息不支持该指令类型 | 请检查消息指令类型 |
| 40034108 | 指令参数长度超限 | 请缩短指令参数 |
| 40034109 | 指令参数解析失败 | 请检查指令参数格式 |
| 40034122 | 召回消息已达区间上限 | 召回消息已达上限，无法继续召回 |
| 40034123 | 不支持召回消息 | 该消息不支持召回操作 |
| 40034124 | markdown消息参数错误 | 请检查Markdown参数格式 |
| 40034127 | 无markdown模板权限 | 请先申请Markdown模板权限 |
| 40034128 | 被动回复时间或次数超限 | 请在收到事件后尽快回复 |
| 40054004 | 无好友关系 | 请先添加好友后再发送私信 |
| 40054005 | 消息被去重 | 请确保每次请求使用不同的msgseq值 |
| 40054006 | 验证好友关系失败 | 请重试 |
| 40054007 | 消息长度超限 | 请缩短消息内容 |
| 40054013 | 用户拒收消息 | 用户已拒收消息，无法发送 |
| 40054016 | 机器人已下线 | 请检查机器人状态 |
| 40054018 | 消息过长或异常 | 请缩短消息内容 |
| 50055002 | 消息发送异常，请稍后重试 | 请稍后重试 |

### 11.5 发送群聊消息 错误码（逐字）

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 22006 | 消息类型与内容不匹配 | 请检查msg_type与content是否对应 |
| 304004 | 无权限使用该ARK模板 | 请先申请ARK模板权限 |
| 304036 | 无Markdown模板权限 | 请先申请Markdown模板权限 |
| 304061 | 消息内容无效 | 请检查消息格式是否符合要求 |
| 304064 | 订阅消息未授权 | 请先引导用户授权订阅消息 |
| 304080 | 文件信息无效 | 请检查文件信息格式是否正确 |
| 304103 | 消息ID已过期，不能回复 | 请在收到消息后尽快回复 |
| 305007 | 键盘样式参数错误 | 请检查keyboard参数 |
| 340069 | 消息类型无效 | 请检查msg_type取值 |
| 40034004 | 富媒体信息转存失败 | 请重试 |
| 40034005 | 回复消息msg_id已过期 | 请在收到消息后尽快回复 |
| 40034006 | 消息内容违规 | 请修改消息内容后重试 |
| 40034008 | markdown参数有空值 | 请确保所有Markdown参数都有值 |
| 40034009 | markdown参数有换行符 | 请移除Markdown参数中的换行符 |
| 40034010 | 模版参数中不能含有markdown语法 | 请使用纯文本参数，不要包含Markdown语法 |
| 40034011 | 无效的markdown内容 | 请检查Markdown语法是否正确 |
| 40034024 | 请求参数msg_id无效或越权 | 请检查msg_id是否正确 |
| 40034025 | 请求参数event_id无效 | 请检查event_id是否正确 |
| 40034026 | 请求参数event_id已过期 | 请在收到事件后尽快回复 |
| 40034027 | 该事件不支持回复消息 | 请确认事件类型是否支持回复 |
| 40034029 | 内联键盘行/列超限 | 请减少键盘按钮数量 |
| 40034100 | 主动消息发送超过频控限制 | 请降低发送频率或等待配额恢复 |
| 40034101 | 机器人非群成员 | 请先将机器人加入群聊 |
| 40034105 | 主动消息发送失败，无权限 | 请检查机器人权限设置 |
| 40034106 | 消息不支持该指令类型 | 请检查消息指令类型 |
| 40034108 | 指令参数长度超限 | 请缩短指令参数 |
| 40034109 | 指令参数解析失败 | 请检查指令参数格式 |
| 40034124 | markdown消息参数错误 | 请检查Markdown参数格式 |
| 40034127 | 无markdown模板权限 | 请先申请Markdown模板权限 |
| 40034128 | 被动回复时间或次数超限 | 请在收到事件后尽快回复 |
| 40054002 | 机器人被禁言 | 请等待解禁后再发送 |
| 40054003 | 机器人不是群成员 | 请先将机器人加入群聊 |
| 40054005 | 消息被去重 | 请确保每次请求使用不同的msgseq值 |
| 40054007 | 消息长度超限 | 请缩短消息内容 |
| 40054010 | 不允许发送URL | 请移除消息中的URL |
| 40054016 | 机器人已下线 | 请检查机器人状态 |
| 50055001 | 消息发送异常，请稍后重试 | 请稍后重试 |
| 50055006 | ARK消息发送异常，请稍后重试 | 请稍后重试 |

### 11.6 流式发送单聊消息 错误码（逐字）

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 40007 | 已下发内容前缀不可修改 | 请保持已下发内容前缀一致 |
| 50001 | 服务内部错误 | 请稍后重试 |
| 50002 | 频率限制 | 请降低调用频率 |

### 11.7 撤回单聊消息 错误码（逐字）

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 306009 | 用户openid无效 | 请检查user_openid是否正确 |
| 40061001 | 请求参数无效 | 请检查请求参数格式 |
| 40061002 | 请求参数msgid无效 | 请检查msgid格式是否正确 |
| 40064004 | 已超出消息撤回时限 | 消息发送超过2分钟后不可撤回 |

### 11.8 撤回群聊消息 错误码（逐字）

| 错误码 | 描述 | 排查建议 |
|---|---|---|
| 40061001 | 请求参数无效 | 请检查请求参数格式 |
| 40062003 | 无操作权限 | 请检查机器人是否有操作权限，机器人是否为群管理员或者发消息的用户是否为普通用户 |
| 40064004 | 已超出消息撤回时限 | 消息发送超过2分钟后不可撤回 |
| 50065001 | 消息撤回失败，请稍后重试 | 请稍后重试 |

### 11.9 富媒体上传 / 分片上传 错误码（六页共用同一张表，逐字）

| 错误码 | 描述 | 排查建议（单聊上传 / 群聊上传 页） |
|---|---|---|
| 850018 | 群被禁言或者机器人被禁言 | 请检查机器人是否被禁言 |
| 850019 | 不支持的文件格式 | 请检查 file_type 是否正确 |
| 850026 | 下载原始文件失败 | 请检查 URL 是否可访问或重试 |
| 850031 | 上传文件超过大小限制 | 请减小文件大小 |
| 850027 | 发送数据超时 | 请稍后重试 |
| 10000 | 不支持的操作 | 请检查请求参数 |
| 40093001 | 文件上传失败，请重试 | 大文件分片上传中 BDH 通道异常，请重试 |
| 40093002 | 超过今天发送文件容量上限 | 请明天再试或减少文件大小 |

各页面对 `40093001` / `40093002` 的「排查建议」措辞略有不同（逐字差异）：

| 页面 | 40093001 排查建议 | 40093002 排查建议 |
|---|---|---|
| 单聊富媒体上传 | 大文件分片上传中 BDH 通道异常，请重试 | 超过今天发送文件容量上限 |
| 群聊富媒体上传 | 大文件分片上传中 BDH 通道异常，请重试 | 超过今天发送文件容量上限 |
| 单聊/群聊预上传 | 申请上传失败，请重试 | （该页未列出 40093002） |
| 单聊/群聊分片上传完成 | 分片转存 BDH 通道异常，请重试 | 超过今天发送文件容量上限 |

### 11.10 表情表态 错误码

官方 emoji.html 页**未给出**独立错误码表，仅写「详见错误码」并指向 `https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html`（该页不在本组页面清单内）。
可参考本组 11.2 公共错误码中的 `620001-629999 表情表态错误` 段落。

### 11.11 Embed 错误码

官方 embed.html 页**未给出**独立错误码表，仅写「详见错误码」并指向 `https://bot.q.qq.com/wiki/develop/api-v2/openapi/error/error.html`。
可参考本组 11.2 公共错误码中的 `304005 EMBED_LIMIT embed 长度超限` 等条目。

---

## 12. 官方文档未提供的内容清单

以下条目为本组 25 个页面（另加 1 个补充页）范围内**确实未出现**的内容，按要求标注「官方文档未提供」，未做任何推测或补全：

1. **`GET /app/getAppAccessToken`**：官方文档标注的方法为 **POST**，未提供 GET 方式的说明。
2. **`https://api.sgroup.qq.com` 域名**：本组官方页面给出的统一请求地址为 `https://api.bot.qq.com`，未出现 sgroup 域名。
3. **`User-Agent` 约定**：本组官方页面未出现任何 User-Agent 相关要求。
4. **`X-Union-Appid` 特殊请求头**：本组官方页面未出现该头；仅在公共错误码文本中出现过 `X-Uin`（错误码 503008），但无请求头用法定义。
5. **调用 OpenAPI 时的请求体 `sign` 签名算法**：官方 sign.html 只描述「回调请求验签（Ed25519）」，未给出调用 OpenAPI 时对请求体做签名的规则。
6. **OAuth 授权码流程细节**：仅有「AppSecret 用于在 oauth 场景进行请求签名的密钥」一句，未给出 authorize/token 端点、scope 列表、签名步骤。
7. **Token（已弃用）的详细差异项**：格式、有效期、刷新机制、使用位置均未提供（仅给出「可用于调用开放接口的鉴权」与「已废弃」两点）。
8. **单聊/群聊 messages 接口的复合 `content` JSON 字符串结构**（含 text/attachments/ark/markdown/embed/media/image/emoji 子字段）：官方请求体为平铺字段（content/markdown/media/keyboard），未提供此类复合结构。相关子类型仅在「接收侧 message_type / attachments」与 ark/embed 独立章节给出。
9. **`file_data` 直传字段**：上传接口官方请求体未包含该字段，仅支持 URL 上传与分片上传合并。
10. **流式消息的具体发送节奏数值**：未给出「片间最小间隔毫秒数 / 每秒最多下发片数 / 单次切片最大字符数」；仅给出 50 QPS、`remain_msg_len`、index 递增、input_mode/input_state 语义。
11. **`GROUP_AT_MESSAGE_CREATE` / `C2C_MESSAGE_CREATE` 事件体字段结构**：事件页不在本组页面清单内，仅覆盖了回复所需的 msg_id/event_id 取用说明。
12. **EmojiType 数值表与 Emoji 完整 id 列表**：官方指向 `openapi/emoji/model.html`，该页不在本组清单内。
13. **按钮 `action.at_bot_show_channel_list` / `click_limit` 的现行状态**：官方标注为「已弃用」，未给出替代字段。
14. **未认证/企业认证/个人认证在单聊的「每日上限」以外的总量限制**：仅给出每用户/每群 1000 条/天。
15. **`40093002 超过今天发送文件容量上限` 的具体容量数值**：仅给出错误文案，未给出数字。
16. **消息审核（MESSAGE_AUDIT / MessageAudited）的完整事件订阅流程**：本组仅给出 MessageAudited 对象字段（9.8），审核事件订阅细节在其它页面。
17. **`@全部成员` 权限的具体申请方式**：仅说明「需要机器人拥有发送 @全部成员 消息的权限」，未给出申请入口。
18. **接口 `GET /app/getAppAccessToken` 的 QPS 限制数字**：未给出，仅有错误码 100001 Too many requests。

---

## 附录 A：接口索引（本组覆盖的全部端点）

| # | 方法 | 路径 | 说明 | 来源页面 |
|---|---|---|---|---|
| 1 | POST | https://api.bot.qq.com/app/getAppAccessToken | 获取 access_token | access-token.html / api-use.html |
| 2 | POST | /v2/users/{user_openid}/messages | 发送单聊消息 | users_messages.post.html |
| 3 | POST | /v2/groups/{group_openid}/messages | 发送群聊消息 | groups_messages.post.html |
| 4 | POST | /v2/users/{user_openid}/stream_messages | 流式发送单聊消息 | stream_messages.post.html |
| 5 | DELETE | /v2/users/{user_openid}/messages/{message_id} | 撤回单聊消息 | users delete |
| 6 | DELETE | /v2/groups/{group_openid}/messages/{message_id} | 撤回群聊消息 | groups delete |
| 7 | POST | /v2/users/{user_openid}/files | 单聊富媒体上传 | users_files.post.html |
| 8 | POST | /v2/groups/{group_openid}/files | 群聊富媒体上传 | groups_files.post.html |
| 9 | POST | /v2/users/{user_id}/upload_prepare | 单聊富媒体预上传 | users prepare |
| 10 | POST | /v2/users/{user_id}/upload_part_finish | 单聊分片上传完成 | users part_finish |
| 11 | POST | /v2/groups/{group_id}/upload_prepare | 群聊富媒体预上传 | groups prepare |
| 12 | POST | /v2/groups/{group_id}/upload_part_finish | 群聊分片上传完成 | groups part_finish |
| 13 | PUT | /channels/{channel_id}/messages/{message_id}/reactions/{type}/{id} | 机器人发表表情表态 | emoji.html |
| 14 | DELETE | /channels/{channel_id}/messages/{message_id}/reactions/{type}/{id} | 删除表情表态 | emoji.html |
| 15 | GET | /channels/{channel_id}/messages/{message_id}/reactions/{type}/{id} | 获取表情表态用户列表 | emoji.html |
| 16 | PUT | /interactions/{interaction_id} | 回应按钮交互（INTERACTION_CREATE） | msg-btn.html |

---

*本文件由 QQ 机器人开放平台官方文档（https://bot.q.qq.com/wiki）抓取整理，抓取日期 2026-09-26。所有字段表、JSON 样例、错误码、频率限制数字均逐字取自官方文档；未提供项已在第 12 章逐条标注。*
