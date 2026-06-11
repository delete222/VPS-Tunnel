# 德国 Oracle 中转到美国 GCP 出口：重装系统后简化版

默认路线：

```text
中国客户端 -> 德国 Oracle 的 sing-box-yg 多协议入口 -> Tailscale 内链 -> 美国 GCP SOCKS 出口 -> 互联网
```

两台 VPS 都刚重装完系统时，照这个顺序：

1. 本地生成 `00-vars.env`，填入两个 Tailscale auth key。
2. 美国 GCP 上传本包，运行 `sudo bash fresh-gcp.sh`。
3. 德国 Oracle 上传同一份本包，运行 `sudo bash fresh-oracle.sh`。
4. 在 `sing-box-yg` 菜单里确认端口、证书、订阅、协议都调好后，运行 `sudo bash oneclick-oracle-after-sing-box-yg.sh`。
5. 中国真实网络连接 `sing-box-yg` 生成的节点，确认出口 IP 是美国 GCP。

德国的 VLESS/VMess+CDN、HY2、Reality、SSL 证书、订阅配置，都继续交给 `yonggekkk/sing-box-yg` 处理。本包只负责 Tailscale 内链和“最终出口改成 GCP”。

## 最短执行顺序

本地电脑：

```bash
curl -L -o VPS-Tunnel.tar.gz https://github.com/delete222/VPS-Tunnel/releases/latest/download/VPS-Tunnel.tar.gz
tar -xzf VPS-Tunnel.tar.gz
cd VPS-Tunnel
chmod +x *.sh
./init-quickstart-env.sh
```

编辑 `00-vars.env`，填入：

```bash
TAILSCALE_AUTH_KEY_GCP="你的 GCP Tailscale auth key"
TAILSCALE_AUTH_KEY_ORACLE="你的 Oracle Tailscale auth key"
```

然后有两种方式把脚本放到 VPS。

方式 A：直接上传同一份目录到两台 VPS：

```bash
./upload-to-vps.sh ubuntu@你的GCP_IP ubuntu@你的德国Oracle_IP
```

方式 B：两台 VPS 自己下载脚本，你只上传同一份 `00-vars.env`：

```bash
# 在 GCP VPS 和德国 Oracle VPS 上都执行
cd ~
rm -rf VPS-Tunnel
curl -L -o VPS-Tunnel.tar.gz https://github.com/delete222/VPS-Tunnel/releases/latest/download/VPS-Tunnel.tar.gz
tar -xzf VPS-Tunnel.tar.gz
cd VPS-Tunnel
chmod +x *.sh
```

然后从你的电脑上传同一份环境配置：

```bash
scp 00-vars.env ubuntu@你的GCP_IP:~/VPS-Tunnel/00-vars.env
scp 00-vars.env ubuntu@你的德国Oracle_IP:~/VPS-Tunnel/00-vars.env
```

GCP VPS：

```bash
cd ~/VPS-Tunnel
sudo bash fresh-gcp.sh
```

Oracle VPS：

```bash
cd ~/VPS-Tunnel
sudo bash fresh-oracle.sh
```

在 `sing-box-yg` 菜单里把端口、证书、协议、订阅都设置完，然后仍在 Oracle VPS 上运行：

```bash
sudo bash oneclick-oracle-after-sing-box-yg.sh
```

最后在 Oracle VPS 上验证 TCP 和 UDP：

```bash
sudo bash verify-vps-links.sh oracle
```

看到 `Germany through GCP SOCKS exit IP` 显示 GCP 美国 IP，并且 UDP 段显示 `OK: SOCKS5 UDP works`，就说明内链出口基本正常。

## 为什么是这个顺序

GCP 是最终出口，所以要先准备好：

- `Tailscale`：让德国和 GCP 进入同一个私有网络。
- `sing-box`：在 GCP 上开一个只给 Tailscale 内链使用的 SOCKS5 出口。

德国 Oracle 后配置，因为它的补丁脚本需要先找到 GCP 的 Tailscale 节点 `gcp-us-exit`，然后才能把 `sing-box-yg` 的出站改过去。

推荐路线不需要 Caddy。SSL 证书由 `sing-box-yg` 自己申请/管理。

## 0. 本地准备配置

这个仓库是公开的。推荐是在你自己的电脑上先生成 `00-vars.env`，然后让两台 VPS 自己下载脚本，你只上传同一份 `00-vars.env`。这样步骤更少，也能保证两边的 SOCKS 密码完全一致。

