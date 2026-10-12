# 笔记图片：阿里云 OSS 直传

在「随手笔记」里粘贴 / 拖拽 / 选图时，图片**直接传到 OSS**，N1 只保存一个 key，不占 eMMC。

## 线上现状（2026-10-12 配好并验证）

| 项 | 值 |
| --- | --- |
| bucket / region | `mianhome` / `cn-shenzhen` |
| 上传域名 | `https://mianhome.oss-cn-shenzhen.aliyuncs.com`（**经典 bucket 域名**） |
| 图片路径 | `notes/<年>/<月>/<16位随机>.<ext>` |
| 读权限 | **私有**：该阿里云账号禁止设公共读，所以走签名 GET |
| 服务端钩子 | `/opt/pocketbase/pb_hooks/oss.pb.js`（AK/SK 只在这台机器上） |
| 前端 | `src/api/oss.ts` + `NoteEditorPane.vue` |

## 架构

```
浏览器 ─(1) POST /api/oss/policy 拿上传凭证──> PocketBase 钩子（只在本机持有 AK/SK）
      ─(2) POST multipart 直传─────────────> OSS（bucket 私有 + 已配 CORS）
      ─(3) 正文写入 <img data-oss-key="notes/…" src="签名地址">
渲染  ─  GET /api/oss/sign?keys=a,b,c 换一批新的签名地址（默认 6 小时有效）
```

要点：

- **正文以 `data-oss-key` 为准**，`src` 只是当下有效的签名地址；每次打开发布前 `applySignedSources()` 会重新签名，过期不影响。
- 桶保持私有：裸链接匿名访问 403，带签名 200。
- 上传凭证：10 分钟有效、限定 `notes/` 前缀、限定大小；浏览器拿不到 AK/SK。
- 前端把 >1.5MB 的图先压到 1600px 再传（`shrinkIfNeeded`）。

## 服务端钩子的四个硬约束（本版本 PocketBase 0.40.5 实测）

1. **处理器看不到文件级作用域**：`routerAdd` 回调在每个请求时按源码重建，文件里的 `const`/`function`、乃至 `globalThis` 在回调里都是 `undefined`（实测 `typeof OSS_CONFIG === 'undefined'`、`ReferenceError: HELPER_KEY is not defined`）。唯一可靠的桥是 **`$app.store()`**：文件级 `$app.store().set('oss_upload_helpers', {…})`，回调里 `$app.store().get('oss_upload_helpers')`；连 key 都必须用字面量。
2. **JSVM 没有 `require` 模块**（`crypto/hmac`、`encoding/base64`、`os`、`fs` 全是 `Invalid module`），只有 `$security`（md5/sha256/sha512/hs256/hs512/equal/randomString…）。OSS 的 V1 签名要 HMAC-SHA1，所以钩子里自带纯 JS 的 UTF-8 / SHA-1 / HMAC-SHA1 / Base64（已与 Node crypto 对拍一致）。
3. **`$os.readFile` 返回字节对象**，且**读不存在的文件会触发 Go 层 panic**（JS try/catch 拦不住，整个路由返回 400）。所以配置直接写在钩子文件的 `OSS_CONFIG` 里，不读外部 JSON。`$os.getenv` 对不存在的变量安全（返回 ''），可作环境变量覆盖。
4. 钩子里的错误默认只变成笼统的 400，排查时要在回调里 `try/catch` 并把 `String(err)` 返回来定位。

## bucket 侧配置（已用 API 完成，可复核）

- **CORS**：`PUT /?cors`（签名带 Content-MD5/Content-Type）→ 200 ✔。规则允许来源 `http://192.168.1.168:8090`、`http://localhost:5173`，方法 POST/GET/HEAD，Header `*`。**不加 CORS 浏览器直传会被拦。**
- **公共读：做不到，也不必要**。`PUT /?policy` → `Put public bucket policy is not allowed`；`PUT /?acl`（`x-oss-acl: public-read`）→ `Put public bucket acl is not allowed`；`GET /?acl` 显示 `private`。该账号禁止公共读，所以设计成签名 GET。
- **接入点（Access Point）ARN 用不上**：用户给的是 `acs:oss:cn-shenzhen:<uid>:accesspoint/home/object/*`，但实测 `home-<uid>.cn-shenzhen.oss-accesspoint.aliyuncs.com` 等接入点域名都解析不了，而经典 bucket 域名上传/签名都通——PostObject 走经典域名即可。
- AK 建议用 RAM 子账号、只授 `oss:PutObject`（+ `oss:GetObject`）；AK/SK 只写在服务器的 `oss.pb.js` 里，别进 git。

