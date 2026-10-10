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

-- GET /pass_md5/... from one origin; nil unless the answer is an http(s) URL.
-- The old dood host answers its OWN pass endpoint with an empty 200 after it
-- started redirecting the embed page to the new domain, so "empty" must be
-- treated as failure, not as a valid start string.
local function fetchPass(origin, md5, embedUrl)
    local r = http_get(origin:sub(1, -2) .. md5, { timeout = EMBED_TIMEOUT, headers = { ["Referer"] = embedUrl } })
    if not r.success then return nil end
    local start = r.body:gsub("%s+$", ""):gsub("^%s+", "")
    if not start:find("^https?://") then return nil end
    return start
end

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
    local origin = urls.origin(embedUrl)
    if not origin then return nil end
    local token = md5:match("([^/]+)$")

    local start = fetchPass(origin, md5, embedUrl)
    if not start then
        -- Dood clones rotate domains: the old host still serves the embed
        -- page chain (301) but answers its own /pass_md5/ with an empty 200.
        -- Retry from the origin the embed page actually redirects to
        -- (verified live 2026-10-10: doodstream.com/e/ -> playmogo.com/e/).
        local r = http_get(embedUrl, { timeout = EMBED_TIMEOUT, followRedirects = false })
        local loc = r.headers and r.headers.location and r.headers.location[1]
        if loc then
            local origin2 = urls.origin(urls.resolve(loc, embedUrl))
            if origin2 and origin2 ~= origin then
                start = fetchPass(origin2, md5, embedUrl)
                if start then origin = origin2 end
            end
        end
    end
    if not start then return nil end

    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd) .. "?token=" .. tostring(token) .. "&expiry=" .. tostring(os_time())
    return url, "mp4", origin
end

return M
