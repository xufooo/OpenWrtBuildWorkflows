-- SPDX-License-Identifier: MIT
local M = {}

function M.ipv4(value)
    if type(value) ~= "string" then return false end
    local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end
    for _, part in ipairs({a, b, c, d}) do
        if #part > 1 and part:sub(1, 1) == "0" then return false end
        if tonumber(part) > 255 then return false end
    end
    return tonumber(a) > 0 and tonumber(a) < 224 and tonumber(a) ~= 127
end

local function list(value)
    if type(value) == "table" then return value end
    local out = {}
    for item in (value or ""):gmatch("%S+") do out[#out + 1] = item end
    return out
end

function M.plan(s)
    if s.settings.enabled ~= "1" then return {}, "Disabled" end
    if s.broad_offload then return {}, "Disable the standard broad flow-offloading switch" end
    if s.sqm then return {}, "SQM enabled: normal forwarding retained" end
    if s.other_policy then return {}, "Additional routing policy: normal forwarding retained" end
    local requested, seen = {}, {}
    for _, host in ipairs(list(s.settings.hosts)) do
        if not M.ipv4(host) then return {}, "Only individual IPv4 host addresses are supported" end
        if not seen[host] then requested[#requested + 1], seen[host] = host, true end
    end
    if #requested == 0 then return {}, "No direct hosts selected" end
    local allowed = {}
    if s.passwall_active then
        if not s.passwall_ready or not s.acl_enabled then
            return {}, "PassWall direct ACL is not ready"
        end
        -- Fail closed rather than approximate overlapping MAC, range, set or
        -- interface ACLs, or rely on undocumented ACL ordering.
        for _, acl in ipairs(s.acls) do
            if acl.enabled == "1" then
                if acl.mode ~= "0" or (acl.interface or "") ~= "" then
                    return {}, "Mixed or interface PassWall ACLs require normal forwarding"
                end
                local sources = list(acl.sources)
                if #sources == 0 then return {}, "Wildcard PassWall ACL requires normal forwarding" end
                for _, host in ipairs(sources) do
                    if not M.ipv4(host) then return {}, "Complex PassWall ACL requires normal forwarding" end
                    allowed[host] = true
                end
            end
        end
    end
    local hosts = {}
    for _, host in ipairs(requested) do
        if not s.passwall_active or allowed[host] then hosts[#hosts + 1] = host end
    end
    if #hosts == 0 then return {}, "No selected host has an explicit no-proxy ACL" end
    table.sort(hosts)
    return hosts, s.fullcone and "TCP admission ready; FullCone UDP stays on normal path" or "TCP/UDP admission ready"
end

return M
