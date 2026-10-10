-- =====================================================================
-- Lib: VOE (JSON ofuscado: rot13 + patrones + base64 + shift + reverse +
--      base64)
-- Loaded via require_lib("voe"); uses require_lib("urls") and the engine
-- base64_decode. rot13 stays local on purpose (decision m4): voe is the
-- only consumer inside this file.
-- decodeJson() is the same pipeline as the inline voeDecrypt that used
-- to live in ar/anime4up.lua (merged: rot13 -> strip the literals ->
-- drop "_" -> base64 -> shift -3 -> reverse -> base64 -> JSON, both
-- verified equivalent).
--
-- Two entry points, kept apart because the callers want different things:
--   * extractVoe(embedUrl, body) -> (url, mime, ref) — single best URL,
--     the contract of libs/hosters/embeds.lua (es/latanime): domain hop
--     with the embed Referer, taken only when the page has no payload
--     yet, then source/direct_access_url, then the legacy base64
--     'hls'/'mp4' fields.
--   * extractSources(embedUrl, body) -> list | nil, reason — the full
--     player payload (ar/anime4up): hop with a desktop Chrome UA (the
--     mirror signs its tokens under the request UA, see BROWSER_UA
--     below), subtitles collected, both the source and the direct mp4
--     kept.
-- =====================================================================
local version = "1.3.0"

local urls = require_lib("urls")

local M = {}

-- Timeout para peticiones a embebedores (voe hop)
local EMBED_TIMEOUT = 12000

-- VOE mirrors sign the tokens under the User-Agent of the request: the
-- default runtime UA (mobile Chrome on Android) gets i=0.1 -> the CDN
-- answers 403, a desktop Chrome gets a working signature (live
-- 2026-10-02, mint×fetch matrix). The UA on the CDN response itself does
-- not matter — 200 with any/no UA.
local BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    .. "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

local function rot13(s)
    return (s:gsub("%a", function(c)
        local b = c:byte()
        local base = b >= 97 and 97 or 65
        return string.char((b - base + 13) % 26 + base)
    end))
end

local function plainRemove(s, pat)
    local out, i = {}, 1
    while true do
        local a, b = s:find(pat, i, true)
        if not a then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, a - 1)
        i = b + 1
    end
    return table.concat(out)
end

local function voeDecode(enc)
    local s = rot13(enc)
    for _, p in ipairs({ "@$", "^^", "~@", "%?", "*~", "!!", "#&" }) do
        s = plainRemove(s, p)
    end
    s = s:gsub("_", "")
    s = base64_decode(s)
    if type(s) ~= "string" then return nil end
    local shifted = {}
    for i = 1, #s do shifted[i] = string.char((s:byte(i) - 3) % 256) end
    s = table.concat(shifted):reverse()
    s = base64_decode(s)
    if type(s) ~= "string" then return nil end
    return json_parse(s)
end

-- Obfuscated payload -> table ({source, direct_access_url, captions}).
-- May throw on malformed JSON — callers wrap it in pcall (as extractVoe
-- does below).
M.decodeJson = voeDecode

-- The embed page only redirects to the mirror that serves the payload.
-- ua = nil -> hop with the embed Referer; ua = <desktop UA> -> hop with
-- that User-Agent only (mirror signature). Returns body + the URL the
-- body came from.
local function hop(body, embedUrl, ua)
    local target = body:match("window%.location%.href%s*=%s*'([^']+)'")
        or body:match('window%.location%.href%s*=%s*"([^"]+)"')
    if not target or target == "" then return body, embedUrl end
    if not target:find("^https?://") then target = urls.resolve(target, embedUrl) end
    local headers = ua and { ["User-Agent"] = ua } or { ["Referer"] = embedUrl }
    local r = http_get(target, { timeout = EMBED_TIMEOUT, headers = headers })
    if r.success then return r.body, target end
    return body, embedUrl
end

-- Embedded JSON script -> the obfuscated string inside ["…"], or nil.
local function payloadEncode(body)
    local payload = body:match('<script[^>]-type="application/json"[^>]*>(.-)</script>')
        or body:match("<script[^>]-type='application/json'[^>]*>(.-)</script>")
    if not payload then return nil end
    return payload:match('^%s*%["(.-)"%]%s*$') or payload:match('^%s*"(.-)"%s*$')
        or payload:match('%["(.*)"]')
end

-- captions[] -> { {url=…, label=…} } (the file key is the only one the
-- player reads; label is optional in the payload).
local function captionsOf(data)
    local subs = {}
    if type(data.captions) == "table" then
        for _, c in ipairs(data.captions) do
            if type(c) == "table" and type(c.file) == "string" and c.file ~= "" then
                subs[#subs + 1] = {
                    url   = c.file,
                    label = type(c.label) == "string" and c.label or "Subtitle",
                }
            end
        end
    end
    return subs
end

function M.extractVoe(embedUrl, body)
    -- salto de dominio: la pagina inicial solo redirige
    if not body:find("application/json", 1, true) and not body:find("hls", 1, true) then
        body, embedUrl = hop(body, embedUrl, nil)
    end

    local ref = urls.origin(embedUrl)

    -- Formato nuevo
    local enc = payloadEncode(body)
    if enc then
        local ok, data = pcall(voeDecode, enc)
        if ok and type(data) == "table" then
            local u = data.source or data.direct_access_url
            if type(u) == "string" and u ~= "" then
                return u, (u:lower():find(".m3u8", 1, true) and "hls" or "mp4"), ref
            end
        end
    end

    -- Formato antiguo: 'hls': 'BASE64' / 'mp4': 'BASE64'
    local h = body:match("['\"]hls['\"]%s*:%s*['\"]([A-Za-z0-9+/=_%-]+)['\"]")
    if h then
        -- engine base64_decode returns nil on url-safe/invalid input
        local u = base64_decode(h)
        if u and u:find("^https?://") then return u, "hls", ref end
    end
    local m = body:match("['\"]mp4['\"]%s*:%s*['\"]([A-Za-z0-9+/=_%-]+)['\"]")
    if m then
        local u = base64_decode(m)
        if u and u:find("^https?://") then return u, "mp4", ref end
    end
    return nil
end

-- Embed body -> list of { url, subtitles, direct } (source first, then
-- the direct mp4), or nil + reason ("no player payload on the mirror" |
-- "payload not decrypted" | "no source/direct_access_url in payload").
-- direct = true marks the progressive mp4 so the caller can label it.
-- No mime here: both URLs carry their own media extension, the caller
-- keeps the original behaviour of guessing nothing.
function M.extractSources(embedUrl, body)
    if type(body) ~= "string" or body == "" then return nil, "no embed body" end
    body = hop(body, embedUrl, BROWSER_UA)
    local enc = payloadEncode(body)
    if not enc then return nil, "no player payload on the mirror" end
    local ok, data = pcall(voeDecode, enc)
    if not ok or type(data) ~= "table" then return nil, "payload not decrypted" end
    local subs = captionsOf(data)
    local out = {}
    local src = data.source
    if type(src) == "string" and src ~= "" then
        out[#out + 1] = { url = src, subtitles = subs }
    end
    local mp4 = data.direct_access_url
    if type(mp4) == "string" and mp4 ~= "" then
        out[#out + 1] = { url = mp4, subtitles = subs, direct = true }
    end
    if #out == 0 then return nil, "no source/direct_access_url in payload" end
    return out
end

return M
