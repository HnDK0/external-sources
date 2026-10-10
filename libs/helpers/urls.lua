-- =====================================================================
-- Lib: shared URL helpers (origin, unescapeSlashes, hostOf, resolve,
--      driveDirectUrl) for videohost extractors.
-- Loaded via require_lib("urls"). No dependencies on other libs.
-- =====================================================================
local version = "1.1.0"

local M = {}

-- =====================================================================
-- URL helpers
-- =====================================================================

function M.origin(url)
    local scheme, host = url:match("^(https?)://([^/?#]+)")
    if not scheme then return nil end
    return scheme .. "://" .. host .. "/"
end

function M.unescapeSlashes(s)
    local r = s:gsub("\\/", "/")
    r = r:gsub("\\u0026", "&")
    return r
end

function M.hostOf(url)
    return ((url or ""):match("^https?://([^/?#:]+)") or ""):lower()
end

-- Relative / protocol-relative URL -> absolute (relative to the embed).
function M.resolve(u, embedUrl)
    u = M.unescapeSlashes(u)
    if u:sub(1, 2) == "//" then return "https:" .. u end
    if u:find("^https?://") then return u end
    local o = M.origin(embedUrl or "")
    if o then
        o = o:gsub("/$", "")
        return o .. (u:sub(1, 1) == "/" and u or ("/" .. u))
    end
    return u
end

-- Google Drive file page -> direct usercontent download URL, no network:
-- the file id lives in the link itself (checked live 2026-10-03, usercontent
-- with confirm=t answers 206 without a single header).
-- Merged from the four inline copies: ar/anime4up.lua:813, ar/witanime.lua:1423,
-- ar/animephoenix.lua:698, es/latanime.lua:280 — all equivalent; the union keeps
-- the nil-safe host match (anime4up dereferenced match() without `or ""`).
-- ponytail: no playback-API fallback for "download disabled" (403 + UA binding) —
-- add it when locked links actually show up on the sites.
function M.driveDirectUrl(link)
    if type(link) ~= "string" then return nil end
    local host = (link:match("^https?://([^/]+)") or ""):lower()
    host = host:gsub("^www%.", "")
    if host ~= "drive.google.com" and host ~= "drive.usercontent.google.com" then
        return nil
    end
    local id = link:match("/file/d/([%w_-]+)") or link:match("[?&]id=([%w_-]+)")
    if not id then return nil end
    local u = "https://drive.usercontent.google.com/download?id=" .. id
        .. "&export=download&confirm=t"
    local rk = link:match("[?&]resourcekey=([%w_-]+)")
    if rk then u = u .. "&resourcekey=" .. rk end
    return u
end

return M
