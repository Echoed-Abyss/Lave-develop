pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 阿里云镜像放在最前面：默认的 google() / mavenCentral() 在本机实测
        // 只有约 140 KB/s，且会在传输中途被对端中断（TLS 握手被终止），
        // 导致依赖解析反复失败。镜像命中后无需再走原站。
        maven {
            url = uri("https://maven.aliyun.com/repository/google")
            content { includeGroupByRegex("com\\.android.*") ; includeGroupByRegex("com\\.google.*") }
        }
        maven {
            url = uri("https://maven.aliyun.com/repository/gradle-plugin")
            content { includeGroupByRegex("org\\.jetbrains.*") ; includeGroupByRegex("com\\.gradle.*") }
        }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        // 原站作为兜底：镜像未收录的构件仍可回源。
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
