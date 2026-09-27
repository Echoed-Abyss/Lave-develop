# 事件订阅 intents

intents 是一个**位掩码**：想要哪一类事件，就把对应位在 `Identify` 的
`intents` 字段里置位（多位用位或合并）。

!!! danger "读这一页之前先记住官方这句话"

    除了 `GUILDS`，`PUBLIC_GUILD_MESSAGES`，`GUILD_MEMBERS` 事件是基础的事件，
    默认有权限订阅之外，其他的特殊事件，都需要经过申请才能够使用，
    **如果在鉴权的时候传递了无权限的 `intents`，`websocket` 会报错，并直接关闭连接。**

注意后果是**关闭连接**，不是「收不到那一类事件」。所以乱开位的代价是「机器人彻底连不上」。

## 全表

| Intent | 位 | 值 | 覆盖事件 | 权限 |
| --- | --- | --- | --- | --- |
| `GUILDS` | `1 << 0` | 1 | `GUILD_CREATE` / `GUILD_UPDATE` / `GUILD_DELETE` / `CHANNEL_*` | 基础，默认有权限 |
| `GUILD_MEMBERS` | `1 << 1` | 2 | `GUILD_MEMBER_ADD` / `GUILD_MEMBER_UPDATE` / `GUILD_MEMBER_REMOVE` | 基础，默认有权限 |
| `GUILD_MESSAGES` | `1 << 9` | 512 | `MESSAGE_CREATE` / `MESSAGE_DELETE`（官方注明「仅私域机器人可设置」） | 需申请 |
| `GUILD_MESSAGE_REACTIONS` | `1 << 10` | 1024 | `MESSAGE_REACTION_ADD` / `MESSAGE_REACTION_REMOVE` | 需申请 |
| `DIRECT_MESSAGE` | `1 << 12` | 4096 | `DIRECT_MESSAGE_CREATE` / `DIRECT_MESSAGE_DELETE` | 需申请 |
| **`GROUP_AND_C2C_EVENT`** | **`1 << 25`** | **33554432** | `C2C_MESSAGE_CREATE`、`FRIEND_ADD`、`FRIEND_DEL`、`C2C_MSG_REJECT`、`C2C_MSG_RECEIVE`、`GROUP_AT_MESSAGE_CREATE`、`GROUP_ADD_ROBOT`、`GROUP_DEL_ROBOT`、`GROUP_MSG_REJECT`、`GROUP_MSG_RECEIVE` | 需申请 |
| `INTERACTION` | `1 << 26` | 67108864 | `INTERACTION_CREATE` | 需申请 |
| `MESSAGE_AUDIT` | `1 << 27` | 134217728 | `MESSAGE_AUDIT_PASS` / `MESSAGE_AUDIT_REJECT` | 需申请 |
| `FORUMS_EVENT` | `1 << 28` | 268435456 | `FORUM_THREAD_*` / `FORUM_POST_*` / `FORUM_REPLY_*`（官方注明「仅私域」） | 需申请 |
| `AUDIO_ACTION` | `1 << 29` | 536870912 | `AUDIO_START` / `AUDIO_FINISH` / `AUDIO_ON_MIC` / `AUDIO_OFF_MIC` | 需申请 |
| `PUBLIC_GUILD_MESSAGES` | `1 << 30` | 1073741824 | `AT_MESSAGE_CREATE` / `PUBLIC_MESSAGE_DELETE` | 基础，默认有权限 |
| `GROUP_MEMBER_EVENT` ⚠️ | `1 << 24` | 16777216 | `GROUP_MEMBER_ADD` / `GROUP_MEMBER_REMOVE` / `GROUP_JOIN_REQUEST` | **见下** |

### ⚠️ 关于 `GROUP_MEMBER_EVENT (1<<24)`

官方文档在这里**自相矛盾**：这一位**没有出现在 `event-emit.html` 的 intents 清单里**，
只出现在各事件页（`group_member_add.html` 等）的「Intent」字段中。

也就是说：按「唯一权威清单」看它不该存在，按事件页看它必须开。
本项目的处理是**默认关闭 + 界面标红提示**——它是最有可能触发
「传递了无权限的 intents → 连接被关闭」的一位。

## 本项目的默认值

**默认只订阅 `GROUP_AND_C2C_EVENT (1<<25)`**（掩码值 `33554432`）。

这不是保守，而是必须：它覆盖了单聊消息、群 @消息、机器人进出群、好友增删、
主动消息开关变更——「机器人能用」的最小集合。其余位在「设置 → 事件订阅范围」
逐个开启。

| 可选位 | 项目 | 说明 |
| --- | --- | --- |
| `INTERACTION` | ✅ 在官方清单中 | 打开后能收到按钮点击、快捷菜单等互动事件 |
| `GROUP_MEMBER_EVENT` | ⚠️ **不在官方清单中** | 打开后才收得到群成员进退、加群申请 |

## 自动降级

被网关以 `4013`（无效的 intent）或 `4014`（intent 无权限）拒绝时，
主程序会：

1. 去掉全部可选位，只保留必需位；
2. 用降级后的掩码重试一次；
3. **把降级结果写回设置**（否则下次冷启动又用回原掩码，再失败一遍）；
4. 记一条 warn 提示去设置页确认。

只有连必需位都被拒才判定为终态并停止重连。

!!! note "为什么不停下来让用户自己改"

    官方对 4013 / 4014 标注「两个都不可重试」，但那是指**用同样的 intents 重试无意义**。
    如果因此直接停止重连，用户看到的是「连不上且永远收不到消息」，
    而实际上只需要去掉无权限的那几位就能恢复。

## 组合方式

官方示例（`GUILDS (1<<0)` 与 `PUBLIC_GUILD_MESSAGES (1<<30)` 合并）：

```
0 | 1 << 30 | 1 << 1        →  订阅 PUBLIC_GUILD_MESSAGES + GUILD_MEMBERS
```

本项目的掩码由 `QqIntents` 统一计算，界面上显示的是十进制值
（例如只订必需位时显示 `33554432`）。

## 权限被取消会怎样

官方明确：**权限被取消后，当前连接不报错但收不到对应事件，重连才会报错**。

因此「昨天正常、今天收不到」的第一件事就是查平台权限，
而不是查代码——这一点在[故障排查](../guide/troubleshooting.md#机器人连上了但收不到任何消息)里也强调了。
