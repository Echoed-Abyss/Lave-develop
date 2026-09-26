# 内置 Python 运行时（放置目录）

把交叉编译好的 CPython 按 ABI 放到这里，插件即可在 Android 上真正运行。

## 目标布局

```
assets/python/arm64-v8a/python3              # 解释器可执行文件
assets/python/arm64-v8a/lib/python3.12/…     # 标准库
assets/python/armeabi-v7a/…                  # 可选，其它 ABI
assets/python/x86_64/…                       # 可选，模拟器
```

规则说明：

- 目录名必须是 Android 的 ABI 名（`arm64-v8a` / `armeabi-v7a` / `x86_64`），
  因为不同架构的二进制不能混用；运行时按此顺序取第一个真实存在的目录。
- 必须带**完整标准库**。只放一个裸 `python3` 是跑不起来的，
  解释器启动时会找不到 `sys.path` 下的模块。
- 只放需要的 ABI 即可。每个 ABI 会增加数十 MB 包体。

## 运行时如何使用它

启动时会依次尝试：

1. 应用私有目录里已释放的解释器（`<files>/python/python3`）；
2. 从本目录释放（复制到应用私有目录并 `chmod 755`）——**assets 位于 APK 内部，
   没有真实路径也无法设置可执行位，必须先释放出来才能被 `Process.start` 执行**；
3. 系统 PATH 中的 `python3` / `python`（桌面平台走这条）。

三者都不可用时，「插件」页会明确显示原因，而不是静默失败。

## 如何产出这个二进制

本文档不代替交叉编译步骤，只说明落点。可选路线：

- **Chaquopy**：Gradle 插件方式嵌入 CPython。注意它的 Python 运行在 JVM 进程内，
  与本项目的「子进程 + JSON 行协议」不同，接入需要改协议层。
- **python-for-android / 自编译 CPython**：产出真正的 `python3` 可执行文件与
  标准库目录，可直接按上面的布局放入。需要 Android NDK、较长的编译时间与
  数十 GB 磁盘空间。

两条路线都需要完整的 NDK 工具链与大量下载，不适合在受限网络下临时执行。