在本地执行：

```bash
git clone https://github.com/delete222/VPS-Tunnel.git
cd VPS-Tunnel
chmod +x *.sh
./init-quickstart-env.sh
```

也可以在 GitHub 页面下载 ZIP：

```text
https://github.com/delete222/VPS-Tunnel
```

下载后解压，进入解压目录再执行：

```bash
chmod +x *.sh
./init-quickstart-env.sh
```

如果想直接下载最新版 release 压缩包：

```bash
curl -L -o VPS-Tunnel.tar.gz https://github.com/delete222/VPS-Tunnel/releases/latest/download/VPS-Tunnel.tar.gz
tar -xzf VPS-Tunnel.tar.gz
cd VPS-Tunnel
chmod +x *.sh
./init-quickstart-env.sh
```

这会生成最短版 `00-vars.env`，并自动生成 SOCKS 内链密码。你只需要编辑两个 Tailscale auth key：

```bash
TAILSCALE_AUTH_KEY_GCP="你的 GCP Tailscale auth key"
TAILSCALE_AUTH_KEY_ORACLE="你的 Oracle Tailscale auth key"
```

`TAILSCALE_GCP_IP` 可以留空，德国脚本会自动识别。

关键点：GCP 和德国 Oracle 必须使用同一份 `00-vars.env`，尤其是 `GCP_SOCKS_USER` 和 `GCP_SOCKS_PASSWORD` 必须一致。

不要在运行 `./init-quickstart-env.sh` 后再执行 `cp 00-vars.env.example 00-vars.env`，否则会覆盖刚生成的密码。

上传到 VPS 前可以先检查：

```bash
./check-env.sh
```

`fresh-gcp.sh` 和 `fresh-oracle.sh` 也会自动先运行这个检查。

把脚本和配置放到 VPS 有两种方式。

方式 A：上传整个目录，推荐直接用本包的上传脚本：

```bash
./upload-to-vps.sh ubuntu@你的GCP_IP ubuntu@你的德国Oracle_IP
```

如果你的服务器用户名不是 `ubuntu`，把命令里的用户名换成实际 SSH 用户。这个脚本会把当前目录上传到两台服务器的 `~/VPS-Tunnel`。

你也可以手动上传。因为你现在已经在 `VPS-Tunnel` 目录里，先回到上一级再上传整个目录：

```bash
cd ..
scp -r VPS-Tunnel ubuntu@你的GCP_IP:~/
scp -r VPS-Tunnel ubuntu@你的德国Oracle_IP:~/
```

方式 B：两台 VPS 自己下载脚本，你只上传 `00-vars.env`：

```bash
# 在 GCP VPS 和德国 Oracle VPS 上都执行
cd ~
rm -rf VPS-Tunnel
curl -L -o VPS-Tunnel.tar.gz https://github.com/delete222/VPS-Tunnel/releases/latest/download/VPS-Tunnel.tar.gz
tar -xzf VPS-Tunnel.tar.gz
cd VPS-Tunnel
chmod +x *.sh
```

然后在你的电脑上把同一个环境配置文件传给两台 VPS：

```bash
scp 00-vars.env ubuntu@你的GCP_IP:~/VPS-Tunnel/00-vars.env
scp 00-vars.env ubuntu@你的德国Oracle_IP:~/VPS-Tunnel/00-vars.env
```

如果 VPS 上没有 `curl`，可以改用：

```bash
wget -O VPS-Tunnel.tar.gz https://github.com/delete222/VPS-Tunnel/releases/latest/download/VPS-Tunnel.tar.gz
```

## 1. 美国 GCP：先装出口

把整个项目目录上传到 GCP，里面要有你编辑好的 `00-vars.env`。无论从 GitHub 拉取还是下载 release 压缩包，目录名都使用 `VPS-Tunnel`。

在 GCP 上运行：

```bash
cd ~/VPS-Tunnel
sudo bash fresh-gcp.sh
```

它会：

- 安装/加入 Tailscale，主机名为 `gcp-us-exit`
- 安装 sing-box
- 在 GCP 上开一个只给内链使用的 SOCKS5 出口
- 创建 `vps-tunnel-gcp-exit.service`，重启后会等待 Tailscale IP 就绪再启动

验证：

```bash
sudo bash verify-vps-links.sh gcp
systemctl status vps-tunnel-gcp-exit
```

