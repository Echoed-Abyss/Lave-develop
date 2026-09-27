# Lave

QQ 机器人移动客户端。手机端直连腾讯官方 **Gateway WebSocket** 网关接收事件，并用官方 **HTTP OpenAPI** 发送消息、上传富媒体，不依赖任何自建公网后端。

只使用官方协议实现，不包含任何非官方 QQ 协议。

## 平台范围

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Android | ✅ 已交付 | 目标平台，`minSdk 24` |
| iOS | ⛔ 已移除 | 本版本按决定移除 `ios/` 目录；同时 Python 插件在 iOS 上无法以子进程方式运行（`dart:io` 的 `Process.start` 不支持 iOS） |

恢复 iOS：`flutter create --platforms=ios .`，并重新补上两处配置（原先已提交在 git 历史里）：
`Info.plist` 的 `NSPhotoLibraryUsageDescription` / `NSCameraUsageDescription`；
**不要**添加 ATS 例外——`wss://` 本身是 TLS，ATS 默认即允许，加例外是无谓的安全降级。

## 环境要求

| 组件 | 版本 |
| --- | --- |
| Flutter | 3.44.2（stable） |
| Dart | 3.12.2 |
| JDK | 17（Android Studio 内置 JBR 21 亦可） |
| Android SDK | 任一与 `compileSdk` 匹配的 platform + `build-tools` |
| Gradle | 9.1.0（由 wrapper 管理） |
| AGP / Kotlin | 9.0.1 / 2.3.20 |

## 构建

```powershell
flutter pub get
flutter analyze            # 静态检查
flutter test               # 150 项测试
flutter build apk --debug
flutter build apk --release --target-platform android-arm64
flutter run                # 需已连接设备或模拟器
```

`--target-platform android-arm64` 是**必需的**：内置的 Python 运行时只打包了
`arm64-v8a`，不加这个参数 Flutter 会同时放进 armeabi-v7a，而后者没有运行时，
结果是「装得上但插件不可用」。

### 国内网络

Maven 依赖已配置阿里云镜像（`android/settings.gradle.kts` 与 `android/build.gradle.kts`），
Flutter 引擎产物需额外指定镜像基址：

```powershell
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter build apk --release
```

`PUB_HOSTED_URL=https://pub.flutter-io.cn` 在 pub 拉取缓慢时同样有用。

### 签名

正式签名配置在 `android/key.properties`（**已被 .gitignore 排除，不要提交**）：

```properties
storePassword=…
keyPassword=…
keyAlias=key0
storeFile=C:/path/to/keystore
```

`android/app/build.gradle.kts` 在该文件缺失时会回退到 debug 签名，
因此「克隆下来即可编译」与「持有密钥才能出正式包」可以并存。

产物：`build/app/outputs/flutter-apk/app-release.apk`。
核验签名（指纹应与密钥库一致）。注意 `.bat` 包装器在部分受限环境下无法直接执行，
可直接用 `java -jar` 调 `apksigner.jar`：

```powershell
$bt = "$env:LOCALAPPDATA\Android\Sdk\build-tools\37.0.0"
java -jar "$bt\lib\apksigner.jar" verify --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
```

## 构建排障（本机已踩过的坑）

### 机器人连上了却收不到任何消息

**首要怀疑 intents。** 官方原文：

> 如果在鉴权的时候传递了无权限的 `intents`，`websocket` 会报错，并直接关闭连接。
> 除了 `GUILDS`、`PUBLIC_GUILD_MESSAGES`、`GUILD_MEMBERS` 是基础事件默认有权限之外，
> 其他的特殊事件都需要经过申请才能够使用。

也就是说**多订阅一位就可能让连接建不起来**，表现为「一直重连、日志里没有任何事件」。
本项目的处理方式：

- 默认只订阅**必需的一位**（`GROUP_AND_C2C_EVENT`，即单聊与群聊事件），
  覆盖单聊消息、群 @消息、机器人进出群、好友增删；
- 其余可选位（`INTERACTION`、`GROUP_MEMBER_EVENT`）在「设置」页逐个开启，
  其中 `GROUP_MEMBER_EVENT (1<<24)` **不在官方 intents 总表中**，界面会标红提示；
- 若网关仍以 4014 拒绝，会自动降级到必需位重试一次并回写设置——
  而不是直接停止重连（停止就等于永远收不到消息）；
- 若连必需位都被拒，日志会明确提示「请确认机器人已开通单聊/群聊消息权限」。

还有一条容易误判的官方说明：**权限被取消后，当前连接不报错但收不到对应事件，
重连才会报错**。所以「昨天正常、今天收不到」也应先查权限。

### 应用退到后台后连接很快就断

现象：日志反复出现「连接被关闭：1002」，每次连接只活几十秒到两分钟，
断连时应用都不在前台。

原因通常不是协议实现，而是**进程被系统冻结**：应用退到后台后进程进入 cached 状态，
Android 的 cached apps freezer 会在约 10 秒后冻结它；冻结期间 Dart 的定时器不再触发，
心跳发不出去，服务端于是把连接关掉（心跳周期约 41 秒，与观察到的存活时长吻合）。

