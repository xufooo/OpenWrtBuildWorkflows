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

set -euo pipefail
echo "=== script-2 ==="

rm -rf feeds/smpackage/miniupnpd-iptables package/feeds/smpackage/miniupnpd-iptables

CONF_PATH="feeds/smpackage/luci-app-homeproxy/root/etc/config/homeproxy"

# Fix default_server: template uses 114_dns, not the upstream default local-dns
sed -i "s/option default_server 'local-dns'/option default_server '114_dns'/" "$CONF_PATH"

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
	option label 'Default -> 114 DNS'
	option enabled '1'
	option action 'route'
	option server '114_dns'

config routing_rule
	option label 'Ads -> Block'
	option enabled '1'
	list rule_set 'ads'
	option action 'reject'

config routing_rule
	option label 'BT/P2P -> Block'
	option enabled '1'
	list protocol 'bittorrent'
	option action 'reject'

config routing_rule
	option label 'CN IP -> Direct'
	option enabled '1'
	list rule_set 'cn_ip'
	option action 'route'
	option outbound 'direct-out'

config routing_rule
	option label 'Private IP -> Direct'
	option enabled '1'
	list rule_set 'private_ip'
	option action 'route'
	option outbound 'direct-out'

config routing_rule
	option label 'Games -> Proxy'
	option enabled '1'
	list rule_set 'games'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'AI -> Proxy'
	option enabled '1'
	list rule_set 'ai_services'
	list rule_set 'apple_ai'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Netflix -> Proxy'
	option enabled '1'
	list rule_set 'netflix'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Disney+ -> Proxy'
	option enabled '1'
	list rule_set 'disney'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'YouTube -> Proxy'
	option enabled '1'
	list rule_set 'youtube'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Spotify -> Proxy'
	option enabled '1'
	list rule_set 'spotify'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Telegram -> Proxy'
	option enabled '1'
	list rule_set 'telegram'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Twitter/X -> Proxy'
	option enabled '1'
	list rule_set 'twitter'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'TikTok -> Proxy'
	option enabled '1'
	list rule_set 'tiktok'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'GitHub -> Proxy'
	option enabled '1'
	list rule_set 'github'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'OpenAI -> Proxy'
	option enabled '1'
	list rule_set 'openai'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Non-CN -> Proxy'
	option enabled '1'
	list rule_set 'non_cn'
	option action 'route'
	option outbound 'proxy_out'

config routing_rule
	option label 'Default -> Direct'
	option enabled '1'
	option action 'route'
	option outbound 'direct-out'

	echo "Template appended"
fi

echo "=== done ==="
