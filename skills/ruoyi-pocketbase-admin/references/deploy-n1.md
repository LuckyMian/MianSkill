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
