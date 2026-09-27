import java.io.FileInputStream
import java.util.Properties

// ───────────────────────── 签名配置 ─────────────────────────
//
// 口令与密钥库路径放在 `android/key.properties`，该文件已被 .gitignore 排除。
// 这一点必须坚持：本仓库是公开的，签名口令一旦入库，任何人都能伪造
// 以你的身份签名的安装包（Android 的包名+签名是应用身份的唯一凭据）。
//
// 缺失该文件时不报错，而是回退到 debug 签名 —— 这样「克隆下来就能编译」
// 与「拥有密钥才能出正式包」两件事可以并存。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseSigning =
    keystorePropertiesFile.exists() && keystoreProperties.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.echoedabyss.lavedevelop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.echoedabyss.lavedevelop"

        // 显式抬到 24，不沿用 flutter.minSdkVersion 的默认值：
        // image_picker（flutter.dev 官方插件）要求 Android SDK 24+，
        // flutter_secure_storage 10+ 要求 23，取两者较高值。
        // 写死的原因是这个约束会随插件升级而变化，静默变低会推迟到
        // 打包时的清单合并阶段才报错，排查成本高。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // 只打包 arm64-v8a。
            //
            // 内置的 Python 运行时（libpython3.14.so / libcrypto / libssl /
            // libsqlite3 / libpylauncher.so）约 17.7MB，且**按 ABI 各需一份**。
            // 真实手机几乎全是 arm64，因此这里只带一个架构以控制包体；
            // 需要在模拟器（x86_64）上跑插件时，按 README「内置 Python 运行时」
            // 补一份 x86_64 的运行时到 jniLibs 与 assets 即可。
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            // 预编译的官方运行时不能被 AGP 的 strip 处理：
            // 它们已经是 release 形态，再次 strip 可能失败或破坏文件；
            // libpylauncher.so 更是一个可执行文件（PIE），并非共享库。
            keepDebugSymbols += listOf(
                "**/libpylauncher.so",
                "**/libpython3.14.so",
                "**/libcrypto*.so",
                "**/libssl*.so",
                "**/libsqlite3*.so",
            )
            // 必须让原生库被解压到磁盘（而不是直接从 APK 内映射）。
            //
            // 原因：Android 10 起禁止从应用可写数据目录执行文件，
            // 安装后的原生库目录是唯一可执行的落点；而只有解压模式下
            // 这些 .so 才会真正落到磁盘上，libpylauncher.so 才能被 exec。
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // 无密钥时回退 debug 签名，保证 `flutter build apk --release`
                // 仍可产出可安装的包用于验证，但**不可用于分发**。
                signingConfigs.getByName("debug")
            }
            // 不开启混淆与资源裁剪：本项目依赖较多反射（Flutter 插件注册），
            // 开启后需要额外的 keep 规则维护成本；自用场景下保留可读的
            // 崩溃栈比减小体积更有价值。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
