-- =====================================================================
-- Lib: vidyard — embed link -> play.vidyard.com/player/<id>.json ->
--      hls[] profiles.
-- Merged from ar/anime4up.lua:512-549 (VIDYARD_URL, resolveVidYard).
-- Loaded via require_lib("vidyard"). No dependencies on other libs.
--
-- The embed page is never read: the id comes from the link itself
-- (substringAfter("com/") + substringBefore("?")), the data lives in
-- player/<id>.json (reference VidYardExtractor.kt).
-- =====================================================================
local version = "1.0.0"

local VIDYARD_URL = "https://play.vidyard.com"

local M = {}

M.origin = VIDYARD_URL

-- Embed link -> list of { url, quality = <profile>, referer }, or nil +
-- reason ("no id in link" | "player HTTP <code>" |
-- "no hls[] in response" | "no sources in hls[]").
-- quality is the profile name from hls[] (the player's own ladder), not
-- the site's server label.
function M.resolve(link)
    local pos = type(link) == "string" and link:find("com/", 1, true) or nil
    local id = pos and link:sub(pos + 4):match("^[^?]*") or ""
    if id == "" then return nil, "no id in link" end
    local r = http_get(VIDYARD_URL .. "/player/" .. id .. ".json", {
        headers = { ["Referer"] = VIDYARD_URL },
    })
    if not r.success then return nil, "player HTTP " .. tostring(r.code) end
    -- substringAfter("hls\":[") -> substringBefore("]") -> split on
    -- `profile":"` (no Lua alternation needed — a single literal).
    local p = r.body:find('hls":[', 1, true)
    local data = p and r.body:sub(p + 6):match("^[^]]*") or nil
    if not data or data == "" then return nil, "no hls[] in response" end
    local out = {}
    for profile, src in data:gmatch('profile":"([^"]+)".-url":"([^"]+)"') do
        if src ~= "" then
            out[#out + 1] = { url = src, quality = profile, referer = VIDYARD_URL }
        end
    end
    if #out == 0 then return nil, "no sources in hls[]" end
    return out
end

return M
