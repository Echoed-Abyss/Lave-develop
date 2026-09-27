<#
.SYNOPSIS
    重新生成内置 Python 的启动器 libpylauncher.so。

.DESCRIPTION
    背景：官方在 python.org 提供的 Android 包（"Android embeddable package"）
    只有 libpython3.14.so，**没有 python3 可执行文件**——它是给进程内嵌入用的。
    而本项目的插件体系是「独立子进程 + JSON 行协议」，需要一个可执行文件被
    Process.start 调用。

    因此用一个极薄的 C 启动器调用 Py_BytesMain，行为与官方 python3 CLI 一致。
    编译产物提交在 android/app/src/main/jniLibs/<abi>/libpylauncher.so。

    何时需要重新运行：
      - 升级内置 Python（新的 libpython 版本 → 源码里的注释与版本目录同步更新）；
      - 需要额外支持某个 ABI（例如给模拟器加 x86_64）。

.PARAMETER PythonPrefix
    官方包解压后的 prefix 目录（其中应包含 lib/ 与 include/python3.<x>/）。

.PARAMETER Abi
    目标 ABI，默认 arm64-v8a。

.PARAMETER ApiLevel
    目标 Android API level，默认 24（与 app 的 minSdk 一致）。

.PARAMETER NdkVersion
    SDK 下的 NDK 版本目录名。

.EXAMPLE
    pwsh -File tools/build_py_launcher.ps1 -PythonPrefix C:\temp\py\prefix -Abi x86_64

.NOTES
    本文件含中文，**必须保存为 UTF-8 with BOM**。
    Windows PowerShell 5.1 对无 BOM 的文件按 GBK 解码，中文注释里的字节组合
    可能被解成引号或反引号，导致整个脚本语法错误（症状是报
    "Unexpected token"、"Missing closing '}'" 之类，且与报错行无直接关系）。
#>
param(
    [Parameter(Mandatory = $true)][string]$PythonPrefix,
    [string]$Abi = 'arm64-v8a',
    [string]$ApiLevel = '24',
    [string]$NdkVersion = '27.0.12077973'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$cppDir = Join-Path $repoRoot 'android/app/src/main/cpp'
$jniDir = Join-Path $repoRoot "android/app/src/main/jniLibs/$Abi"
$sdkDir = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$llvmDir = Join-Path $sdkDir "ndk/$NdkVersion/toolchains/llvm/prebuilt/windows-x86_64"
$clang = Join-Path $llvmDir 'bin/clang.exe'

if (-not (Test-Path $clang)) {
    throw "找不到 NDK 的 clang：$clang`n请确认 NDK 版本，或用 -NdkVersion 指定。"
}
if (-not (Test-Path (Join-Path $PythonPrefix 'include'))) {
    throw "PythonPrefix 下没有 include/：$PythonPrefix"
}

# 头文件直接取官方包里的，**不随仓库提交**。
# 283 个 CPython 头文件约 1.9MB，而重建时无论如何都要先下载官方包
# （libpython3.14.so 与标准库都在里面），把它们塞进仓库只会白白让 clone 变大。
$includeDir = (Get-ChildItem (Join-Path $PythonPrefix 'include') -Directory |
    Where-Object { $_.Name -like 'python3.*' } | Select-Object -First 1).FullName
if (-not $includeDir) { throw '未在 include/ 下找到 python3.x 目录' }

# 运行时库（jniLibs 与标准库资产需要用户自行准备，见 README「内置 Python 运行时」）。
# 只取 libpython 与带 _python 后缀的三个依赖库：
# 不带后缀的 libcrypto/libssl/libsqlite3 与它们逐字节相同且无人引用（见 assets/python/README.md）。
New-Item -ItemType Directory -Force -Path $jniDir | Out-Null
$libDir = Join-Path $PythonPrefix 'lib'
foreach ($name in @('libpython3.14.so',
        'libcrypto_python.so', 'libssl_python.so', 'libsqlite3_python.so')) {
    $src = Join-Path $libDir $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $jniDir $name) -Force }
}

# 编译启动器。
# 说明：直接调 clang.exe 并显式给出 --target 与 --sysroot，
# 避免依赖 NDK 的 .cmd 包装脚本（部分受限环境下无法执行 .bat/.cmd）。
# 被链接的 .so 以路径形式给出，而不是 -l<name>：
# PowerShell 会把 `-lpython3.14` 拆成 `-lpython3` 与 `.14` 两个参数。
$launcher = Join-Path $jniDir 'libpylauncher.so'
& $clang "--target=$Abi-linux-android$ApiLevel" `
    "--sysroot=$(Join-Path $llvmDir 'sysroot')" `
    -O2 -fPIE -pie -Wall `
    -o $launcher `
    "-I$includeDir" `
    (Join-Path $cppDir 'python_launcher.c') `
    (Join-Path $jniDir 'libpython3.14.so')
if ($LASTEXITCODE -ne 0) { throw "编译失败，clang 退出码 $LASTEXITCODE" }

$size = [math]::Round((Get-Item $launcher).Length / 1KB, 1)
Write-Host "已生成 $launcher（$size KB）"
