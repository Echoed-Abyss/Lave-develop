# -*- coding: utf-8 -*-
"""Lave 示例插件（插件协议 v2）。

这个文件同时是**可运行的示例**和**协议参考实现**。它刻意只依赖标准库，
并且把「与主进程通信」封装成一个薄类，方便你直接改。

协议基础
--------
* 传输：stdin / stdout，**一行一条 JSON**（JSON Lines）；
* 主进程 → 插件：``init`` / ``event`` / ``config_update`` / ``ping`` / ``shutdown``；
* 插件 → 主进程：``ready`` / ``log`` / ``reply`` / ``state_set`` / ``state_remove`` / ``pong``；
* 每条消息形如 ``{"type": "...", "id": "...", "payload": {...}}``；
* 主进程用 ``PYTHONUNBUFFERED=1`` 启动本进程，因此 ``print`` 会立刻送达——
  但**协议消息必须走 stdout 且是合法 JSON**，非 JSON 的输出会被当作日志收走。

生命周期
--------
1. 进程启动后，主进程下发 ``init``（含配置、上次的状态、可写数据目录）；
2. 插件完成初始化后**必须**回一条 ``ready``，否则主进程会在握手超时后结束进程；
3. 之后按 ``event`` 投递事件；插件可以用 ``reply`` 请求主进程代发消息；
4. 收到 ``shutdown`` 时应尽快退出（主进程会等 3 秒，然后强杀）。

为什么是「主进程代发消息」
--------------------------
插件**永远拿不到 access_token**。回复消息要走 ``reply`` 交给主进程，
由它调用官方接口。这样即使插件被替换成恶意代码，也拿不到机器人凭证。
"""

import json
import os
import sys
import traceback

PROTOCOL_VERSION = 2


class Host:
    """与主进程通信的薄封装。"""

    def __init__(self):
        self.plugin_id = None
        self.config = {}
        self.state = {}
        self.data_dir = None
        self.handled = 0

    # ── 发送 ──────────────────────────────────────────────

    def send(self, kind, payload=None, request_id=None):
        message = {"type": kind, "payload": payload or {}}
        if request_id:
            message["id"] = request_id
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()

    def log(self, text, level="info"):
        self.send("log", {"level": level, "message": text})

    def set_state(self, patch):
        """持久化状态：**顶层合并**，只需给出变化的键。"""
        self.state.update(patch)
        self.send("state_set", {"state": patch})

    def reply(self, request_id, bot_id, scope, conversation_id, text, msg_id=None):
        """请求主进程代发一条消息。

        ``msg_id`` 与 ``event_id`` 只能二选一（官方规则）：
        回复用户消息用 ``msg_id``，响应事件才用 ``event_id``。
        两者都不传即为主动消息，受独立频控约束。
        """
        payload = {
            "bot_id": bot_id,
            "conversation_id": conversation_id,
            "scope": scope,
            "text": text,
        }
        if msg_id:
            payload["msg_id"] = msg_id
        self.send("reply", payload, request_id)


# ── 各阶段处理 ────────────────────────────────────────────


def on_init(host, payload):
    host.plugin_id = payload.get("plugin_id")
    host.config = payload.get("config") or {}
    host.state = payload.get("state") or {}
    host.data_dir = payload.get("data_dir")
    host.handled = int(host.state.get("handled", 0))

    capability = payload.get("capability") or {}
    host.log(
        "初始化完成：协议 v%s，平台 %s，累计处理 %d 条"
        % (payload.get("protocol_version"), capability.get("platform"), host.handled)
    )
    if host.data_dir:
        host.log("数据目录：%s" % host.data_dir)

    # 必须回 ready，主进程才开始投递事件。
    host.send("ready")


def on_config_update(host, payload):
    host.config = payload.get("config") or {}
    host.log("配置已更新：trigger=%r" % host.config.get("trigger"))


def on_event(host, envelope, payload):
    """处理一个事件。

    ``envelope`` 的 ``id`` 用于把回复与原事件对应起来（可用可不用），
    ``payload`` 是归一化后的事件内容——**不是官方原始 JSON**，
    字段名由 Lave 保证稳定。
    """
    event = payload.get("event") or {}
    bot_id = payload.get("bot_id")
    scope = event.get("scope")
    conversation_id = event.get("conversation_id")
    content = event.get("content") or ""
    sender = (event.get("sender") or {}).get("name") or "未知用户"

    host.handled += 1
    host.set_state({"handled": host.handled})

    if host.config.get("log_every_message", True):
        host.log("收到消息（%s / %s）：%s" % (scope, sender, content))

    trigger = (host.config.get("trigger") or "").strip()
    if not trigger or not content.strip().startswith(trigger):
        return

    # 被动回复窗口只有群聊 5 分钟 / 单聊 60 分钟，主进程已在事件里算好。
    if not event.get("can_reply", False):
        host.log("被动回复窗口已关闭，跳过回复", "warn")
        return

    host.reply(
        request_id=envelope.get("id"),
        bot_id=bot_id,
        scope=scope,
        conversation_id=conversation_id,
        text=host.config.get("greeting") or "你好",
        msg_id=event.get("message_id"),
    )


def on_shutdown(host):
    """退出前的收尾。

    演示 ``data_dir`` 的用法：它是插件**专属的可写目录**，
    插件根目录只放代码，运行时数据写在这里，升级插件时不会互相干扰。
    """
    if host.data_dir:
        try:
            os.makedirs(host.data_dir, exist_ok=True)
            with open(os.path.join(host.data_dir, "stats.json"), "w", encoding="utf-8") as fh:
                json.dump({"handled": host.handled}, fh, ensure_ascii=False)
            host.log("已把统计写入数据目录：%s" % host.data_dir)
        except OSError as error:
            host.log("写入数据目录失败：%s" % error, "error")
    host.log("示例插件已退出")


def main():
    host = Host()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            envelope = json.loads(line)
        except ValueError:
            # 主进程不会发非法 JSON；真出现了也只记一条，不要因此退出。
            host.log("无法解析的协议行：%s" % line[:200], "warn")
            continue

        kind = envelope.get("type")
        payload = envelope.get("payload") or {}

        try:
            if kind == "init":
                on_init(host, payload)
            elif kind == "event":
                on_event(host, envelope, payload)
            elif kind == "config_update":
                on_config_update(host, payload)
            elif kind == "ping":
                host.send("pong", {}, envelope.get("id"))
            elif kind == "shutdown":
                on_shutdown(host)
                break
            else:
                host.log("未知消息类型：%s" % kind, "warn")
        except Exception as error:  # noqa: BLE001 - 示例刻意兜住所有异常
            # 单个事件处理失败不应该让整个插件退出：进程一退，
            # 主进程就会记一次崩溃并（在预算内）重启它，代价远大于跳过一条消息。
            host.log(
                "处理 %s 时出错：%s\n%s" % (kind, error, traceback.format_exc()),
                "error",
            )

    return 0


if __name__ == "__main__":
    sys.exit(main())
