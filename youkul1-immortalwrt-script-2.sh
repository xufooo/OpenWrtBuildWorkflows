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
# 3. P5: ECH import support for VLESS/Trojan subscription share links

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
	option domain_resolver 'default-dns'
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
	option address_resolver 'default-dns'
	option enabled '1'

config dns_server 'google_dns'
	option label 'Google DNS'
	option type 'https'
	option server 'dns.google'
	option server_port '443'
	option path '/dns-query'
	option outbound 'proxy_out'
	option address_resolver 'default-dns'
	option enabled '1'

config ruleset 'cn_domain'
	option label 'CN Domains'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-geolocation-cn.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'cn_ip'
	option label 'CN IPs'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@rule-set/cn.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'non_cn'
	option label 'Non-CN Sites'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-geolocation-!cn.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'gfw'
	option label 'GFW List'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-gfw.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'netflix'
	option label 'Netflix'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-netflix.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'disney'
	option label 'Disney+'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-disney.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'youtube'
	option label 'YouTube'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-youtube.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'spotify'
	option label 'Spotify'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-spotify.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'openai'
	option label 'OpenAI / ChatGPT'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-openai.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'ai_services'
	option label 'AI Services'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-ai-!cn.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'apple_ai'
	option label 'Apple Intelligence'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-apple-intelligence.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'telegram'
	option label 'Telegram'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-telegram.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'twitter'
	option label 'Twitter / X'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-twitter.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'tiktok'
	option label 'TikTok'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-tiktok.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'github'
	option label 'GitHub'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-github.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'ads'
	option label 'Ad Blocking'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-ads.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'private_ip'
	option label 'Private IPs'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-private.srs'
	option update_interval '72h'
	option enabled '1'

config ruleset 'games'
	option label 'Games'
	option type 'remote'
	option format 'binary'
	option url 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set/geosite-category-games.srs'
	option update_interval '72h'
	option enabled '1'

config dns_rule
	option label 'Block SVCB/HTTPS'
	option enabled '1'
	list query_type '64'
	list query_type '65'
	option action 'reject'

config dns_rule
	option label 'GFW -> CF DoH'
	option enabled '1'
	list rule_set 'gfw'
	option action 'route'
	option server 'cloudflare_dns'

config dns_rule
	option label 'Ads -> Block (DNS)'
	option enabled '1'
	list rule_set 'ads'
	option action 'reject'

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
	option server 'tencent_dns'

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

# P5: ECH import support for VLESS/Trojan subscription share links
# ===========================================================================
# Patches update_subscriptions.uc (subscription backend) to parse:
#   ech=<SNI>+<base64_or_URL>  (overrides tls_sni, sets tls_ech_config)
#   ech=<SNI>                   (overrides tls_sni only)
#   security=ech + EchConfigList  (standard sing-box format)
SUB_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/homeproxy/scripts/update_subscriptions.uc"

if [ -f "$SUB_PATH" ] && command -v python3 >/dev/null 2>&1; then
	python3 << 'PYEOF'
import sys

path = "feeds/smpackage/luci-app-homeproxy/root/etc/homeproxy/scripts/update_subscriptions.uc"
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# VLess ECH: insert after vless_flow line, before closing };
old = "				vless_flow: (params.security in ['tls', 'reality']) ? params.flow : null
			};"
new = (
    "				vless_flow: (params.security in ['tls', 'reality']) ? params.flow : null
"
    "			};
"
    "			if (params.ech) {
"
    "				config.tls_ech = '1';
"
    "				const ech_parts = split(params.ech, '+');
"
    "				if (length(ech_parts) >= 2) {
"
    "					config.tls_sni = urldecode(ech_parts[0]);
"
    "					config.tls_ech_config = urldecode(ech_parts[1]);
"
    "				} else {
"
    "					config.tls_sni = urldecode(ech_parts[0]);
"
    "				}
"
    "			}
"
    "			if (!config.tls_ech && params.security === 'ech')
"
    "				config.tls_ech = '1';
"
    "			if (params.EchConfigList)
"
    "				config.tls_ech_config = urldecode(params.EchConfigList);"
)
assert old in content, 'VLess ECH anchor not found'
content = content.replace(old, new, 1)
print('P5 VLess ECH: OK')

# Trojan ECH: insert after tls_sni line, before closing };
old = "				tls_sni: params.sni
			};"
new = (
    "				tls_sni: params.sni
"
    "			};
"
    "			if (params.ech) {
"
    "				config.tls_ech = '1';
"
    "				const ech_parts = split(params.ech, '+');
"
    "				if (length(ech_parts) >= 2) {
"
    "					config.tls_sni = urldecode(ech_parts[0]);
"
    "					config.tls_ech_config = urldecode(ech_parts[1]);
"
    "				} else {
"
    "					config.tls_sni = urldecode(ech_parts[0]);
"
    "				}
"
    "			}
"
    "			if (!config.tls_ech && params.security === 'ech')
"
    "				config.tls_ech = '1';
"
    "			if (params.EchConfigList)
"
    "				config.tls_ech_config = urldecode(params.EchConfigList);"
)
assert old in content, 'Trojan ECH anchor not found'
content = content.replace(old, new, 1)
print('P5 Trojan ECH: OK')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF

	echo "P5 ECH import: done"
else
	echo "P5 ECH import: SKIP"
fi


echo "=== done ==="
