#!/usr/bin/env python3
"""Finish policy integration in the HomeProxy package selected by feeds."""
from pathlib import Path
import sys

package = Path(sys.argv[1]).resolve()
generator = package / 'root/etc/homeproxy/scripts/generate_client.uc'
text = generator.read_text()
assert text.count("import { readfile, writefile } from 'fs';") == 1
text = text.replace("import { readfile, writefile } from 'fs';", "import { readfile, writefile, mkdir } from 'fs';")
text = text.replace("system('mkdir -p ' + RUN_DIR);", 'mkdir(RUN_DIR);')
assert text.count('\t\t\tserver: wan_dns,') == 1
text = text.replace('\t\t\tserver: wan_dns,', '''\t\t\tserver: (routing_mode === 'custom' && uci.get(uciconfig, ucimain, 'dns_routing') === 'chinadns')
\t\t\t\t? (validation('ip4addr', uci.get(uciconfig, ucimain, 'dns_china')) ? uci.get(uciconfig, ucimain, 'dns_china') : '119.29.29.29')
\t\t\t\t: wan_dns,''', 1)

# This is DomainResolveOptions, not a route action in sing-box 1.12.
text = text.replace("\t\taction: 'resolve',\n\t\tserver: get_resolver(default_outbound_dns)",
                    "\t\tserver: get_resolver(default_outbound_dns)")
start = text.index("\tuci.foreach(uciconfig, uciroutingrule, (cfg) => {")
end = text.index("\n\tconfig.route.final =", start)
block = text[start:end]
assert block.count('push(config.route.rules, {') == 1
block = block.replace("\tuci.foreach(uciconfig, uciroutingrule, (cfg) => {",
                      "\tconst add_routing_rule = (cfg) => {", 1)
block = block.replace("\t\tif (cfg.enabled !== '1')", "\t\tif (!cfg || cfg.enabled !== '1')", 1)
block = block.replace("\t\tpush(config.route.rules, {", "\t\tlet rule = {", 1)
assert block.endswith('\t});\n')
block = block[:-len('\t});\n')]
assert block.endswith('\t\t});\n')
block = block[:-len('\t\t});\n')] + '''\t\t};
\t\tappend_policy_rule(rule);
\t};
'''
helpers = '''
\tconst chinadns_policy = uci.get(uciconfig, ucimain, 'dns_routing') === 'chinadns';
\tconst user_rules = ['dns_block', 'dns_direct', 'dns_proxy'];
\tfunction append_policy_rule(rule) {
\t\t// Preserve the original match predicates. Reject only UDP/443 that
\t\t// would take this proxy route; earlier direct/reject rules still win.
\t\tif (chinadns_policy && rule.action === 'route' && rule.outbound &&
\t\t    rule.outbound !== 'direct-out' && rule.outbound !== 'block-out') {
\t\t\tlet matcher = {};
\t\t\tfor (let key in keys(rule))
\t\t\t\tif (!(key in ['action', 'outbound', 'override_address', 'override_port',
\t\t\t\t              'udp_disable_domain_unmapping', 'udp_connect', 'udp_timeout',
\t\t\t\t              'tls_fragment', 'tls_fragment_fallback_delay', 'tls_record_fragment']))
\t\t\t\t\tmatcher[key] = rule[key];
\t\t\tif (!length(filter(keys(matcher), (key) => key !== 'invert' && matcher[key] !== null))) {
\t\t\t\tpush(config.route.rules, {network: 'udp', port: [443], action: 'reject', method: 'default'});
\t\t\t\tpush(config.route.rules, rule);
\t\t\t\treturn;
\t\t\t}
\t\t\tpush(config.route.rules, {
\t\t\t\ttype: 'logical', mode: 'and',
\t\t\t\trules: [matcher, {network: 'udp', port: [443]}],
\t\t\t\taction: 'reject', method: 'default'
\t\t\t});
\t\t}
\t\tpush(config.route.rules, rule);
\t}
'''
ordered = '''
\t// Empty UI placeholders must never turn into unconditional routes.
\tfor (let name in user_rules) {
\t\tlet cfg = uci.get_all(uciconfig, name);
\t\tif (!cfg)
\t\t\tcontinue;
\t\tlet domains = type(cfg.domain) === 'array' ? cfg.domain : [cfg.domain || ''];
\t\tif (length(filter(domains, (domain) => length(trim(domain)))))
\t\t\tadd_routing_rule(cfg);
\t}
\tuci.foreach(uciconfig, uciroutingrule, (cfg) => {
\t\tif (!(cfg['.name'] in user_rules))
\t\t\tadd_routing_rule(cfg);
\t});
\tif (chinadns_policy && get_outbound(default_outbound) !== 'direct-out')
\t\tpush(config.route.rules, {network: 'udp', port: [443], action: 'reject', method: 'default'});
'''
text = text[:start] + helpers + block + ordered + text[end:]
generator.write_text(text)

