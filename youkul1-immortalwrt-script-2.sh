#!/bin/bash
# Copyright (c) 2022-2023 Curious <https://www.curious.host>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/Curious-r/OpenWrtBuildWorkflows
#-------------------------------------------------------------------------------------------------------
#
# 1. Remove smpackage miniupnpd-iptables (conflict with official nftables variant)
# 2. Append custom-mode routing template (idempotent, HP_TEMPLATE guarded)
# 3. P5: ECH import support for VLESS/Trojan share links and subscriptions

set -euo pipefail

echo "=== script-2 ==="

rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

CONF_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/config/homeproxy"
if grep -q 'HP_TEMPLATE' "$CONF_PATH" 2>/dev/null; then
	echo "Template already present, skip"
else
	cat >> "$CONF_PATH" << 'CONFEOF'
# ============================================================================
# HomeProxy 最优分流配置模板 v3
#
# 依据：HomeProxy 官方文档 + 8 篇社区实践教程交叉验证
#   Yuzi / 闲作坊 / 奶油之家 / RULTR / Remyy / DustinWin / SagerNet / MetaCubeX
#
# 设计要点
# --------
# 1. 规则集统一走 jsDelivr CDN 前缀，避免初始化时下载不及时导致 sing-box
#    配置生成失败崩溃（社区踩坑点）。
# 2. 路由规则顺序即优先级，靠前先生效：
#    自定义 → 阻断 → 基础设施 → 国内 → 服务分类 → 境外 → 兜底
# 3. DNS 规则顺序：
#    节点域名(用户自加，必须第一) → 阻断 → GFW → 国内 → 境外 → 兜底
#    节点域名必须第一，否则解析节点域名要走代理、而代理又要先解析节点域名，
#    形成死循环。
# 4. 私有地址拆成两条：geoip-private(IP 段) + geosite-private(域名)。
#    只用后者会漏掉裸 IP 访问（NAS、路由器、其他设备），流量绕境外一圈。
# 5. DNS 分流：国内 UDP 直连（快），境外 DoH 经代理（防污染）。
#    全部走国内 DNS 是常见错误 —— 境外域名会被污染。
# 6. 命名统一 <序号>-<类别> <说明>。
#
# 本模板零私有信息：不含节点、订阅、域名、凭据。
# ============================================================================

# ---------------------------------------------------------------------------
# 主配置段（段名格式必须是 config homeproxy 'config'，不是 config control）
#
# main_node 指向下方 routing_node 里的 proxy_out（即你的自建节点）。
# 想用哪条线路，就把它填进来。
# ---------------------------------------------------------------------------

config homeproxy 'config'
	option main_node 'proxy_out'
	option main_udp_node 'proxy_out'
	option routing_mode 'custom'
	option routing_port 'common'
	option proxy_mode 'redirect_tproxy'
	option ipv6_support '1'
	option log_level 'warn'

config homeproxy 'routing'
	option sniff_override '1'
	option default_outbound 'proxy_out'
	option default_outbound_dns 'default-dns'

config homeproxy 'dns'
	option default_strategy 'prefer_ipv4'
	option default_server 'default-dns'
	option disable_cache '1'
	option disable_cache_expire '0'

# ---------------------------------------------------------------------------
# 路由节点
#
# ★ 节点字段的三个坑（都是实测踩过的，会导致隧道根本建不起来）：
#
# 1) 不要锁 TLS 版本！
#    节点里若设了 tls_min_version='1.3' + tls_max_version='1.3'，
#    sing-box 生成的出站会写成 min_version/max_version 双重锁定，
#    一旦服务端或中间链路有兼容问题，整条隧道直接建不起来
#    （现象: 到 VPS 0 条 ESTABLISHED，所有境外站 curl 返回 000）。
#    服务端通常同时支持 1.2 和 1.3，交给它自动协商即可 ——
#    删掉这两个字段，什么都不设。
#    ★ 特别注意: 如果你还建了 urltest 组，锁了 TLS 的节点会被组选优
#      跳过、选到别的可用节点，看起来一切正常 —— 直到你切回单节点才炸。
#      所以务必单独验证单节点路径。
#
# 2) node 字段不能填 'direct' / 'block'：
#    生成器会去 uci.get_all(uciconfig, 'direct') 拿到 null，
#    随后 config.outbounds[-1] 赋值崩溃:
#      attempt to set property on null value
#    直连与阻断直接在规则的 outbound 写 'direct-out'，不建 routing_node。
#
# 3) TLS SNI 与 WS Host 都要填：
#    address 用裸 IP 而不填 SNI/Host，TLS 校验直接失败。
#
# 下面 proxy_out 假设你的节点段名叫 'proxy'，请改成你自己的段名。
# ---------------------------------------------------------------------------

config routing_node 'proxy_out'
	option label 'Main Proxy'
	option enabled '1'
	option node 'proxy'
	option domain_strategy 'prefer_ipv4'

# ---------------------------------------------------------------------------
# 如果你想用 urltest 组（多节点自动选优）而非单节点：
#
# 约束 1: node='urltest' 时必须列出 urltest_nodes，否则生成器崩溃:
#           Type error: (null) is not iterable
# 约束 2: interval 必须 <= idle_timeout，否则启动失败:
#           FATAL start outbound/urltest: interval must be less or equal
#                 than idle_timeout
# 常用值: interval=3600 + idle_timeout=7200, tolerance=160（防横跳）
#
# 用 urltest 时记得把上面 main_node / default_outbound 也改成 urltest。
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# DNS 服务器
#   国内：UDP 直连，快且无污染风险
#   境外：DoH 经代理，防 DNS 污染
# ---------------------------------------------------------------------------

config dns_server '114_dns'
	option label '114 DNS'
	option type 'udp'
	option server '114.114.114.114'
	option server_port '53'
	option outbound 'direct-out'
	option enabled '1'

