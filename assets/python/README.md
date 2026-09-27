# 内置 Python 运行时

本目录存放随 APK 分发的 CPython **标准库**，使用户无需任何二次下载。
运行时本体（`libpython3.14.so` 等）与启动器放在 `android/app/src/main/jniLibs/`。

## 组成与落点

| 内容 | 来源 | 仓库位置 | 运行时落点 |
| --- | --- | --- | --- |
| 启动器 | 本仓库用 NDK 编译（`tools/build_py_launcher.ps1`） | `android/app/src/main/jniLibs/arm64-v8a/libpylauncher.so` | 安装后的**原生库目录** |
| 解释器 | python.org 官方 Android 包 | `android/app/src/main/jniLibs/arm64-v8a/libpython3.14.so` | 同上 |
| 依赖库 | 同上，但**只取 `lib*_python.so` 三个** | 同上 | 同上 |
| 标准库 | 同上（已裁掉 CPython 测试套件） | `assets/python/arm64-v8a/lib/python3.14/**` | 应用私有目录 `<files>/python/lib/python3.14/**` |

**为什么分成两处**：Android 10 起禁止从应用可写数据目录执行文件，
因此可执行文件只能放在安装后的原生库目录（为此 `extractNativeLibs` 必须为 `true`，
见 `android/app/build.gradle.kts` 的 `packaging.jniLibs.useLegacyPackaging`）；
而标准库只需读取，放在私有目录即可。

启动器为什么要自己编：官方 Android 包**没有 `python3` 可执行文件**，
只有 `libpython3.14.so`（进程内嵌入形态）。本项目的插件是独立子进程 + JSON 行协议，
因此需要一个可执行文件，`python_launcher.c` 就是调 `Py_BytesMain` 的薄壳。

### 为什么只保留 `lib*_python.so`

官方包同时提供了 `libcrypto.so` 与 `libcrypto_python.so`（其余两组同理，两组内容逐字节相同）。
带 `_python` 后缀是本包**故意**的重命名：Android 的系统链接器会在自己的命名空间里
优先命中系统同名库，改名后才能确保 Python 用到自带的这份。

名字里带 `lib` 的 `.so` 会被 Android 无条件解包进原生库目录，不区分是否被用到。
实测（统计 `libpython3.14.so` 与全部 `lib-dynload/*.so` 的 `DT_NEEDED`）：

```
libcrypto_python.so   <- _hashlib, _ssl
libsqlite3_python.so  <- _sqlite3
libssl_python.so      <- _ssl
```

即**只有带 `_python` 后缀的三个被引用**，三个不带后缀的纯属重复（6.09MB），已删除。
若日后引入需要按通用名 `dlopen("libssl.so")` 的第三方插件，再把它们放回来即可。

## ⚠️ 声明资产时必须列出每个子目录

`pubspec.yaml` 里的 `assets:` 目前逐条列出了 57 个子目录，**这是必须的**：
**Flutter 的资产目录声明不是递归的**。只写 `- assets/python/` 只会把该目录下的
直接文件打进包，653 个位于子目录中的标准库文件会全部丢失——
而症状是插件启动后立刻报 `ModuleNotFoundError: No module named 'encodings'`，
排查时很容易误判成 Python 本身有问题。

新增目录或升级 Python 版本后，用以下命令重新生成清单：

```powershell
$repo = (Get-Location).Path
$root = "$repo\assets\python"
$dirs = Get-ChildItem $root -Recurse -Directory |
    ForEach-Object { 'assets/python/' + ($_.FullName.Substring($root.Length + 1) -replace '\\','/') + '/' } |
    Sort-Object
$dirs | ForEach-Object { "    - $_" }
```

把输出粘贴进 `pubspec.yaml` 的 `assets:` 段，然后**必须验证**（数量应等于目录内文件数）：

```powershell
tar -tf build\app\outputs\flutter-apk\app-release.apk | Select-String 'assets/python/'
```

## 重建运行时（升级 Python 或增加 ABI）

1. 下载官方包：<https://www.python.org/downloads/android/>
   （形如 `python-3.14.7-aarch64-linux-android.tar.gz`），解压出 `prefix/`。
2. 复制 `prefix/lib/` 下的 `libpython3.14.so` 与 `lib*_python.so`（各三个）到
   `android/app/src/main/jniLibs/arm64-v8a/`；
   **跳过** 0 字节的符号链接（`libpython3.so`、`libsqlite3.so.0`）与不带 `_python` 后缀的重复副本
   （理由见上）。
3. 复制 `prefix/lib/python3.x/` 到 `assets/python/arm64-v8a/lib/python3.x/`，
   建议排除 `test`（CPython 自带测试套件，约 32MB）与 `tkinter`、`idlelib`、`turtledemo`。
4. 编译启动器：`pwsh -File tools/build_py_launcher.ps1 -PythonPrefix <prefix 路径>`
5. 更新 `lib/plugins/plugin_runtime.dart` 中的 `bundledPythonVersionDir`。
6. 按上文重新生成 `pubspec.yaml` 的资产清单。
7. 重新打包并用上面的 `tar` 命令核对文件数。

### 增加 x86_64（模拟器）

当前只内置 `arm64-v8a`（真实手机几乎全是该架构，且每个 ABI 的运行时约 17.7MB）。
需要模拟器支持时：下载 `x86_64` 的官方包，重复第 2、3 步到
`jniLibs/x86_64/` 与 `assets/python/x86_64/`，并在 `pubspec.yaml` 中补上对应目录、
在 `android/app/build.gradle.kts` 的 `ndk.abiFilters` 与构建命令的
`--target-platform` 中一并加上 `android-x64`。
