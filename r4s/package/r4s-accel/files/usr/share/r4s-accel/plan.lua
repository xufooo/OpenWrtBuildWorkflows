-- SPDX-License-Identifier: MIT
local cursor = require("uci").cursor()
local policy = dofile("/usr/share/r4s-accel/policy.lua")
local settings = cursor:get_all("r4s_accel", "main") or {}
local global = {}
cursor:foreach("passwall", "global", function(s) global = s end)
local acls, sqm, broad, fullcone = {}, false, false, false
cursor:foreach("passwall", "acl_rule", function(s) acls[#acls + 1] = s end)
cursor:foreach("sqm", "queue", function(s) if s.enabled == "1" then sqm = true end end)
cursor:foreach("firewall", "defaults", function(s)
    broad = s.flow_offloading == "1" or s.flow_offloading_hw == "1"
    fullcone = s.fullcone4 == "1"
end)
local function exists(path)
    local file = io.open(path)
    if not file then return false end
    file:close()
    return true
end
local hosts, reason = policy.plan({
    settings = settings, acls = acls, sqm = sqm, broad_offload = broad,
    fullcone = fullcone,
    other_policy = exists("/etc/config/pbr") or exists("/etc/config/mwan3"),
    passwall_active = global.enabled == "1" or global.acl_enable == "1" or os.getenv("R4S_PSW_READY") == "1",
    passwall_ready = os.getenv("R4S_PSW_READY") == "1",
    acl_enabled = global.acl_enable == "1"
})
io.stderr:write(reason, "\n")
for _, host in ipairs(hosts) do print(host) end
