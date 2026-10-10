-- =====================================================================
-- Lib: otaku-embed player — provider page -> master m3u8 + subtitles.
-- The player config sits in window.__P = base64(xor(json)) with the key
-- below; the XOR roundtrip (the site JS deobfuscate() over UTF-8 bytes)
-- stays in Lua inside this lib.
-- Extracted from en/hianimes.lua:292-351 (xorDecode + resolveStream).
-- Loaded via require_lib("otaku"); uses engine API base64_decode_bytes
-- (the caller's guard checks it, canon: guards verify transitive APIs).
-- Pure parse: the caller fetches the provider page(s) and builds the
-- final sources (quality label, Referer headers).
-- =====================================================================
local version = "1.0.0"

-- Player config key: window.__P = base64(xor(json)) with this key.
local OBF_KEY = "otaku-embed-v1"

local M = {}

-- Byte-wise XOR with OBF_KEY (the JS deobfuscate() roundtrip over UTF-8 bytes;
-- Lua strings are byte arrays, so no transcoding is needed).
local function xorDecode(data)
    local out = {}
    for i = 1, #data do
        local a = data:byte(i)
        local b = OBF_KEY:byte((i - 1) % #OBF_KEY + 1)
        local r, p = 0, 1
        for _ = 1, 8 do
            if a % 2 ~= b % 2 then r = r + p end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            p = p * 2
        end
        out[i] = string.char(r)
    end
    return table.concat(out)
end

-- Provider page body -> master m3u8 URL + subtitle list (nil when absent).
function M.resolve(html)
    if type(html) ~= "string" then return nil, nil end
    -- Pattern A: a direct HLS URL embedded in the page.
    local direct = html:match('(https?://[^"\'%s]+%.m3u8[^"\'%s]*)')
    if direct then return direct, nil end

    -- Pattern B: obfuscated player config.
    local blob = html:match('window%.__P%s*=%s*"([^"]+)"')
        or html:match("window%.__P%s*=%s*'([^']+)'")
    if not blob then return nil, nil end
    -- Engine API returns raw bytes; nil means the blob is not valid base64.
    local cfgBytes = base64_decode_bytes(blob)
    if not cfgBytes then return nil, nil end
    local cfg = json_parse(xorDecode(cfgBytes))
    if type(cfg) ~= "table" or type(cfg.src) ~= "string" or cfg.src == "" then
        return nil, nil
    end

    local subtitles = nil
    if type(cfg.subtitles) == "table" then
        subtitles = {}
        for _, s in ipairs(cfg.subtitles) do
            if type(s) == "table" and type(s.src) == "string" and s.src ~= "" then
                local track = { url = s.src }
                if type(s.label) == "string" and s.label ~= "" then track.label = s.label end
                if type(s.lang) == "string" and s.lang ~= "" then track.lang = s.lang end
                table.insert(subtitles, track)
            end
        end
        if #subtitles == 0 then subtitles = nil end
    end
    return cfg.src, subtitles
end

return M
