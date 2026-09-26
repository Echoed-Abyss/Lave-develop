# Lave

Lave 移动端应用，基于 Flutter 构建，支持 Android 与 iOS 双平台。

## 环境要求

| 组件 | 版本 |
| --- | --- |
| Flutter | 3.44.2（stable） |
| Dart | 3.12.2 |
| Android | JDK 17、Android SDK（compileSdk / minSdk 取 Flutter 默认值） |
| iOS | Xcode 15+、CocoaPods（仅 macOS 可构建） |

## 快速开始

```powershell
flutter pub get       # 拉取依赖
flutter run           # 调试运行（需已连接设备或模拟器）
flutter test          # 运行单元测试
flutter analyze       # 静态检查
```

查看可用设备：

```powershell
flutter devices
```

## 构建产物

```powershell
flutter build apk --release              # Android APK
flutter build appbundle --release        # Android AAB（上架 Google Play）
flutter build ios --release              # iOS（需 macOS + 签名配置）
```

## 目录结构

```
android/            Android 原生工程（Kotlin，Gradle KTS）
ios/                iOS 原生工程（Swift，Xcode 工程）
lib/                Dart 业务代码入口
test/               单元测试与 Widget 测试
analysis_options.yaml  lint 规则（flutter_lints）
pubspec.yaml        依赖与版本配置
```

## 应用标识

| 平台 | 标识 |
| --- | --- |
| Android applicationId / namespace | `com.echoedabyss.lavedevelop` |
| iOS Bundle Identifier | `com.echoedabyss.lavedevelop` |
| 版本号 | `1.0.0+1`（见 `pubspec.yaml`） |

修改包名后需同步更新 Android 的 `namespace` 与 `applicationId`、iOS 的 `PRODUCT_BUNDLE_IDENTIFIER`，以及 `android/app/src/main/kotlin/` 下的包目录结构。

## 发版前待办

- 配置 Android 正式签名（当前 release 沿用 debug 签名，见 `android/app/build.gradle.kts`）
- 配置 iOS 证书与描述文件
- 替换默认应用图标与启动图
- 按需接入 CI 流程

## 许可证

见 [LICENSE](LICENSE)。
