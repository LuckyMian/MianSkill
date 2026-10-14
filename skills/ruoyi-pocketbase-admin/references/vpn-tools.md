# VPN 面板入口（nginx 反代 mihomo 的 metacubexd 面板）

> **2026-10-14 改版：页面已下线。** 菜单「工具 → VPN」（`sys_menu` 的 `/tools` + `/tools/vpn`）已删除，
> `views/tools/vpn/Index.vue` 也已删掉（`fallbackMenu.ts` 同步去掉）。现在入口只有一个：
> **工作台主页顶部的「打开 VPN 面板」按钮**（`views/dashboard/Index.vue`），点击**新标签**打开面板。
> 为什么改：内嵌 iframe 拿不到 Basic 凭证（见下），弹框反复出现，用户体感很差；直接新标签打开一切正常。
> 这页剩下的内容是 nginx 侧怎么配、怎么排查，以及（万一以后要恢复内嵌时的）iframe 认证方案。

面板**不是直连 9090，而是走 N1 上的 nginx 入口 9080**（2026-10-13 起）；
入口地址由工作台主页那个按钮拼（主机名沿用当前控制台，内网 9080 / 外网 19080）。

## 现在的链路

```
浏览器 ──9080──> nginx（N1 / iStoreOS）
                  ├─ /                    → 播种页（写同源 localStorage 再跳面板）
                  ├─ /_ping               → 免认证探活，只回 "vpn-proxy-ok"
                  ├─ /ui/metacubexd/* 等  → 127.0.0.1:9090（注入 Authorization: Bearer <secret>，Basic Auth 保护）
                  └─ /traffic /memory /connections /logs（WebSocket）
                                          → 127.0.0.1:9090，**不套 Basic**，改校验 ?token=<secret>
      mihomo（clash）仍监听 0.0.0.0:9090：它自己托管面板静态文件 + 控制 API；
      nginx 走 127.0.0.1:9090，所以以后把 9090 从局域网/公网关掉也不影响这个页面。
```

好处：外网只需要转发**一个**端口（加一层 Basic Auth，将来加 TLS 也只改这一处）；
密钥由 nginx 注入，页面使用者不用再手填密钥。

**端口对照（2026-10-14 起）**：

| 场景 | 控制台 | 面板入口 | 说明 |
| --- | --- | --- | --- |
| 内网 | `http://192.168.1.168:8090` | `http://192.168.1.168:9080/` | nginx 本口，直连 |
| 外网 | `http://luckymian.xyz:18090` | `http://luckymian.xyz:19080/` | 电信网关上「外部 19080 → 192.168.1.168:9080」 |

**两条入口（2026-10-14 起）**：

| 谁在用 | 怎么进 | 认证 |
| --- | --- | --- |
| 人（浏览器直接打开/收藏夹） | `http://<主机>:9080/`（外网 `:19080`） | Basic 弹框，用户名 `admin`，密码在 `vpn.htpasswd` |
| 应用内嵌的 iframe | `http://<主机>:9080/__panel?token=<TOKEN>` | 该口只认 token，`Set-Cookie: vpn_ok=<TOKEN>` 后 302 到 `/`，之后全站靠 Cookie 走 |

为什么内嵌非要绕这一圈：**iframe 里没法带 Basic 凭证**——Chromium 会把 URL 里 `user:pass@` 的
整个子帧请求直接丢掉（2026-10-14 实测：带凭证的 iframe 连请求都不发，控制帧却照发），
于是只能靠弹框；而弹框每个浏览器会话、每个 origin 都要来一次，用户体感就是「密码老是重复弹」。
token → Cookie 之后，内嵌面板零弹框（实测：在一个**没有任何缓存凭证**的 origin 上，
浏览器从控制台页面里加载 `/__panel`，全程没有一个 401）。

配置要点（`/etc/nginx/conf.d/vpn.conf`）：

- `map_hash_bucket_size 128;` + `map $cookie_vpn_ok $vpn_ok {...}`：Cookie 命中即视为已认证（这个 build 没有 `auth_request` 模块，所以用 map）。
- `location = /__panel`：校验 `?token=`，种 Cookie，302 到 `/`。
- `location = /__seed`、`location /__open/`：`internal` 落地页（带 Cookie 的请求由 `if ($vpn_ok = 1) { rewrite … last; }` 转进来），后者用 `proxy_pass http://127.0.0.1:9090$request_uri` 把原 URI 转给 mihomo。
- WS 那几个路径照旧只认 `?token=<mihomo secret>`；`/_ping` 照旧免认证。

