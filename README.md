# 德国 Oracle 中转到美国 GCP 出口：重装系统后简化版

默认路线：

```text
中国客户端 -> 德国 Oracle 的 sing-box-yg 多协议入口 -> Tailscale 内链 -> 美国 GCP SOCKS 出口 -> 互联网
```

两台 VPS 都刚重装完系统时，照这个顺序：

1. 本地生成 `00-vars.env`，填入两个 Tailscale auth key。
2. 美国 GCP 上传本包，运行 `sudo bash fresh-gcp.sh`。
3. 德国 Oracle 上传同一份本包，运行 `sudo bash fresh-oracle.sh`。
4. 中国真实网络连接 `sing-box-yg` 生成的节点，确认出口 IP 是美国 GCP。

德国的 VLESS/VMess+CDN、HY2、Reality、SSL 证书、订阅配置，都继续交给 `yonggekkk/sing-box-yg` 处理。本包只负责 Tailscale 内链和“最终出口改成 GCP”。

## 为什么是这个顺序

GCP 是最终出口，所以要先准备好：

- `Tailscale`：让德国和 GCP 进入同一个私有网络。
- `sing-box`：在 GCP 上开一个只给 Tailscale 内链使用的 SOCKS5 出口。

德国 Oracle 后配置，因为它的补丁脚本需要先找到 GCP 的 Tailscale 节点 `gcp-us-exit`，然后才能把 `sing-box-yg` 的出站改过去。

推荐路线不需要 Caddy。SSL 证书由 `sing-box-yg` 自己申请/管理。

## 0. 本地准备配置

这个仓库是 private，所以最稳的方式是在你自己的电脑上先 clone，再把同一个目录上传到两台 VPS。

在本地执行：

```bash
gh repo clone delete222/VPS-Tunnel
cd VPS-Tunnel
chmod +x *.sh
./init-quickstart-env.sh
```

如果不用 GitHub CLI，也可以在 GitHub 页面下载 ZIP：

```text
https://github.com/delete222/VPS-Tunnel
```

下载后解压，进入解压目录再执行：

```bash
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

把配置好的同一个目录上传到 GCP 和德国 Oracle。因为你现在已经在 `VPS-Tunnel` 目录里，推荐先回到上一级再上传整个目录：

```bash
cd ..
scp -r VPS-Tunnel ubuntu@你的GCP_IP:~/
scp -r VPS-Tunnel ubuntu@你的德国Oracle_IP:~/
```

如果你的服务器用户名不是 `ubuntu`，把命令里的用户名换成实际 SSH 用户。

## 1. 美国 GCP：先装出口

把整个项目目录上传到 GCP，里面要有你编辑好的 `00-vars.env`。如果从 GitHub 拉取，可以用仓库目录名 `VPS-Tunnel`；如果用压缩包，可以解压成 `vps-relay-kit`。

在 GCP 上运行：

```bash
cd ~/VPS-Tunnel   # 或 cd ~/vps-relay-kit
sudo bash fresh-gcp.sh
```

它会：

- 安装/加入 Tailscale，主机名为 `gcp-us-exit`
- 安装 sing-box
- 在 GCP 上开一个只给内链使用的 SOCKS5 出口

验证：

```bash
sudo bash verify-vps-links.sh gcp
```

看到的出口 IP 应该是美国 GCP 的公网 IP。

## 2. 德国 Oracle：装入口并补丁

把同一个项目目录上传到德国 Oracle，里面要是同一份 `00-vars.env`。

在德国 Oracle 上运行：

```bash
cd ~/VPS-Tunnel   # 或 cd ~/vps-relay-kit
sudo bash fresh-oracle.sh
```

它会：

- 安装/加入 Tailscale，主机名为 `oracle-de-entry`
- 拉取并运行最新版 `yonggekkk/sing-box-yg`
- 你按上游菜单配置 VLESS/VMess+CDN、HY2、Reality、SSL 证书和订阅
- 上游菜单退出后，自动寻找 `gcp-us-exit` 的 Tailscale IP
- 备份 `/etc/s-box/sb10.json`、`/etc/s-box/sb11.json`、`/etc/s-box/sb.json`
- 新增 `gcp-us-exit` 出站
- 把非 `block`/`dns` 的出站规则都改到美国 GCP
- 重启 sing-box
- 验证德国经内链访问外网时出口是否为美国 GCP

如果你之后重新运行 `sing-box-yg` 并重置配置，需要再跑一次：

```bash
sudo bash oneclick-oracle-after-sing-box-yg.sh
```

如果补丁后服务异常，可以恢复最近一次备份：

```bash
sudo bash restore-sing-box-yg-backup.sh
```

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

## Fork 还是薄封装

不建议长期 fork 并魔改 `sb.sh` 主体。上游脚本很大，更新频繁，直接改主文件以后每次同步都容易冲突。

本包采用薄封装策略：

- 每次安装时从上游拉取最新版 `sb.sh`。
- 上游继续负责协议、证书、订阅和菜单。
- 本包只在安装完成后修改服务端 JSON 的出站，让最终出口变成美国 GCP。

如果将来上游结构大改，只需要修 `patch-sing-box-yg-oracle.sh` 这个小补丁脚本，而不是维护整份 fork。

## 高级备用

推荐路线只需要 `fresh-gcp.sh` 和 `fresh-oracle.sh`。其它脚本是高级备用：

- `oneclick-gcp-exit.sh`：GCP 出口底层一键脚本。
- `oneclick-oracle-after-sing-box-yg.sh`：德国已装好 `sing-box-yg` 后单独打补丁。
- `install-gcp-exit.sh`：支持 WireGuard、SSH+SOCKS 等高级内链模式。
- `patch-sing-box-yg-oracle.sh`：德国补丁底层脚本，支持高级内链模式。
- `restore-sing-box-yg-backup.sh`：恢复最近一次补丁前备份。
- `install-oracle-entry.sh`：完全不用 `sing-box-yg` 时，由本包自建德国入口，会用到 Caddy。
