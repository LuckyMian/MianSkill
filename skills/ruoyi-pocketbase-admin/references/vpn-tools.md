# 工具 → VPN（nginx 反代 mihomo 的 metacubexd 面板）

页面：`views/tools/vpn/Index.vue`，路由 `/tools/vpn`，菜单「工具 → VPN」（`sys_menu` 两条：`/tools` 父级 + `/tools/vpn`，
图标 `Tools` / `Connection`）。页面本身只是一条地址栏 + 铺满的 `iframe`；
**面板不是直连 9090，而是走 N1 上新增的 nginx 入口 9080**（2026-10-13 改）。

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

好处：外网只需要转发 **9080** 一个端口（加一层 Basic Auth，将来加 TLS 也只改这一处）；
密钥由 nginx 注入，页面使用者不用再手填密钥。

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

# 加 TLS（外网访问建议）：需要真证书（自签会被浏览器拦），在 vpn.conf 的 server 里加
#   listen 9443 ssl;  ssl_certificate /path/fullchain.pem;  ssl_certificate_key /path/privkey.pem;
# 外网只转发 9443，并在应用里把 VPN 地址换成 https://<域名>:9443/

# 彻底不让局域网直连 9090（可选；nginx 走 127.0.0.1，不受影响）
iptables -I INPUT -i br-lan -p tcp --dport 9090 -j DROP     # 撤销：把 -I 换成 -D
```

## 应用侧

- 地址来源优先级：`localStorage.pb_vpn_url`（这台设备选过的）> `sys_dict` 的 `vpn_dashboard` 条目（默认
  `http://192.168.1.168:9080/`，改它不用重新构建）> 代码兜底常量。
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
