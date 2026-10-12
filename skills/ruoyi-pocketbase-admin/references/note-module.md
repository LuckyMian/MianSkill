# 随手笔记模块（Apple 备忘录风格）

和待办一样是**专用视图**，不走 CrudTable：`src/views/work/note/Index.vue` + `src/components/NoteBoard/`（`NoteSidebar` / `NoteListPane` / `NoteEditorPane`），状态在 `src/stores/note.ts`。数据在 `work_note`（笔记，正文是富文本 HTML）与 `work_note_folder`（文件夹）。

## 界面与行为（对齐 Apple 备忘录）

- 三栏：左「全部笔记 / 未分类 / 文件夹 / 最近删除」，中「搜索 + 新建 + 笔记列表」，右「正文编辑区」。窄屏（<1200px）侧栏与编辑区收成抽屉。
- **点开即写，没有弹窗、没有标题输入框**：列表里的标题就是**正文第一行**（`deriveTitle()`，最多 80 字），列表第二行显示日期 + 正文摘要（`noteSummary()`）。
- **自动保存**：输入后 800ms 落盘（`queueSave` → `flush`），切换笔记、失焦、离开组件时都会先 flush；底部显示「已自动保存 HH:MM:SS」。
- 新建 = 建一条空笔记并立刻聚焦正文；在某个文件夹里新建就自动归属该文件夹。
- 置顶（`pinned`）排最前；删除进「最近删除」（`trashed=true` + `trashed_at`），可恢复，也可彻底删除。
- 删除文件夹不删笔记：里面的笔记 `folder` 清空移到「未分类」。

## 富文本编辑器（零依赖，踩过的坑都在这）

用原生 `contenteditable` + `document.execCommand`，没有引入 Tiptap 之类的依赖；工具栏：加粗/斜体/下划线/删除线/小标题/无序列表/有序列表/待办勾选/清除格式，`Ctrl+B/I/U` 快捷键同样走 execCommand。

1. **工具栏必须用 `@mousedown.prevent`**，不能只用 `@click`：点击按钮会先抢走编辑器焦点，`execCommand` 就作用到错误的位置（表现为标题被后续文字串掉、列表插错地方）。这是最容易复发的坑。
2. **待办勾选不打乱 DOM**：`toggleChecklist()` 只给当前 `ul` 打 `class="checklist"`，方框用 CSS 伪元素画（`li::before` 的 ☐/☑、`li[data-checked="true"]` 加删除线），点条目左侧 22px 内切换 `data-checked` 再保存。这样回车新建条目、退格合并都不需要特殊处理，光标也不会乱跳。
3. **HTML→文本转换要在开标签前也补换行**：`contenteditable` 里回车产生的是 `<div>下一行</div>`，如果只把 `</div>` 换成换行，首行会和次行粘成一行，标题就串了（`htmlToText()` 里 `<br>`、闭合块标签、**开块标签**三处都要处理）。
4. 正文存 PocketBase 的 `editor` 字段（HTML）。`work_note.title` 只是派生出来给搜索和列表用的，不算「字段」。

## 扩展注意点

- 想换成 Tiptap/Quill：只需替换 `NoteEditorPane.vue` 的编辑器与 `exec` 调用，`store.saveNote(id, { content, title })` 这层契约不用动。
- 加「标签/附件/共享」之前先想清楚：Apple 备忘录的标签是正文里的 `#标签`，要真做建议在 `htmlToText` 后正则提取并写入 `tags` 字段（字段已存在，当前未使用）。
- 列表加载上限 300 条/视图，`-updated` 服务端排序 + 前端按「置顶优先、更新时间倒序」兜底（PocketBase 对 bool 排序不可靠）。

## 图片

粘贴 / 拖拽 / 工具栏选图**先在编辑器里本地预览**，点右下角「保存」才把图片传到阿里云 OSS，同时回收正文里被删掉的图片（N1 只存 URL，不占 eMMC）。上传凭证与删除都由 PocketBase 钩子签名，配置与坑见 [oss-images.md](oss-images.md)。
