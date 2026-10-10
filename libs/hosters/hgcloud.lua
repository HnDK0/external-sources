-- =====================================================================
-- Lib: hgcloud — /e/<id> page -> packed config on a mirror -> stream URLs.
-- Merged from two copies: ar/anime4up.lua:1084-1150 (HGCLOUD_MIRRORS,
-- hgcloudMediaUrls, resolveHgcloud) and ar/witanime.lua:1538-1616 (the
-- same three, plus its own first attempt of the gate link). The body
-- parsing and the mirror walk were equivalent.
-- Loaded via require_lib("hgcloud"). Uses engine API unpack_packed
-- ("" when there is no packer).
--
-- HTTP stays with the caller through a fetch(url, referer) callback
-- returning (body, code): ar/anime4up gets the first body from its batch
-- (no Referer), ar/witanime fetches the gate link with the episode
-- Referer — the callback keeps both call sites intact.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Mirrors of the hgcloud.to rotator (main.js, observation 2026-10-06);
-- if they stop serving the config, refresh from the rotator's main.js.
local MIRRORS = { "hanerix.com", "vibuxer.com", "audinifer.com" }

M.mirrors = MIRRORS

-- Links from the player config: unpacked text + original body. The config
-- sits in links = {hls2:…, hls3:…} while the setup reads
-- file: links.hls4||links.hls3||links.hls2, so a bare file:"…" never
-- matches — hence the own URL scan below.
function M.mediaUrls(body)
    if type(body) ~= "string" then return {} end
    local text = body
    local un = unpack_packed(body)
    if un ~= "" then text = un .. "\n" .. body end
    local out, seen = {}, {}
    local function add(u)
        if seen[u] then return end
        seen[u] = true
        out[#out + 1] = u:gsub("\\/", "/"):gsub("&amp;", "&")
    end
    -- Order = priority: the first candidate is master.txt (hls3 out of hls4||hls3).
    for u in text:gmatch([[https?://[^"'%s<>\\]+master%.txt[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+master%.m3u8[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.m3u8[^"'%s<>\\]*]]) do add(u) end
    return out
end

-- Stub page? The embed path (/e/<id>) is taken from the original URL.
local function embedPath(body, link)
    if type(body) ~= "string" or type(link) ~= "string" then return nil end
    if not body:find("/main.js", 1, true) then return nil end
    return link:match("^https?://[^/]+(/[^?#]*)")
end

-- body/link — the page already in hand; fetch — the mirror walk (and only
-- that: no HTTP happens here). Returns urls, finalRef, tried, path.
-- finalRef = the page the config was taken from: without it master.txt and
-- the segments answer 404 (live 2026-10-06). tried = "code url" per mirror,
-- path = embed path or nil when the input page has neither config nor
-- main.js (the caller reports that case with its own wording).
function M.resolve(body, link, fetch)
    local urls = M.mediaUrls(body)
    local finalRef = link
    local tried = {}
    local path = embedPath(body, link)
    if not path then return urls, finalRef, tried, path end
    for i = 1, #MIRRORS do
        if #urls > 0 then break end
        local mirror = MIRRORS[i]
        local ref = "https://" .. mirror .. "/"
        local url = "https://" .. mirror .. path
        local b, code = fetch(url, ref)
        tried[#tried + 1] = tostring(code) .. " " .. url
        local mu = M.mediaUrls(b)
        if #mu > 0 then urls, finalRef = mu, ref end
    end
    return urls, finalRef, tried, path
end

return M