处理方式是一个真正的前台服务 `GatewayKeepAliveService`：

- 「设置 → 后台保活」开启且至少有一个启用的机器人时，服务挂一条常驻通知
  （内容为当前在线机器人数）。进程因此脱离 cached 状态，不再被冻结；
- Android 14+ 用 `specialUse` 而不是 `dataSync`：后者在 Android 15 上
  24 小时内累计只能运行 6 小时，对需要长期在线的机器人客户端是致命的；
- 同时持一把 `PARTIAL_WAKE_LOCK`：前台服务只解决「进程被冻结」，
  不解决息屏后 CPU 停止调度，而心跳是定时任务；
- 低电耗模式（Doze）会忽略唤醒锁，彻底解决需要把应用加入**电池优化白名单**——
  设置页提供跳转入口，并显示当前是否已加白。

排查入口：设置页「后台保活」同时显示开关状态与服务**真实运行状态**，
两者不一致时日志里也有记录；连接被关闭时日志会附带「距离最后一次收到数据过了多久」，
该时长超过一个心跳周期基本可判定为进程被冻结或网络中断，而非协议层被拒绝。

### 机器人不回复指令 / 回复失败

先看日志里是否有「msg_id 与 event_id 只能二选一」。官方把被动消息分成
两条**互斥**的路径：

| 路径 | 触发事件 | 携带字段 | 取值来源 |
| --- | --- | --- | --- |
| 回复用户消息 | `GROUP_AT_MESSAGE_CREATE`、`C2C_MESSAGE_CREATE` | `msg_id` | 消息事件体的 `d.id` |
| 响应事件 | `INTERACTION_CREATE`、`GROUP_ADD_ROBOT`、`C2C_MSG_RECEIVE`、`FRIEND_ADD` | `event_id` | 事件最外层 payload 的 `id` |

回复一条**消息**只用 `msg_id`，把 `event_id` 一起带上属于非法请求。
本项目把选择收进 `PassiveCredential` 类型，两者在类型层面就无法同时出现。

被动回复另有两个硬约束：有效期（群聊 5 分钟 / 单聊 60 分钟）与次数上限
（群聊 5 次 / 单聊 4 次），对同一条消息多次回复需递增 `msg_seq`。
任一条不满足时本项目不再放弃回复，而是改用**主动消息**发出并记一条 WARN
说明降级原因——主动消息是官方支持的正常路径，只是受独立频控约束。

### 其它

以下三条是本机构建失败的真实原因与处理方式，换机器时可能不需要：

1. **C 盘空间不足**。Gradle 家目录默认在 `C:\Users\<用户>\.gradle`，依赖缓存与发行包可达数 GB。
   曾因 C 盘仅剩 0.6 GB 导致下载被截断（报错却是「zip 损坏」「TLS 握手被中断」，很有误导性）。
   处理：把 `.gradle` 整体移到其它磁盘并建目录联接：
   ```powershell
   robocopy "$env:USERPROFILE\.gradle" 'E:\gradle-home\.gradle' /E /MOVE
   Remove-Item "$env:USERPROFILE\.gradle" -Recurse -Force
   New-Item -ItemType Junction -Path "$env:USERPROFILE\.gradle" -Target 'E:\gradle-home\.gradle'
   ```
2. **Kotlin 增量缓存损坏**。构建被中断后 `build/<module>/kotlin/**/caches-jvm/*.tab` 会残留，
   之后每次都失败在 `Could not close incremental caches`。已在 `android/gradle.properties`
   中设 `kotlin.incremental=false`。
3. **Gradle 发行包下载被截断**。若 wrapper 反复失败，可用 `curl` 单独下载
   `gradle-9.1.0-bin.zip` 到 `~/.gradle/wrapper/dists/gradle-9.1.0-bin/<hash>/` 并解压出
   `gradle-9.1.0/` 目录（该目录下需恰好只有一个顶层目录）。
   `gradle-wrapper.properties` 使用 `-bin` 而非 `-all`：后者只多出源码与文档，构建不需要。

## 目录结构

```
lib/
  app/          应用装配（服务容器）、主题、App 与 Tab 注册
  core/         环境配置、官方常量与端点、协议枚举、错误体系、日志、工具
  gateway/      WSS 协议层：帧模型、事件模型、连接状态机、接入点、心跳、事件分发、多机器人注册表
  api/          HTTP 层：客户端、access_token、消息、富媒体分片上传、互动回应、DTO
  data/         本地存储（JSON 文档 + Keychain/KeyStore 凭证）与仓储
  domain/       领域模型与指令引擎（纯 Dart，无 Flutter 依赖）
  plugins/      Python 插件子进程运行时与管理器
  features/     四个 Tab：机器人 / 日志 / 插件 / 设置
  shared/       玻璃组件集（GlassPanel / GlassExpandableCard / GlassLogItem 等）
test/           测试（含以官方 JSON 样例为输入的事件解析回归、应用骨架冒烟测试）
docs/qq-bot/    官方文档知识库（字段、枚举、限流、错误码的事实基准）与架构设计
android/        Android 原生工程（Kotlin，Gradle KTS）
```