init = package / 'root/etc/init.d/homeproxy'
source = init.read_text()
start = source.index('\t\t\t[ -s "/etc/chinadns-ng/user_block.txt" ]')
end = source.index('\t\t\t# 默认大表用 HomeProxy', start)
groups = source[start:end]
import re
parts = re.findall(r'\t\t\t\[ -s "/etc/chinadns-ng/user_(block|direct|proxy)\.txt" \] && \{\n.*?\t\t\t\}\n', groups, re.S)
assert len(parts) == 3
chunks = {name: re.search(r'\t\t\t\[ -s "/etc/chinadns-ng/user_' + name + r'\.txt" \] && \{\n.*?\t\t\t\}\n', groups, re.S)[0] for name in parts}
chunks['proxy'] = chunks['proxy'].replace('\t\t\t}\n', '''\t\t\t\tcase "$_cdng_nipv6" in
\t\t\t\t\t*tag:gfw*) _cdng_args="$_cdng_args -N tag:proxylist" ;;
\t\t\t\tesac
\t\t\t}\n''')
# ChinaDNS loads later-declared groups first: block > direct > proxy.
source = source[:start] + ''.join(chunks[name] for name in ['proxy', 'direct', 'block']) + source[end:]
old = '\t\t\t[ -f "$HP_DIR/resources/china_list.txt" ] && _cdng_args="$_cdng_args -m $HP_DIR/resources/china_list.txt -M -a"\n\t\t\t[ -f "$HP_DIR/resources/gfw_list.txt" ] && _cdng_args="$_cdng_args -g $HP_DIR/resources/gfw_list.txt"'
new = '''\t\t\t_cdng_args="$_cdng_args -m $RUN_DIR/china_list.filtered -g $RUN_DIR/gfw_list.filtered"
\t\t\t# Do not expand the static China CIDR database with learned CDN IPs.
'''.rstrip()
assert source.count(old) == 1
source = source.replace(old, new, 1)
# Do not restore answers classified under an older rule set after a restart.
source = source.replace('--cache $_cdng_cache --cache-db /var/run/chinadns-ng.cache', '--cache $_cdng_cache')
marker = '\t\t\tgen_chinadns_lists\n'
assert source.count(marker) == 1
source = source.replace(marker, '\t\t\tgen_chinadns_lists || return 1\n', 1)
marker = '\t_ipset_load chnroute6 "$HP_DIR/resources/china_ip6.txt"\n'
assert source.count(marker) == 1
source = source.replace(marker, marker + '''
\t# User suffix overrides beat built-in child exceptions. GFW suffixes also
\t# exclude domestic child entries (e.g. Chrome update endpoints marked @cn).
\t[ -s "$HP_DIR/resources/china_list.txt" ] && [ -s "$HP_DIR/resources/gfw_list.txt" ] || return 1
\tcat "$_block" "$_direct" "$_proxy" > "$RUN_DIR/user_overrides.txt"
\t_filter_domains() {
\t\tawk 'FILENAME == ARGV[1] { deny[$0]=1; next }
\t\t{ d=$0; reject=0; while (d != "") {
\t\t    if (d in deny) { reject=1; break }
\t\t    if (d !~ /\\./) break
\t\t    sub(/^[^.]*\\./, "", d)
\t\t  } if (!reject && length($0)) print $0 }' "$1" "$2"
\t}
\t_filter_domains "$RUN_DIR/user_overrides.txt" "$HP_DIR/resources/gfw_list.txt" > "$RUN_DIR/gfw_list.filtered"
\tcat "$RUN_DIR/user_overrides.txt" "$HP_DIR/resources/gfw_list.txt" > "$RUN_DIR/china_exclusions.txt"
\t_filter_domains "$RUN_DIR/china_exclusions.txt" "$HP_DIR/resources/china_list.txt" > "$RUN_DIR/china_list.filtered"
''', 1)
source = source.replace('[ -s "$_src" ] || return 0', '[ -s "$_src" ] || return 1')
source = source.replace('| ipset restore -exist 2>/dev/null', '| ipset restore -exist 2>/dev/null || return 1')
source = source.replace('_ipset_load chnroute "$HP_DIR/resources/china_ip4.txt"', '_ipset_load chnroute "$HP_DIR/resources/china_ip4.txt" || return 1')
source = source.replace('_ipset_load chnroute6 "$HP_DIR/resources/china_ip6.txt"', '_ipset_load chnroute6 "$HP_DIR/resources/china_ip6.txt" || return 1')
source = source.replace('"tag:gfw"', '"tag:gfw,tag:none@ip:non_china"')
# Native mode must remove the UCI upstream left by an earlier ChinaDNS run.
source, count = re.subn(r'\t\telse\n(?:\n|\t\t# DNSMasq rules\n)*(?=\t\tlocal ipv6_support dns_port)', '''\t\telse
\t\t\tlocal _old_cdng_port
\t\t\tconfig_get _old_cdng_port config dns_chinadns_port 5353
\t\t\tuci -q del_list "dhcp.@dnsmasq[0].server=127.0.0.1#$_old_cdng_port"
\t\t\tuci -q commit dhcp
''', source, count=1)
assert count == 1
init.write_text(source)

# Build defaults have one definition per named UCI section. Preserve the
# template's last definition instead of appending duplicate named sections.
config = package / 'root/etc/config/homeproxy'
source = config.read_text()
sections = re.split(r'(?=^config )', source, flags=re.M)
last = {}
for index, section in enumerate(sections):
    name = re.match(r"config homeproxy '([^']+)'", section)
    if name:
        last[name[1]] = index
kept = []
for index, section in enumerate(sections):
    name = re.match(r"config homeproxy '([^']+)'", section)
    if not name or last[name[1]] == index:
        kept.append(section)
defaults = ''.join(kept).replace("option dns_chinadns_no_ipv6 'tag:gfw'", "option dns_chinadns_no_ipv6 'tag:gfw,tag:none@ip:non_china'")
config.write_text(defaults)
print('HomeProxy selected-package policy integration complete')
