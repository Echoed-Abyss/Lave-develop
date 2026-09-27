# 最佳实践

这一页是「别人踩过的坑」的汇总。每条都对应一个具体的故障，而不是泛泛的原则。

## 必须做的

### 收到 `init` 后一定要回 `ready`

```python
if kind == "init":
    do_init(payload)
    send("ready")        # 忘了这句，20 秒后进程会被结束
```

### 处理事件时兜住异常

```python
try:
    handle(payload)
except Exception:
    log(traceback.format_exc(), "error")
```

进程退出会让主程序记一次崩溃并重启插件，代价远大于跳过一条消息。

### 未知 `type` 只记录不退出

主程序将来会新增消息类型（协议 v1 → v2 就加了三类）。
旧插件遇到不认识的类型时应该忽略，而不是退出。

### 用 `data_dir` 存文件

```python
path = os.path.join(host.data_dir, "cache.json")
```

不要用相对路径，也不要往插件目录写数据——那只放代码。

### 回复消息用 `msg_id`

`msg_id` 与 `event_id` 互斥，回复消息只能用前者。
两者都传会被官方拒绝（本项目会保留 `msg_id` 并记一条 warn，但那意味着你的插件有问题）。

### 带上 `bot_id`

多机器人同时在线时，不带 `bot_id` 的回复会发不出去（主程序找不到对应的发送通道）。

### 先看 `can_reply`

被动回复的窗口与次数由主程序算好并放进事件里。
自己算会出现两套实现，而且你拿不到准确的事件接收时刻。

## 不要做的

### 不要在顶层做阻塞操作

```python
# ✗ 顶层就跑一次网络请求：请求慢的时候，init 迟迟收不到，握手超时
data = requests.get("https://example.com/config").json()

# ✓ 放到 on_init 里，而且加超时
def on_init(payload):
    try:
        data = requests.get(url, timeout=5).json()
    except Exception:
        log("拉取远程配置失败，使用默认值", "warn")
```

握手有 20 秒上限。顶层阻塞会让插件在「启动中」卡到超时，然后被记为崩溃——
而它在你的电脑上跑得好好的。

!!! note "标准库里没有 requests"

    内置运行时只带标准库。用 `urllib.request`，或者把依赖 vendor 进插件目录
    （纯 Python 的可以，带 C 扩展的不行）。

### 不要在循环里 `print`

日志有每秒 40 行的上限，超出的会被丢弃并计数。看到「丢弃日志」这个数字，
先去看代码而不是调高上限。

### 不要吞掉所有异常

```python
# ✗ 出错后什么都没有，用户只看到插件不工作
try:
    risky()
except Exception:
    pass
```

至少 `log(...)` 一条。跨进程的异常栈在手机上没有别的办法看到。

### 不要把凭证写进配置或状态

插件包导出**只包含源码**，但配置与状态会存在设备上且是明文。
真要存密钥，至少要在文档里提醒用户。

### 不要依赖 `stderr` 之外的调试手段

没有调试器可以附加。`print` 与 `stderr` 都会被收进「日志」页，
这是唯一的观察窗口。把关键分支都打上日志——排查时你会庆幸自己打了。

## 性能

| 建议 | 原因 |
| --- | --- |
| 插件启动时一次性完成初始化，别在每条事件里重做 | 每条消息都重建一次 HTTP 连接会慢到用户能感觉出来 |
| 长任务不要阻塞主循环 | 阻塞期间收不到 `ping`，90 秒静默就判定卡死 |
| 需要并发时用 `threading` | 主循环必须保持能读 stdin；把耗时工作丢给后台线程 |
| 状态别存大对象 | 它会落进主程序的 JSON 文档，每次写入都是整份文档 |

!!! tip "要跑长任务怎么办"

    启动一个后台线程处理，主循环继续读 stdin：

    ```python
    import threading

    def long_task(payload):
        ...            # 耗时工作

    if kind == "event":
        threading.Thread(target=long_task, args=(payload,), daemon=True).start()
    ```

    注意线程里写 stdout 可能交错，建议给发送函数加一把锁，
    或让后台线程把结果投进 `queue.Queue`，由主循环统一发送。

## 调试流程

1. **装上、看状态**：插件卡片上的状态与 `lastError` 是最快的信号；
2. **看日志**：「日志」页筛「插件」来源，插件自己打的日志与 `stderr` 都在这里；
3. **确认事件到了没**：在 `on_event` 第一行打一条日志。没打出来说明事件没投递到——
   检查 `events` 声明、主程序的 intents 设置、以及机器人在平台上有没有相应权限；
4. **确认回复发出没**：回复失败会在日志里显示官方错误码与 `trace_id`；
5. **怀疑卡死**：界面显示「无响应」时，通常是死锁或长时间阻塞调用。

## 一个可复用的骨架

```python
import json, sys, threading, traceback

class Host:
    def __init__(self):
        self.config, self.state, self.data_dir = {}, {}, None
        self._lock = threading.Lock()

    def send(self, kind, payload=None, request_id=None):
        message = {"type": kind, "payload": payload or {}}
        if request_id:
            message["id"] = request_id
        with self._lock:                      # 多线程发送时保证不交错
            sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
            sys.stdout.flush()

    def log(self, text, level="info"):
        self.send("log", {"level": level, "message": text})


def main():
    host = Host()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            envelope = json.loads(line)
        except ValueError:
            continue                          # 不是协议行就忽略
        kind = envelope.get("type")
        payload = envelope.get("payload") or {}
        try:
            if kind == "init":
                host.config = payload.get("config") or {}
                host.state = payload.get("state") or {}
                host.data_dir = payload.get("data_dir")
                host.send("ready")
            elif kind == "ping":
                host.send("pong")
            elif kind == "shutdown":
                break
            elif kind == "event":
                pass                          # ← 你的逻辑
        except Exception:
            host.log(traceback.format_exc(), "error")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```