config dns_server 'tencent_dns'
	option label 'Tencent DNS'
	option type 'udp'
	option server '119.29.29.29'
	option server_port '53'
	option outbound 'direct-out'
	option enabled '1'

config dns_server 'cloudflare_dns'
	option label 'Cloudflare DoH'
	option type 'https'
	option server 'cloudflare-dns.com'
	option server_port '443'
	option path '/dns-query'
	option outbound 'proxy_out'
	option address_resolver '114_dns'
	option enabled '1'

config dns_server 'google_dns'
	option label 'Google DoH'
	option type 'https'
	option server 'dns.google'
	option server_port '443'
	option path '/dns-query'
	option outbound 'proxy_out'
	option address_resolver '114_dns'
	option enabled '1'

config dns_server 'alidns'
	option label 'AliDNS DoH'
	option type 'https'
	option server 'dns.alidns.com'
	option server_port '443'
	option path '/dns-query'
	option outbound 'direct-out'
	option address_resolver '114_dns'
	option enabled '1'

# ---------------------------------------------------------------------------
# 规则集
#   CDN 前缀保证启动时能取到；update_interval 按变化频率调整
#   （分类规则集变化慢，168h；geolocation 类变化快，72h）
# ---------------------------------------------------------------------------

config ruleset 'private_cidr'
	option label 'Private IP Ranges'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/private.srs'
	option outbound 'direct-out'
	option update_interval '720h'
	option enabled '1'

config ruleset 'private_domain'
	option label 'Private Domains'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-private.srs'
	option outbound 'direct-out'
	option update_interval '720h'
	option enabled '1'

config ruleset 'cn_domain'
	option label 'CN Domains'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/cn.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'cn_ip'
	option label 'CN IPs'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@rule-set/cn.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'microsoft'
	option label 'Microsoft CN'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-microsoft.srs'
	option outbound 'direct-out'
	option update_interval '168h'
	option enabled '1'

config ruleset 'scholar'
	option label 'Scholar Sites'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-scholar-!cn.srs'
	option outbound 'direct-out'
	option update_interval '168h'
	option enabled '1'

config ruleset 'ads'
	option label 'Ad Blocking'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-ads.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'gfw'
	option label 'GFW List'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-gfw.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'ai_services'
	option label 'AI Services'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-ai-!cn.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'apple_ai'
	option label 'Apple Intelligence'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-apple-intelligence.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'netflix'
	option label 'Netflix'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-netflix.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'disney'
	option label 'Disney Plus'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-disney.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'youtube'
	option label 'YouTube'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-youtube.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'spotify'
	option label 'Spotify'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-spotify.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'telegram'
	option label 'Telegram'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-telegram.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'twitter'
	option label 'Twitter X'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-twitter.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'tiktok'
	option label 'TikTok'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-tiktok.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'github'
	option label 'GitHub'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-github.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'games'
	option label 'Games'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-games.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'non_cn'
	option label 'Non-CN Sites'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-geolocation-!cn.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

# ===========================================================================
# DNS 规则
#   顺序敏感。用户加节点后须把「节点域名」规则插到最前面（见文末）。
# ===========================================================================

# 00 节点域名 —— 占位，用户需在 LuCI 中新增到第一位
#     说明：示例见文末，不要直接用 example.com

# 01 屏蔽 SVCB/HTTPS（qtype 64/65），避免浏览器 ECH 走意外路径
config dns_rule
	option label '01 Block SVCB HTTPS'
	option enabled '1'
	list query_type '64'
	list query_type '65'
	option action 'reject'

# 02 广告拦截
config dns_rule
	option label '02 Ads Block'
	option enabled '1'
	list rule_set 'ads'
	option action 'reject'

# 03 GFWList 内的域名必须走境外 DNS，否则被污染
config dns_rule
	option label '03 GFW Domains'
	option enabled '1'
	list rule_set 'gfw'
	option action 'route'
	option server 'cloudflare_dns'

# 04 国内域名走国内 DNS（直连，快）
config dns_rule
	option label '04 CN Domains'
	option enabled '1'
	list rule_set 'cn_domain'
	option action 'route'
	option server '114_dns'

# 05 境外域名走境外 DoH（经代理，防污染）
config dns_rule
	option label '05 Non-CN Domains'
	option enabled '1'
	list rule_set 'non_cn'
	option action 'route'
	option server 'cloudflare_dns'

# 06 兜底走境外 DNS —— 未匹配到的域名多为境外
config dns_rule
	option label '06 Default'
	option enabled '1'
	option action 'route'
	option server 'cloudflare_dns'

# ===========================================================================
# 路由规则
#   顺序敏感，靠前先生效。
# ===========================================================================

# 02 阻断广告
config routing_rule
	option label '01 Block Ads'
	option enabled '1'
	list rule_set 'ads'
	option action 'reject'

# 03 BT/P2P 直连，避免占用节点带宽
config routing_rule
	option label '02 Direct BT P2P'
	option enabled '1'
	list protocol 'bittorrent'
	option action 'route'
	option outbound 'direct-out'

# 04 私有 IP 段直连 —— NAS、路由器、局域网设备裸 IP 访问
config routing_rule
	option label '03 Direct Private IP'
	option enabled '1'
	list rule_set 'private_cidr'
	option action 'route'
	option outbound 'direct-out'

# 05 私有域名直连 —— *.local / plex.direct 等
config routing_rule
	option label '04 Direct Private Domain'
	option enabled '1'
	list rule_set 'private_domain'
	option action 'route'
	option outbound 'direct-out'

# 06 国内 IP 直连
config routing_rule
	option label '05 Direct CN IP'
	option enabled '1'
	list rule_set 'cn_ip'
	option action 'route'
	option outbound 'direct-out'