**换 token 要同时改两处**：nginx 里 `__panel`/map 的 token，和 `sys_dict` 里 `dict_type='vpn_panel_token'`
那条记录（前端读它拼 iframe 地址）。少改一处 = iframe 拿到 401 弹框。token 是**凭据**，
只存在路由器配置和数据库里，别写进技能文档或前端代码。

前端**按当前访问的主机名自动选端口**：私有网段（10./192.168./172.16-31./localhost）走 9080，其余（域名/公网 IP）走 19080；
主机名沿用你访问控制台的那个，所以内网 IP、公网 IP、域名三种进法都自洽。先探 9080/19080 里该走的那个，不通再试另一个。

## 三条硬约束（决定了为什么要这么搭）

1. **浏览器不会给 `ws://` 带 Basic 凭证**（实测报 `HTTP Authentication failed; no valid credentials available`）。
   所以 WS 那几个路径不能套 Basic Auth，改成校验面板自己带的 `?token=<secret>`（metacubexd 用 query 传，因为 WS 没法加自定义头）。
   连带结论：**播种页里写的 secret 必须是 mihomo 的真值**，否则 WS 的 token 对不上。
2. **metacubexd 把「后端地址 + 密钥」存在它自己 origin 的 localStorage**：`endpointList = [{id,url,secret}]`、
   `selectedEndpoint = "id"`（值都是 JSON 字符串，键名来自打包后的源码 `it(J([]), { name: 'endpointList' })`）。
   要让面板打开就是配置好的、不再弹「填地址/密钥」，就得**在同源的页面里先写好这两个键** → 这就是播种页的作用。
3. **PocketBase 钩子代理不了 WebSocket**（JSVM 只有 `$http.send`），nginx 可以 ✔ —— 所以这一层放在 nginx，而不是前端或 PocketBase。

## N1 上的文件（都在路由器上，不进前端仓库）

| 路径 | 作用 |
| --- | --- |
| `/etc/nginx/conf.d/vpn.conf` | 唯一的 server 块：9080 监听、Basic Auth、注入 secret、WS 处理 |
| `/etc/nginx/seed/index.html` | 播种页：写 localStorage → `location.replace('/ui/metacubexd/#/overview')` |
| `/etc/nginx/conf.d/vpn.htpasswd` | Basic Auth 账号（`openssl passwd -apr1` 生成，0600） |
| `/etc/nginx/uci.conf` | OpenWrt 的 nginx 是 **uci 驱动**生成这个文件；`/etc/nginx/nginx.conf` 根本不存在，`nginx -t` 要 `-c /etc/nginx/uci.conf` |

nginx 相关操作：

```sh
/etc/init.d/nginx enable && /etc/init.d/nginx start   # 开机自启 + 启动
/etc/init.d/nginx reload                              # 改完 conf.d 后重载（scp 覆盖不会自动生效！）
nginx -t -c /etc/nginx/uci.conf                       # 语法检查
```

## 踩过的坑（改这份配置前必读）

1. **包自带的默认 server 会抢 80/443**（那是 uhttpd/LuCI 的端口）→ nginx 起不来、procd 崩溃循环。
   处理：`uci delete nginx._lan`、`uci delete nginx._redirect2ssl`、`uci commit nginx`（保留 `nginx.global.uci_enable='true'`，
   否则 init 脚本会说 “NOT using conf file!” 并去找不存在的 `/etc/nginx/nginx.conf`）。
2. **`auth_basic` 提到 server 级后，WS 的 location 必须显式 `auth_basic off`**，否则 WS 握手照样被 Basic 拦（就是坑 1 的翻版）。
3. **`location = /` 里不要用 `index index.html`**：index 模块会内部重定向到 `/index.html`，反而落到带代理的 `location /`。
   用 `try_files /index.html =404;` + 单独一个 `location = /index.html`。
4. **scp 覆盖配置后一定要 reload**，否则你以为改好了、其实跑的还是旧配置（排查时 `nginx -T` 看生效内容最省事）。

## 常用维护动作

