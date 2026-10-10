-- =====================================================================
-- Lib: Doodstream y clones (dsvplay, dood.*)
-- Loaded via require_lib("dood"); uses require_lib("urls").
-- =====================================================================
local version = "1.1.0"

local urls = require_lib("urls")

local M = {}

-- Timeout para peticiones a embebedores (dood pass_md5); the inline copies
-- used 8000-10000 ms, the shared lib keeps the conservative 12000 ms.
local EMBED_TIMEOUT = 12000

local RANDOM_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

-- Merged from the four inline copies of resolveDood (ar/anime4up.lua:1377,
-- ar/witanime.lua:1188, id/anichin.lua:656, id/animexin.lua:642) and the
-- former extractDood — the bodies were equivalent; fetching the embed page
-- itself (witanime) belongs to the caller, as does logging (the copies
-- reported "RELOAD"/HTTP status with their own prefixes).
-- Returns url, "mp4", origin of the embed (referer of the final stream),
-- or nil when there is no /pass_md5 (captcha variant) or the round trip
-- failed.
function M.resolveDood(embedUrl, body)
    if type(body) ~= "string" then return nil end
    local md5 = body:match("(/pass_md5/[^'\"]+)")
    if not md5 then return nil end
    local o = urls.origin(embedUrl)
    if not o then return nil end
    local token = md5:match("([^/]+)$")
    local r = http_get(o:sub(1, -2) .. md5, { timeout = EMBED_TIMEOUT, headers = { ["Referer"] = embedUrl } })
    if not r.success then return nil end
    local start = r.body:gsub("%s+$", ""):gsub("^%s+", "")
    if not start:find("^https?://") then return nil end

    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd) .. "?token=" .. tostring(token) .. "&expiry=" .. tostring(os_time())
    return url, "mp4", o
end

return M