# 07 微软中国区直连（Office/OneDrive 国内节点，不走代理更快）
config routing_rule
	option label '06 Direct Microsoft CN'
	option enabled '1'
	list rule_set 'microsoft'
	option action 'route'
	option outbound 'direct-out'

# 08 学术站点直连
#     geosite-category-scholar-!cn 含 acm.org / ieee / springer 等。
#     这类站点 GFW 一般不干扰，境内直连更快更稳（避免学术 PDF 走海外卡住）。
config routing_rule
	option label '08 Direct Scholar'
	option enabled '1'
	list rule_set 'scholar'
	option action 'route'
	option outbound 'direct-out'

# 08b Google Scholar 走代理 —— 必须排在 08 之后
#      scholar 规则集里含 scholar.google.*，若不单独指定会被 08 直连，
#      但 Google Scholar 在境内经常被干扰，需要走代理。
config routing_rule
	option label '08b Proxy Google Scholar'
	option enabled '1'
	list domain 'scholar.google.com'
	list domain 'scholar.google.com.hk'
	list domain 'scholar.googleusercontent.com'
	option action 'route'
	option outbound 'proxy_out'

# 09 AI 服务代理 —— ChatGPT / Claude / Perplexity 等需要干净 IP
config routing_rule
	option label '09 Proxy AI Services'
	option enabled '1'
	list rule_set 'ai_services'
	list rule_set 'apple_ai'
	option action 'route'
	option outbound 'proxy_out'

# 10-13 流媒体代理 —— 奈飞/迪士尼需同时匹配域名+IP，否则无法解锁
config routing_rule
	option label '10 Proxy Netflix'
	option enabled '1'
	list rule_set 'netflix'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label '11 Proxy Disney Plus'
	option enabled '1'
	list rule_set 'disney'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label '12 Proxy YouTube'
	option enabled '1'
	list rule_set 'youtube'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label '13 Proxy Spotify'
	option enabled '1'
	list rule_set 'spotify'
	option action 'route'
	option outbound 'proxy_out'

# 14-17 通讯工具代理
config routing_rule
	option label '14 Proxy Telegram'
	option enabled '1'
	list rule_set 'telegram'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label '15 Proxy Twitter X'
	option enabled '1'
	list rule_set 'twitter'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label '16 Proxy TikTok'
	option enabled '1'
	list rule_set 'tiktok'
	option action 'route'
	option outbound 'proxy_out'

# 17 GitHub 代理 —— 国内直连不稳定，强制走代理避免 clone/pull 失败
config routing_rule
	option label '17 Proxy GitHub'
	option enabled '1'
	list rule_set 'github'
	option action 'route'
	option outbound 'proxy_out'

# 18 游戏代理
config routing_rule
	option label '18 Proxy Games'
	option enabled '1'
	list rule_set 'games'
	option action 'route'
	option outbound 'proxy_out'

# 19 境外站点代理
config routing_rule
	option label '19 Proxy Non-CN'
	option enabled '1'
	list rule_set 'non_cn'
	option action 'route'
	option outbound 'proxy_out'

# 20 兜底直连 —— 未匹配的多为国内长尾
config routing_rule
	option label '20 Direct Default'
	option enabled '1'
	option action 'route'
	option outbound 'direct-out'

# ============================================================================
# 添加节点后必做
#
# 在 LuCI 的 DNS 规则列表中，把下面这条拖到**第一位**，
# 把 example.com 换成你节点的真实域名：
#
#   名称:     00 节点域名
#   域名:     example.com
#   出站:     route
#   DNS 服务器: 114_dns
#
# 原因：解析节点域名必须用能直连的国内 DNS。若走境外 DNS，需要先建代理
# 隧道；而建隧道又需要先解析节点域名 —— 形成死循环，表现为节点连不上。
# ============================================================================

# ============================================================================
# 可选：按需自定义规则（示例，取消注释并改成你的域名后使用）
#
# 走代理的特定服务（放在 20 Proxy Non-CN 之前）：
# config routing_rule
# 	option label 'XX Custom Proxy'
# 	option enabled '1'
# 	list domain 'example-api.com'
# 	option action 'route'
# 	option outbound 'proxy_out'
#
# 走直连的特定服务（放在 06 Direct CN IP 之前）：
# config routing_rule
# 	option label 'XX Custom Direct'
# 	option enabled '1'
# 	list domain 'example-cn.com'
# 	option action 'route'
# 	option outbound 'direct-out'
# ============================================================================

CONFEOF
	echo "Template appended"
fi

# ===========================================================================
# P5: ECH import support for VLESS/Trojan share links and subscriptions
# ===========================================================================
# Strategy for sing-box <=1.12.x (no query_server_name field):
#   - Set tls_ech_config_path='/etc/homeproxy/ech_<SNI>.pem' (dynamic per ECH SNI)
#   - Keep tls_sni = Worker SNI (from share link sni= param) — not overwritten
#   - PEM auto-fetched via ucode wGET() from AliDNS DoH at subscription update time
#   - PEM path derived from ech= SNI; PEM auto-fetched via ucode AliDNS DoH
# ===========================================================================

# ------------------------------------------------------------------
# P5a: PEM fetch is now inline ucode in update_subscriptions.uc (no shell script)
echo "P5a: PEM fetch via ucode (inline)"

# ------------------------------------------------------------------
# P5b: Patch node.js — share link import frontend
# ------------------------------------------------------------------
NODEJS_PATH="feeds/smpackage/luci-app-homeproxy/htdocs/luci-static/resources/view/homeproxy/node.js"

if [ -f "$NODEJS_PATH" ] && command -v python3 >/dev/null 2>&1; then
	python3 << 'PYEOF'
import sys

