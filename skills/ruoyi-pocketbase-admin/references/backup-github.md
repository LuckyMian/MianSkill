# 定时整容器备份 → GitHub（N1 上已上线）

2026-10-14 上线。**每周一 00:00（即「周日晚上 12 点」）**，N1 把 `pocketbase` 容器整包打成一个
快照，提交到私有仓库 `LuckyMian/n1-pocketbase-backup` 的 **`main` 分支**；在任意装了 docker
的机器上 `git clone --single-branch` 后 `./restore.sh` 一键还原。

## 关键坐标

| 项 | 值 |
| --- | --- |
| 工具目录（宿主） | `/opt/pb-backup/`（**故意不在** `/opt/pocketbase` 里，容器卷被清掉也不影响备份工具） |
| 本地 git 仓库 | `/opt/pb-backup/repo`（工作副本 + `snapshots/`） |
| 配置 | `/opt/pb-backup/backup.conf` |
| 日志 / 状态 | `logs/backup.log`、`logs/last-status`（一行 `OK`/`FAILED`）、`logs/cron.log`、`logs/manual.log` |
| 远端 | `git@github.com:LuckyMian/n1-pocketbase-backup.git` 的 `main` 分支（仓库**必须私有**） |
| 备用远端 | `ssh://git@ssh.github.com/LuckyMian/n1-pocketbase-backup.git` + `-p 443`（见坑 5） |
| 部署密钥 | `/opt/pb-backup/.ssh/id_ed25519`（Ed25519 / dropbear 格式 / 600），配置项 `SSH_KEY`；GitHub 上标题 `n1-istoreos-pocketbase-backup`（write） |
| 已废弃仓库 | `LuckyMian/MianHelperDocker`（2026-10-21 确认 GitHub API 404，不再使用） |
| 开发机源码 | `G:\文档\ChatGPT\ruoyi\backup\`：`backup.sh` / `install.sh` / `apply-schedule.sh` / `restore.sh` / `backup.conf.example` / `README.md` / `tools\gh-init.ps1`、`tools\gh-repo-info.ps1` |

**仓库用途**：`n1-pocketbase-backup` 专用于 N1 整包备份。备份采用覆盖式提交（每次都只保留最近
`KEEP_SNAPSHOTS` 份快照），不要把需要长期保存的其它文件放进这个仓库。

## 快照内容（`snapshots/<YYYY-MM-DD_HHMMSS>/`）

| 文件 | 内容 |
| --- | --- |
| `data/pocketbase.tar.gz` | `/opt/pocketbase` 全量（`pb_data`、`pb_public`、`pb_hooks`、`pb_migrations`、PocketBase 二进制），排除 `pb_public/index.backup-*.html` 与 `pb_data/backups/*.zip` |
| `container/params.env` | 镜像/端口/挂载/内存/重启策略/入口/命令，**值必须带引号**（`restore.sh` 要 source 它） |
| `container/env.list` | 环境变量（`TZ=Asia/Shanghai` 等，已滤掉 PATH 等） |
| `container/run.sh` | 等价于备份时实况的 `docker run` |
| `container/inspect.json` | 原始 `docker inspect` |
| `images/alpine-3.24.tar.gz` | 基础镜像（约 3MB），还原时 `docker load`，不用联网 |
| `extra/host-config.tar.gz` | 宿主侧配置（默认含 `/etc/nginx/conf.d`、`/etc/nginx/seed`，即 VPN 面板那套） |
| `SHA256SUMS` / `manifest.txt` | 校验和 / 人类可读摘要 |

容器自身的可写层没有业务数据（`docker diff pocketbase` 只多一个空的 `/pb`），所以
「数据目录 + 基础镜像 + 运行参数」就是完整重建。仓库根目录还带一份 `restore.sh` +
`install.sh` + `README.md`，clone 下来就能还原、也能在新设备上重新装定时任务。

## 一致性与耗时（实测）

`docker stop`（约 1s）→ `tar czf /opt/pocketbase`（**停机约 23–28s**）→ `docker start`
→ 采集 inspect、导出镜像 → 算校验和 → 提交 → `git push --force`（约 45–70s）。
一次完整备份约 **1.5–2 分钟**，快照 **31.3MB**（数据包 27.4MB），本地仓库 4 份约 170MB。
脚本里有 `trap ... EXIT` 保证中途出错也会把容器启回来。

`STOP_DURING_BACKUP=0` 可改为不停机（快照有极小概率不一致）；想再快就清
`pb_public/assets` 里历史构建的废弃文件（917 个 / 52MB，只有几十个被当前 `index.html` 引用）。

## 保留策略与仓库体积

默认 `REWRITE_HISTORY=1`：每次用 orphan 提交把分支重写成「只含最近 `KEEP_SNAPSHOTS`（4）份」，
再 `git push -f`。**必须先 `git reflog expire --expire=now --all` 再 `git gc --prune=now`**，
否则旧提交还挂在 reflog 上收不掉，仓库会每次变大（实测 62MB→31MB 的差别）。
实测 `KEEP=4` 稳定在约 170MB（eMMC 剩 1GB）。想要完整追加历史把 `REWRITE_HISTORY` 改成 0。

## 改备份时间

```sh
vi /opt/pb-backup/backup.conf           # CRON_SCHEDULE='0 0 * * 1' 就是每周一 00:00
sh /opt/pb-backup/apply-schedule.sh      # 重写 /etc/crontabs/root 里带 “# pb-backup” 的那行并重启 cron
```

**坑**：iStoreOS 的 busybox `crond`（`/usr/sbin/crond -f -c /etc/crontabs -l 7`）只在**启动时**
读 crontab —— 手工往 `/etc/crontabs/root` 加行、不重启 cron，任务永远不会被执行（实测：加探针
6 分钟无反应，`/etc/init.d/cron restart` 后当分钟就跑了）。所以 `apply-schedule.sh` 用 `restart`
而不是 `reload`。

## 还原（在其他 docker 上）

```sh
git clone --single-branch https://github.com/LuckyMian/n1-pocketbase-backup.git
cd n1-pocketbase-backup
./restore.sh --list
./restore.sh                                              # → /opt/pocketbase，容器 pocketbase，8090
./restore.sh --target /srv/pb --port 18090 --name pb-n1    # 换目录/端口/名字
./restore.sh --dry-run                                     # 只看命令
```

`restore.sh` 五步：校验 `SHA256SUMS` → 缺镜像就 `docker load` → 解包（已存在的目录改名成
`*.before-restore-<时间>`，绝不删除）→ 同名容器 stop+rename 后按 `params.env` 重建 →
轮询 `/api/health`。在 N1 上实测：还原到 `/opt/pb-restore-test` + 8099 端口，健康检查通过，
`pb_data/types.d.ts` 与 `auxiliary.db` 的 md5 与线上完全一致，`pb_hooks/oss.pb.js` 生效
（`/api/oss/fetch` 同样返回 401），`pb_public/assets` 同样是 917 个文件。

## 坑清单（都踩过）

1. **仓库必须私有，推之前先查**。备份里含：`pb_data` 全部业务数据与超管密码哈希、`pb_hooks/oss.pb.js` 里 15 处阿里云 OSS 凭据（`LTAI…`）、nginx 的 VPN 面板 token 与 Basic Auth 密码、mihomo secret。公开提交等于把这些钥匙一起交出去。
2. **同一把公钥不能同时当两个仓库的 deploy key**（GitHub 返回 422 `key already in use`）。当前使用 `/opt/pb-backup/.ssh/id_ed25519`，对应 GitHub 部署密钥 `n1-istoreos-pocketbase-backup`；切换仓库时必须同步检查该仓库的 deploy key。
3. **端口别用 `NetworkSettings.Ports`**：它把 IPv4/IPv6 各算一条，`-p` 会变成 `8090:8090:8090`（非法）。要用 `HostConfig.PortBindings`，再 `sort -u`。
4. **`params.env` 的值要加引号**：`CMD=serve --http=0.0.0.0:8090` 被 `source` 时会把 `--http=...` 当命令执行。
5. **N1 到 GitHub 的 22 端口偶发不通**（走 OpenClash 透明代理），表现是 `ssh: Connection to git@github.com:22 exited: No auth methods could be used.` 但手动重试又成功。所以 `backup.sh` 现在每个地址试两次、再退到 443 入口。注意 **dropbear 的 `GIT_SSH_VARIANT=simple` 不支持 URL 里带端口**（`fatal: ssh variant 'simple' does not support setting port`），端口要用 `ssh -p 443` 传，URL 写成 `ssh://git@ssh.github.com/owner/repo.git`（配置项 `REMOTE_FALLBACK_URL` + `REMOTE_FALLBACK_SSH_PORT`）。
6. **清理旧快照时跳过本次新快照**：`ls | sort | head -n DROP` 依赖名字按时间排序，加一道 `[ "$old" = "$SNAP_NAME" ] && continue` 保底。
7. **部署密钥认证要点**：N1 的 `ssh` 是 dropbear（`/usr/bin/ssh -> /usr/sbin/dropbear`），git 默认会塞 `-o SendEnv=…` 之类它不认，所以用 `GIT_SSH_VARIANT=simple` + `GIT_SSH_COMMAND="ssh -y -i <key>"`。密钥用 `dropbearkey -t ed25519 -f <file>` 生成，公钥用 `dropbearkey -y -f <file> | sed -n 2p` 取出贴到 GitHub。
8. **`backup.sh` 里显式设 `PATH`/`HOME`**：cron 环境很干净（实测 PATH 是 `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`、HOME=/root），自己设一遍更稳（`env -i /bin/sh backup.sh` 也能跑通）。
9. **换仓库/建仓库用开发机上已存的 GitHub 凭据**：`backup\tools\gh-init.ps1`（`git credential fill` 读 Windows 凭据管理器，令牌只在内存里用、不打印）、`gh-repo-info.ps1`（查仓库是否私有、分支、已有 deploy key）。路由器上不落任何账号令牌。
10. **Windows 上 clone 时 autocrlf 会把文本文件换成 CRLF**，`SHA256SUMS` 全部对不上、`restore.sh` 会拒绝还原。仓库里已写 `.gitattributes`（`* -text`）禁掉转换；老 clone 删掉重来。

## 日常运维

```sh
sh /opt/pb-backup/backup.sh                 # 立刻备份
tail -20 /opt/pb-backup/logs/backup.log     # 日志
cat /opt/pb-backup/logs/last-status         # 上次结果
docker ps --format '{{.Names}}|{{.Status}}' # 备份期间容器会被 stop/start 一次
crontab -l | grep pb-backup                 # 当前定时
```

想给它做 UI（例如把 `logs/last-status` 显示到工作台），照 [architecture.md](architecture.md) 的
配置化 CRUD 加一个只读页即可 —— 备份目录在宿主上，PocketBase 读不到，需要走 SSH 或加一个
宿主侧的小接口。
