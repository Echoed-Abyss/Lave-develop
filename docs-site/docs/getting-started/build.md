# 从源码构建

## 工具链

| 组件 | 版本 |
| --- | --- |
| Flutter | 3.44.2（stable） |
| Dart | 3.12.2 |
| JDK | 17（Android Studio 内置的 JBR 21 也可以） |
| Android SDK | 任一与 `compileSdk` 匹配的 platform + `build-tools` |
| Gradle | 9.1.0（由 wrapper 管理） |
| AGP / Kotlin | 9.0.1 / 2.3.20 |

## 命令

```powershell
flutter pub get
flutter analyze            # 静态检查
flutter test               # 全部单元测试（纯 Dart，不需要设备）
flutter build apk --release --target-platform android-arm64
```

测试覆盖的是「算得出对错」的部分：协议帧编解码、intents 掩码、关闭码判定、
富媒体分片协议、插件清单与状态机、回复凭据互斥、时间与统计数据。界面与真机行为
（保活是否真的生效、上传是否真的落盘）在单元测试里验不了，只能上真机。

::: danger `--target-platform android-arm64` 是必需的

内置的 Python 运行时只打包了 `arm64-v8a`。不加这个参数，Flutter 会同时放进
`armeabi-v7a`，而后者没有运行时，结果是**装得上但插件不可用**。

:::

产物在 `build/app/outputs/flutter-apk/app-release.apk`，约 22.4MB。

### 包体为什么是 22.4MB

其中约 11.8MB 是原生库（Flutter 引擎 + 内置 Python 运行时），
7MB 是 Python 标准库资产，其余是 Dart AOT 产物与 dex。

`android/app/build.gradle.kts` 里显式设置了 `packaging.dex.useLegacyPackaging = true`：
`minSdk` 提到 31 后 AGP 默认**不压缩** dex（API 28+ 可直接 mmap 加载，
启动更快、设备上更省空间），但那会让 APK 多出约 6MB（22.4 → 28.6MB）。
本项目通过 GitHub 分发 APK，下载体积比毫秒级启动差异更值得优化。
想要更快的冷启动可以去掉这一段。

## 国内网络

Maven 依赖已配置阿里云镜像（`android/settings.gradle.kts` 与 `android/build.gradle.kts`）。
Flutter 引擎产物需要额外指定镜像：

```powershell
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter build apk --release --target-platform android-arm64
```

## 签名

口令与密钥库路径放在 `android/key.properties`，该文件已被 `.gitignore` 排除。
**这一点必须坚持**：仓库是公开的，签名口令一旦入库，任何人都能伪造以你的身份签名的安装包
（包名 + 签名是应用身份的唯一凭据）。

缺失该文件时不报错，会回退到 debug 签名——「克隆下来就能编译」与
「拥有密钥才能出正式包」两件事因此可以并存。

## 内置 Python 运行时

这是构建环节里唯一不标准的部分，值得单独说清楚。

### 为什么需要一个自编的启动器

python.org 提供的 Android 包是**进程内嵌入形态**：只有 `libpython3.14.so`，
**没有 `python3` 可执行文件**。而本项目的插件是「独立子进程 + JSON 行协议」，
必须有可执行文件。因此仓库里有一个 5.7KB 的 C 薄壳：

```c
#include <Python.h>
int main(int argc, char **argv) {
    return Py_BytesMain(argc, argv);   // 等价于命令行调用 python3
}
```

用 NDK 交叉编译成 `libpylauncher.so`，与 `libpython3.14.so` 一起放进 `jniLibs/`。

### 为什么运行时分成两处

| 内容 | 落点 | 原因 |
| --- | --- | --- |
| `libpylauncher.so` / `libpython3.14.so` / `lib*.so` | 安装后的**原生库目录** | Android 10 起禁止从应用可写数据目录执行文件，原生库目录是唯一可执行落点 |
| Python 标准库（653 个文件） | 应用**私有目录** | 只需读取；且释放放在「首次启动插件」时做，避免首次冷启动白屏 |

为此 `extractNativeLibs` 必须为 `true`（与 `packaging.jniLibs.useLegacyPackaging` 一致），
否则 `.so` 不会被解压到磁盘，也就无法被 `exec`。

### 重新生成

1. 下载官方包（形如 `python-3.14.7-aarch64-linux-android.tar.gz`）并解压出 `prefix/`；
2. 复制 `prefix/lib/` 下的 `libpython3.14.so` 与三个 `lib*_python.so` 到
   `android/app/src/main/jniLibs/arm64-v8a/`；
3. 复制 `prefix/lib/python3.14/` 到 `assets/python/arm64-v8a/lib/python3.14/`
   （排除 `test`、`tkinter`、`turtledemo`）；
