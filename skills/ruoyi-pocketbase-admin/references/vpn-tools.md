# 工具 → VPN（内嵌 mihomo 的 metacubexd 面板）

页面：`views/tools/vpn/Index.vue`，路由 `/tools/vpn`，菜单「工具 → VPN」（`sys_menu` 里两条：`/tools` 父级 + `/tools/vpn`，
图标 `Tools` / `Connection`）。页面本身很简单——一条地址栏 + 一个铺满内容区的 `iframe`，重点是**地址可配**和**外网怎么走**。

## 环境事实（2026-10-13 实测）

| 项 | 值 |
| --- | --- |
| 面板服务 | **mihomo（clash）直接跑在 N1 宿主机上**，不是 Docker 容器；`netstat` 显示 `:::9090 LISTEN`（**全接口**，含 IPv6） |
| 面板路径 | `http://192.168.1.168:9090/ui/metacubexd/#/overview`（mihomo 的 `external-ui` 静态托管） |
| 控制 API | 同一端口的根路径（`/version` 等）**需要 secret**，不带 secret 返回 401 |
| 响应头 | HTML **没有 `X-Frame-Options`、没有 CSP** → 可以正常被 iframe 内嵌 |
| 注意 | 该服务只允许 **GET**：`curl -I`（HEAD）返回 **405 Method Not Allowed**，做连通性探测要用 GET |

## 地址是数据，不是代码（改地址不用重新构建）

优先级从高到低：

1. `localStorage.pb_vpn_url`——在这台设备上选过/填过的地址（切内外网时最有用）；
2. `sys_dict` 里 `dict_type='vpn_dashboard'` 的条目——页面下拉里的预设，**在「系统管理 → 字典配置」改完刷新即生效**；
3. 代码兜底 `http://192.168.1.168:9090/ui/metacubexd/#/overview`。

`pnpm setup:pb` 会灌一条默认预设（`setup-collections.mjs` 的 `DICTS`）。**字典灌入改成了按 `dict_type` 粒度**：
只有整类不存在时才写默认值，不会覆盖你在界面上改过的条目（原来只在「表为空」时才灌，新增一类字典就永远进不去）。

页面上还会做**可达性探测**：`fetch(url, { mode: 'no-cors', cache: 'no-store' })` + 6 秒超时。
`no-cors` 拿不到响应内容，但**请求完成就会 resolve**（401/404 也算通），只有网络层失败/混合内容拦截才会 reject；
不可达时页面给出兜底说明（含「在新标签打开」出口）。这套判断是**在浏览器侧**做的——服务端从 N1 探 9090 永远是通的，没有参考价值。

## 为什么不从 PocketBase 反向代理它

两点硬约束（别浪费时间去试）：

1. **控制面板的 API 与实时流量走 WebSocket**，而 PocketBase 的 JSVM 钩子只有 `$http.send`，**没法代理 WebSocket 升级**；
   代理过去会得到「页面能打开、数据全是空的」的半残效果。
2. **iframe 的 origin 必须保持 `http://<host>:9090`**：metacubexd 把「后端地址 + secret」存在**该 origin 的 localStorage** 里。
   如果改成从 8090 同源代理，origin 变了 → 面板要重新配置，而且和你平时单开面板那个标签页的设置不再共享。

所以这个页面就是「浏览器直连 9090」的壳，不要在后台侧做转发。

## 后期外网访问要怎么配

1. 让 **9090 能在公网访问**（iStoreOS 上加一条端口转发；或把面板挂到带 HTTPS 的反向代理上）。
2. 在 VPN 页面把地址切到对外地址（下拉里加一条字典条目，或直接用「自定义地址…」）。
3. 注意两条：
   - **混合内容**：如果这个后台以后是 HTTPS，浏览器会拦掉 `http://…:9090` 的内嵌页。页面已经会直接提示这一点——
     要么给 9090 也配 HTTPS（反代 + 证书），要么后台继续走 HTTP。
   - **安全**：mihomo 的 external-controller 只有一个 secret 做鉴权，**别把 9090 裸奔到公网**；优先「只放行给固定 IP / 走 VPN 或隧道 / 反代加一层认证 + TLS」。
4. 用户菜单里的「服务地址」是给前端连 PocketBase 用的，与这个 iframe 无关。

## 页面细节

- 顶栏：预设下拉（内网 / 自定义…）、地址输入（仅自定义时出现）、刷新（重载 iframe 并重新探测）、新标签打开、右侧状态（检测中/地址可达/面板已加载/不可达）。
- `iframe` 不 sandbox（要保留它的 localStorage 与 WebSocket），`allow="fullscreen; clipboard-read; clipboard-write"`。
- 高度沿用全站那套 `calc(100vh - var(--app-header-height) - var(--app-tags-height))`，手机上标签栏/顶栏变量归零后自动铺满。
- 手机端地址栏自动换行（媒体查询里 `select` 独占一行、输入框整行、状态另起一行）。

## 验证方法

用 `puppeteer-core` 打开 `#/tools/vpn`：

- 断言 `iframe[src]` 指向 `9090/ui/metacubexd/`，且**监听到对 9090 的真实响应**（`page.on('response')` 里能看到
  `/ui/metacubexd/` 与它的 `assets/*.js|css` 返回 200）——这是「真的嵌进去了」最硬的证据；
- 故意切到一个不可达地址（如 `http://192.168.1.99:9090/…`）断言出现兜底面板与「在新标签打开」；
- 最后切回内网预设，断言 iframe 恢复。
