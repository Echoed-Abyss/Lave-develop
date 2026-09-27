# 通信协议

主进程与插件之间是 **stdin / stdout 上的 JSON Lines**：一行一条 JSON 对象。

选它而不是更严格的长度头协议，理由很实际：`stdout` 天然按行分帧，
插件作者用 `print` 就能调试，不需要任何序列化框架。

## 信封

每条消息都是同一个信封：

```json
{"type": "<消息类型>", "id": "<可选，请求 id>", "payload": { … }}
```

| 字段 | 说明 |
| --- | --- |
| `type` | 消息类型，见下 |
| `id` | 请求 id。主进程投递事件时带上，插件回复时**原样带回**即可与原事件对应 |
| `payload` | 载荷，结构随类型而定 |

!!! note "非 JSON 的 stdout 输出不会丢"

    插件里 `print("调试")` 输出的是非 JSON 行，主程序会把它当作一条
    **info 级日志**收进「日志」页，而不是丢弃。这是刻意保留的调试手段。

    `stderr` 的每一行同理，按 error 级收进日志。

## 消息类型总表

| 类型 | 方向 | 用途 |
| --- | --- | --- |
| `init` | 主进程 → 插件 | 下发配置、状态、数据目录、平台能力 |
| `ready` | 插件 → 主进程 | **握手完成**，可以接收事件了 |
| `event` | 主进程 → 插件 | 投递一个 QQ 事件 |
| `reply` | 插件 → 主进程 | 请求主进程代发消息 |
| `log` | 插件 → 主进程 | 写一条日志 |
| `state_set` | 插件 → 主进程 | 持久化状态（顶层合并） |
| `state_remove` | 插件 → 主进程 | 删除若干状态键 |
| `config_update` | 主进程 → 插件 | 配置在运行中被修改 |
| `ping` | 双向 | 探活 |
| `pong` | 双向 | 探活应答 |
| `shutdown` | 主进程 → 插件 | 优雅停止 |

---

## `init`（主进程 → 插件）

进程启动后主进程立刻下发，插件据此完成初始化。

