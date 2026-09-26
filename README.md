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
flutter test               # 145 项测试
flutter build apk --debug
flutter build apk --release
flutter run                # 需已连接设备或模拟器
```

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
| Android | ⚠️ 需自行打包 Python 运行时 | 系统未内置 `python`；需 Chaquopy 或自编译 CPython |
| iOS | ❌ | `Process.start` 不支持 iOS，只能改为内嵌解释器方案 |

## 已知缺口

如实记录当前版本**尚未实现**的能力，避免误以为已经可用：

- **后台保活**：Android 前台服务与 iOS BGTask 的原生部分未实现，目前只有 Dart 侧的退避重连。
  `AppConfig.enableForegroundService` 因此保持 `false`。
- **消息面板**：机器人 Tab 中会话以摘要列表呈现，未做成完整消息气泡列表，图片因此不能在应用内点开预览。
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