path = "feeds/smpackage/luci-app-homeproxy/htdocs/luci-static/resources/view/homeproxy/node.js"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Helper: normalize ECH config + simplified applyECHParam
helper = """function normalizeECHConfig(value) {
\tif (!value)
\t\treturn null;

\tvalue = decodeURIComponent(value).replace(/ /g, '+');
\tif (value.includes('BEGIN ECH CONFIGS'))
\t\treturn value;

\tvar nl=String.fromCharCode(10);\n\treturn '-----BEGIN ECH CONFIGS-----'+nl+value+nl+'-----END ECH CONFIGS-----';
}

function applyECHParam(config, echParam) {
	if (!echParam)
		return;

	const sep = echParam.includes("+") ? echParam.indexOf("+") : echParam.indexOf(" ");
	if (sep <= 0)
		return;

	config.tls = '1';
	config.tls_ech = '1';
	config.tls_sni = decodeURIComponent(echParam.slice(0, sep));
	config.tls_ech_config_path = '/etc/homeproxy/ech_' + decodeURIComponent(echParam.slice(0, sep)) + '.pem';
	if (echParam.slice(sep + 1).indexOf('http') !== 0)
		config.tls_ech_config = normalizeECHConfig(echParam.slice(sep + 1));
}

"""
anchor = "function parseShareLink(uri, features) {\n"
if "function normalizeECHConfig(value)" not in content:
    assert anchor in content, "ECH helper anchor not found"
    content = content.replace(anchor, helper + anchor, 1)

# VLess ECH: add tls_ech + tls_ech_config_path
old = "\t\t\t\tvless_flow: ['tls', 'reality'].includes(params.get('security')) ? params.get('flow') : null\n\t\t\t};"
new = "\t\t\t\tvless_flow: ['tls', 'reality'].includes(params.get('security')) ? params.get('flow') : null,\n\t\t\t\ttls_ech: (params.get('security') === 'ech' || params.get('ech')) ? '1' : '0',\n\t\t\t\ttls_ech_config_path: '/etc/homeproxy/ech.pem',\n\t\t\t\ttls_ech_config: normalizeECHConfig(params.get('EchConfigList'))\n\t\t\t};\n\n\t\t\tif (config.tls_ech === '1')\n\t\t\t\tconfig.tls = '1';\n\t\t\tapplyECHParam(config, params.get('ech'));"
assert old in content, "VLess ECH anchor not found"
content = content.replace(old, new, 1)
print("P5b VLess ECH: OK")

# Trojan ECH: add tls_ech + tls_ech_config_path
old = "\t\t\t\ttls_sni: params.get('sni')\n\t\t\t};\n\t\t\tswitch (params.get('type')) {"
new = "\t\t\t\ttls_sni: params.get('sni'),\n\t\t\t\ttls_ech: (params.get('security') === 'ech' || params.get('ech')) ? '1' : '0',\n\t\t\t\ttls_ech_config_path: '/etc/homeproxy/ech.pem',\n\t\t\t\ttls_ech_config: normalizeECHConfig(params.get('EchConfigList'))\n\t\t\t};\n\n\t\t\tapplyECHParam(config, params.get('ech'));\n\t\t\tswitch (params.get('type')) {"
assert old in content, "Trojan ECH anchor not found"
content = content.replace(old, new, 1)
print("P5b Trojan ECH: OK")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF

	echo "P5b node.js ECH import: done"
else
	echo "P5b node.js ECH import: SKIP"
fi

# ------------------------------------------------------------------
# P5c: Patch update_subscriptions.uc — subscription backend
# ------------------------------------------------------------------
SUBS_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/homeproxy/scripts/update_subscriptions.uc"

if [ -f "$SUBS_PATH" ] && command -v python3 >/dev/null 2>&1; then
	python3 << 'PYEOF'
path = "feeds/smpackage/luci-app-homeproxy/root/etc/homeproxy/scripts/update_subscriptions.uc"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Helper: normalize_ech_config + simplified apply_ech_param
helper = """function normalize_ech_config(value) {
\tif (isEmpty(value))
\t\treturn null;

\tvalue = replace(urldecode(value), / /g, '+');
\tif (match(value, /BEGIN ECH CONFIGS/))
\t\treturn value;

\tlet nl=chr(10);\n\treturn '-----BEGIN ECH CONFIGS-----'+nl+value+nl+'-----END ECH CONFIGS-----';
}

function apply_ech_param(config, ech_param) {
	if (isEmpty(ech_param))
		return;

	ech_param = urldecode(ech_param);
	let sep = index(ech_param, "+");
	if (sep < 0)
		sep = index(ech_param, " ");
	if (sep <= 0)
		return;

	const ech_sni = urldecode(substr(ech_param, 0, sep));
	config.tls = '1';
	config.tls_ech = '1';
	config.tls_sni = ech_sni;
	config.tls_ech_config_path = '/etc/homeproxy/ech_' + ech_sni + '.pem';
	if (index(substr(ech_param, sep + 1), 'http') != 0)
		config.tls_ech_config = normalize_ech_config(substr(ech_param, sep + 1));
}

"""
anchor = "/* Common var start */\n"
if "function normalize_ech_config(value)" not in content:
    assert anchor in content, "subscription ECH helper anchor not found"
    content = content.replace(anchor, helper + anchor, 1)

