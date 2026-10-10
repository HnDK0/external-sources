-- =====================================================================
-- Lib: share4max — Inertia page -> partial XHR (files/mirror/video) ->
--      props.streams.
-- Merged from ar/anime4up.lua:791-852 (share4maxVersion,
-- resolveShare4max).
-- UNVERIFIED: no live file link could be obtained 2026-10-05 (the home
-- page lists nothing, robots.txt = Disallow: /, every guessed path is
-- 404) — the scheme comes from the reference (Animerco.kt /
-- Share4maxInertiaResponse).
-- Loaded via require_lib("share4max"); uses require_lib("urls") and
-- require_lib("hls").
--
-- The embed page body is passed in (ar/anime4up gets it from its batch);
-- when it carries no Inertia version the page is re-fetched here. The
-- partial request (X-Inertia headers, 10s timeout) stays here too.
--
-- The version lives in <script data-page="app" type="application/json">:
-- {"component":…,"props":{…},"version":"a601a2d0…"} (checked live on
-- share4max.com 2026-10-05).
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")
local hls  = require_lib("hls")

local M = {}

-- Page body -> Inertia version, or nil.
function M.version(body)
    if type(body) ~= "string" then return nil end
    local payload = body:match('data%-page="app"[^>]*>(.-)</script>')
    if not payload then return nil end
    return payload:match('"version":"([^"]+)"')
end

-- Embed body + embed link -> list of { url, quality, direct }, or nil +
-- reason ("Inertia version not found" | "partial HTTP <code>" |
-- "no props.streams in partial response" | "empty props.streams").
-- direct = true: the URL is already a media file (push it as a
-- candidate); otherwise it is a mirror player page that has to be
-- fetched and dispatched again.
function M.resolve(body, link)
    local ver = M.version(body)
    if not ver then
        local r = http_get(link, { timeout = 10000 })
        ver = r.success and M.version(r.body) or nil
    end
    if not ver then return nil, "Inertia version not found" end
    local r = http_get(link, {
        headers = {
            ["X-Inertia"] = "true",
            ["X-Requested-With"] = "XMLHttpRequest",
            ["X-Inertia-Version"] = ver,
            ["X-Inertia-Partial-Component"] = "files/mirror/video",
            ["X-Inertia-Partial-Data"] = "streams",
            ["Referer"] = link,
        },
        timeout = 10000,
    })
    if not r.success then return nil, "partial HTTP " .. tostring(r.code) end
    local ok, data = pcall(json_parse, r.body)
    local props = ok and type(data) == "table" and data.props or nil
    local streams = type(props) == "table" and props.streams or nil
    if type(streams) ~= "table" then
        return nil, "no props.streams in partial response"
    end
    local out = {}
    for _, s in ipairs(streams) do
        if type(s) == "table" then
            local u = type(s.url) == "string" and s.url
                or (type(s.src) == "string" and s.src)
                or (type(s.link) == "string" and s.link) or nil
            if u and u ~= "" then
                local name = type(s.name) == "string" and s.name
                    or (type(s.server) == "string" and s.server) or nil
                out[#out + 1] = {
                    url     = urls.resolve(u, link),
                    quality = name and ("share4max · " .. name) or "share4max",
                    direct  = hls.hasMediaExt(u) and true or false,
                }
            end
        end
    end
    if #out == 0 then return nil, "empty props.streams" end
    return out
end

return M