```json
{
  "type": "init",
  "payload": {
    "plugin_id": "demo_plugin",
    "protocol_version": 2,
    "manifest": { … },            // 完整清单，见 manifest.md
    "config": { "trigger": "#hi" },  // 默认值 + 用户保存值，已合并
    "state": { "handled": 41 },      // 上次持久化的状态
    "data_dir": "/data/…/plugins/demo_plugin/data",
    "capability": {
      "platform": "android",
      "python": "/data/app/…/lib/arm64-v8a/libpylauncher.so"
    }
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `config` | 已经与清单里的 `default` 合并过，插件不需要自己处理缺省值 |
| `state` | 插件上次通过 `state_set` 存下的内容；首次运行为 `{}` |
| `data_dir` | **插件专属的可写目录**。目录一定存在，可直接往里写文件 |
| `capability.python` | 实际使用的解释器路径（排障用） |

!!! danger "收到 `init` 后必须回 `ready`"

    主进程在 **20 秒**内没收到 `ready` 就会强杀该进程并记为崩溃。
    这是刻意的：一个连初始化都完不成的插件，留在内存里只会继续堆积事件。

---

## `ready`（插件 → 主进程）

```json
{"type": "ready", "payload": {}}
```

握手完成的标志。**只有收到它，主进程才把状态标为「运行中」并开始投递事件。**
在此之前到达的事件不会被投递（避免插件在自身初始化尚未完成时被唤醒）。

---

## `event`（主进程 → 插件）

```json
{
  "type": "event",
  "id": "evt-12",
  "payload": {
    "t": "GROUP_AT_MESSAGE_CREATE",   // 事件类型
    "bot_id": "102810595",            // 触发它的机器人
    "protocol_version": 2,            // 协议版本
    "event": { … }                    // 归一化后的事件内容，见下
  }
}
```

**`id` 是回复时要带回去的请求 id**（见 `reply`）。

### 事件内容：消息类

对 `GROUP_AT_MESSAGE_CREATE` / `C2C_MESSAGE_CREATE`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `scope` | string | `group` 或 `c2c` |
| `conversation_id` | string | 会话标识：群聊为 `group_openid`，单聊为 `user_openid` |
| `message_id` | string | 官方消息 id（消息事件的 `d.id`）。**回复时用它** |
| `content` | string | 文本内容。群聊场景官方**已去除 @前缀**，不要再自己剥 |
| `timestamp` | string | ISO8601 |
| `sender.id` | string | 发送者在会话内的标识 |
| `sender.name` | string | 昵称（**官方经常为空**，官方示例里就是空字符串） |
| `sender.role` | string? | 群内角色：`owner` / `admin` / `member` |
| `sender.is_bot` | bool | 是否机器人 |
| `attachments` | array | 附件，见下 |
| `can_reply` | bool | **现在还能不能被动回复**（主程序已算好窗口与次数） |
| `remaining_replies` | int | 本条消息还剩几次被动回复 |

!!! tip "为什么要有 `can_reply`"

    被动回复的窗口（群聊 5 分钟 / 单聊 60 分钟）与次数上限（5 / 4 次）
    都由主程序在收到事件时算好。插件不必自己记时间戳，
    也不该自己算——那会让「窗口判定」出现两套实现。

附件（`attachments[]`）：

| 字段 | 说明 |
| --- | --- |
| `url` | 下载地址（**预签名，会过期**） |
| `filename` / `content_type` / `size` | 文件信息 |
| `width` / `height` | 图片尺寸 |
| `voice_wav_url` | 语音转 WAV 的地址 |
| `asr_text` | 语音的机器识别文本（仅供参考） |

### 事件内容：生命周期类

以 `t` 区分，共有字段是 `t` / `bot_id` / `seq`，另有：

| 事件 | 附加字段 |
| --- | --- |
| `GROUP_ADD_ROBOT`、`GROUP_DEL_ROBOT` | `group_openid`、`op_member_openid` |
| `GROUP_MEMBER_ADD`、`GROUP_MEMBER_REMOVE` | `group_openid`、`member_openid`、`user_openid` |
| `GROUP_JOIN_REQUEST` | `group_openid`、`join_request_id`、`username`、`risk_tips`、`apply_source` |
| `FRIEND_ADD` | `openid`、`scene`、`scene_param` |
| `FRIEND_DEL` | `openid` |
| `C2C_MSG_RECEIVE` / `C2C_MSG_REJECT` / `GROUP_MSG_RECEIVE` / `GROUP_MSG_REJECT` | `target`、`enabled`、`openid`、`group_openid` |
| `INTERACTION_CREATE` | `interaction_id`、`interaction_type`、`requires_ack`、`group_openid`、`user_openid`、`button_data` |
| 未建模的事件 | 只有公共字段（`t` / `bot_id` / `seq`），日志里会记一条「未识别事件」 |

!!! note "载荷是归一化后的结构，不是官方原始 JSON"

    这是刻意的：官方字段改名不会直接打断插件，插件也无法依赖内部实现细节。
    需要原始 `d` 的场景（比如官方新加字段）目前不支持——
    如果你的插件需要它，请提 issue 说明用途。

---

## `reply`（插件 → 主进程）

请求主进程代发一条消息。**插件永远拿不到 `access_token`**，这是唯一的发送通道。

```json
{
  "type": "reply",
  "id": "evt-12",
  "payload": {
    "bot_id": "102810595",
    "conversation_id": "B2C3D4…",
    "scope": "group",
    "text": "你好",
    "msg_id": "ROBOT1.0_…"
  }
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `bot_id` | ✅ | 要由哪个机器人发出。**多机器人场景必须传对**，否则会出现「A 机器人的回复发到 B 的会话里」 |
| `conversation_id` | ✅ | 目标会话 |
| `text` | ✅ | 文本内容 |
| `scope` | — | `group` 或 `c2c`，缺省按 `c2c` |
| `msg_id` | — | 要回复的消息 id。取自事件里的 `message_id` |
| `event_id` | — | 要响应的事件 id。**与 `msg_id` 二选一** |

### `msg_id` 与 `event_id` 只能二选一

官方把被动消息分成两条互斥路径：

| 路径 | 用什么 | 取值 |
| --- | --- | --- |
| 回复用户消息 | `msg_id` | 事件里的 `message_id` |
| 响应事件（按钮回调、入群、加好友…） | `event_id` | 事件最外层的 `event_id` |

**两个都传会被官方拒绝**。本项目对这种情况的处理是：保留 `msg_id`、丢弃
`event_id`，同时在日志里记一条 warn——插件作者能据此知道自己多传了字段，
而不是收到一个语焉不详的失败。

两个都不传即为**主动消息**：受独立频控约束，且用户可以在 QQ 客户端关闭接收。

---

## `log`（插件 → 主进程）

```json
{"type": "log", "payload": {"level": "info", "message": "处理完成", "tag": "可选"}}
```

`level` 取 `debug` / `info` / `warn` / `error`。

!!! warning "日志有每秒行数上限"

    默认 40 行/秒，超出会被丢弃并计数（插件详情里能看到「丢弃日志 N 行」）。
    这是为了保护主程序：每一行日志都会触发界面刷新并排队写盘，
    死循环 `print` 几千行足以让界面卡住几秒。

---

## `state_set` / `state_remove`（插件 → 主进程）

```json
{"type": "state_set", "payload": {"state": {"handled": 42}}}
{"type": "state_remove", "payload": {"keys": ["tmp"]}}
```

`state_set` 的语义是**顶层合并**，不是整体替换：插件可以只发变化的那几个键。
这样插件不必记住主程序维护的其它字段，也不会因为只发一部分而把别的键抹掉。

状态会在下次 `init` 时原样下发，因此**可以跨重启保存计数、会话映射等数据**。
存储量请保持在 KB 级——它最终会落进主程序的 JSON 文档。

---

## `config_update`（主进程 → 插件）

```json
{"type": "config_update", "payload": {"plugin_id": "demo_plugin", "config": { … }}}
```

用户在应用里保存配置时下发（**仅当插件正在运行**）。收到后应重新读取 `payload.config`，
不需要重启。

---

## `ping` / `pong`（双向）

主进程每个心跳周期发一次 `ping`，插件应回 `pong`：

```python
elif kind == "ping":
    send("pong")
```

连续 **3 次**未收到 `pong`（约 90 秒完全静默）即判定为**卡死**：
主进程会记一条 error、把状态标为「无响应」、并结束该进程。

取 3 次而不是 1 次：插件正常处理一条消息也可能占住事件循环几百毫秒，
阈值太紧会误杀；而 90 秒的完全静默基本只可能是死锁或长时间阻塞调用。

插件也可以主动发 `ping`，主进程会回 `pong`。

---

## `shutdown`（主进程 → 插件）

```json
{"type": "shutdown", "payload": {}}
```

收到后应尽快退出。主进程会等 **3 秒**，超时则 `SIGKILL`。

退出前适合做收尾（把统计写入 `data_dir`、关闭文件句柄等）。

---

## 时序

=== "启动"

    ```
    主进程                          插件
      │── 创建进程 ─────────────────▶│
      │── init ─────────────────────▶│  读配置/状态/数据目录
      │◀──────────────── ready ──────│  ★ 只有到这里才算「运行中」
      │── ping ─────────────────────▶│
      │◀──────────────── pong ───────│
      │── event ────────────────────▶│
      │◀──────────────── reply ──────│  请求代发消息
      │◀──────────────── log ────────│
    ```

    20 秒内没等到 `ready` → 强杀进程并记为崩溃。

=== "正常停止"

    ```
      │── shutdown ─────────────────▶│
      │                              │  收尾
      │◀──────────────── 进程退出 ────│  ★ 不算崩溃
    ```

    主动停止**不计入崩溃次数**。这曾经是个缺陷：早期实现把主动停止也记成崩溃，
    用户每点一次「停止」，插件就多一次「已崩溃」。

=== "卡死与自动重启"

    ```
      │── ping ─────────────────────▶│
      │  （无响应）                    │
      │── ping ─────────────────────▶│
      │  （无响应）                    │
      │── ping ─────────────────────▶│
      │  （无响应）→ 判定卡死          │
      │── SIGKILL ──────────────────▶│
      │  记一次崩溃 + 退避重启（最多 2 次）
    ```

## 版本历史

| 版本 | 变更 |
| --- | --- |
| **1** | 初版：`init` / `ready` / `event` / `reply` / `log` / `shutdown` / `ping` / `pong` |
| **2** | `init` 增加 `config` / `state` / `data_dir` / `protocol_version`；新增 `state_set`、`state_remove`、`config_update`；去掉嵌套事件体里那份重复的 `protocol_version`（版本只保留在 `event` 的 `payload` 顶层） |

插件在 `plugin.json` 里用 `protocol_version` 声明针对哪一版编写，见[清单](manifest.md#protocol_version)。

## 未知消息类型

插件应对未知的 `type` **记录并忽略**，而不是退出——主程序将来可能新增消息类型，
旧插件不该因此崩溃。同理，主进程对插件发来的未知 `type` 也只会忽略。

## 调试建议

1. 先用 `print` 打日志，确认事件确实到达了；
2. 出错时把 `traceback.format_exc()` 一起打进日志——跨进程的异常栈在手机上没有别的办法看到；
3. 单个事件处理失败不要退出进程（见[最佳实践](best-practices.md)）。
