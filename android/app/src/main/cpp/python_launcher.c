/*
 * 最小 Python 启动器（Android / arm64-v8a）。
 *
 * ## 为什么需要它
 *
 * 官方在 python.org 提供的 Android 包（"Android embeddable package"）里
 * **没有 python3 可执行文件**，只有 `libpython3.14.so` —— 它是给「进程内嵌入」
 * 用的形态（官方 README 也建议 app 开发者改用 Chaquopy / Briefcase 这类工具）。
 *
 * 而本项目的插件体系是「独立子进程 + JSON 行协议」，需要一个可执行文件被
 * `Process.start` 调用。这个启动器就是把 `libpython` 变成可执行的薄壳：
 * 调用 `Py_BytesMain` 之后，它的行为与官方 python3 CLI 完全一致
 * （argv[1] 为脚本路径，其后为脚本参数）。
 *
 * ## 为什么不做进程内嵌入
 *
 * 进程内嵌入（Chaquopy 那种）需要自行维护 GIL、线程与 Java 回调桥，
 * 而且**插件崩溃会直接带走主进程**，失去本项目的崩溃隔离保证。
 * 子进程方案在这个项目里更合适。
 *
 * ## 运行时依赖
 *
 * - `libpython3.14.so` 与它依赖的 `libcrypto` / `libssl` / `libsqlite3`
 *   随 APK 一起放进原生库目录（jniLibs），因此需要由上层设置
 *   `LD_LIBRARY_PATH` 指向该目录；
 * - 标准库由 `PYTHONHOME` 指向应用私有目录中释放出来的那份（见
 *   `assets/python/arm64-v8a/lib/python3.14/`）。
 *
 * ## 重新生成
 *
 * 本文件编译产物 `libpylauncher.so` 已随仓库提交（见 tools/build_py_launcher.ps1，
 * 里面有完整的重建命令）。
 */

#include <Python.h>

int main(int argc, char **argv) {
    /* Py_BytesMain 会完成解释器初始化、解析 argv（含 -c / -m / 脚本路径）、
       sys.path 装配与脚本执行，并返回退出码。等价于命令行调用 python3。 */
    return Py_BytesMain(argc, argv);
}
