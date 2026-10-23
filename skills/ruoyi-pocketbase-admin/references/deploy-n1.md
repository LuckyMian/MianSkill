# 部署到 N1 与线上排查

## 目标设备（实测）

Phicomm N1，刷 iStoreOS（OpenWrt 系）。4 核 ARM，内存约 1.9GB、**无 swap**，rootfs 是 1.2GB eMMC 的 overlay（可用约 1.1GB）。Docker 已开机自启（`S99dockerd`）。

容器：`pocketbase`，镜像 `alpine:3.24`，`--restart unless-stopped`，命令 `serve --http=0.0.0.0:8090`，`-p 8090:8090`，`-v /opt/pocketbase:/pb`，内存限制 **96MiB**。二进制是静态 arm64 的 PocketBase 0.40.5，放在挂载卷里，升级只需替换 `/opt/pocketbase/pocketbase`。

关键结论：**前端不增加 N1 负担**——产物是 1.6MB 静态文件，由 PocketBase 顺带发出（实测容器 CPU 0.07%、内存 20.84MiB/96MiB）。真正要留意的是 eMMC 只有 1.2GB：`pb_data` 目前约 33MB，若要存附件应先把 `/opt/pocketbase` 迁到外置盘。

## 三种发布方式

发布 = 把 `frontend/dist` 覆盖到 `/opt/pocketbase/pb_public`。PocketBase 实时读盘，**不用重启容器**。

1. 交互式（推荐，自动探测容器与挂载；用 SSH 密码）：
   ```powershell
   pwsh -File scripts\deploy-interactive.ps1
   ```
   它先跑 `docker ps` 认容器、`docker inspect` 读挂载，优先写 bind mount 的宿主目录，命名卷才回退 `docker cp`；覆盖前把旧 `index.html` 改名成 `index.backup-<时间>.html`。
2. 非交互（凭据已配好时）：`pnpm deploy:pb --target=docker://root@192.168.1.168:22/pocketbase:/pb/pb_public`
3. 直接写宿主目录（已映射共享或本机就在 N1 上）：`pnpm deploy:pb --target="\\192.168.1.168\…\pb_public"`

`scripts/deploy.mjs` 只写入不删除，并要求目标路径以 `pb_public` 结尾（否则需显式 `--force`）。

## SSH 凭据：从环境变量读，不要硬编码

N1 目前仍是**密码登录**（没装公钥），任何 `ssh` / `scp` 都要密码。凭据只存在**本机用户级环境变量**里，技能文件、脚本、命令行参数里都不出现：

| 变量 | 含义 |
| --- | --- |
| `N1_SSH_HOST` | `192.168.1.168`（内网地址，本身不是秘密） |
| `N1_SSH_USER` | `root` |
| `N1_SSH_PASSWORD` | 登录密码，只存在于环境变量 |

**Windows 上设置（一次性）**，写入用户级注册表，新开的终端才生效：

```powershell
[Environment]::SetEnvironmentVariable('N1_SSH_HOST','192.168.1.168','User')
[Environment]::SetEnvironmentVariable('N1_SSH_USER','root','User')
[Environment]::SetEnvironmentVariable('N1_SSH_PASSWORD','<密码>','User')
```

**读取**：

```powershell
[Environment]::GetEnvironmentVariable('N1_SSH_PASSWORD','User')
```

注意：`SetEnvironmentVariable(...,'User')` 只写注册表，**已经运行中的进程看不到**——已开着的终端、WorkBuddy/Codex 进程里 `$env:N1_SSH_PASSWORD` 仍是空的，必须重开进程。PowerShell 用上面带 `'User'` 作用域的写法可以直读注册表，不受影响；Bash 里要用新的 shell 会话。

**非交互执行 ssh/scp**：Bash 工具里没有 tty，`ssh` 不会弹密码提示，会直接 `Permission denied`。要用 `SSH_ASKPASS` 把密码喂进去，且密码从环境变量取、经临时文件转手，避免出现在 `ps` 或命令行历史里：

