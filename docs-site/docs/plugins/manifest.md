# 清单 `plugin.json`

插件目录里必须有 `plugin.json`，否则扫描时整个目录会被跳过。

## 完整字段表

| 字段 | 类型 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `id` | string | ✅ | — | 插件唯一标识。**必须与目录名一致**（删除时按目录定位）。只允许字母、数字、下划线、连字符与点，最长 64 字符 |
| `name` | string | — | 取 `id` | 界面展示名 |
| `version` | string | — | — | 版本号，纯展示 |
| `description` | string | — | — | 描述，显示在卡片上 |
| `author` | string | — | — | 作者，纯展示 |
| `entry` | string | — | `main.py` | 入口文件，**相对插件目录**。绝对路径或含 `..` 会被拒绝 |
| `events` | string[] | — | `[]` | 订阅的事件类型（官方 `t` 值）。**空数组表示订阅全部** |
| `enabled_by_default` | boolean | — | `false` | 首次发现时是否默认启用 |
| `protocol_version` | integer | — | 当前版本 | 插件针对哪一版协议编写 |
| `config` | object[] | — | `[]` | 配置项声明，见下 |

### 字段详解

#### `id`

同时是目录名与配置状态的键名，因此**改了 `id` 等于换了一个新插件**：
原配置与状态不会被继承。

导入插件包时 `id` 会经过校验：`..`、含 `/`、含中文、空字符串一律拒绝——
它会被拼进文件路径，不校验就等于允许插件包写到任意位置。

#### `events`

按官方事件名（`t`）过滤，例如：

```json
"events": ["GROUP_AT_MESSAGE_CREATE", "C2C_MESSAGE_CREATE"]
```

**留空或不写 = 订阅全部事件**。设计这个字段的用途是减少无用投递：
一个只关心群消息的插件不该被每条好友变更事件唤醒。

常用事件名：

| 事件名 | 含义 |
| --- | --- |
| `GROUP_AT_MESSAGE_CREATE` | 群里 @机器人 |
| `C2C_MESSAGE_CREATE` | 单聊消息 |
| `GROUP_ADD_ROBOT` / `GROUP_DEL_ROBOT` | 机器人被拉入 / 移出群 |
| `GROUP_MEMBER_ADD` / `GROUP_MEMBER_REMOVE` | 群成员加入 / 退出 |
| `GROUP_JOIN_REQUEST` | 用户申请加群（机器人是管理员时才收得到） |
| `FRIEND_ADD` / `FRIEND_DEL` | 用户添加 / 删除机器人 |
| `C2C_MSG_RECEIVE` / `C2C_MSG_REJECT` | 用户开启 / 关闭主动消息 |
| `GROUP_MSG_RECEIVE` / `GROUP_MSG_REJECT` | 群管理员开启 / 关闭主动消息 |
| `INTERACTION_CREATE` | 按钮点击、快捷菜单等互动事件 |

!!! warning "订阅了不等于收得到"

    事件能否送达取决于两件事：**主程序订阅了对应的 intent**（见「设置 → 事件订阅范围」），
    以及**机器人在平台上申请到了相应权限**。
    插件声明 `events` 只能在「已经到达主程序的事件」里做二次过滤。

#### `enabled_by_default`

默认 `false` 是刻意的：**新插件不应自动获得处理用户消息的能力**。
否则用户「装了个插件包」就等于把机器人交给了它。

#### `protocol_version`

声明值**大于**主程序支持的版本会被**拒绝加载**——那意味着插件依赖了主程序
还不认识的字段，放行只会让它在运行时静默行为异常，比直接拒绝更难排查。

小于等于当前版本则照常加载：旧插件能跑就不要拦住它。

当前协议版本：**2**。版本历史见[通信协议](protocol.md#版本历史)。

#### `config`

配置项声明。完整说明见 [配置与状态](config-and-state.md)。

```json
"config": [
  {
    "key": "trigger",
    "label": "触发前缀",
    "type": "string",
    "default": "#hi",
    "description": "收到的消息以它开头时回复",
    "required": true
  },
  {
    "key": "verbose",
    "label": "记录每条消息",
    "type": "boolean",
    "default": false
  }
]
```

| 子字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `key` | string | ✅ | 下发到插件配置对象里的字段名。**没有 `key` 的项会被跳过**（而不是让整个清单解析失败） |
| `label` | string | — | 表单上的显示名，缺省取 `key` |
| `type` | string | — | `string` / `text` / `boolean` / `integer` / `number`，未知类型退化为 `text` |
| `default` | any | — | 默认值 |
| `description` | string | — | 表单下方的小字 |
| `required` | boolean | — | 必填。为空时**插件不会被启动**，并提示去填写 |

## 一个完整的例子

```json
{
  "id": "demo_plugin",
  "name": "示例插件",
  "version": "1.1.0",
  "description": "演示插件协议 v2。",
  "author": "Lave",
  "entry": "main.py",
  "protocol_version": 2,
  "events": ["GROUP_AT_MESSAGE_CREATE", "C2C_MESSAGE_CREATE"],
  "enabled_by_default": false,
  "config": [
    {
      "key": "trigger",
      "label": "触发前缀",
      "type": "string",
      "default": "#hi",
      "required": true
    }
  ]
}
```

## 容错行为

清单解析是**尽力而为**的：

| 情况 | 行为 |
| --- | --- |
| JSON 语法错误 | 整个插件被跳过，日志里记一条 warn |
| 缺少 `id` | 整个插件被跳过 |
| 某个 `config` 项缺 `key` | 只跳过该项，插件照常加载 |
| `events` 里有非字符串 | 跳过该元素 |
| `entry` 指向目录外 | 启动时拒绝，并给出「入口路径不合法」 |

设计取向：**一个写错的配置项不该让插件完全无法加载**——
用户至少还能用其余功能，并在日志里看到提示。
