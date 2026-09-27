# 五分钟上手

目标：跑起来一个会回复消息的插件，并看到它的日志。

## 1. 装示例插件

打开应用 →「插件」页 → 右上角「安装示例插件」。它会：

- 把内置的示例插件复制到插件目录；
- 自动把开关打开。

之后卡片上会出现「配置」「文件」「导出」等按钮。回到上一页再进来，
状态应该在几秒内从「启动中」变成**运行中**。

!!! tip "如果一直停在「启动中」"

    插件进程起来后必须回一条 `ready`，主程序才认为握手完成。
    20 秒内没收到就会结束该进程并记为崩溃，`lastError` 里会写明原因。
    最常见的原因是 `main.py` 导入阶段抛了异常。

## 2. 看它工作

给机器人发一条消息（群聊里 @ 它，或单聊）：

- 「日志」页会出现 `收到消息（group / 小明）：…`；
- 发 `#hi`（示例插件的默认触发前缀）会收到一句问候。

这条问候是**插件请求主进程代发**的——插件自己不持有任何凭证。

## 3. 改一行

插件卡片 →「文件」→ 点 `main.py` → 改 `on_event` 里的问候语 → 保存。

!!! warning "改完要重启插件"

    保存只是写回磁盘。正在跑的插件进程加载的还是旧代码，
    因此改完要在卡片上点「停止」再「启动」。

## 4. 加一个配置项

插件卡片 →「文件」→ 打开 `plugin.json`，在 `config` 数组里加一项：

```json
{
  "key": "reply_delay_ms",
  "label": "回复延迟（毫秒）",
  "type": "integer",
  "default": 0,
  "description": "为了让回复看起来不像机器人，可以加一点延迟。"
}
```

保存 → 重启插件 → 点「配置」，表单里就会出现这一项。

配置项是**插件自己声明**的：用户不需要知道配置文件存在哪，
插件也不需要自己解析命令行或环境变量。运行中改配置会立刻下发，不会重启进程。

## 5. 从零写一个

最小可用插件的全部内容：

```json title="plugin.json"
{
  "id": "my_first_plugin",
  "name": "我的第一个插件",
  "version": "1.0.0",
  "entry": "main.py",
  "events": ["GROUP_AT_MESSAGE_CREATE", "C2C_MESSAGE_CREATE"],
  "protocol_version": 2
}
```

```python title="main.py"
import json
import sys

def send(kind, payload=None):
    sys.stdout.write(json.dumps({"type": kind, "payload": payload or {}}) + "\n")
    sys.stdout.flush()

for line in sys.stdin:                    # 一行一条 JSON
    message = json.loads(line)
    kind = message.get("type")
    payload = message.get("payload") or {}

    if kind == "init":                    # ① 初始化
        send("ready")                     # ② 必须回 ready，否则握手超时
    elif kind == "event":                 # ③ 收到事件
        event = payload.get("event") or {}
        send("log", {"level": "info", "message": "收到：" + (event.get("content") or "")})
    elif kind == "ping":                  # ④ 探活，必须回 pong
        send("pong")
    elif kind == "shutdown":              # ⑤ 优雅退出
        break
```

把这两个文件放进插件目录，或把它们组成插件包 JSON 从剪贴板导入（见下）。

## 6. 怎么把它装到手机上

调试用的机器在电脑上写代码，装进手机有三条路（Android 11 起应用私有目录
不再对文件管理器可见，所以没有「复制文件进去」这条路）：

=== "从剪贴板导入（推荐）"

    把插件打成插件包 JSON 复制，然后在插件页点右下角「导入插件」：

    ```json
    {
      "lave_plugin_bundle": 1,
      "id": "my_first_plugin",
      "files": {
        "plugin.json": "{\"id\":\"my_first_plugin\", …}",
        "main.py": "import json\nimport sys\n…"
      }
    }
    ```

    也可以直接在手机的「插件 → 文件」里新建文件、粘贴内容。

=== "应用内手写"

    先在插件页装一次示例插件，再去「文件」里把所有内容改成你的。
    好处是马上能跑，坏处是手机上的编辑器不好用。

=== "从示例导出"

    装一次示例插件 → 点「导出」把 JSON 复制到电脑 →
    在电脑上改好 → 复制回手机 → 导入并改掉 `id`。

## 下一步

- [清单 plugin.json](manifest.md)：全部字段
- [通信协议](protocol.md)：每条消息的确切结构
- [最佳实践](best-practices.md)：别人踩过的坑
