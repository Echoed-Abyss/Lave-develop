# 端点索引

全部路径逐字取自官方 api-v2 文档。唯一官方统一域名是 `https://api.bot.qq.com`
（旧版文档里的 `api.sgroup.qq.com` 与沙箱域名不在本项目使用范围内）。

::: info 命名约定

- `{user_openid}` / `{group_openid}` 是单聊、群聊场景的用户与群标识；
- `{user_id}` / `{group_id}` 是**富媒体预上传与分片完成**接口用的标识，
  官方参数名如此，与 openid **不是同一个东西**，不要互相替换。

:::

## 鉴权

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/app/getAppAccessToken` | 用 `appId` + `clientSecret` 换 `access_token`（2 小时）。**失败时 HTTP 仍返回 200**，必须读响应体的 `code` |
| GET | `/users/@me` | 机器人自身资料，**唯一的头像来源**（`avatar` 字段） |

## WSS 接入点

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/gateway` | 通用接入点，2 QPM |
| GET | `/gateway/bot` | 带分片信息的接入点，额外返回 `session_start_limit`。**本项目用这个** |

返回的 `url` **必须使用**，不要硬编码域名。

## 单聊（C2C）

| 方法 | 路径 | 限频 |
| --- | --- | --- |
| POST | `/v2/users/{user_openid}/messages` | 100 QPS |
| POST | `/v2/users/{user_openid}/stream_messages` | 50 QPS |
| DELETE | `/v2/users/{user_openid}/messages/{message_id}` | 10 QPS |
| POST | `/v2/users/{user_openid}/files` | 50 QPS |
| POST | `/v2/users/{user_id}/upload_prepare` | 10 QPS |
| POST | `/v2/users/{user_id}/upload_part_finish` | 10 QPS |

## 群聊（Group）

| 方法 | 路径 | 限频 |
| --- | --- | --- |
| POST | `/v2/groups/{group_openid}/messages` | 100 QPS |
| DELETE | `/v2/groups/{group_openid}/messages/{message_id}` | 10 QPS |
| POST | `/v2/groups/{group_openid}/files` | 50 QPS |
| POST | `/v2/groups/{group_id}/upload_prepare` | 10 QPS |
| POST | `/v2/groups/{group_id}/upload_part_finish` | 10 QPS |

::: warning 单聊与群聊的上传接口相互独立

同一份文件不能跨场景复用：往群聊上传得到的 `file_info` 只能用于群聊消息。

:::

## 互动与表情

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| PUT | `/interactions/{interaction_id}` | 回应消息按钮 / 快捷菜单。**同一 id 只能回应一次**，不回应客户端会一直 loading |
| PUT/DELETE/GET | `/channels/{channel_id}/messages/{message_id}/reactions/{type}/{id}` | 表情表态（频道体系） |
| GET | `/users/@me/guilds` | 机器人加入的频道列表（本项目不处理频道） |

## 抓取域名

| 域名 | 用途 |
| --- | --- |
| `api.bot.qq.com` | 官方 OpenAPI |
| `q.qlogo.cn` / `thirdqq.qlogo.cn` | 头像 CDN（`/qqapp/{appid}/{openid}/{size}`），**未在官方文档中出现**，见[头像](../guide/troubleshooting.md#头像显示的是灰色默认头像) |

## 本项目未实现的端点

| 能力 | 状态 |
| --- | --- |
| 流式消息（`stream_messages`） | 端点已定义，未实现 |
| 频道（Guild）相关全部端点 | 未实现：本项目以单聊 / 群聊为核心 |
| 语音 / 视频相关 | 未实现 |
