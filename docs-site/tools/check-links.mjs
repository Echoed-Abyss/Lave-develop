/**
 * 校验构建产物里的站内链接与锚点。
 *
 * 为什么不能只靠 VitePress 自带的 `ignoreDeadLinks: false`：
 *
 * 1. 它只检查 Markdown 源文件里能解析成页面/资源的链接。指向 `public/`
 *    里静态文件（那两份手写 HTML、SVG、图片）的链接，写错了它多半看不出来。
 * 2. 锚点（`#xxx`）完全不检查。中文标题的锚点尤其容易退化——一旦
 *    slugify 把非 ASCII 字符丢掉，站内互链与分享出去的 URL 会一起失效，
 *    而构建过程不会有任何提示。
 *
 * 这个脚本按浏览器的方式解算相对路径，逐个验证目标文件与锚点，
 * 任何一条坏了就以非 0 退出，让 CI 直接失败。
 *
 * 用法：node tools/check-links.mjs docs/.vitepress/dist [站点根前缀]
 */

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve, sep } from 'node:path'

const siteRoot = resolve(process.argv[2] ?? 'docs/.vitepress/dist')
// 站点根前缀（GitHub Pages 项目页是 /<repo>/）。产物里的绝对链接会带上它。
const base = (process.argv[3] ?? '/Lave-develop').replace(/\/$/, '')

if (!existsSync(siteRoot) || !statSync(siteRoot).isDirectory()) {
  console.error(`产物目录不存在：${siteRoot}`)
  process.exit(2)
}

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (statSync(full).isDirectory()) walk(full, out)
    else if (name.endsWith('.html')) out.push(full)
  }
  return out
}

const idCache = new Map()

/** 该 HTML 文件里所有可作跳转目标的 id / name；非 HTML 返回 null（不校验锚点）。 */
function anchorsOf(file) {
  if (!file.endsWith('.html')) return null
  if (idCache.has(file)) return idCache.get(file)
  const html = readFileSync(file, 'utf8')
  const ids = new Set()
  for (const m of html.matchAll(/\bid\s*=\s*"([^"]+)"/g)) ids.add(m[1])
  for (const m of html.matchAll(/\bname\s*=\s*"([^"]+)"/g)) ids.add(m[1])
  idCache.set(file, ids)
  return ids
}

/** 给出一个链接可能对应的磁盘路径候选（命中任一即算存在）。 */
function candidates(fromFile, pathname) {
  const out = []
  if (pathname.startsWith('/')) {
    let rel = pathname.slice(1)
    if (base && (rel === base.slice(1) || rel.startsWith(base.slice(1) + '/'))) {
      rel = rel.slice(base.length)
    } else if (rel.includes('/')) {
      // 前缀判断失误时再剥一段，兼容「产物根就是站点根」的情况
      out.push(resolve(siteRoot, rel.split('/').slice(1).join('/')))
    }
    out.unshift(resolve(siteRoot, rel))
  } else {
    out.push(resolve(dirname(fromFile), pathname))
  }

  const expanded = []
  for (const c of out) {
    expanded.push(c)
    if (pathname.endsWith('/') || !/\.[a-z0-9]+$/i.test(c)) {
      expanded.push(join(c, 'index.html'))
    }
  }
  return expanded
}

/**
 * 相对链接必须相对**当前页面**解算。
 *
 * 这里踩过一次：起初用 `new URL(raw, 'https://example.invalid/')` 解析，
 * 基准路径是根，于是页面里的 `./protocol.html` 被解成 `/protocol.html`，
 * 所有同目录互链都被误报成坏链——一个「检查工具自己坏了」的假阳性，
 * 比漏报更浪费时间。基准要带上当前页面在站点里的相对路径。
 */
function resolveUrl(raw, fromFile) {
  const pagePath = relative(siteRoot, fromFile).split(sep).join('/')
  return new URL(raw, `https://example.invalid/${pagePath}`)
}

const SKIP = /^(https?:)?\/\/|^mailto:|^tel:|^data:|^javascript:/i

let checked = 0
const broken = []
const pages = walk(siteRoot)

for (const page of pages) {
  const html = readFileSync(page, 'utf8')
  for (const m of html.matchAll(/(?:href|src)\s*=\s*"([^"]*)"/gi)) {
    const raw = m[1].trim()
    if (!raw || SKIP.test(raw) || raw.startsWith('#')) {
      // 纯页内锚点单独处理
      if (raw.startsWith('#') && raw.length > 1) {
        const available = anchorsOf(page)
        checked++
        if (available && !available.has(decodeURIComponent(raw.slice(1)))) {
          broken.push(`${relative(siteRoot, page)} -> ${raw}  (锚点不存在)`)
        }
      }
      continue
    }

    let url
    try {
      url = resolveUrl(raw, page)
    } catch {
      continue
    }
    if (url.origin !== 'https://example.invalid') continue

    const pathname = decodeURIComponent(url.pathname)
    const fragment = decodeURIComponent(url.hash.replace(/^#/, ''))
    const resolved = candidates(page, pathname)
    const target = resolved.find((c) => existsSync(c))

    checked++
    if (!target) {
      broken.push(`${relative(siteRoot, page)} -> ${raw}  (目标不存在)`)
      continue
    }
    if (!fragment) continue
    const available = anchorsOf(target)
    if (available && !available.has(fragment)) {
      broken.push(`${relative(siteRoot, page)} -> ${raw}  (锚点不存在)`)
    }
  }
}

console.log(`检查了 ${pages.length} 个页面 / ${checked} 条站内链接`)
if (broken.length > 0) {
  console.error(`\n发现 ${broken.length} 条坏链：`)
  for (const line of broken.slice(0, 60)) console.error('  ' + line)
  if (broken.length > 60) console.error(`  …另有 ${broken.length - 60} 条`)
  process.exit(1)
}
console.log('没有坏链。')