# Trojan config: add tls_ech + tls_ech_config_path
old = "\t\t\tconfig = {\n\t\t\t\tlabel: url.hash ? urldecode(url.hash) : null,\n\t\t\t\ttype: 'trojan',\n\t\t\t\taddress: url.hostname,\n\t\t\t\tport: url.port,\n\t\t\t\tpassword: urldecode(url.username),\n\t\t\t\ttransport: (params.type !== 'tcp') ? params.type : null,\n\t\t\t\ttls: '1',\n\t\t\t\ttls_sni: params.sni\n\t\t\t};\n\t\t\tswitch(params.type) {"
new = "\t\t\tconfig = {\n\t\t\t\tlabel: url.hash ? urldecode(url.hash) : null,\n\t\t\t\ttype: 'trojan',\n\t\t\t\taddress: url.hostname,\n\t\t\t\tport: url.port,\n\t\t\t\tpassword: urldecode(url.username),\n\t\t\t\ttransport: (params.type !== 'tcp') ? params.type : null,\n\t\t\t\ttls: '1',\n\t\t\t\ttls_sni: params.sni,\n\t\t\t\ttls_ech: (params.security === 'ech' || params.ech) ? '1' : '0',\n\t\t\t\ttls_ech_config: normalize_ech_config(params.EchConfigList),\n\t\t\t\ttls_ech_config_path: '/etc/homeproxy/ech.pem'\n\t\t\t};\n\t\t\tapply_ech_param(config, params.ech);\n\t\t\tswitch(params.type) {"
assert old in content, "subscription Trojan ECH anchor not found"
content = content.replace(old, new, 1)
print("P5c subscription Trojan ECH: OK")

# VLess config: add tls_ech + tls_ech_config_path
old = "\t\t\tconfig = {\n\t\t\t\tlabel: url.hash ? urldecode(url.hash) : null,\n\t\t\t\ttype: 'vless',\n\t\t\t\taddress: url.hostname,\n\t\t\t\tport: url.port,\n\t\t\t\tuuid: url.username,\n\t\t\t\ttransport: (params.type !== 'tcp') ? params.type : null,\n\t\t\t\ttls: (params.security in ['tls', 'xtls', 'reality']) ? '1' : '0',\n\t\t\t\ttls_sni: params.sni,\n\t\t\t\ttls_alpn: params.alpn ? split(urldecode(params.alpn), ',') : null,\n\t\t\t\ttls_reality: (params.security === 'reality') ? '1' : '0',\n\t\t\t\ttls_reality_public_key: params.pbk ? urldecode(params.pbk) : null,\n\t\t\t\ttls_reality_short_id: params.sid,\n\t\t\t\ttls_utls: sing_features.with_utls ? params.fp : null,\n\t\t\t\tvless_flow: (params.security in ['tls', 'reality']) ? params.flow : null\n\t\t\t};\n\t\t\tswitch(params.type) {"
new = "\t\t\tconfig = {\n\t\t\t\tlabel: url.hash ? urldecode(url.hash) : null,\n\t\t\t\ttype: 'vless',\n\t\t\t\taddress: url.hostname,\n\t\t\t\tport: url.port,\n\t\t\t\tuuid: url.username,\n\t\t\t\ttransport: (params.type !== 'tcp') ? params.type : null,\n\t\t\t\ttls: (params.security in ['tls', 'xtls', 'reality', 'ech'] || params.ech) ? '1' : '0',\n\t\t\t\ttls_sni: params.sni,\n\t\t\t\ttls_alpn: params.alpn ? split(urldecode(params.alpn), ',') : null,\n\t\t\t\ttls_reality: (params.security === 'reality') ? '1' : '0',\n\t\t\t\ttls_reality_public_key: params.pbk ? urldecode(params.pbk) : null,\n\t\t\t\ttls_reality_short_id: params.sid,\n\t\t\t\ttls_utls: sing_features.with_utls ? params.fp : null,\n\t\t\t\tvless_flow: (params.security in ['tls', 'reality']) ? params.flow : null,\n\t\t\t\ttls_ech: (params.security === 'ech' || params.ech) ? '1' : '0',\n\t\t\t\ttls_ech_config: normalize_ech_config(params.EchConfigList),\n\t\t\t\ttls_ech_config_path: '/etc/homeproxy/ech.pem'\n\t\t\t};\n\t\t\tapply_ech_param(config, params.ech);\n\t\t\tswitch(params.type) {"
assert old in content, "subscription VLess ECH anchor not found"
content = content.replace(old, new, 1)
print("P5c subscription VLess ECH: OK")

