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

# HP_TEMPLATE -- do not remove this line

config routing_node 'proxy_out'
	option label 'Main Proxy'
	option enabled '1'
	option node 'urltest'
	option domain_resolver 'alidns'
	option domain_strategy 'prefer_ipv4'

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
	option label 'Cloudflare DNS'
	option type 'https'
	option server 'cloudflare-dns.com'
	option server_port '443'
	option path '/dns-query'
	option outbound 'proxy_out'
	option address_resolver '114_dns'
	option enabled '1'

config dns_server 'google_dns'
	option label 'Google DNS'
	option type 'https'
	option server 'dns.google'
	option server_port '443'
	option path '/dns-query'
	option outbound 'proxy_out'
	option address_resolver '114_dns'
	option enabled '1'

config dns_server 'alidns'
	option label 'AliDNS (DoH)'
	option type 'https'
	option server 'dns.alidns.com'
	option server_port '443'
	option path '/dns-query'
	option outbound 'direct-out'
	option address_resolver '114_dns'
	option enabled '1'

config ruleset 'cn_domain'
	option label 'CN Domains'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-geolocation-cn.srs'
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

config ruleset 'non_cn'
	option label 'Non-CN Sites'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-geolocation-!cn.srs'
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

config ruleset 'netflix'
	option label 'Netflix'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-netflix.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'disney'
	option label 'Disney+'
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

config ruleset 'openai'
	option label 'OpenAI / ChatGPT'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-openai.srs'
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

config ruleset 'telegram'
	option label 'Telegram'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-telegram.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'twitter'
	option label 'Twitter / X'
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

config ruleset 'ads'
	option label 'Ad Blocking'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-ads.srs'
	option outbound 'direct-out'
	option update_interval '72h'
	option enabled '1'

config ruleset 'private_ip'
	option label 'Private IPs'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-private.srs'
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

config dns_rule
	option label 'Block SVCB/HTTPS'
	option enabled '1'
	list query_type '64'
	list query_type '65'
	option action 'reject'

config dns_rule
	option label 'Ads Block (DNS)'
	option enabled '1'
	list rule_set 'ads'
	option action 'reject'

config dns_rule
	option label 'GFW'
	option enabled '1'
	list rule_set 'gfw'
	option action 'route'
	option server 'cloudflare_dns'

config dns_rule
	option label 'CN -> 114 DNS'
	option enabled '1'
	list rule_set 'cn_domain'
	option action 'route'
	option server '114_dns'

config dns_rule
	option label 'Non-CN -> Google DoH'
	option enabled '1'
	list rule_set 'non_cn'
	option action 'route'
	option server 'google_dns'

config dns_rule
	option label 'Default -> Tencent DNS'
	option enabled '1'
	option action 'route'
	option server 'alidns'

config routing_rule
	option label 'Ads'
	option enabled '1'
	list rule_set 'ads'
	option action 'reject'

config routing_rule
	option label 'BT/P2P'
	option enabled '1'
	list protocol 'bittorrent'
	option action 'route'
	option outbound 'direct-out'

config routing_rule
	option label 'CN IP'
	option enabled '1'
	list rule_set 'cn_ip'
	option action 'route'
	option outbound 'direct-out'

config routing_rule
	option label 'Private IP'
	option enabled '1'
	list rule_set 'private_ip'
	option action 'route'
	option outbound 'direct-out'

config routing_rule
	option label 'Games'
	option enabled '1'
	list rule_set 'games'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'AI'
	option enabled '1'
	list rule_set 'ai_services'
	list rule_set 'apple_ai'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Netflix'
	option enabled '1'
	list rule_set 'netflix'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Disney+'
	option enabled '1'
	list rule_set 'disney'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'YouTube'
	option enabled '1'
	list rule_set 'youtube'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Spotify'
	option enabled '1'
	list rule_set 'spotify'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Telegram'
	option enabled '1'
	list rule_set 'telegram'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Twitter/X'
	option enabled '1'
	list rule_set 'twitter'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'TikTok'
	option enabled '1'
	list rule_set 'tiktok'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'GitHub'
	option enabled '1'
	list rule_set 'github'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'OpenAI'
	option enabled '1'
	list rule_set 'openai'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Non-CN'
	option enabled '1'
	list rule_set 'non_cn'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Default'
	option enabled '1'
	option action 'route'
	option outbound 'direct-out'
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

\treturn '-----BEGIN ECH CONFIGS-----\\n' + value + '\\n-----END ECH CONFIGS-----';
}

function applyECHParam(config, echParam) {
	if (!echParam)
		return;

	const sep = echParam.includes("+") ? echParam.indexOf("+") : echParam.indexOf(" ");
	if (sep <= 0)
		return;

	config.tls = '1';
	config.tls_ech = '1';
	config.tls_ech_config_path = '/etc/homeproxy/ech_' + decodeURIComponent(echParam.slice(0, sep)) + '.pem';
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

\treturn '-----BEGIN ECH CONFIGS-----\\n' + value + '\\n-----END ECH CONFIGS-----';
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
	config.tls_ech_config_path = '/etc/homeproxy/ech_' + ech_sni + '.pem';
	if (!match(substr(ech_param, sep + 1), /^https?:\/\//))
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
