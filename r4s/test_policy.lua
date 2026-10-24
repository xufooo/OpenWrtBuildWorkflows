local policy = dofile(arg[1] .. "/package/r4s-accel/files/usr/share/r4s-accel/policy.lua")
local count = 0
local function fixture()
    return {
        settings = {enabled = "1", hosts = {"192.0.2.2"}},
        acls = {{enabled = "1", mode = "0", sources = {"192.0.2.2"}}},
        passwall_active = true, passwall_ready = true, acl_enabled = true
    }
end
local function check(change, expected, reason)
    local state = fixture()
    change(state)
    local hosts, status = policy.plan(state)
    assert(#hosts == expected, status)
    if reason then assert(status:find(reason, 1, true), status) end
    count = count + 1
end
check(function() end, 1)
check(function(s) s.settings.enabled = "0" end, 0, "Disabled")
check(function(s) s.settings.hosts = {} end, 0, "No direct")
check(function(s) s.settings.hosts = {"192.0.2.3"} end, 0, "explicit no-proxy")
check(function(s) s.settings.hosts = {"192.0.2.2", "192.0.2.2"} end, 1)
check(function(s) s.settings.hosts = {"192.0.2.2; accept"} end, 0, "individual IPv4")
check(function(s) s.settings.hosts = {"192.0.2.0/24"} end, 0)
check(function(s) s.settings.hosts = {"2001:db8::2"} end, 0)
check(function(s) s.broad_offload = true end, 0, "standard broad")
check(function(s) s.sqm = true end, 0, "SQM")
check(function(s) s.other_policy = true end, 0, "Additional routing")
check(function(s) s.passwall_ready = false end, 0, "not ready")
check(function(s) s.acl_enabled = false end, 0)
check(function(s) s.acls[1].mode = "1" end, 0, "Mixed")
check(function(s) s.acls[1].interface = "lan" end, 0, "interface")
check(function(s) s.acls[1].sources = {} end, 0, "Wildcard")
check(function(s) s.acls[1].sources = {"AA:BB:CC:DD:EE:FF"} end, 0, "Complex")
check(function(s) s.acls[2] = {enabled = "1", mode = "1"} end, 0, "Mixed")
check(function(s) s.acls[2] = {enabled = "0", mode = "1"} end, 1)
check(function(s) s.passwall_active = false end, 1)
check(function(s) s.fullcone = true end, 1, "UDP stays on normal path")
for _, bad in ipairs({"", "127.0.0.1", "0.0.0.0", "224.0.0.1", "256.1.2.3", "01.2.3.4"}) do
    assert(not policy.ipv4(bad))
end
print(count .. " admission policy checks passed (no network performance claim)")