看到的出口 IP 应该是美国 GCP 的公网 IP。

## 2. 德国 Oracle：装入口，确认后再补丁

把同一个项目目录上传到德国 Oracle，里面要是同一份 `00-vars.env`。

在德国 Oracle 上运行：

```bash
cd ~/VPS-Tunnel
sudo bash fresh-oracle.sh
```

它会：

- 安装/加入 Tailscale，主机名为 `oracle-de-entry`
- 拉取并运行最新版 `yonggekkk/sing-box-yg`
- 你按上游菜单配置 VLESS/VMess+CDN、HY2、Reality、SSL 证书和订阅
- 上游菜单退出后停止，不会自动修改 yg 配置

等你确认端口、证书、订阅、协议都设置完，再运行：

```bash
sudo bash oneclick-oracle-after-sing-box-yg.sh
```

它会：

- 自动寻找 `gcp-us-exit` 的 Tailscale IP
- 备份 `/etc/s-box/sb10.json`、`/etc/s-box/sb11.json`、`/etc/s-box/sb.json`
- 先生成临时配置并通过 `sing-box check`，验证成功后才覆盖原文件
- 如果当前实际配置 `sb.json` 存在，且当前 sing-box 版本无法校验旧模板 `sb10.json`/`sb11.json`，脚本只会警告；如果 `sb.json` 不存在或 `sb.json` 本身校验失败，脚本会终止
- 新增 `gcp-us-exit` 出站
- 把非 `block`/`dns` 的出站规则都改到美国 GCP
- 重启 sing-box
- 验证德国经内链访问外网时出口是否为美国 GCP

如果你之后重新运行 `sing-box-yg` 并重置配置，需要再跑一次：

```bash
sudo bash oneclick-oracle-after-sing-box-yg.sh
```

如果只是想检查补丁有没有被 `sing-box-yg` 菜单操作覆盖，可以运行：

```bash
sudo bash check-oracle-patch-status.sh
```

尤其是你在 `sing-box-yg` 菜单里执行过重装、切换 sing-box 内核、重置配置、修改 WARP/出站等操作后，建议先检查；如果提示补丁缺失，就重新运行 `oneclick-oracle-after-sing-box-yg.sh`。

如果你希望以后直接输入 `sb` 改完 yg 菜单后自动检查并补回 GCP 出口，可以安装可选钩子：

```bash
sudo bash install-yg-auto-repatch-hook.sh install
```

它会把原 `/usr/bin/sb` 备份到 `/usr/bin/sb.yg-original`，再创建一个包装器。你照常运行 `sb`，菜单退出后它会先离线检查三份配置；只有发现 `gcp-us-exit` 被覆盖时，才自动重新打补丁。

如果 `/usr/bin/sb` 是符号链接，钩子安装器会拒绝包装，避免误覆盖链接目标。

如果不想用了，可以恢复原始 yg 入口：

```bash
sudo bash install-yg-auto-repatch-hook.sh remove
```

如果补丁后服务异常，可以恢复最近一次备份：

```bash
sudo bash restore-sing-box-yg-backup.sh
```

## VPS 重启后自检

两台 VPS 重启后，通常会自动恢复。建议按下面顺序确认：

GCP：

```bash
systemctl status tailscaled
systemctl status vps-tunnel-gcp-exit
sudo bash verify-vps-links.sh gcp
```

Oracle：

```bash
systemctl status tailscaled
systemctl status sing-box
sudo bash check-oracle-patch-status.sh
sudo bash verify-vps-links.sh oracle
```

如果 GCP 刚重启时 Tailscale 较慢，`vps-tunnel-gcp-exit.service` 会持续重试，不需要手动抢救。Oracle 的 `sing-box-yg` 服务不依赖 GCP 先在线；GCP 暂时不可达时客户端可能连不上出口，但不会让 yg 菜单或配置文件失效。

## UDP 和协议影响

本包用 SOCKS5 作为 Oracle 到 GCP 的应用层出口。TCP 出口可以用 `curl --socks5` 验证；UDP 需要 SOCKS5 UDP ASSOCIATE 单独验证。

在 Oracle 上运行：

```bash
sudo bash verify-vps-links.sh oracle
```

其中会额外执行 `test-socks5-udp.py`，通过 GCP SOCKS5 出口向 `1.1.1.1:53` 发 UDP DNS 查询。看到 `OK: SOCKS5 UDP works` 才能说明 Oracle -> GCP 的 SOCKS5 UDP 链路可用。

