-- =====================================================================
-- Lib: gdriveplayer resolver — embed2.php serves a page whose inline
--      script body is atob()'ed and XOR-encrypted with the key from
--      `var k="..."`; the decrypted JS carries a relative HLS path
--      HLS="hlsplaylist.php?s=…&idhls=….m3u8" — a media playlist with
--      direct segments on a third-party CDN.
-- From one copy: id/animexin.lua:568-617 (resolveGdriveplayer + bxor8).
-- Loaded via require_lib("gdriveplayer"). No dependencies on other libs.
--
-- Pure decode: the caller does the batch GET (Referer = embed origin);
-- logging stays with the caller. base64_decode is engine API («Тяжёлые
-- операции»); the XOR loop stays in Lua — it runs over one short script.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- XOR of two bytes, bit by bit (sandbox is Lua 5.1 — no bitwise ops).
local function bxor8(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local ab, bb = a % 2, b % 2
        if ab ~= bb then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

-- body — the embed2.php page; origin — "scheme://host/" of the embed
-- (used to absolutise a relative HLS path).
-- Returns a list of { url, mime = "hls" } or nil + reason:
-- "no key/atob in embed" | "atob did not decode" | "HLS= not found after decrypt".
function M.decode(body, origin)
    if type(body) ~= "string" then return nil, "no key/atob in embed" end
    local key = body:match('var k="([^"]+)"')
    local blob = body:match('atob%("([^"]+)"%)')
    if not key or not blob or #key == 0 then
        return nil, "no key/atob in embed"
    end
    local raw = base64_decode(blob)
    if type(raw) ~= "string" or raw == "" then
        return nil, "atob did not decode"
    end
    local chars = {}
    local klen = #key
    for i = 1, #raw do
        chars[i] = string.char(bxor8(raw:byte(i), key:byte((i - 1) % klen + 1)))
    end
    local decoded = table.concat(chars)
    local hls = decoded:match('HLS="([^"]+)"')
    if not hls then return nil, "HLS= not found after decrypt" end
    hls = hls:gsub("\\/", "/")
    if hls:sub(1, 2) == "//" then
        hls = "https:" .. hls
    elseif hls:sub(1, 1) == "/" then
        hls = origin .. hls
    else
        hls = origin .. "/" .. hls
    end
    return { { url = hls, mime = "hls" } }
end

return M