```sh
# 改 nginx 入口账号密码（用户名 admin）——只动这一处，不用碰 OpenClash
openssl passwd -apr1 '新密码' > /tmp/h && printf 'admin:%s\n' "$(cat /tmp/h)" > /etc/nginx/conf.d/vpn.htpasswd && rm -f /tmp/h
chmod 600 /etc/nginx/conf.d/vpn.htpasswd && /etc/init.d/nginx reload

# 注意区分两串密码：
#   nginx 入口密码（浏览器弹框要输的）只在 vpn.htpasswd 里，随便改；
#   mihomo 的 secret 是 nginx 注入上游用的，还写在播种页里给 WebSocket 当 ?token=，
#   改它要同时改三处：OpenClash 设置（dashboard_password）、vpn.conf 的 Bearer、seed/index.html 的 secret。
# 改完入口密码后，浏览器可能还拿旧密码重试 → 再弹一次框输新密码即可（或在浏览器里删掉该站点的密码记录）。

# 忘了入口密码怎么办（2026-10-14 踩过）：**htpasswd 里的密码不一定是 mihomo secret**，
# 别拿 OpenClash 那串去试。用 apr1 哈希直接核对/重设，验证只用 curl 看状态码，别把密码打进日志：
#   HASH=$(cut -d: -f2 /etc/nginx/conf.d/vpn.htpasswd); SALT=$(printf '%s' "$HASH" | cut -d'$' -f3)
#   openssl passwd -apr1 -salt "$SALT" '候选密码'      # 与 $HASH 相同即该密码有效
#   curl -s -o /dev/null -w '%{http_code}\n' -u admin:'候选密码' http://127.0.0.1:9080/version   # 200 = 有效
# 弹框里的 realm 文案是 `VPN Panel`（vpn.conf 的 auth_basic），用来区分「nginx 的弹框」和
# 「日常工作台自己的登录页（要 PocketBase 账号，见下）」。

# 「密码明明对，浏览器却一直弹框 / 一直说不对」的排查顺序（2026-10-14 用户实际遇到）：
#   1) 先在 N1 上验证服务端：curl -u admin:'密码' http://127.0.0.1:9080/version → 200 就是服务端没问题；
#   2) 那就是浏览器把**以前保存的旧密码**自动填进了弹框（历史上 vpn.htpasswd 的密码从 mihomo secret 改成过
#      用户自己的密码，Chrome 还记着旧的）。让用户去 chrome://password-manager/passwords 搜该域名删除旧记录，
#      或用无痕窗口手输验证一次，成功后正常窗口再输一次并保存。
#   3) 顺带确认他盯的是不是另一个弹框：控制台登录卡片要的是 PocketBase 账号（`admin@istoreos.lan`），
#      nginx 那套 `admin`/入口密码在这里一定失败 —— 两个密码不要混用同一串测试。

# 加 TLS（外网访问建议）：需要真证书（自签会被浏览器拦），在 vpn.conf 的 server 里加
#   listen 9443 ssl;  ssl_certificate /path/fullchain.pem;  ssl_certificate_key /path/privkey.pem;
# 外网只转发 9443，并在应用里把 VPN 地址换成 https://<域名>:9443/

# 彻底不让局域网直连 9090（可选；nginx 走 127.0.0.1，不受影响）
iptables -I INPUT -i br-lan -p tcp --dport 9090 -j DROP     # 撤销：把 -I 换成 -D
```

## 应用侧（2026-10-14 二次改：按钮由数据字典配置）

工作台主页顶部那排快捷按钮**完全由数据驱动**，代码里不写死地址、也不做主机名/端口推导：

- 数据来源：`sys_dict` 里 `dict_type = 'dashboard_link'` 的记录 —— `label` = 按钮文字、`value` = 网址、
  `color` = 按钮颜色（`primary/success/warning/danger/info`，其它值按 `primary`）、`sort` = 前后顺序。
  目前只有一条：`VPN 面板 → http://luckymian.xyz:19080/ui/metacubexd/#/overview`。
- 增删按钮 = 在「系统管理 → 字典配置」里加/删这条记录（`value` 必须以 `http://` 或 `https://` 开头才会渲染成按钮）；
  一条都没有时这行不显示。
- 点击一律 `window.open(url, '_blank', 'noopener')`：**新标签打开**，不顶掉工作台。
- 旧的两版实现都已删除：`views/tools/vpn/Index.vue`（地址栏 + iframe 专用页）没了，工作台里那套
  「同主机名 + 9080/19080 自动选端口」和读 `vpn_panel_token` 拼 `/__panel?token=` 的写法也一并去掉了
  （用户明确要「直接跳那个地址」+「按钮自己能加能删」）。
- `/__panel?token=…` 这套 nginx 机制和 `sys_dict.vpn_panel_token` 记录**留着但不被前端调用**：
  哪天想在按钮上免掉 Basic 弹框，把某个 `dashboard_link` 的 `value` 设成
  `http://<主机>:9080/__panel?token=<TOKEN>`（或外网 19080 那条）即可，落点一样是面板。
