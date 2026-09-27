"""检查文档站产物里所有站内链接是否真的指向存在的文件与锚点。

为什么需要这个脚本，而不是只靠 `mkdocs build --strict`：

1. MkDocs 自带的链接校验只盯 Markdown 源文件的链接。站点里的静态资源
   （手写的 HTML、图片、SVG）作为链接目标时，校验非常宽松，写错也不报错。
2. 更隐蔽的一种：Material 的卡片网格 `<div class="grid cards" markdown>`
   依赖 `md_in_html` 扩展。忘了开这个扩展时，块内的 Markdown 根本不会被
   解析成 HTML，于是 `**[标题](链接)**` 原样显示在页面上——它不是 `<a>`，
   校验器自然看不见，但用户点不到，链接也是错的。
3. 锚点（`#xxx`）在中文标题下尤其容易出问题：默认 slugify 会把非 ASCII
   字符整段丢掉，锚点退化成 `#_2` 这种形式，站内互链与分享出去的 URL 全废。

脚本按浏览器的方式解算相对路径，逐个验证目标文件与锚点，任何一条坏了就
以非 0 退出，让 CI 直接失败。

用法：
    python check_links.py site /Lave-develop
"""

from __future__ import annotations

import pathlib
import re
import sys
import urllib.parse

SITE = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "site").resolve()
# 站点根前缀：site_url 形如 https://x.github.io/<repo>/，
# 主题生成的 404.html 里导航用的是 /<repo>/guide/... 这种绝对路径。
BASE = (sys.argv[2] if len(sys.argv) > 2 else "").rstrip("/")

A_RE = re.compile(r"""(?:href|src)\s*=\s*(?P<q>["'])(?P<url>.*?)(?P=q)""", re.I)
ID_RE = re.compile(r"""\bid\s*=\s*(?P<q>["'])(?P<id>[^"']+)(?P=q)""", re.I)
NAME_RE = re.compile(r"""\bname\s*=\s*["']([^"']+)["']""", re.I)

SKIP_PREFIX = (
    "http://",
    "https://",
    "//",
    "mailto:",
    "tel:",
    "data:",
    "javascript:",
)


def anchors_of(path: pathlib.Path) -> set[str] | None:
    """返回该文件里可作为跳转目标的 id/name 集合；非 HTML 返回 None（不校验锚点）。"""
    if path.suffix.lower() not in (".html", ".htm"):
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    ids = {m.group("id") for m in ID_RE.finditer(text)}
    return ids | set(NAME_RE.findall(text))


def resolve(page: pathlib.Path, raw_path: str) -> list[pathlib.Path]:
    """给出一个链接可能对应的磁盘路径（候选列表，命中任一即算存在）。"""
    out: list[pathlib.Path] = []
    if raw_path.startswith("/"):
        rel = raw_path.lstrip("/")
        if BASE and rel.startswith(BASE.lstrip("/") + "/"):
            rel = rel[len(BASE.lstrip("/")) + 1 :]
        out.append(SITE / rel)
        # 兜底：前缀判断失误时再剥一段（兼容 site 目录直接就是根的情况）
        if "/" in rel:
            out.append(SITE / rel.split("/", 1)[1])
    else:
        out.append((page.parent / raw_path).resolve())

    expanded: list[pathlib.Path] = []
    for c in out:
        expanded.append(c)
        if raw_path.endswith("/") or not c.suffix:
            expanded.append(c / "index.html")
    return expanded


def main() -> int:
    if not SITE.is_dir():
        print(f"site 目录不存在: {SITE}")
        return 2

    pages = sorted(SITE.rglob("*.html"))
    anchor_cache: dict[pathlib.Path, set[str] | None] = {}
    broken: list[str] = []
    checked = 0

    for page in pages:
        html = page.read_text(encoding="utf-8", errors="replace")
        for url in A_RE.findall(html):
            url = url[1].strip()
            if not url or url.startswith(SKIP_PREFIX):
                continue

            if url.startswith("#"):
                target = page
                frag = urllib.parse.unquote(url[1:])
            else:
                split = urllib.parse.urlsplit(url)
                if split.scheme or split.netloc:
                    continue
                raw_path = urllib.parse.unquote(split.path)
                frag = urllib.parse.unquote(split.fragment)
                candidates = resolve(page, raw_path)
                target = next((c for c in candidates if c.exists()), candidates[0])

            checked += 1
            if not target.exists():
                broken.append(f"{page.relative_to(SITE)} -> {url}  (目标不存在)")
                continue
            if not frag:
                continue
            if target not in anchor_cache:
                anchor_cache[target] = anchors_of(target)
            available = anchor_cache[target]
            if available is None:
                continue
            if frag not in available:
                broken.append(f"{page.relative_to(SITE)} -> {url}  (锚点不存在)")

    print(f"检查了 {len(pages)} 个页面 / {checked} 条站内链接")
    if broken:
        print(f"\n发现 {len(broken)} 条坏链:")
        for line in broken:
            print("  " + line)
        return 1
    print("没有坏链。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
