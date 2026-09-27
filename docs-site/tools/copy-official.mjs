/**
 * 把 docs/qq-bot/ 下的手写 HTML 复制进站点的 public 目录。
 *
 * 为什么用脚本而不是在 CI 里加一步 cp：
 *
 * 那两份 HTML（官方文档知识库、系统架构说明）的源头在仓库的 `docs/qq-bot/`，
 * 文档站只是把它们并进站点。如果靠 CI 单独一步复制，本地 `vitepress dev`
 * 就会看不到它们，而侧栏与正文都引用了这两个页面——贡献者必须先知道
 * 「有个额外的复制步骤」才能本地预览。挂到 predev/prebuild 之后，
 * 在任何机器上跑 `npm run dev` / `npm run build` 都是自洽的。
 *
 * public 目录会被 VitePress 原样复制到产物根，因此页面地址是 /official/xxx.html。
 * 生成物已在 .gitignore 里：源头只有一份，不留副本，避免两份内容各自漂移。
 */

import { existsSync, mkdirSync, readdirSync, rmSync, copyFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '..', '..')
const sourceDir = join(repoRoot, 'docs', 'qq-bot')
const targetDir = join(here, '..', 'docs', 'public', 'official')

if (!existsSync(sourceDir)) {
  // 来源不在（比如只 checkout 了 docs-site 这一层）不算致命：
  // 只要目标目录里已有文件，构建仍能继续。
  console.warn(`[copy-official] 跳过：找不到 ${sourceDir}`)
  process.exit(0)
}

mkdirSync(targetDir, { recursive: true })

const copied = readdirSync(sourceDir).filter((name) => name.endsWith('.html'))
for (const name of copied) {
  copyFileSync(join(sourceDir, name), join(targetDir, name))
}

// 清掉历史上复制过、但源头已删的文件，免得站点里留着过期的孤儿页。
for (const name of readdirSync(targetDir)) {
  if (name.endsWith('.html') && !copied.includes(name)) {
    rmSync(join(targetDir, name))
    console.log(`[copy-official] 移除已过期的 ${name}`)
  }
}

console.log(`[copy-official] 已并入 ${copied.length} 份：${copied.join(', ') || '无'}`)
