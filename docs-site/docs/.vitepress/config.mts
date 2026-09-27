import { defineConfig } from 'vitepress'

/**
 * 中文分词式的本地搜索。
 *
 * MiniSearch 默认按空白与标点切词。中文没有词间空格，于是一整句会被当成
 * 一个 token——搜「心跳」命中不了「网关会每隔 30 秒发一次心跳」。
 *
 * 这里用**二元切分（bigram）**：把每段连续中文切成相邻两字的组合，
 * 同时保留单字。理由是这样切不依赖任何词典，而词典路线在本项目上实测不可靠：
 * Node 的 `Intl.Segmenter('zh-CN')` 能把「心跳」「系统」「总览」切对，
 * 却把「插件」切成「插」+「件」，把「网关」切成「网」+「关」——
 * 而这些恰好是本文档里最高频的词。词典缺词导致的偏差是最难察觉的一类问题：
 * 搜索看起来还能用，只是最该命中的词排不到前面。
 *
 * 索引与查询用的是同一个函数，所以「插件」在两边都会被切成
 * `插` / `件` / `插件`，其中 `插件` 这个二元词 rarity 更高、权重更大，
 * 含该词的页面自然会排在只含「插」或「件」的页面之前。
 * 代价是索引体积大约是原来的两倍，对一份不到 1MB 的索引完全可以接受。
 */
const CJK = /[\u4e00-\u9fff\u3400-\u4dbf]/
const CJK_RUN = /[\u4e00-\u9fff\u3400-\u4dbf]+/g
const NON_WORD = /[\s\-_/.,:;!?()[\]{}<>"'`|*#>]+/

function tokenize(text: string): string[] {
  const terms: string[] = []
  // 按中文段切开，非中文段仍走常规按空白/标点切词
  for (const part of text.split(new RegExp(`(${CJK_RUN.source})`))) {
    if (!part) continue
    if (CJK.test(part)) {
      if (part.length === 1) {
        terms.push(part)
        continue
      }
      for (let i = 0; i < part.length; i++) {
        terms.push(part[i])
        if (i + 1 < part.length) terms.push(part.slice(i, i + 2))
      }
    } else {
      for (const word of part.split(NON_WORD)) {
        if (word) terms.push(word.toLowerCase())
      }
    }
  }
  return terms
}

export default defineConfig({
  // GitHub Pages 的项目站点，路径前缀是仓库名。
  // base 写错的表现是「页面能打开但样式全丢」，属于最容易被忽略的一类部署问题。
  base: '/Lave-develop/',
  lang: 'zh-CN',
  title: 'Lave 文档',
  description:
    'QQ 机器人移动客户端 —— 用户手册、架构说明与插件开发文档',

  // 死链不要放过：Markdown 里写错的相对链接默认只是被原样输出，
  // 构建成功、点进去 404。parity 之外还有 tools/check-links.mjs 兜底。
  cleanUrls: false,
  lastUpdated: true,
  ignoreDeadLinks: false,

  head: [
    ['meta', { name: 'theme-color', content: '#12b7f5' }],
    ['meta', { name: 'author', content: 'BaiXuan' }],
  ],

  themeConfig: {
    siteTitle: 'Lave 文档',
    outline: { level: [2, 3], label: '本页目录' },
    darkModeSwitchLabel: '主题',
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '目录',
    lastUpdatedText: '最后更新',
    docFooter: { prev: '上一篇', next: '下一篇' },

    nav: [
      { text: '开始', link: '/getting-started/install', activeMatch: '/getting-started/' },
      { text: '使用手册', link: '/guide/architecture', activeMatch: '/guide/' },
      { text: '插件开发', link: '/plugins/', activeMatch: '/plugins/' },
      { text: '参考', link: '/reference/intents', activeMatch: '/reference/' },
      { text: '常见问题', link: '/faq' },
    ],

    sidebar: {
      '/getting-started/': [
        {
          text: '快速上手',
          items: [
            { text: '安装与首次配置', link: '/getting-started/install' },
            { text: '从源码构建', link: '/getting-started/build' },
          ],
        },
      ],
      '/guide/': [
        {
          text: '使用手册',
          items: [
            { text: '架构概览', link: '/guide/architecture' },
            { text: '网关连接', link: '/guide/gateway' },
            { text: '收发消息', link: '/guide/messages' },
            { text: '消息统计', link: '/guide/statistics' },
            { text: '后台保活', link: '/guide/keep-alive' },
            { text: '故障排查', link: '/guide/troubleshooting' },
          ],
        },
      ],
      '/plugins/': [
        {
          text: '插件开发',
          items: [
            { text: '插件系统总览', link: '/plugins/' },
            { text: '五分钟上手', link: '/plugins/quickstart' },
            { text: '清单 plugin.json', link: '/plugins/manifest' },
            { text: '通信协议', link: '/plugins/protocol' },
            { text: '配置与状态', link: '/plugins/config-and-state' },
            { text: '文件与数据目录', link: '/plugins/files-and-data' },
            { text: '生命周期与故障', link: '/plugins/lifecycle' },
            { text: '示例插件详解', link: '/plugins/example' },
            { text: '最佳实践', link: '/plugins/best-practices' },
            { text: '内置命令与插件的边界', link: '/plugins/builtin-commands' },
          ],
        },
      ],
      '/reference/': [
        {
          text: '参考',
          items: [
            { text: '事件订阅 intents', link: '/reference/intents' },
            { text: '官方限制速查', link: '/reference/limits' },
            { text: '错误码与处置', link: '/reference/error-codes' },
            { text: '端点索引', link: '/reference/endpoints' },
            { text: '官方文档知识库', link: '/reference/official-notes' },
          ],
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/Echoed-Abyss/Lave-develop' },
    ],

    search: {
      provider: 'local',
      options: {
        locales: {
          root: {
            translations: {
              button: { buttonText: '搜索文档', buttonAriaLabel: '搜索文档' },
              modal: {
                displayDetails: '显示详细列表',
                resetButtonTitle: '重置搜索',
                backButtonTitle: '关闭搜索',
                noResultsText: '没有找到结果',
                footer: {
                  selectText: '选择',
                  selectKeyAriaLabel: '回车',
                  navigateText: '切换',
                  navigateUpKeyAriaLabel: '上箭头',
                  navigateDownKeyAriaLabel: '下箭头',
                  closeText: '关闭',
                  closeKeyAriaLabel: 'Esc',
                },
              },
            },
          },
        },
        miniSearch: {
          options: {
            // 中文分词是这份配置里唯一真正影响可用性的一项，见文件顶部说明。
            tokenize,
          },
          searchOptions: {
            fuzzy: 0.2,
            prefix: true,
            boost: { title: 4, text: 2, titles: 1 },
          },
        },
      },
    },

    footer: {
      message: '仅使用腾讯 QQ 机器人开放平台官方接口实现，不含任何逆向协议方案',
      copyright: '作者 BaiXuan',
    },

    editLink: {
      pattern: 'https://github.com/Echoed-Abyss/Lave-develop/edit/main/docs-site/docs/:path',
      text: '在 GitHub 上编辑此页',
    },
  },
})
