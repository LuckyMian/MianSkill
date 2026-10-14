# 定时整容器备份 → GitHub（N1 上已上线）

2026-10-14 上线。**每周一 03:30**，N1 把 `pocketbase` 容器整包打成一个快照，提交到
GitHub 私有仓库 `LuckyMian/n1-pocketbase-backup`；在任意装了 docker 的机器上
`git clone` 后 `./restore.sh` 一键还原。

## 关键坐标

| 项 | 值 |
| --- | --- |
| 工具目录（宿主） | `/opt/pb-backup/`（**故意不在** `/opt/pocketbase` 里，容器卷被清掉也不影响备份工具） |
| 本地 git 仓库 | `/opt/pb-backup/repo`（工作副本 + `snapshots/`） |
| 配置 | `/opt/pb-backup/backup.conf` |
| 日志 / 状态 | `/opt/pb-backup/logs/backup.log`、`logs/last-status`（一行 `OK`/`FAILED`）、`logs/cron.log` |
| 部署密钥 | `/opt/pb-backup/.ssh/id_ed25519`（Ed25519，600，dropbear 格式），公钥作为仓库 Deploy key（write） |
| 远端 | `git@github.com:LuckyMian/n1-pocketbase-backup.git`（私有，`main`） |
| 开发机源码 | `G:\文档\ChatGPT\ruoyi\backup\`（`backup.sh` / `install.sh` / `apply-schedule.sh` / `restore.sh` / `backup.conf.example` / `README.md` / `tools/gh-init.ps1`） |

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
`install.sh` + `README.md`，所以 clone 下来就能还原、也能在新设备上重新装定时任务。

## 一致性与耗时（实测）

备份流程：`docker stop`（约 1s）→ `tar czf /opt/pocketbase`（**停机约 23–28s**）→ `docker start`
→ 采集 inspect、导出镜像 → 算校验和 → 提交 → `git push --force`（约 45–60s）。
一次完整备份约 **1.5 分钟**，快照 **31.3MB**（数据包 27.4MB），本地仓库 4 份约 170MB。
脚本里有 `trap ... EXIT` 保证中途出错也会把容器启回来。

`STOP_DURING_BACKUP=0` 可改为不停机（快照有极小概率不一致）；
想再快就清 `pb_public/assets` 里历史构建的废弃文件（917 个 / 52MB，只有几十个被当前
`index.html` 引用）。

## 保留策略与仓库体积

默认 `REWRITE_HISTORY=1`：每次用 orphan 提交把仓库重写成「只含最近 `KEEP_SNAPSHOTS`（4）份」，
再 `git push -f`。**必须先 `git reflog expire --expire=now --all` 再 `git gc --prune=now`**，
否则旧提交还挂在 reflog 上收不掉，仓库会每次变大（实测 62MB→31MB 的差别）。
实测 `KEEP=4` 稳定在约 170MB（eMMC 剩 1GB）。想要完整追加历史把 `REWRITE_HISTORY` 改成 0。

## 改备份时间

```sh
vi /opt/pb-backup/backup.conf          # CRON_SCHEDULE='0 4 * * 0' 之类
sh /opt/pb-backup/apply-schedule.sh     # 重写 /etc/crontabs/root 里带 “# pb-backup” 的那行并重启 cron
```

**坑**：iStoreOS 的 busybox `crond`（`/usr/sbin/crond -f -c /etc/crontabs -l 7`）只在**启动时**
读 crontab —— 手工往 `/etc/crontabs/root` 加行、不重启 cron，任务永远不会被执行（实测：
加探针 6 分钟无反应，`/etc/init.d/cron restart` 后当分钟就跑了）。所以 `apply-schedule.sh`
用 `restart` 而不是 `reload`。

## 还原（在其他 docker 上）

```sh
git clone https://github.com/LuckyMian/n1-pocketbase-backup.git && cd n1-pocketbase-backup
./restore.sh --list
./restore.sh                                            # → /opt/pocketbase，容器 pocketbase，8090
./restore.sh --target /srv/pb --port 18090 --name pb-n1  # 换目录/端口/名字
./restore.sh --dry-run                                   # 只看命令
```

`restore.sh` 五步：校验 `SHA256SUMS` → 缺镜像就 `docker load` → 解包（已存在的目录改名成
`*.before-restore-<时间>`，绝不删除）→ 同名容器 stop+rename 后按 `params.env` 重建 →
轮询 `/api/health`。在 N1 上实测：还原到 `/opt/pb-restore-test` + 8099 端口，健康检查通过，
`pb_data/types.d.ts` 与 `auxiliary.db` 的 md5 与线上完全一致，`pb_hooks/oss.pb.js` 生效
（`/api/oss/fetch` 同样返回 401），`pb_public/assets` 同样是 917 个文件。

**坑**：Windows 上 clone 时 autocrlf 会把文本文件换成 CRLF，`SHA256SUMS` 全部对不上、
`restore.sh` 会拒绝还原。仓库里已写 `.gitattributes`（`* -text`）禁掉转换；老 clone 删掉重来。

## 坑清单（都踩过）

1. **端口别用 `NetworkSettings.Ports`**：它把 IPv4/IPv6 各算一条，`-p` 会变成 `8090:8090:8090`（非法）。要用 `HostConfig.PortBindings`，再 `sort -u`。
2. **`params.env` 的值要加引号**：`CMD=serve --http=0.0.0.0:8090` 被 `source` 时会把 `--http=...` 当命令执行。
3. **清理旧快照时跳过本次新快照**：`ls | sort | head -n DROP` 依赖名字按时间排序，加一道 `[ "$old" = "$SNAP_NAME" ] && continue` 保底。
4. **部署密钥认证要 `GIT_SSH_VARIANT=simple`**：N1 的 `ssh` 是 dropbear（`/usr/bin/ssh -> /usr/sbin/dropbear`），git 默认塞 `-o SendEnv=...` 之类它不认；用 `simple` + `GIT_SSH_COMMAND="ssh -y -i <key>"`。密钥用 `dropbearkey -t ed25519 -f`,公钥用 `dropbearkey -y -f key | sed -n 2p` 取出贴到 GitHub。
5. **`backup.sh` 里显式设 `PATH`/`HOME`**：cron 环境很干净，实测 cron 的 PATH 是 `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`、HOME=/root，但自己设一遍更稳（`env -i /bin/sh backup.sh` 也能跑通）。
6. **建仓库用开发机已存的 GitHub 凭据**：`backup/tools/gh-init.ps1`（`git credential fill` 从 Windows 凭据管理器取令牌，只在内存里用、不打印），一次调用就能建私有仓库 + 登记部署密钥，路由器上不落任何账号令牌。

## 日常运维

```sh
sh /opt/pb-backup/backup.sh                 # 立刻备份
tail -20 /opt/pb-backup/logs/backup.log     # 日志
cat /opt/pb-backup/logs/last-status         # 上次结果
docker ps --format '{{.Names}}|{{.Status}}' # 备份期间容器会被 stop/start 一次
```

想给它做 UI（例如把 `logs/last-status` 显示到工作台），照 [architecture.md](architecture.md) 的
配置化 CRUD 加一个只读页即可 —— 备份目录在宿主上，PocketBase 读不到，需要走 SSH 或加一个
宿主侧的小接口。
