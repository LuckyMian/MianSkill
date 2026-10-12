# 笔记图片走阿里云 OSS 直传

目标：在「随手笔记」里粘贴/拖拽/选择图片时，图片**直接传到 OSS**，N1 只保存一条 URL，不占 eMMC。

## 架构

```
浏览器 ──(1) POST /api/oss/policy 拿上传凭证──> PocketBase 钩子（持有 AK/SK，只在本机）
   └──(2) POST multipart 直传───────────────> 阿里云 OSS
   └──(3) 把 publicUrl 以 <img> 插进正文，自动保存
```

实现位置：服务端 `/opt/pocketbase/pb_hooks/oss.pb.js`；前端 `src/api/oss.ts`（取状态/取凭证/上传 + 大图压缩到 1600px）+ `NoteEditorPane.vue`（粘贴、拖拽、工具栏选图三个入口，都走同一条上传逻辑）。

## 服务端钩子的三个硬约束（本版本 PocketBase 0.40.5 实测）

1. **处理器看不到文件级作用域**。`routerAdd` 的回调在每个请求时会按源码重建，所以文件里的 `const`、`function`、甚至 `globalThis` 在回调里全是 `undefined`（实测 `typeof OSS_CONFIG === 'undefined'`、`ReferenceError: loadOssConfig is not defined`）。**唯一可靠的桥是 `$app.store()`**：文件级 `$app.store().set('oss_upload_helpers', {…})`，回调里 `$app.store().get('oss_upload_helpers')`；连 store 的 key 都必须用字面量（引用文件级常量同样 undefined）。所以 `oss.pb.js` 里所有实现都包在 `buildOssHelpers()` 里、经 store 传递。
2. **JSVM 没有 `require` 模块**（`crypto/hmac`、`encoding/base64`、`os`、`fs` 全都 `Invalid module`），只有 `$security`（md5/sha256/sha512/hs256/hs512/equal/randomString…）。OSS PostObject 要 HMAC-SHA1，所以钩子里自带纯 JS 的 UTF-8 / SHA-1 / HMAC-SHA1 / Base64 实现（放在 `buildOssHelpers()` 内）。
3. **`$os` 的坑**：`$os.readFile` 返回的是字节对象（不是字符串），而且**读不存在的文件会触发 Go 层 panic**——JS 的 `try/catch` 拦不住，整个路由直接返回 400（`Something went wrong while processing your request.`）。同理不要用"先读文件探测是否存在"的写法。`$os.getenv` 对不存在的变量安全（返回 ''），所以配置支持环境变量覆盖。

推论：钩子里出问题时的 400 是笼统的，排查要在回调里自己 `try/catch` 并把 `String(err)` 返回出去，否则只知道"失败了"。

## 配置（在服务器上填，别进 git）

`/opt/pocketbase/pb_hooks/oss.pb.js` 顶部的 `OSS_CONFIG`：

```js
const OSS_CONFIG = {
  accessKeyId: '',
  accessKeySecret: '',
  bucket: '',
  endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  dir: 'notes/',                 // key 形如 notes/2026/10/xxxxxxxx.png
  publicBaseUrl: '',             // 绑了自定义域名/CDN 就填，否则默认 https://<bucket>.<endpoint>
  maxSizeMB: 10,
  expireSeconds: 600,
}
```

也支持容器环境变量覆盖：`OSS_ACCESS_KEY_ID` / `OSS_ACCESS_KEY_SECRET` / `OSS_BUCKET` / `OSS_ENDPOINT` / `OSS_PUBLIC_BASE_URL`。

要点：

- AK/SK 只存在于 N1 上，浏览器只拿到"一次一签"的 policy + signature（默认 10 分钟有效、限目录前缀、限大小）。
- 建议在 RAM 里给这对 AK 只授 `oss:PutObject`（+ 需要的 `GetObject`），别用主账号 AK。
- `hooksWatch` 默认开启：改 `oss.pb.js` 后容器会自动重启（日志会打印 `File /pb/pb_hooks/oss.pb.js changed, restarting...`），约 5–8 秒生效。
- **`bucket` 必须允许跨域**：OSS 控制台加 CORS 规则，来源包含 `http://192.168.1.168:8090`（本地开发再加 `http://localhost:5173`），方法 `POST/GET/HEAD`，Header `*`。不加的话浏览器直传会被 CORS 拦掉。
- 当前实现假定 **bucket 可公有读**（正文里存的是普通 URL）。要放私有桶，需要再做一个"按 key 签 GET URL"的接口并在渲染时改写正文里的图片地址——没做，先别切私有读。

## 前端行为

- 三个入口：Ctrl+V 粘贴图片、把图片拖进正文、工具栏「插入图片」。三者共用 `uploadImageToOss()`。
- 大于 1.5MB 的图片先用 canvas 压到 1600px 内、JPEG 0.86 再传（透明图仍是 PNG 优先保留？当前实现：PNG 超过阈值也会压成 JPEG，如需保留透明要改 `shrinkIfNeeded`）。
- 上传中给一个常驻提示，成功后插入 `<img src="publicUrl">` 并触发自动保存；失败时提示具体原因，正文不会插入空标签。
- 未配置时前端会先查 `/api/oss/status`，直接给"去服务器填 OSS_CONFIG"的提示，不会白传。

## 部署与验证

- 部署钩子：**不要用 `cat > file <<EOF` 走 SSH exec**（命令一长就 `Unable to exec`），用 SFTP：`node put.mjs <本地文件> /opt/pocketbase/pb_hooks/oss.pb.js`，然后等 5–8 秒自动重启。
- 健康检查：`curl http://192.168.1.168:8090/api/oss/status` → `{"configured":true,...}`。
- **没有真密钥也能验证签名**：用测试密钥部署，POST `/api/oss/policy`（要带登录 token）拿回 policy/signature，再用 Node 独立复算 `base64(hmac_sha1(secret, policy))` 比对（脚本：`check-policy.mjs`），并检查 policy 的 `content-length-range` 与 `starts-with` 条件、key 前缀是否满足。这一步能证明除"OSS 是否接受"以外的整条链路都对。
- 真机验证：填好真密钥后，在笔记里贴一张图，`curl -I <publicUrl>` 应 200；如果 403，多半是 bucket 不是公有读或 CORS 没配。
