# 示例插件详解

随应用分发的示例插件在 `assets/plugins/demo_plugin/`，
装到手机上之后也能在「插件 → 文件」里直接读。
它同时是**可运行的示例**与**协议参考实现**。

## 它做了什么

1. 启动后读取配置、上次的状态与数据目录，回 `ready` 完成握手；
2. 每收到一条群聊 / 单聊消息就记一行日志，并把累计条数持久化；
3. 消息以配置里的**触发前缀**（默认 `#hi`）开头时，请求主进程代发一句问候；
4. 收到 `shutdown` 时把统计写入自己的数据目录再退出。

## 清单

```json title="plugin.json"
{
  "id": "demo_plugin",
  "name": "示例插件",
  "version": "1.1.0",
  "entry": "main.py",
  "protocol_version": 2,
  "events": ["GROUP_AT_MESSAGE_CREATE", "C2C_MESSAGE_CREATE"],
  "enabled_by_default": false,
  "config": [
    { "key": "trigger",  "label": "触发前缀",   "type": "string",  "default": "#hi", "required": true },
    { "key": "greeting", "label": "回复内容",   "type": "text",    "default": "你好，我是由 Python 插件发出的回复。", "required": true },
    { "key": "log_every_message", "label": "记录每条消息", "type": "boolean", "default": true },
    { "key": "note",     "label": "备注",       "type": "text",    "default": "" }
  ]
}
```

几个值得注意的点：

- `events` 只列了两个消息事件——示例插件不关心入群、好友变更，
  声明范围能让它不被那些事件唤醒；
- `enabled_by_default` 是 `false`：**新插件不该自动获得处理用户消息的能力**；
- 四个配置项刻意覆盖了 `string` / `text` / `boolean` 三种控件，
  装上就能看到配置表单长什么样。

## 代码逐段看

### 通信封装

```python title="main.py"
class Host:
    def send(self, kind, payload=None, request_id=None):
        message = {"type": kind, "payload": payload or {}}
        if request_id:
            message["id"] = request_id
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()
```

封装成一个类而不是散落的 `print`，有两个实际好处：

1. **`ensure_ascii=False`**：中文不会被转义成 `\uXXXX`，日志里能直接读；
2. **`flush()` 只写一次**：主进程虽然用 `PYTHONUNBUFFERED=1` 启动本进程，
   但显式 flush 让行为不依赖那个环境变量——插件被换一种方式启动时也不会静默丢消息。

### 初始化

```python
def on_init(host, payload):
    host.plugin_id = payload.get("plugin_id")
    host.config = payload.get("config") or {}
    host.state = payload.get("state") or {}
    host.data_dir = payload.get("data_dir")
    host.handled = int(host.state.get("handled", 0))
    host.send("ready")            # ★ 必须回，否则 20 秒后进程被结束
```

`config` 已经与清单里的 `default` 合并过，因此这里直接读就行。

### 处理事件

```python
def on_event(host, envelope, payload):
    event = payload.get("event") or {}
    bot_id = payload.get("bot_id")
    # ★ scope / conversation_id / content / sender 都在 event 里，不在 payload 顶层。
    #   payload 顶层只有 t / bot_id / protocol_version / event 四个键。
    scope = event.get("scope")
    conversation_id = event.get("conversation_id")
    content = event.get("content") or ""
    sender = (event.get("sender") or {}).get("name") or "未知用户"

    host.handled += 1
    host.set_state({"handled": host.handled})     # 顶层合并，只发变化的部分

    if host.config.get("log_every_message", True):
        host.log("收到消息（%s / %s）：%s" % (scope, sender, content))

    trigger = (host.config.get("trigger") or "").strip()
    if not trigger or not content.strip().startswith(trigger):
        return

    if not event.get("can_reply", False):         # ★ 窗口与次数由主程序算好
        host.log("被动回复窗口已关闭，跳过回复", "warn")
        return

    host.reply(
        request_id=envelope.get("id"),
        bot_id=bot_id,
        scope=scope,
        conversation_id=conversation_id,
        text=host.config.get("greeting") or "你好",
        msg_id=event.get("message_id"),           # ★ 回复消息用 msg_id
    )
```

::: warning 最常见的两个错误

- 从 `payload` 顶层取 `scope` / `content`。它们都在嵌套的 `event` 对象里，
  写错了不会报错，只会一直拿到 `None`——表现为「插件收到事件了但什么都没做」。
- 把 `host.reply()` 写成 `print()`。`print` 只会进日志，不会发出任何消息。

:::

三个关键点：

| 点 | 为什么 |
| --- | --- |
| 先检查 `can_reply` | 被动回复窗口（群聊 5 分钟、单聊 60 分钟）与次数上限（5 次 / 4 次）由主程序算好。插件自己算会出现两套实现，且它拿不到准确的事件接收时刻 |
| `msg_id` 而不是 `event_id` | 回复**消息**必须用 `msg_id`；两者互斥，都传会被官方拒绝 |
| 带 `bot_id` | 多机器人场景下，不带就会「A 机器人的回复发到 B 的会话里」 |

### 主循环：单个事件出错不要退出

```python
try:
    if kind == "init":            on_init(host, payload)
    elif kind == "event":         on_event(host, envelope, payload)
    elif kind == "config_update": on_config_update(host, payload)
    elif kind == "ping":          host.send("pong", {}, envelope.get("id"))
    elif kind == "shutdown":      on_shutdown(host); break
    else:                         host.log("未知消息类型：%s" % kind, "warn")
except Exception as error:
    host.log("处理 %s 时出错：%s\n%s" % (kind, error, traceback.format_exc()), "error")
```

外层的 `try/except` 是刻意加的：**单个事件处理失败不该让整个插件退出**。
进程一退，主程序就会记一次崩溃并（在预算内）重启它，
代价远大于跳过这一条消息。

未知的 `type` 只记日志不退出——主程序将来新增消息类型时，旧插件不该因此崩溃。

### 收尾

```python
def on_shutdown(host):
    if host.data_dir:
        with open(os.path.join(host.data_dir, "stats.json"), "w", encoding="utf-8") as fh:
            json.dump({"handled": host.handled}, fh, ensure_ascii=False)
```

用 `data_dir` 而不是相对路径：插件目录只放代码，运行时数据写在自己的数据目录里。
这样「重装插件」不会误删用户数据。

## 自己试一遍

1. 装示例插件 → 加一个测试群 → 发 `#hi`，应该收到问候；
2. 改「配置」里的回复内容，再发一次——**不需要重启插件**，
   运行中改配置会立刻通过 `config_update` 下发；
3. 把 `log_every_message` 关掉，再发几条消息，日志会安静下来；
4. 点「停止」再「启动」，观察日志里的「已停止」与「已就绪」两条；
5. 故意在 `on_event` 里写一句 `1 / 0`，保存并重启——插件不会死，
   错误会出现在日志里（这就是外层 `try/except` 的作用）。