# Add PEM refresh call in main() after node processing loop via ucode
insert_marker = "if (isEmpty(node_result)) {"
import base64
fetch_code = base64.b64decode("CS8qIEZldGNoIEVDSCBQRU0gZnJvbSBBbGlETlMgRG9IIGZvciBlYWNoIHVuaXF1ZSBFQ0ggU05JICovCgljb25zdCBlY2hfc25pcyA9IFtdOwoJLyogQ29sbGVjdCBmcm9tIG5ld2x5IHBhcnNlZCBub2RlcyAqLwoJZm9yIChsZXQgbm9kZXMgaW4gbm9kZV9yZXN1bHQpCgkJbWFwKG5vZGVzLCAobm9kZSkgPT4gewoJCQlpZiAobm9kZS50bHNfZWNoX2NvbmZpZ19wYXRoKSB7CgkJCQljb25zdCBlY2hfbSA9IG1hdGNoKG5vZGUudGxzX2VjaF9jb25maWdfcGF0aCwgL2VjaF8oW15cL10rKVwucGVtJC8pOwoJCQkJaWYgKGVjaF9tICYmICF+aW5kZXgoZWNoX3NuaXMsIGVjaF9tWzFdKSkKCQkJCQlwdXNoKGVjaF9zbmlzLCBlY2hfbVsxXSk7CgkJCX0KCQl9KTsKCS8qIEFsc28gY29sbGVjdCBmcm9tIGV4aXN0aW5nIFVDSSBub2RlcyAqLwoJdWNpLmZvcmVhY2godWNpY29uZmlnLCAnbm9kZScsIChuY2ZnKSA9PiB7CgkJaWYgKG5jZmcudGxzX2VjaCA9PT0gJzEnICYmIG5jZmcudGxzX2VjaF9jb25maWdfcGF0aCkgewoJCQljb25zdCBlY2hfbSA9IG1hdGNoKG5jZmcudGxzX2VjaF9jb25maWdfcGF0aCwgL2VjaF8oW15cL10rKVwucGVtJC8pOwoJCQlpZiAoZWNoX20gJiYgIX5pbmRleChlY2hfc25pcywgZWNoX21bMV0pKQoJCQkJcHVzaChlY2hfc25pcywgZWNoX21bMV0pOwoJCX0KCX0pOwoJLyogRG93bmxvYWQgUEVNIGZvciBlYWNoIHVuaXF1ZSBTTkkgKi8KCW1hcChlY2hfc25pcywgKGVjaF9zbmkpID0+IHsKCQl0cnkgewoJCQljb25zdCBlY2hfZG9oID0gJ2h0dHBzOi8vZG5zLmFsaWRucy5jb20vcmVzb2x2ZT9uYW1lPScgKyBlY2hfc25pICsgJyZ0eXBlPUhUVFBTJzsKCQkJY29uc3QgZWNoX3Jlc3AgPSB3R0VUKGVjaF9kb2gsICdzaW5nLWJveC8xLjEyJyk7CgkJCWlmICghaXNFbXB0eShlY2hfcmVzcCkpIHsKCQkJCWNvbnN0IGVjaF9kYXRhID0ganNvbihlY2hfcmVzcCk7CgkJCQljb25zdCBlY2hfYW5zd2VycyA9IGVjaF9kYXRhLkFuc3dlciB8fCBbXTsKCQkJCWZvciAobGV0IGVjaF9hbnMgaW4gZWNoX2Fuc3dlcnMpIHsKCQkJCQljb25zdCBlY2hfc3RyID0gZWNoX2Fucy5kYXRhIHx8ICcnOwoJCQkJCWNvbnN0IGVjaF9iNjRtID0gbWF0Y2goZWNoX3N0ciwgL2VjaD0iKFtBLVphLXowLTkrXC89XSspIi8pOwoJCQkJCWlmIChlY2hfYjY0bSkgewoJCQkJCQljb25zdCBlY2hfcGVtID0gJy0tLS0tQkVHSU4gRUNIIENPTkZJR1MtLS0tLQonICsgZWNoX2I2NG1bMV0gKyAnCi0tLS0tRU5EIEVDSCBDT05GSUdTLS0tLS0nOwoJCQkJCQljb25zdCBlY2hfZiA9IG9wZW4oJy9ldGMvaG9tZXByb3h5L2VjaF8nICsgZWNoX3NuaSArICcucGVtJywgJ3cnKTsKCQkJCQkJaWYgKGVjaF9mKSB7CgkJCQkJCQllY2hfZi53cml0ZShlY2hfcGVtKTsKCQkJCQkJCWVjaF9mLmNsb3NlKCk7CgkJCQkJCQlsb2coJ0VDSCBQRU0gdXBkYXRlZCBmb3IgJyArIGVjaF9zbmkgKyAnICgnICsgbGVuZ3RoKGVjaF9iNjRtWzFdKSArICcgYnl0ZXMgYmFzZTY0KScpOwoJCQkJCQl9CgkJCQkJCWJyZWFrOwoJCQkJCX0KCQkJCX0KCQkJfQoJCX0gY2F0Y2goZWNoX2VycikgewoJCQlsb2coJ0VDSCBQRU0gZmV0Y2ggZmFpbGVkIGZvciAnICsgZWNoX3NuaSArICc6ICcgKyBlY2hfZXJyKTsKCQl9Cgl9KTsK").decode("utf-8")
fetch_call = fetch_code

# Add urltest_nodes auto-sync after node processing
sync_code = base64.b64decode("CS8qIFN5bmMgdXJsdGVzdF9ub2RlcyBpbiByb3V0aW5nX25vZGUgZW50cmllcyB3aXRoIHN1YnNjcmlwdGlvbiBub2RlcyAqLwoJdWNpLmZvcmVhY2godWNpY29uZmlnLCAncm91dGluZ19ub2RlJywgKHJjZmcpID0+IHsKCQlpZiAocmNmZy5lbmFibGVkICE9PSAnMScgfHwgcmNmZy5ub2RlICE9PSAndXJsdGVzdCcpCgkJCXJldHVybjsKCQljb25zdCBydGFnID0gcmNmZ1snLm5hbWUnXTsKCQljb25zdCBuZXdfbGlzdCA9IFtdOwoJCXVjaS5mb3JlYWNoKHVjaWNvbmZpZywgJ25vZGUnLCAobmNmZykgPT4gewoJCQlpZiAobmNmZy5ncm91cGhhc2ggJiYgbmNmZ1snLm5hbWUnXSAmJiAhfmluZGV4KG5ld19saXN0LCBuY2ZnWycubmFtZSddKSkKCQkJCXB1c2gobmV3X2xpc3QsIG5jZmdbJy5uYW1lJ10pOwoJCX0pOwoJCXN5c3RlbShbJ3VjaScsICdkZWxldGUnLCAnaG9tZXByb3h5LicgKyBydGFnICsgJy51cmx0ZXN0X25vZGVzJ10pOwoJCW1hcChuZXdfbGlzdCwgKG5pZCkgPT4gc3lzdGVtKFsndWNpJywgJ2FkZF9saXN0JywgJ2hvbWVwcm94eS4nICsgcnRhZyArICcudXJsdGVzdF9ub2Rlcz0nICsgbmlkXSkpOwoJCXN5c3RlbShbJ3VjaScsICdjb21taXQnLCAnaG9tZXByb3h5J10pOwoJCWxvZyhzcHJpbnRmKCdTeW5jZWQgdXJsdGVzdF9ub2RlcyBmb3IgJXM6ICVkIG5vZGVzJywgcnRhZywgbGVuZ3RoKG5ld19saXN0KSkpOwoJfSk7Cg==").decode("utf-8")