- `sys_dict.vpn_dashboard`（老的内网地址预设）同样只剩历史用途，前端不再读。

### 老版本（专用页面）的地址解析，留着参考

- 地址来源优先级（2026-10-14 改）：**下拉选「自动（内网 9080 / 外网 19080）」= 默认** ——
  按 `location.hostname` 判断私有网段选端口（`isPrivateHost()`），拼出 `协议//主机名:9080|19080/`，
  先探主端口再探另一个（`autoCandidates()` / `resolveAuto()`）；dev（localhost:5173）时改用 PocketBase 服务器的主机名。
  用户手动切过预设/自定义地址才写 `localStorage.pb_vpn_url`（按设备生效），列表里再切回「自动」＝`clearPersist()` 恢复自动；
  `sys_dict` 的 `vpn_dashboard` 条目现在只是「手动可选项」，不再是默认值。旧版本在「内网（默认）」上存过的那条
  `http://192.168.1.168:9080/` 会在挂载时被识别并清掉，免得带出外网还一直指向内网地址。
- **iframe 地址 = 入口地址 + `__panel?token=…`**：`entryToken` 读 `sys_dict` 的 `vpn_panel_token`，
  拼成 `frameSrc`（`openExternal()` 也用它）；没配 token 就退回直连（会弹一次 Basic 框，功能不受影响）。
  `checkReach()` 探活仍打入口的 `/_ping`（免认证），所以地址可达性不受 token 影响。
- 探活：`fetch(<origin>/_ping, { mode: 'no-cors' })` + 6 秒超时（`no-cors` 看不到状态码，但请求完成即 resolve；
  `/_ping` 是免认证的，所以不会被 Basic 干扰）。
- 第一次打开会弹一次 **nginx 的账号密码**（Basic Auth 的浏览器行为，输一次就记住）——这是页面顶栏那句提示的由来。
- 混合内容：后台若是 HTTPS，内嵌的 `http://…:9080` 会被浏览器拦，页面会直接提示要一起换 HTTPS。

## 环境事实

- N1 是 **iStoreOS 25.12.5（amlogic/meson）**，包管理器是 **`apk`（apk-tools 3.0.5），不是 opkg**（`opkg: not found`）。
  nginx 用 `apk add nginx` 装的（装的是 `nginx-ssl 1.26.3`）。
- overlay 分区 1.2G / 空闲约 1.0G，nginx 这套只占几百 KB。
- mihomo 由 OpenClash 拉起（进程 `clash -d /etc/openclash -f /etc/openclash/<配置>.yaml`），
  `external-controller: 0.0.0.0:9090`、`secret` 与 `openclash.config.dashboard_password` 同一个值——
  **改密码要改 OpenClash 那边的设置**，然后同步更新 `vpn.conf` 里注入的 Bearer 和播种页里的 secret。

## 怎么验（两条腿都要走）

## 外网访问：卡点在电信网关的端口映射（2026-10-14 实测）

报「外网访问不到 VPN 页面」时，**先分清楚是 N1 侧坏了还是外网没转发**，两边都查一遍：

| 检查 | 命令 / 结果 |
| --- | --- |
| N1 侧 nginx 活着吗 | `curl -s -o /dev/null -w '%{http_code}' http://192.168.1.168:9080/_ping` → 200；`netstat -lntp \| grep 9080` 有 `uci.conf` 进程 |
| 外网到底开了哪些端口 | 用外部视角测（N1 自己看不到 hairpin）：`https://check-host.net/check-tcp?host=<WAN_IP>%3A<port>&max_nodes=2`，再取 `https://check-host.net/check-result/<request_id>` |
| 域名指向对不对 | `https://luckymian.xyz` 由 **ddns-go**（alidns，网卡 br-lan）维护，日志在 `/var/log/ddns-go.log`，配置 `/etc/ddns-go/ddns-go-config.yaml` |

**2026-10-14 的实测结论**：N1 侧完全正常（nginx 9080 在听、`/_ping` 200、mihomo 9090 在听），
**但电信网关（`192.168.1.1`，中国电信智能网关，Web 8080/80，无 SSH、无 UPnP IGD）只转发了 `18090 → 192.168.1.168:8090`（控制台）**；
从公网测 `113.222.41.217` 的 8090 / 9080 / 9090 / 9876 / 443 / 80 … 全部 `Connection refused`，
所以 VPN 面板（9080）从外网进不来。DDNS 没问题（WAN IP 113.222.41.217 未变，`ddns-go` 03:07 还比对过一次）。

