-- =====================================================================
-- Lib: seekplayer (StreamWish clone) — hex blob of /api/v1/video ->
--      AES-128-CBC -> JSON with the stream sources.
-- Merged from two copies: ar/anime4up.lua:1152-1284 (hexToBase64,
-- resolveSeekplayer) and id/animexin.lua:538-640 (hexToBase64,
-- resolveSeekplayer). The key/IV constants, hexToBase64 and the
-- streamingConfig ordering were identical; only the shape of the result
-- differed (candidates vs plain list) and is unified as a list.
-- Loaded via require_lib("seekplayer"). No dependencies on other libs.
--
-- Pure decode: the HTTP call (and the mandatory browser User-Agent —
-- the API answers 400 otherwise) stays with the caller; animexin gets
-- the body from its batch, ar/anime4up fetches it itself.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Key/IV from the player bundle (te()/oe() in index-*.js): fixed 16-byte
-- ASCII constants, they depend only on location.protocol and the presence
-- of a hash. aes_decrypt expects the ciphertext in base64, so hex is
-- converted by hexToBase64 — no binary string (bytes >= 0x80 break on
-- UTF-8 round-trip) is ever created.
local SP_KEY = "kiemtienmua911ca"
local SP_IV  = "1234567890oiuytr"
local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function hexToBase64(hex)
    local out, i, n = {}, 1, #hex
    while i + 5 <= n do
        local v = tonumber(hex:sub(i, i + 5), 16)
        local a = math.floor(v / 262144) % 64
        local b = math.floor(v / 4096) % 64
        local c = math.floor(v / 64) % 64
        local d = v % 64
        out[#out + 1] = B64_ALPHABET:sub(a + 1, a + 1)
            .. B64_ALPHABET:sub(b + 1, b + 1)
            .. B64_ALPHABET:sub(c + 1, c + 1)
            .. B64_ALPHABET:sub(d + 1, d + 1)
        i = i + 6
    end
    local rest = n - i + 1
    if rest == 2 then
        local v = tonumber(hex:sub(i), 16) * 16
        local a = math.floor(v / 64)
        out[#out + 1] = B64_ALPHABET:sub(a + 1, a + 1)
            .. B64_ALPHABET:sub(v % 64 + 1, v % 64 + 1) .. "=="
    elseif rest == 4 then
        local v = tonumber(hex:sub(i), 16) * 256
        local a = math.floor(v / 262144)
        local b = math.floor(v / 4096) % 64
        local c = math.floor(v / 64) % 64
        out[#out + 1] = B64_ALPHABET:sub(a + 1, a + 1)
            .. B64_ALPHABET:sub(b + 1, b + 1)
            .. B64_ALPHABET:sub(c + 1, c + 1) .. "="
    end
    return table.concat(out)
end

M.hexToBase64 = hexToBase64

-- eu() of the player: order and parameters of the candidates live in
-- streamingConfig (a string -> second json_parse), without it the default
-- order is used; a relative URL (Tiktok) resolves against the embed origin,
-- /hls/ is rewritten to /hlsmod/<domain>/ by adjust.<name>.domain, params
-- are appended to the query. The direct cf (.txt on the cdn) always answers
-- 403 — never taken; cfNative wins over cf.
-- Returns a list of { url, mime = "hls" } (possibly empty) and, on a hard
-- failure, nil + reason: "payload is not hex" | "AES decrypt failed" |
-- "decrypted payload is not JSON".
function M.decode(payload, origin)
    if type(payload) ~= "string" then return nil, "payload is not hex" end
    local hex = payload:gsub("%s", ""):lower()
    if #hex == 0 or #hex % 2 ~= 0 or hex:match("[^%x]") then
        return nil, "payload is not hex"
    end
    local plain = aes_decrypt(hexToBase64(hex), SP_KEY, SP_IV)
    if type(plain) ~= "string" or plain == "" then
        return nil, "AES decrypt failed"
    end
    local data = json_parse(plain)
    if type(data) ~= "table" then
        return nil, "decrypted payload is not JSON"
    end

    local conf = {}
    if type(data.streamingConfig) == "string" then
        conf = json_parse(data.streamingConfig)
    end
    if type(conf) ~= "table" then conf = {} end
    local order = type(conf.order) == "table" and conf.order
        or { "Tiktok", "Google", "Cloudflare", "In-House" }
    local adjust = type(conf.adjust) == "table" and conf.adjust or {}
    local map = {
        ["Tiktok"]     = data.hlsVideoTiktok,
        ["Google"]     = data.hlsVideoGoogle,
        ["Cloudflare"] = data.cfNative or data.cf,
        ["In-House"]   = data.source,
    }
    local out = {}
    for _, name in ipairs(order) do
        local u = map[name]
        local adj = type(adjust[name]) == "table" and adjust[name] or {}
        if type(u) == "string" and u ~= "" and not adj.disabled then
            local abs = type(origin) == "string" and origin ~= ""
                and url_resolve(origin, u) or u
            if type(adj.params) == "table" then
                for k, v in pairs(adj.params) do
                    local sep = abs:find("?", 1, true) and "&" or "?"
                    abs = abs .. sep .. tostring(k) .. "=" .. url_encode(tostring(v))
                end
            end
            if type(adj.domain) == "string" and adj.domain ~= ""
                and abs:find("/hls/", 1, true) then
                abs = abs:gsub("/hls/", "/hlsmod/" .. adj.domain .. "/", 1)
            end
            out[#out + 1] = { url = abs, mime = "hls" }
        end
    end
    return out
end

return M