if sync_code not in content:
    content = content.replace(insert_marker, sync_code + insert_marker, 1)
    print("P5c urltest sync: added")
else:
    print("P5c urltest sync: already present")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF

	echo "P5c subscription ECH import: done"
else
	echo "P5c subscription ECH import: SKIP"
fi

echo "=== done ==="

# ===========================================================================
# P6: generate_client.uc — robustness and ECH resilience
# ===========================================================================
GCU_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/homeproxy/scripts/generate_client.uc"
if [ -f "$GCU_PATH" ] && command -v python3 >/dev/null 2>&1; then
	python3 << 'PYEOF_P6'
import pathlib

path = "feeds/smpackage/luci-app-homeproxy/root/etc/homeproxy/scripts/generate_client.uc"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

fixes = 0

# P6a: strToTime for gRPC/HTTP2 transport timeouts (upstream 4613766)
for old, label in [
    ("idle_timeout: (node.http_idle_timeout),", "idle_timeout"),
    ("ping_timeout: (node.http_ping_timeout),", "ping_timeout"),
]:
    if old in content:
        content = content.replace(old, old.replace("(node.", "strToTime(node.").replace("),", "),"), 1)
        fixes += 1
        print(f"P6a strToTime {label}: OK")
    else:
        print(f"P6a strToTime {label}: SKIP")

# P6b: ECH PEM file existence check
old = "ech: (node.tls_ech === '1') ? {\n\t\t\t\tenabled: true,\n\t\t\t\tconfig: node.tls_ech_config,\n\t\t\t\tconfig_path: node.tls_ech_config_path\n\t\t\t} : null,"
new = """ech: (node.tls_ech === '1') ? (() => {
\t\t\t\tconst ech_config = node.tls_ech_config;
\t\t\t\tconst ech_path = (node.tls_ech_config_path && readfile(node.tls_ech_config_path)) ? node.tls_ech_config_path : null;
\t\t\t\tif (isEmpty(ech_config) && isEmpty(ech_path))
\t\t\t\t\treturn null;
\t\t\t\treturn {
\t\t\t\t\tenabled: true,
\t\t\t\t\tconfig: ech_config,
\t\t\t\t\tconfig_path: ech_path
\t\t\t\t};
\t\t\t})() : null,"""
if old in content:
    content = content.replace(old, new, 1)
    fixes += 1
    print("P6b ECH file check: OK")
else:
    print("P6b ECH file check: SKIP")

# P6c: main_node !== 'nil' guards (3 locations)
for anchor, old_guard in [
    ("/* Main DNS */", "if (!isEmpty(main_node)) {"),
    ("/* Main outbounds */", "if (!isEmpty(main_node)) {"),
    ("/* Routing rules */", "if (!isEmpty(main_node)) {"),
]:
    new_guard = "if (!isEmpty(main_node) && main_node !== 'nil') {"
    if anchor in content and old_guard in content:
        content = content.replace(old_guard, new_guard, 1)
        fixes += 1
    else:
        print(f"P6c nil guard: SKIP ({anchor[:20]}...)")

print(f"P6c nil guards: applied")

# P6d: null-guard generate_outbound returns
for old, new in [
    ("push(config.outbounds, generate_outbound(main_node_cfg));\n\t\t\tconfig.outbounds[length(config.outbounds)-1].tag = 'main-out';",
     "const ob = generate_outbound(main_node_cfg);\n\t\t\tif (ob) {\n\t\t\t\tpush(config.outbounds, ob);\n\t\t\t\tconfig.outbounds[length(config.outbounds)-1].tag = 'main-out';\n\t\t\t}"),
    ("push(config.outbounds, generate_outbound(main_udp_node_cfg));\n\t\t\tconfig.outbounds[length(config.outbounds)-1].tag = 'main-udp-out';",
     "const ob = generate_outbound(main_udp_node_cfg);\n\t\t\tif (ob) {\n\t\t\t\tpush(config.outbounds, ob);\n\t\t\t\tconfig.outbounds[length(config.outbounds)-1].tag = 'main-udp-out';\n\t\t\t}"),
]:
    if old in content:
        content = content.replace(old, new, 1)
        fixes += 1
        print("P6d null-guard: OK")
    else:
        print("P6d null-guard: SKIP")

# P6e: DNS/route final fallbacks
if "}\n/* DNS end */" in content:
    content = content.replace("}\n/* DNS end */", "}\nif (isEmpty(config.dns.final))\n\tconfig.dns.final = 'default-dns';\n/* DNS end */", 1)
    fixes += 1
    print("P6e DNS final: OK")
if "}\n/* Routing rules end */" in content:
    content = content.replace("}\n/* Routing rules end */", "}\nif (isEmpty(config.route.final))\n\tconfig.route.final = 'direct-out';\n/* Routing rules end */", 1)
    fixes += 1
    print("P6e route final: OK")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print(f"P6 generate_client.uc: {fixes} fixes")
PYEOF_P6
	echo "P6 generate_client.uc: done"
else
	echo "P6 generate_client.uc: SKIP"
fi

# ---------------------------------------------------------------------------
# P7: config/homeproxy — safe defaults for first-time flash
# ---------------------------------------------------------------------------
if [ -f "$CONF_PATH" ]; then
	sed -i "s/option main_node 'nil'/option main_node ''/" "$CONF_PATH" && echo "P7a empty main_node: OK" || echo "P7a SKIP"
	sed -i "s/option main_udp_node 'same'/option main_udp_node ''/" "$CONF_PATH" && echo "P7a empty main_udp_node: OK" || echo "P7a SKIP"
	sed -i "s/option default_server 'local-dns'/option default_server 'default-dns'/" "$CONF_PATH" && echo "P7b default-dns: OK" || echo "P7b SKIP"
else
	echo "P7 config: SKIP"
fi

