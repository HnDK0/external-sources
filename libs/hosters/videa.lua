-- =====================================================================
-- Lib: videa.hu (obfuscated _xt -> XML, often RC4 + base64 -> sources
--      with md5/expires).
-- Merged from two copies: ar/anime4up.lua:699-807 (videaToken, inline
-- random, resolveVidea) and ar/witanime.lua:1002-1129 (videaToken,
-- videaRandom8, resolveVidea). The token code was byte-identical; the
-- randomizer differs only in shape (inline table vs helper) and is
-- unified in random8().
-- Loaded via require_lib("videa"). No dependencies on other libs.
--
-- The HTTP stays with the caller (both copies build their own request:
-- different Referer source, different timeout), so the lib is split in
-- two pure steps: request() before the fetch, parse() after it.
-- =====================================================================
local version = "1.0.0"

local M = {}

local VIDEA_O = "xHb0ZvME5q8CBcoQi6AngerDu3FGO9fkUlwPmLVY_RTzj2hJIS4NasXWKy1td7p"
local VIDEA_R = { "e", "a", "g", "j", "d", "c", "h", "i", "b", "f" }
local VIDEA_RR = { "f", "h", "c", "b", "i" }

local function headerValue(headers, name)
    local v = headers and (headers[name] or headers[string.lower(name)])
    if type(v) == "table" then return v[1] end
    if type(v) == "string" then return v end
    return nil
end

-- _xt -> { t, k }: t goes into the XML request, k is the RC4 key of the
-- answer. Both halves must be assembled completely, otherwise the token
-- is wrong (returns nil).
local function token(xt)
    local c = {}
    for i = 1, #xt do
        local i0 = i - 1
        local k = VIDEA_R[math.floor(i0 / 8) + 2]
        if not k then return nil end
        if i0 % 8 == 0 then c[k] = "" end
        c[k] = (c[k] or "") .. xt:sub(i, i)
    end
    local d = (c.a or "") .. (c.g or "") .. (c.j or "") .. (c.d or "")
    local u = (c.c or "") .. (c.h or "") .. (c.i or "") .. (c.b or "")
    if d == "" or u == "" then return nil end
    local m = {}
    for i = 1, #d do
        local oi = VIDEA_O:find(d:sub(i, i), 1, true)
        if not oi then return nil end
        -- oi is 1-based while the reference formula is 0-based:
        -- i - (oi0 - 31) + 1
        local at = i - (oi - 32)
        if at < 1 or at > #u then return nil end
        m[i] = u:sub(at, at)
    end
    local mm = table.concat(m)
    c = {}
    for i = 1, #mm do
        local i0 = i - 1
        local k = VIDEA_RR[math.floor(i0 / 8) + 2]
        if k then
            if i0 % 8 == 0 then c[k] = "" end
            c[k] = (c[k] or "") .. mm:sub(i, i)
        end
    end
    c.f = ""
    return {
        t = (c.h or "") .. (c.c or ""),
        k = (c.b or "") .. (c.i or ""),
    }
end

-- The _s request parameter: 8 random [a-z0-9] chars, part of the RC4 key.
local function random8()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local out = {}
    for i = 1, 8 do
        local n = math.random(#chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

M.random8 = random8

-- Embed page -> descriptor for the XML request, or nil + reason.
-- Descriptor: { url, key, rnd } — caller does http_get(url), then hands
-- the descriptor and the response to parse().
function M.request(link, body)
    if type(link) ~= "string" or type(body) ~= "string" then
        return nil, "no videa link"
    end
    local vcode = link:match("[?&]v=([%w]+)")
    if not vcode then return nil, "no v= in link" end
    local xt = body:match('_xt%s*=%s*"([^"]+)"') or body:match("_xt%s*=%s*'([^']+)'")
    if not xt then return nil, "no _xt in page" end
    local parts = token(xt)
    if not parts then return nil, "cannot parse _xt" end
    local rnd = random8()
    return {
        url = "https://videa.hu/player/xml"
            .. "?v=" .. url_encode(vcode)
            .. "&_t=" .. url_encode(parts.t)
            .. "&_s=" .. url_encode(rnd)
            .. "&platform=desktop&lang=en&start=0",
        key = parts.k,
        rnd = rnd,
    }
end

-- XML response -> list of { url, name }, or nil + reason.
-- The answer is either text/xml or RC4(key .. rnd .. x-videa-xs) over
-- base64 bytes; the server may also answer with an <error> element.
function M.parse(req, resp)
    if type(req) ~= "table" or type(resp) ~= "table" then
        return nil, "no videa response"
    end
    local contentType = headerValue(resp.headers, "content-type") or ""
    local xml
    if contentType:sub(1, 7) == "text/xml" then
        xml = resp.body
    else
        local xs = headerValue(resp.headers, "x-videa-xs") or ""
        xml = rc4(req.key .. req.rnd .. xs, base64_decode_bytes(resp.body) or "")
    end
    if type(xml) ~= "string" then return nil, "cannot decode XML" end

    local err = xml:match("<error[^>]*>([^<]*)</error>")
    if err then return nil, err end

    local exp = xml:match('<video_sources[^>]*exp="(%d+)"')
        or xml:match('<video_source[^>]*exp="(%d+)"')
    if not exp then return nil, "no exp in XML" end

    -- No backreference in Lua patterns, so the pattern stops right after
    -- `</hash_value_`. The two copies differed on the trailing `>` (only
    -- witanime's shape matches `</hash_value_1>`); dropping it keeps both
    -- possible closing-tag shapes working.
    local hashes = {}
    for name, h in xml:gmatch("<hash_value_([^>]+)>([^<]+)</hash_value_") do
        hashes[name] = h
    end

    local out = {}
    for name, path in xml:gmatch('<video_source name="([^"]+)"[^>]*>([^<]+)</video_source>') do
        local md5 = hashes[name]
        if md5 then
            out[#out + 1] = {
                url = "https:" .. path .. "?md5=" .. md5 .. "&expires=" .. exp,
                name = name,
            }
        end
    end
    if #out == 0 then return nil, "no sources in XML" end
    return out
end

return M
