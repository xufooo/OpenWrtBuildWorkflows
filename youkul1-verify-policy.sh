#!/bin/bash
# Validate the packaged MIPS generator without starting router services.
set -euo pipefail
image="$1"
offset="$2"
rootfs="$(mktemp -d /tmp/yk-policy.XXXXXX)"
rmdir "$rootfs"
trap 'if [ -n "${ubus_pid:-}" ]; then sudo kill "$ubus_pid" 2>/dev/null || true; fi; sudo rm -rf "$rootfs"' EXIT
sudo unsquashfs -no-progress -o "$offset" -d "$rootfs" "$image" >/dev/null
sudo chown -R "$(id -u):$(id -g)" "$rootfs"
init="$rootfs/etc/init.d/homeproxy"
grep -Fq 'gen_chinadns_lists()' "$init"
grep -Fq 'china_list.filtered' "$init"
grep -Fq 'append_policy_rule' "$rootfs/etc/homeproxy/scripts/generate_client.uc"
grep -Fq "'dns_routing'" "$rootfs/www/luci-static/resources/view/homeproxy/client.js"
test "$(grep -c "^config homeproxy 'config'" "$rootfs/etc/config/homeproxy")" = 1
bash -n "$init"
sudo cp /usr/bin/qemu-mipsel-static "$rootfs/usr/bin/"
sudo mkdir -p "$rootfs/tmp/run/homeproxy" "$rootfs/tmp/run/ubus" "$rootfs/tmp/lock"
target() { sudo chroot "$rootfs" /usr/bin/qemu-mipsel-static "$@"; }
sudo chroot "$rootfs" /usr/bin/qemu-mipsel-static /sbin/ubusd &
ubus_pid=$!
for attempt in {1..30}; do
    [ -S "$rootfs/tmp/run/ubus/ubus.sock" ] && break
    sleep 0.1
done
target /usr/bin/ucode -c -o /tmp/subscriptions.ucb /etc/homeproxy/scripts/update_subscriptions.uc
target /usr/bin/chinadns-ng --group proxylist \
    --group-dnl /etc/homeproxy/resources/gfw_list.txt \
    --group-upstream '127.0.0.1#5333' -N tag:proxylist \
    -N 'tag:gfw,tag:none@ip:non_china' --cache 4096 -V
# Public fixture in the extracted copy only; never embedded in firmware.
target /sbin/uci set homeproxy.ci_node=node
target /sbin/uci set homeproxy.ci_node.type=socks
target /sbin/uci set homeproxy.ci_node.address=127.0.0.1
target /sbin/uci set homeproxy.ci_node.port=9
target /sbin/uci set homeproxy.proxy_out.node=ci_node
target /sbin/uci set homeproxy.routing.default_outbound=proxy_out
target /sbin/uci set homeproxy.dns_block.domain=blocked.example
target /sbin/uci set homeproxy.dns_proxy.domain=proxy.example
target /sbin/uci commit homeproxy
target /usr/bin/ucode -S /etc/homeproxy/scripts/generate_client.uc
target /usr/bin/sing-box check -c /var/run/homeproxy/sing-box-c.json
python3 - "$rootfs/tmp/run/homeproxy/sing-box-c.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
rules = config['route']['rules']
block = next(i for i, r in enumerate(rules) if r.get('domain') in ('blocked.example', ['blocked.example']))
assert rules[block]['action'] == 'reject'
proxy = next(i for i, r in enumerate(rules) if r.get('domain') in ('proxy.example', ['proxy.example']))
reject = rules[proxy - 1]
assert block < proxy
assert reject['type'] == 'logical' and reject['action'] == 'reject'
assert reject['rules'][1] == {'network': 'udp', 'port': [443]}
assert not any(r.get('domain') == '' for r in rules)
fallback = next(i for i, r in enumerate(rules) if r.get('action') == 'route' and r.get('outbound') == 'direct-out' and set(r) == {'action', 'outbound'})
assert proxy < fallback
assert 'action' not in config['route']['default_domain_resolver']
PY
# All three empty UI fields must be inert, especially empty block/direct rules.
for name in dns_block dns_direct dns_proxy; do
    target /sbin/uci set "homeproxy.$name.domain="
done
target /sbin/uci commit homeproxy
target /usr/bin/ucode -S /etc/homeproxy/scripts/generate_client.uc
target /usr/bin/sing-box check -c /var/run/homeproxy/sing-box-c.json
python3 - "$rootfs/tmp/run/homeproxy/sing-box-c.json" <<'PY'
import json, sys
rules = json.load(open(sys.argv[1]))['route']['rules']
assert sum(r == {'action': 'route', 'outbound': 'direct-out'} for r in rules) == 1
assert not any(r == {'action': 'reject'} for r in rules)
assert not any(r == {'action': 'route', 'outbound': 'cfg-ci_node-out'} for r in rules)
PY
# Switching DNS routing back to native must not retain the QUIC policy.
target /sbin/uci set homeproxy.config.dns_routing=native
target /sbin/uci commit homeproxy
target /usr/bin/ucode -S /etc/homeproxy/scripts/generate_client.uc
target /usr/bin/sing-box check -c /var/run/homeproxy/sing-box-c.json
python3 - "$rootfs/tmp/run/homeproxy/sing-box-c.json" <<'PY'
import json, sys
rules = json.load(open(sys.argv[1]))['route']['rules']
assert not any(r.get('action') == 'reject' and r.get('method') == 'default' for r in rules)
PY
echo 'Packaged HomeProxy patches, MIPS configuration and user/QUIC policy verified'