## 插件

插件是**独立的 Python 进程**，通过 JSON 行（JSON Lines）协议与主程序通信：

- 主进程 → 插件：`{"type":"init"|"event"|"shutdown","id":"…","payload":{…}}`
- 插件 → 主进程：`{"type":"ready"|"log"|"reply","id":"…","payload":{…}}`

设计要点：

- **崩溃隔离**：每个插件独立进程，崩溃只影响它自己，且**不会自动重启**（避免崩溃循环）。
- **插件永远拿不到 access_token**：插件通过 `reply` 请求主进程代发消息。
- **非 JSON 的 `print` 输出不会被丢弃**，一律作为日志收进「日志」Tab，便于插件作者调试。

平台能力（界面会明确显示，不会静默失败）：

| 平台 | 可否运行插件 | 原因 |
| --- | --- | --- |
| Windows / macOS / Linux | ✅（需系统装有 Python 3） | 可直接创建子进程 |
| Android | ⚠️ 需放入内置解释器 | 系统未内置 `python`；见下节 |
| iOS | ❌ | `Process.start` 不支持 iOS，只能改为内嵌解释器方案 |

## 内置 Python 运行时

**APK 已内置 CPython 3.14，用户无需任何二次下载。** 组成与落点：

| 内容 | 仓库位置 | 运行时落点 |
| --- | --- | --- |
| 启动器（本仓库用 NDK 编译） | `jniLibs/arm64-v8a/libpylauncher.so` | 安装后的**原生库目录** |
| 解释器与依赖库 | `jniLibs/arm64-v8a/libpython3.14.so` 等 | 同上 |
| 标准库（653 个文件） | `assets/python/arm64-v8a/lib/python3.14/**` | 应用私有目录 `<files>/python/lib/python3.14/**` |

三处关键设计：

**启动器为什么要自己编。** 官方 Android 包（<https://www.python.org/downloads/android/>）
**没有 `python3` 可执行文件**，只有 `libpython3.14.so`——它是给进程内嵌入用的形态。
本项目的插件是独立子进程 + JSON 行协议，需要一个可执行文件，
因此用 `android/app/src/main/cpp/python_launcher.c` 调 `Py_BytesMain` 编了个 5.7KB 的薄壳。

**为什么可执行文件与标准库分开放。** Android 10 起禁止从应用可写数据目录执行文件，
可执行文件只能放在安装后的原生库目录（因而 `extractNativeLibs` 必须为 `true`，
见 `android/app/build.gradle.kts`）；标准库只需读取，放私有目录即可。

**为什么启动时不释放标准库。** 释放要写 600 多个文件，放在启动流程里会让首次启动
白屏数秒。改为在真正点「启动插件」时才释放（幂等，只做一次）。

标准库的释放依赖 `pubspec.yaml` 中逐条声明的 57 个资产子目录——
**Flutter 的资产目录声明不是递归的**，只写 `assets/python/` 会导致标准库全部丢失，
而这在打包时不会报错。完整的重建步骤、x86_64 扩展方式与踩坑说明见
[`assets/python/README.md`](assets/python/README.md)。

## 已知缺口

如实记录当前版本**尚未实现**的能力，避免误以为已经可用：

- **后台保活仅 Android 且未真机验证**：Android 侧已实现前台服务（含
  `specialUse` 类型、唤醒锁、通知权限与电池优化入口），但「切到后台长时间不掉线」
  需要在真机上确认；iOS 仍是缺口。另外**国产 ROM 的省电策略差异很大**，
  必要时需在系统里手动允许自启动与后台运行。
- **内置 Python 仅 arm64-v8a**：模拟器（x86_64）不在内置范围内，扩展方式见
  [`assets/python/README.md`](assets/python/README.md)。
- **内置 Python 未经真机运行验证**：打包链路与产物均已逐项核对（见下），
  但「解释器在设备上真正跑起来」这一步需要在真机上确认。
- **流式消息**：端点已定义，未实现 API 类。
- **频道（Guild）事件**：未建模，本项目以单聊 / 群聊为核心。
- **iOS**：见「平台范围」。

## 文档

| 文档 | 内容 |
| --- | --- |
| [`docs/qq-bot/knowledge-base.html`](docs/qq-bot/knowledge-base.html) | 官方文档知识库：全部字段、枚举、限流、错误码、事件 JSON 样例 |
| [`docs/qq-bot/app-architecture.html`](docs/qq-bot/app-architecture.html) | 系统架构：分层、模块职责、数据模型、连接状态机、目录结构 |
| `docs/qq-bot/raw/*.md` | 逐字原始笔记与核查记录 |

## 应用标识

| 项 | 值 |
| --- | --- |
| Android applicationId / namespace | `com.echoedabyss.lavedevelop` |
| 版本号 | `1.0.0+1`（见 `pubspec.yaml`） |

## 许可证

见 [LICENSE](LICENSE)。
