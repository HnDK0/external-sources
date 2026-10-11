-- =====================================================================
-- Lib: shared URL helpers (origin, unescapeSlashes, hostOf, resolve,
--      absUrl, driveDirectUrl) for videohost and novel extractors.
-- Loaded via require_lib("urls"). No dependencies on other libs.
-- =====================================================================
local version = "1.2.0"

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

-- RFC 3986 merge, mirroring java.net.URI(base):resolve(href) — the exact
-- semantics of the engine global url_resolve (plugin-tester-jvm
-- LuaEngineCli.kt:355). Used only when that global is unavailable
-- (offline tests); in the app the global always wins.
local function removeDotSegments(p)
    local leading = p:sub(1, 1) == "/"
    local segs = {}
    for seg in p:gmatch("[^/]+") do
        if seg == ".." then
            if #segs > 0 and segs[#segs] ~= ".." then
                segs[#segs] = nil
            elseif not leading then
                segs[#segs + 1] = seg
            end
        elseif seg ~= "." then
            segs[#segs + 1] = seg
        end
    end
    local out = table.concat(segs, "/")
    if leading then out = "/" .. out end
    if p:sub(-1) == "/" and out:sub(-1) ~= "/" then out = out .. "/" end
    return out
end

local function splitRef(u)
    local path, query, fragment = u, "", ""
    local hash = path:find("#", 1, true)
    if hash then fragment = path:sub(hash + 1) path = path:sub(1, hash - 1) end
    local qm = path:find("?", 1, true)
    if qm then query = path:sub(qm + 1) path = path:sub(1, qm - 1) end
    return path, query, fragment
end

local function resolveRef(base, ref)
    if type(base) ~= "string" or type(ref) ~= "string" then return ref end
    if ref:match("^%a[%w+.-]*:") then return ref end
    local scheme, authority, rest = base:match("^(%a[%w+.-]*)://([^/?#]*)(.*)$")
    if not scheme then return ref end
    if ref:sub(1, 2) == "//" then return scheme .. "://" .. ref:sub(3) end
    local rPath, rQuery, rFrag = splitRef(ref)
    local bPath, bQuery = splitRef(rest)
    local path, query
    if rPath == "" then
        path = bPath
        query = (rQuery ~= "") and rQuery or bQuery
    elseif rPath:sub(1, 1) == "/" then
        path = rPath
        query = rQuery
    else
        path = (bPath:match("^.*/") or "/") .. rPath
        query = rQuery
    end
    local out = scheme .. "://" .. authority .. removeDotSegments(path)
    if query ~= "" then out = out .. "?" .. query end
    if rFrag ~= "" then out = out .. "#" .. rFrag end
    return out
end

-- href found in a page -> absolute URL, relative to `base` (usually baseUrl).
-- Union of the two inline variants: the dominant url_resolve one (guide:1763,
-- 36 byte-identical copies, e.g. ru/ranobehub.lua:11) and the manual sub/find
-- one (es/latanime.lua:94, en/hianimes.lua:50, id/anichin.lua:70). They agree
-- on absolute / protocol-relative / root-relative hrefs; for a bare relative
-- href the canonical url_resolve merge (RFC 3986) is used, the manual copies
-- joined it as baseDir .. "/" .. href — plugins relying on that join must be
-- checked during migration. Empty or non-string href -> "" (guide template).
function M.absUrl(base, href)
    if type(href) ~= "string" or href == "" then return "" end
    if href:sub(1, 4) == "http" then return href end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if type(url_resolve) == "function" then return url_resolve(base, href) end
    return resolveRef(base, href)
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