4. 编译启动器：`pwsh -File tools/build_py_launcher.ps1 -PythonPrefix <prefix 路径>`；
5. 重新生成 `pubspec.yaml` 的资产清单并核对文件数。

详细步骤与坑见 [`assets/python/README.md`](https://github.com/Echoed-Abyss/Lave-develop/blob/main/assets/python/README.md)。

::: warning Flutter 的资产目录声明不是递归的

只写 `assets/python/` 只会把该目录下的**直接文件**打进包，
653 个位于子目录中的标准库文件会全部丢失——而打包过程**不会报错**。
症状是插件启动后立刻 `ModuleNotFoundError: No module named 'encodings'`，
很容易被误判成 Python 本身有问题。因此 `pubspec.yaml` 里逐条列出了全部子目录。

:::

### 增加 x86_64（模拟器）

当前只内置 `arm64-v8a`。需要模拟器支持时：下载 `x86_64` 官方包，
重复上述第 2、3 步到 `jniLibs/x86_64/` 与 `assets/python/x86_64/`，
在 `pubspec.yaml` 中补上对应目录，并在 `ndk.abiFilters` 与构建命令的
`--target-platform` 中一并加上 `android-x64`。

## 本机构建踩过的坑

以下三条是真实发生过的构建失败原因，换机器时可能不需要：

1. **C 盘空间不足**。Gradle 家目录默认在 `C:\Users\<用户>\.gradle`，缓存与发行包可达数 GB。
   曾因 C 盘仅剩 0.6GB 导致下载被截断，而报错是「zip 损坏」「TLS 握手被中断」，
   极具误导性。处理方式是把 `.gradle` 整体移到其它磁盘并建目录联接（junction）。
2. **Kotlin 增量缓存损坏**。构建被中断后 `build/<module>/kotlin/**/caches-jvm/*.tab` 会残留，
   之后每次都失败在 `Could not close incremental caches`。
   已在 `android/gradle.properties` 中设 `kotlin.incremental=false`。
3. **Gradle 发行包下载被截断**。wrapper 反复失败时可手动下载
   `gradle-9.1.0-bin.zip` 放进 `~/.gradle/wrapper/dists/`。
   用 `-bin` 而不是 `-all`：后者只多出源码与文档，构建不需要。

## 文档站

文档站用 VitePress（纯静态站点生成器，Node 侧），源码在 `docs-site/`：

```powershell
cd docs-site
npm install
npm run dev         # 本地预览 http://localhost:5173
```

推送到 `main` 后由 `.github/workflows/docs.yml` 自动构建并发布到 GitHub Pages。

`docs-site/docs/` 里就是普通的 Markdown。注意两点与 MkDocs 时代的差别：

- 提示块写 `::: tip` / `::: info` / `::: warning` / `::: danger` + 自定义标题，
  不是 `!!!`。VitePress 内置的容器类型里**没有 `note`**，原来的 `!!! note`
  已统一映射到 `::: info`。
- 没有「标签页」语法。原来用 `=== "标题"` 的地方已经改成小节标题——
  这样正文能被本地搜索索引到，而藏在标签页里的字是搜不到的。

### 改动文档后请跑一遍这两条

```powershell
cd docs-site
npm run build       # VitePress 构建，死链会让构建失败（ignoreDeadLinks: false）
npm run check       # 校验产物里的站内链接与锚点
```

VitePress 的死链检查只能覆盖 Markdown 源文件里能解析成页面的链接。下面两类它看不见，
所以还要跑一遍 `tools/check-links.mjs`：

- **静态资源目标**：指向 `public/` 里那两份手写 HTML、图片、SVG 的链接，
  写错了构建照样成功；
- **锚点（`#xxx`）**：完全不检查。中文标题的锚点尤其危险——一旦 slugify
  把非 ASCII 字符丢掉，站内互链与分享出去的 URL 会一起失效，
  而构建过程不会有任何提示。

该脚本按浏览器的方式解算相对路径，逐个验证目标文件与锚点，任何一条坏了就
以非 0 退出；它在 CI 里是独立一步，部署前就能拦住死链。

### 官方文档知识库是复制进来的

`docs/qq-bot/*.html` 由 `docs-site/tools/copy-official.mjs` 在
`dev` / `build` 之前复制到 `docs-site/docs/public/official/`
（挂在 `package.json` 的 `predev` / `prebuild` 上）。

不用「CI 里单独 `cp` 一步」是因为：正文与侧栏都引用了那两个页面，
本地少了这一步就会看到断开的目标，贡献者得先知道「有个额外的复制步骤」
才能本地预览。挂到 npm 脚本之后，任何机器上跑 `npm run dev` 都是自洽的。

`docs/public/official/` 已在 `.gitignore` 里，不要提交副本——源头只有一份。
