"""构建钩子：把 docs/qq-bot/ 下的手写 HTML 复制进文档站。

为什么用钩子而不是在 CI 里加一步 `cp`：

那两份 HTML（官方文档知识库、系统架构说明）的源头在仓库的 `docs/qq-bot/`，
文档站只是把它们并进站点。如果靠 CI 里单独一步复制，本地 `mkdocs build`
就会因为找不到 `official/knowledge-base.html`（nav 里引用了它）而直接失败，
贡献者得先知道「有个额外的复制步骤」才能本地预览——这种隐性前置条件最容易
把人卡住。放进钩子后，`mkdocs build` 与 `mkdocs serve` 在任何机器上都自洽。

`on_pre_build` 的时机很关键：MkDocs 在触发该事件之后才扫描 docs 目录建立
文件集合，所以在这里落盘的文件会被当成正常的站点文件处理（含 nav 校验、
链接改写），而不是构建完才冒出来的孤儿文件。
"""

from __future__ import annotations

import pathlib
import shutil

# 钩子文件位于 docs-site/hooks/，所以仓库根是上两级。
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "docs" / "qq-bot"
TARGET_DIR = pathlib.Path(__file__).resolve().parents[1] / "docs" / "official"


def on_pre_build(config, **kwargs) -> None:  # noqa: ANN001 - MkDocs 钩子签名
    if not SOURCE_DIR.is_dir():
        # 来源目录不在（比如只拿了 docs-site 这一层）也不算致命错误：
        # 只要 TARGET_DIR 里已有文件，构建仍能继续。
        print(f"[copy_official] 跳过：找不到 {SOURCE_DIR}")
        return

    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []
    for src in sorted(SOURCE_DIR.glob("*.html")):
        dst = TARGET_DIR / src.name
        shutil.copy2(src, dst)
        copied.append(src.name)

    # 清掉历史上复制过、但源头已经删掉的文件，避免站点里留着过期的孤儿页。
    for stale in sorted(TARGET_DIR.glob("*.html")):
        if stale.name not in copied:
            stale.unlink()
            print(f"[copy_official] 移除已过期的 {stale.name}")

    print(f"[copy_official] 已并入 {len(copied)} 份：{', '.join(copied) or '无'}")