```bash
mkdir -p /tmp/n1 && printf '%s' "$N1_SSH_PASSWORD" > /tmp/n1/pass && chmod 600 /tmp/n1/pass
printf '#!/bin/sh\ncat /tmp/n1/pass\n' > /tmp/n1/ap.sh && chmod 700 /tmp/n1/ap.sh
export SSH_ASKPASS=/tmp/n1/ap.sh SSH_ASKPASS_REQUIRE=force DISPLAY=:0

scp -O -q file.txt root@192.168.1.168:/tmp/
ssh root@192.168.1.168 'echo ok'

rm -rf /tmp/n1   # 用完立刻删
```

四个容易踩的点：

- `SSH_ASKPASS_REQUIRE=force` 是关键。少了它，ssh 在存在 tty 时仍走终端提示，在工具里就会直接失败。
- `DISPLAY` 必须非空（随便填），否则 askpass 被当成无效环境忽略。
- 密码文件 0600、askpass 脚本 0700，用完 `rm -rf`；不要 `echo $N1_SSH_PASSWORD`，也不要用 `-o` 把密码塞进 ssh 参数。
- `scp` 仍要加 `-O`（dropbear 没有 sftp-server）。

## 两个必须知道的坑

- **`scp` 必须加 `-O`**。iStoreOS 的 SSH 是 dropbear，通常没装 `sftp-server`，OpenSSH 9.x 默认走 SFTP 子系统会失败；`scp -O` 强制用旧 SCP 协议才通。手工传文件时同理。
- **hash 路由**。静态托管没有 SPA 回退，`http://192.168.1.168:8090/work/task` 会 404；正确地址是 `http://192.168.1.168:8090/#/work/task`。

## 发布后的验证清单

```powershell
$b='http://192.168.1.168:8090'
curl.exe -s -o NUL -w "%{http_code}`n" "$b/"          # 200，且内容含「日常工作台」
curl.exe -s -o NUL -w "%{http_code}`n" "$b/_/"        # 200：PocketBase 管理后台没被影响
curl.exe -s "$b/api/health"                            # {"code":200,...}
```

再从首页 HTML 里取出 `./assets/index-*.js` 逐个请求，确认静态资源都 200（PocketBase 对缺失文件返回 404，不会回退到 index.html）。

## 回滚

`pb_public/index.backup-<时间>.html` 就是被替换掉的旧首页，改回 `index.html` 即恢复；`assets/` 是本次新增的，删掉即可。没有任何数据库改动，所以回滚是纯文件操作。

## 迁移到外置盘（eMMC 空间不够时）

```sh
docker rm -f pocketbase
cp -a /opt/pocketbase /mnt/<外置盘>/pocketbase
docker run -d --name pocketbase --restart unless-stopped -p 8090:8090 \
  -e TZ=Asia/Shanghai -v /mnt/<外置盘>/pocketbase:/pb --memory 192m \
  --entrypoint /pb/pocketbase alpine:3.24 serve --http=0.0.0.0:8090
```

数据格式不变，前端产物也跟着一起搬（因为就在 `pb_public` 里）。顺手把内存上限从 96MiB 调到 192–256MiB 更稳妥。

## 线上诊断命令（SSH 到 N1 后）

```sh
docker ps --format '{{.Names}}|{{.Image}}'          # 认容器
docker inspect pocketbase --format '{{json .Mounts}}'   # 认挂载
docker stats --no-stream pocketbase                  # 内存/CPU 实况
free -m; df -h /opt; du -sh /opt/pocketbase          # 资源与占用
docker logs --tail 50 pocketbase                     # 启动日志（含首次安装链接、超管提示）
ls -la /opt/pocketbase/pb_public                     # 前端产物与备份文件
```

注意 8090 端口来自 LAN 访问没问题（实测从 192.168.1.210 可直连）；如果哪天要放到公网，必须加 TLS 与访问控制，PocketBase 本身不做账号以外的防护。
