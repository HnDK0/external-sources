-- =====================================================================
-- Lib: soraplay — embed sources:[{"file":…,"label":…}] plus the
--      yonaplay/mirror go_to_player player list.
-- Extracted from ar/witanime.lua:1119-1161 (resolveSoraplay); only the
-- body parsing lives here — HTTP and the recursive host dispatch (the
-- go_to_player targets go back into the plugin's resolveHostedLink) stay
-- with the caller.
-- Loaded via require_lib("soraplay"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- yonaplay/mirror pages carry a player list (extractFromMulti in the
-- reference: .OD li → go_to_player → the host dispatcher again).
function M.isMulti(link)
    if type(link) ~= "string" then return false end
    local low = link:lower()
    return low:find("/mirror", 1, true) ~= nil or low:find("yonaplay", 1, true) ~= nil
end

-- go_to_player('…') targets; protocol-relative ones get the https: prefix.
function M.parsePlayers(body)
    local out = {}
    if type(body) ~= "string" then return out end
    for u in body:gmatch("go_to_player%('([^']*)'%)") do
        if u ~= "" then
            local target = u
            if not string_starts_with(target, "https:") then target = "https:" .. target end
            out[#out + 1] = target
        end
    end
    return out
end

-- Embed body -> list of { url, label }, possibly empty (the reference
-- cuts by `"file":"` / `"label":"`, quoted keys — unlike vidbom).
function M.parseSources(body)
    local out = {}
    if type(body) ~= "string" then return out end
    local p = body:find("sources: [", 1, true)
    local rest = p and body:sub(p + 10) or nil
    local data = rest and (rest:match("^(.-)%],") or rest) or nil
    if not data then return out end
    for src, label in data:gmatch('"file":"([^"]+)".-"label":"([^"]*)"') do
        out[#out + 1] = { url = src, label = label }
    end
    return out
end

return M
