# 亮色 / 暗色 与专注模式（全站外观）

全站共用一套外观状态：`src/stores/ui.ts` 的 `theme`（light/dark）与 `focusMode`，两者都落 localStorage
（`app_theme` / `app_focus_mode`），`main.ts` 在 `app.mount()` **之前**调 `useUiStore().init()`，避免亮→暗闪一下。
切换入口在顶栏（`layout/components/Navbar.vue` 的月亮/太阳图标，类名 `app-navbar__theme`）。

## 两套机制各管一半

1. **Element Plus 组件**（表格、弹窗、下拉、输入框…）走官方暗色变量：`main.ts` 引入
   `element-plus/theme-chalk/dark/css-vars.css`，`ui.applyTheme()` 在 `<html>` 上切 `.dark` 即可，**不用给 el-* 写任何覆盖**。
2. **自己写的页面皮肤**（各类容器的背景/边框/文字）统一用 `style.css` 里定义的语义变量：

| 变量 | 用途 |
| --- | --- |
| `--app-page-bg` | 页面底（body / main） |
| `--app-card-bg` | 白卡片、面板、顶栏 |
| `--app-subtle-bg` | 次级面板、侧栏 |
| `--app-hover-bg` / `--app-chip-bg` | 悬停底、浅灰芯片/按钮底 |
| `--app-active-bg` | 选中高亮底 |
| `--app-border` / `--app-border-soft` | 常规边框 / 分隔线 |
| `--app-text` / `--app-text-sub` / `--app-text-muted` / `--app-text-faint` | 四级文字 |
| `--app-highlight-bg` | 置顶笔记那种浅黄底 |
| `--app-chrome-bg` / `--app-chrome-text` / `--app-chrome-muted` / `--app-chrome-btn-bg` / `--app-chrome-btn-border` / `--app-chrome-shadow` | 画布浮动工具条、右键菜单这类「chrome」 |
| `--app-scrollbar` / `--app-scrollbar-hover` | 滚动条 |

`html.dark { … }` 里覆盖同一批变量即可，组件零改动。**新增样式别再写死中性色**（`#fff` / `#303133` / `#eef1f5` 这类），
否则暗色下就是白斑。装饰色（`#409eff`、`#67c23a`、`#f56c6c`、`#f7ba2a`…）和「彩色底上的白字」保持原样。

批量替换这类字面量时可以写脚本（只处理 `<style>` 块、只匹配 `background/border/color` 属性值），
改完用 `git diff --no-index <快照> <现在>` 复查一遍——本仓库没有基线提交，先拷一份 src 当快照最省事。

## 专注模式（画布全屏）

- `focusMode` 只做一件事：`layout/Index.vue` 的 `v-show="!ui.focusMode"` 收起侧栏/顶栏/标签栏。
- 高度不用改任何页面：`.app-layout.is-focus` 里把 `--app-header-height` / `--app-tags-height` 置 0，
  于是画布页那句 `calc(100vh - var(--app-header-height) - var(--app-tags-height))` 自动变成 100vh。
- 画布工具栏最右的按钮同时做两件事：`document.documentElement.requestFullscreen()`（失败也继续）+ `ui.setFocusMode(true)`；
  `fullscreenchange` 里发现退出全屏就关掉专注模式，于是 **Esc 一次就能回到普通布局**；组件卸载时也清掉，别把全站留在专注态。

## 已知取舍

- 画布**每块板的底色**（`work_canvas.theme`）和全站亮暗是两件事：前者是「参考板画布」，后者是「应用外壳」。
  所以暗色主题下也可以画在浅色板上，反之亦然。
- 没有做「跟随系统自动切换」（只在**首次**没有本地选择时按 `prefers-color-scheme` 取一次默认值），避免用户在系统层面切暗色时把界面突然改掉。