两条修法（都动不了 N1 以外的东西时，得让用户选一条）。**2026-10-14 用户选了第 1 条**：

1. **在网关加一条端口映射**（最贴合本页设计，改动最小）：外部 `19080` → `192.168.1.168:9080` TCP —— 用户已加好，
   外部节点实测 `http://113.222.41.217:19080/` 返回 **401 Unauthorized**（＝ nginx 的 Basic Auth，证明这条转发落到了 9080 而不是 PocketBase），
   前端随即改成「内网 9080 / 外网 19080 自动选」。要再加一个端口就照葫芦画瓢，别忘了同步前端里的
   `INTERNAL_PORT` / `EXTERNAL_PORT` 和本页的端口对照表。
2. **让 nginx 顶上已经转发出去的那个端口**（不需要网关权限，但要动容器和路由）：把 PocketBase 的映射从
   `8090` 改成内部 `8091`（容器参数：`alpine:3.24` + `serve --http=0.0.0.0:8090` + `/opt/pocketbase → /pb` + 96MiB 限制），
   nginx 接管 `8090`：`/` 与 `/api/*` 反代到 `127.0.0.1:8091`（不套 Basic），
   mihomo 的路径（`/ui/metacubexd/*`、`/version`、`/proxies`、`/configs`、`/traffic` 等）按原样反代到 `9090` 并注入 Bearer，
   种子页挪到 `/vpn/`。外网地址不变（`http://luckymian.xyz:18090/` 还是控制台），面板在 `http://luckymian.xyz:18090/vpn/`；
   前端 `VITE_PB_URL` 是空的（同源），所以换到 nginx 后面也不用重新构建。
   **代价**：全站多了一层 nginx（它挂了控制台就外部/局域网都不通），PocketBase 直连地址变成 `192.168.1.168:8091`。

顺带：种子页里写的是 `location.origin`，所以面板挂在哪个 origin 都能自洽，两种修法都不用改它。

## 两个「要密码」的地方别搞混（外网排查时最容易混）

| 弹框形态 | 要的是什么 | 存在哪 |
| --- | --- | --- |
| 浏览器**系统弹框**，文案带 `VPN Panel` | nginx 的 Basic 账号（用户名固定 `admin`，密码见 `vpn.htpasswd`，**不是** mihomo secret） | 按 origin 缓存：内网 `192.168.1.168:9080`、外网 `luckymian.xyz:19080`、公网 IP `:19080` 是三个不同 origin，各弹一次；浏览器重启后可能再弹 |
| 页面里的**登录卡片**（日常工作台 · 账号/密码 + 「登录」按钮） | **PocketBase** 账号（superuser 或 `users` 集合记录），`admin`/nginx 密码在这里必然失败 | `localStorage` 的 token 同样按 origin 存；LAN 登过不代表域名端登过（`router/guard.ts` 里没登录会直接跳 `/login`） |

机器上现存的 superuser 只有 `admin@istoreos.lan`（2026-10-14 在 `pb_data/data.db` 里核对到记录；`codex-temp@` / `codex-verify@` 已删）。
忘记密码就用 `docker exec pocketbase /pb/pocketbase superuser upsert admin@istoreos.lan '<新密码>'` 重设（明文只走命令行、别写进技能文档）。

```sh
# 1) N1 上（或任意在内网的机器）
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.1.168:9080/_ping              # 200，免认证
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.1.168:9080/version            # 401（要 Basic）
curl -s -u admin:<pw> http://192.168.1.168:9080/version                                # 200 {"meta":true,...}
curl -s -u admin:<pw> -o /dev/null -w '%{http_code}\n' http://192.168.1.168:9080/ui/metacubexd/
curl -s -i -N -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Version: 13' \
  "http://192.168.1.168:9080/traffic?token=<secret>" | head -1                          # 101 Switching Protocols
```

浏览器侧（puppeteer，`page.authenticate` 提供 Basic 凭证）：

- 打开 `#/tools/vpn`，断言 iframe 指向 9080、`/_ping` 与面板资源都是 200、**没有 4xx/5xx**；
- 单独开一个页签访问 `http://192.168.1.168:9080/`，等它跳到 `/ui/metacubexd/` 后断言
  **页面上没有输入密钥的表单**（`input[placeholder="secret"]` / 「添加」按钮）——这条就是「不再让你填密钥」的回归断言；
- 再切一个不可达地址（如 `http://192.168.1.99:9090/…`）断言出现兜底面板。