影响说明：

- `tailscale` 和 `wireguard` 内链模式理论上可以承载 UDP，实际以 `test-socks5-udp.py` 结果为准。
- `ssh-socks` 模式使用 SSH `-L` TCP 转发，不应期待 UDP 可用。
- 普通 HTTPS/WebSocket/VLESS/VMess 浏览网页主要走 TCP，通常不受影响。
- QUIC/HTTP3、游戏、部分 DNS、以及代理内承载的 UDP 目标流量依赖 SOCKS5 UDP 测试结果。
- HY2/TUIC 作为客户端到 Oracle 的入站协议本身使用 UDP；入站能否连上取决于 Oracle 公网端口和 `sing-box-yg` 配置。入站解包后的目标 UDP 流量是否经 GCP 出口，则取决于 Oracle -> GCP 的 SOCKS5 UDP 是否通过测试。

## 3. 中国真实网络测试

客户端配置仍然使用 `sing-box-yg` 生成的订阅或节点。

测试时注意：

- 不要用当前已经连着 VPN 的电脑测速判断线路。
- 要断开旧 VPN，或用手机 5G/家庭宽带真实网络测试。
- 连接德国节点后访问 `https://ipinfo.io/ip`，结果必须显示美国 GCP IP。
- 晚高峰分别测试 VLESS/VMess+CDN、HY2、Reality，优先看能不能稳定打开网页和视频。

## 端口

德国 Oracle：

- 按 `sing-box-yg` 的提示开放对应端口。
- VLESS/VMess+CDN 通常走 `443/tcp` 或 Cloudflare 支持的 HTTPS 端口。
- HY2 需要 UDP 端口。
- Reality 需要 TCP 端口。

美国 GCP：

- Tailscale 主线下，不需要把 SOCKS5 端口暴露到公网。
- 只需要允许 GCP 正常连外网，并能安装 Tailscale。
- 本包不会在 Oracle 上额外开放公网端口；Oracle 入站端口按 `sing-box-yg` 和云厂商安全组设置处理。

## Fork 还是薄封装

不建议长期 fork 并魔改 `sb.sh` 主体。上游脚本很大，直接改主文件以后很难判断哪些改动来自上游、哪些来自本包。

本包采用薄封装策略：

- 每次安装时从上游拉取最新版 `sb.sh`。
- 上游继续负责协议、证书、订阅和菜单。
- 本包只在安装完成后修改服务端 JSON 的出站，让最终出口变成美国 GCP。
- 如果你安装了 `install-yg-auto-repatch-hook.sh`，本包会包装 `/usr/bin/sb`，在 yg 菜单退出后自动检查并补回 GCP 出口，但仍保留原始 `/usr/bin/sb.yg-original` 可恢复。

如果将来上游结构大改，只需要修 `patch-sing-box-yg-oracle.sh` 这个小补丁脚本，而不是维护整份 fork。

## 高级备用

推荐路线只需要 `fresh-gcp.sh` 和 `fresh-oracle.sh`。其它脚本是高级备用：

- `oneclick-gcp-exit.sh`：GCP 出口底层一键脚本。
- `install-oracle-upstream-only.sh`：德国 Oracle 只安装/运行上游 `sing-box-yg`，不自动补丁。
- `oneclick-oracle-after-sing-box-yg.sh`：德国已装好 `sing-box-yg` 后单独打补丁。
- `oneclick-oracle-install-upstream-and-patch.sh`：兼容旧入口；现在只运行上游安装，不会自动补丁。
- `install-gcp-exit.sh`：支持 WireGuard、SSH+SOCKS 等高级内链模式。
- `patch-sing-box-yg-oracle.sh`：德国补丁底层脚本，支持高级内链模式。
- `check-oracle-patch-status.sh`：检查 yg 三份配置是否仍指向 GCP 出口。
- `install-yg-auto-repatch-hook.sh`：可选包装 `/usr/bin/sb`，在 yg 菜单退出后自动检查并重补丁。
- `restore-sing-box-yg-backup.sh`：恢复最近一次补丁前备份。
- `install-oracle-entry.sh`：完全不用 `sing-box-yg` 时，由本包自建德国入口，会用到 Caddy；会覆盖 `/etc/sing-box/config.json`、`sing-box.service` 和 Caddyfile，必须显式设置确认变量才会运行。
