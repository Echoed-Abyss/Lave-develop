# 配置与状态

插件有两类需要「留在设备上」的数据，协议把它们分开处理：

| | 配置 | 状态 |
| --- | --- | --- |
| 谁定义 | **插件声明**（`plugin.json` 的 `config`），用户填值 | 插件自己决定 |
| 谁修改 | 用户在应用的配置表单里改 | 插件通过 `state_set` 改 |
| 何时到达插件 | `init` 时下发；运行中改动会收到 `config_update` | `init` 时下发 |
| 典型用途 | 触发前缀、API Key、开关 | 已处理条数、上次同步时间、会话映射 |

分开的理由：配置是**用户的决定**，不该被插件覆盖；状态是**插件的记忆**，
不该出现在配置表单里让用户去改。

## 声明配置项

在 `plugin.json` 里加 `config` 数组：

```json
{
  "id": "weather_plugin",
  "name": "天气插件",
  "config": [
    {
      "key": "api_key",
      "label": "天气 API Key",
      "type": "string",
      "required": true,
      "description": "在服务商控制台申请。"
    },
    {
      "key": "city",
      "label": "默认城市",
      "type": "string",
      "default": "北京"
    },
    {
      "key": "unit",
      "label": "温度单位",
      "type": "string",
      "default": "celsius",
      "description": "celsius 或 fahrenheit"
    },
    {
      "key": "max_per_hour",
      "label": "每小时最多回复次数",
      "type": "integer",
      "default": 10
    },
    {
      "key": "verbose",
      "label": "记录详细日志",
      "type": "boolean",
      "default": false
    },
    {
      "key": "template",
      "label": "回复模板",
      "type": "text",
      "default": "当前温度 {temp}℃",
      "description": "支持 {temp} 占位符，可多行。"
    }
  ]
}
```

保存清单后重新扫描（插件页右上角的刷新），卡片上就会出现「配置（6）」按钮。

### 控件类型

| `type` | 表单控件 | 解析结果 |
| --- | --- | --- |
| `string` | 单行输入框 | string |
| `text` | 多行输入框 | string |
| `boolean` | 开关 | bool |
| `integer` | 数字键盘输入框 | int |
| `number` | 数字键盘（可含小数） | num |
| 其它 | 退化为多行输入框 | string |

::: tip 未知类型不会让配置项消失

官方（或你自己）将来加了新类型时，这里会退化成文本框而不是丢掉该项——
「配置项不见了」比「控件不太好用」更让人困惑。

:::

### `required`

必填项为空时，**插件不会被启动**，界面提示去填写。

这个校验放在启动前而不是插件内部，是因为「启动一个注定不工作的进程」
只会让用户看到插件在跑但什么都不做。

### 值的解析

数字类型解析失败时**不抛异常**：原样把字符串交给插件，由插件自己决定怎么处理。
一个手滑的数字不该让整张配置表单崩掉。

## 读取配置

配置在 `init` 的 `payload.config` 里下发，**已经与默认值合并**，
插件不需要自己处理缺省值：

```python
def on_init(host, payload):
    host.config = payload.get("config") or {}
    host.log("触发前缀是 %r" % host.config.get("trigger"))
```

运行中用户改了配置，会收到 `config_update`：

```python
elif kind == "config_update":
    host.config = payload.get("config") or {}
    host.log("配置已更新")
```

不需要重启插件——这一点在表单上也有说明。

## 持久化状态

用 `state_set` 写入，语义是**顶层合并**：

```python
def send_state(patch):
    sys.stdout.write(json.dumps({
        "type": "state_set",
        "payload": {"state": patch},
    }) + "\n")
    sys.stdout.flush()

# 只发变化的那几个键即可
send_state({"handled": 42})
```

下次启动时，这些值会出现在 `init` 的 `payload.state` 里：

```python
def on_init(host, payload):
    host.state = payload.get("state") or {}
    host.handled = int(host.state.get("handled", 0))
```

删除键用 `state_remove`：

```json
{"type": "state_remove", "payload": {"keys": ["tmp_cache"]}}
```

### 为什么是合并而不是整体替换

插件很容易只记住自己关心的字段。整体替换会把「上一次写进去、这一次忘掉的键」
静默抹掉，而且没有任何报错——这类丢失最难排查。

### 存储建议

- 状态最终会落进主程序的 JSON 文档，**请保持在 KB 级**；
- 需要存大文件（图片缓存、数据库）时请写到 `data_dir`，见[文件与数据目录](files-and-data.md)；
- 状态是明文存储的。**不要往配置或状态里存敏感凭证**——
  它会跟着插件包一起被导出与分享。

::: warning 导出插件包时状态不会被导出

「导出」只包含插件目录下的**源码文件**（不含 `data/`，也不含配置与状态）。
这是刻意的：导入别人的插件时，你不希望连他的 API Key 一起继承过来。

:::

## 用户能对配置做什么

| 操作 | 位置 |
| --- | --- |
| 查看 / 修改 | 插件卡片 →「配置」 |
| 清空配置与状态 | 「删除」插件，或重新导入同名插件包（导入视为一份干净的插件） |

修改配置保存时，如果插件正在运行，会立刻收到一条 `config_update`，
不需要重启进程；插件没在跑就只落盘，下次启动时通过 `init` 下发。

::: info 为什么要「清空而不继承」

配置与状态存在主程序文档里（不在插件目录内），所以删目录、重写文件
都带不走它们，必须由导入流程显式清空。
如果重新导入一个同名插件时继承旧配置，用户会拿到一份自己以为已经删掉的
旧密钥——那是安全问题，不只是体验问题。

:::