## 部署与验证

- 改钩子：**别用 `cat > file <<EOF` 走 SSH exec**（命令一长就 `Unable to exec`），用 SFTP：`node put.mjs <本地文件> /opt/pocketbase/pb_hooks/oss.pb.js`；`hooksWatch` 默认开，5–8 秒自动重启生效。
- 健康检查：`curl /api/oss/status` → `{"configured":true,...}`；凭证：`POST /api/oss/policy`（需登录）→ `key/policy/signature/signedUrl`。
- **没有 OSS 交互也能验证签名**：用 Node 独立复算 `base64(hmac_sha1(secret, policy))` 与 `signature` 比对，再检查 policy 的 `content-length-range`、`starts-with` 条件与 key 前缀（脚本 `check-policy.mjs`）。
- 端到端（必须真机跑）：浏览器插一张图 → 断言正文含 `data-oss-key`、`img.naturalWidth > 0`、刷新后仍能显示、**带签名 200 / 裸链接 403**；完事用签名 DELETE 清掉测试对象。
- 私有桶的签名 GET 格式：`GET\n\n\n<Expires>\n/<bucket>/<key>` → `base64(hmac_sha1(secret, …))`，拼成 `?OSSAccessKeyId=&Expires=&Signature=`（Signature 要 URL 编码）。

## 删除笔记里的图片 → OSS 同步回收（已实现）

### 上传/删除都以「保存」为准（2026-10-12 调整）

- 贴图/拖图/选图：**先只做本地预览**（`blob:` + `data-oss-file-id`），底部提示"N 张图片待上传，点「保存」提交"。
- 点编辑器右下角的**保存**按钮：先把待上传图片传到 OSS（`<img>` 换成 `data-oss-key` + 签名地址）→ 正文存库 → 回收本次被删掉的图片，并弹出可见反馈（如"已保存：上传 1 张图片，删除 1 张已移除的图片"）。
- **文字自动保存仍在**，但有待上传图片时会让位（否则会把 `blob:` 预览地址写进正文，刷新变坏图）；切换笔记/离开页面会强制落盘（`flush(true)`），并有 `beforeunload` 拦截提醒。
- ⚠️ 踩过的坑：`queueSave()` 里**不要**把 `saving` 置 true——`el-button :loading` 会连带禁用按钮，用户每次敲完字再点「保存」都点不动，表现就是"保存/删除没反应"。
- ⚠️ `ElMessage` 默认 3 秒消失，E2E 断言要用**轮询**捕获提示，别用固定 sleep。

- **触发点**：笔记**保存**时对比保存前后正文里的 `data-oss-key`，不再被引用的 key 调 `POST /api/oss/delete` 回收；另外"刚上传、还没保存就被删掉"的（粘了又删）会被 `pendingUploads` 当成孤儿一起回收。
- **删除方式**（钩子 `OSS_CONFIG.deleteMode`）：
  - `'hard'`（**当前线上默认**）：直接物理删除，阿里云控制台立刻看不到文件；
  - `'trash'`：先 CopyObject 到 `trash/<原 key>` 再删原件 → 可恢复（配合已配好的 30 天生命周期规则清理）。
  - 换成 trash 的动机只有一个：误删可恢复；代价是空间不会立刻释放。
- **整条笔记移入「最近删除」不回收图片**（笔记还能恢复）；只有**彻底删除**才回收它引用的所有图片。
- bucket 上已配生命周期规则：`trash/` 前缀 **30 天自动清理**（`PUT /?lifecycle` 200，`GET /?lifecycle` 可回读确认），所以回收站不会无限增长。
- 服务端删除要点：JSVM 里 `$http` **只有 `send` 一个方法**；删除用 V1 签名 `DELETE\n\n\n<Date>\n/<bucket>/<key>`，CopyObject 是 `PUT /<bucket>/<trashKey>` 且必须把 `x-oss-copy-source` 计入 `CanonicalizedOSSHeaders`；`$http.send` 返回的 `body` 是**字节数组**，要读文本得自己转字符串。
- 端到端验证：贴图 → 从笔记里删掉图片 → 断言原 key 404、`trash/<key>` 200；再把整条笔记彻底删除 → 断言图片同样进 trash。收尾用签名 DELETE 清掉 trash 里的测试对象。