# ---------------------------------------------------------------------------
# P8: init.d/homeproxy — chmod RUN_DIR for ujail
# ---------------------------------------------------------------------------
INIT_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/init.d/homeproxy"
sed -i '/chown -R sing-box:sing-box "\$RUN_DIR"/a\	chmod -R a+r "\$RUN_DIR" 2>/dev/null' "$INIT_PATH" 2>/dev/null
grep -q 'chmod -R a+r' "$INIT_PATH" && echo "P8 chmod RUN_DIR: OK" || echo "P8 chmod RUN_DIR: SKIP"

# ---------------------------------------------------------------------------
# P9: luci.homeproxy — pidof for proxy_check
# ---------------------------------------------------------------------------
LUCI_PATH="feeds/smpackage/luci-app-homeproxy/root/usr/share/rpcd/ucode/luci.homeproxy"
if [ -f "$LUCI_PATH" ]; then
	sed -i "s|/usr/bin/wget --spider -qT3 \${url} 2>\"/dev/null\"\`, 3100|pidof sing-box >/dev/null 2>\&1\`|" "$LUCI_PATH" && echo "P9 pidof: OK" || echo "P9 pidof: SKIP"
else
	echo "P9 luci.homeproxy: SKIP"
fi


# ---------------------------------------------------------------------------
# P10: BBR + fq — BBR requires the fq qdisc to fully engage
#   CONFIG_NET_SCH_FQ in .config gets rewritten by make defconfig, so instead:
#   1) select kmod-sched at build time (upstream netsupport.mk: SCHED_MODULES_EXTRA has sch_fq)
#   2) set net.core.default_qdisc=fq in sysctl.conf + rc.local at build time
# ---------------------------------------------------------------------------
SYSCTL="package/base-files/files/etc/sysctl.conf"
if [ -f "$SYSCTL" ]; then
	grep -q 'net.core.default_qdisc' "$SYSCTL" 2>/dev/null || \
		printf '\n# BBR requires fq qdisc\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >> "$SYSCTL"
	grep -q 'net.core.default_qdisc' "$SYSCTL" 2>/dev/null && echo "P10 sysctl fq+bbr: OK" || echo "P10 sysctl: WRITE FAILED"
else
	echo "P10 sysctl: SKIP (not found)"
fi

# rc.local fallback: modprobe sch_fq then set qdisc
RCLOCAL="package/base-files/files/etc/rc.local"
if [ -f "$RCLOCAL" ]; then
	grep -q 'default_qdisc' "$RCLOCAL" 2>/dev/null || {
		awk '
			/^exit 0/ && !done {
				print ""
				print "# BBR requires fq qdisc (sch_fq from kmod-sched)"
				print "modprobe sch_fq 2>/dev/null"
				print "echo fq > /proc/sys/net/core/default_qdisc 2>/dev/null"
				print "echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null"
				print ""
				done=1
			}
			{ print }
		' "$RCLOCAL" > "$RCLOCAL.tmp" && mv "$RCLOCAL.tmp" "$RCLOCAL"
	}
	grep -q 'default_qdisc' "$RCLOCAL" 2>/dev/null && echo "P10 rc.local fq: OK" || echo "P10 rc.local: WRITE FAILED"
else
	echo "P10 rc.local: SKIP (not found)"
fi

# ---------------------------------------------------------------------------
# P11: chinadns-ng — DNS pollution filtering
#   Fills the gap left by sing-box 1.12, which lacks match_response (1.14 only).
#   Logic: query both chn_dns and trust_dns; if chn_dns answers first with a
#   non-CN IP, discard it and wait for trust_dns instead.
#   Chain: client -> dnsmasq(:53) -> chinadns-ng(:5353) -> chn/trust DNS
# ---------------------------------------------------------------------------
CDNG=""
for p in \
	"feeds/luci/applications/luci-app-chinadns-ng/root/etc/config/chinadns-ng" \
	"package/network/services/chinadns-ng/files/chinadns-ng.config" \
	"package/network/services/chinadns-ng/files/chinadns-ng" ; do
	[ -f "$p" ] && { CDNG="$p"; break; }
done

if [ -n "$CDNG" ]; then
	CDNG_SETOPT() {
		KEY="$1"; VAL="$2"
		awk -v k="$KEY" -v v="$VAL" '
			$1 == "option" && $2 == k { print "\toption " k " \047" v "\047"; f=1; next }
			{ print }
			END { if (!f) print "\toption " k " \047" v "\047" }
		' "$CDNG" > "$CDNG.tmp" && mv "$CDNG.tmp" "$CDNG"
	}
	CDNG_SETOPT enabled "1"
	CDNG_SETOPT port "5353"
	CDNG_SETOPT chn_dns "114.114.114.114"
	CDNG_SETOPT trust_dns "127.0.0.1#5333"
	grep -q "5353" "$CDNG" 2>/dev/null && echo "P11 chinadns-ng config: OK ($CDNG)" || echo "P11 chinadns-ng: WRITE FAILED"
else
	echo "P11 chinadns-ng: SKIP (config not found)"
fi

# Point dnsmasq upstream at chinadns-ng
DHCP="package/base-files/files/etc/config/dhcp"
if [ -n "$CDNG" ] && [ -f "$DHCP" ]; then
	if ! grep -q "127.0.0.1#5353" "$DHCP" 2>/dev/null; then
		awk '
			/^config dnsmasq/ && !done { print; print "\toption server \047127.0.0.1#5353\047"; done=1; next }
			{ print }
		' "$DHCP" > "$DHCP.tmp" && mv "$DHCP.tmp" "$DHCP"
	fi
	grep -q "127.0.0.1#5353" "$DHCP" 2>/dev/null && echo "P11 dnsmasq->chinadns-ng: OK" || echo "P11 dnsmasq: WRITE FAILED"
fi
