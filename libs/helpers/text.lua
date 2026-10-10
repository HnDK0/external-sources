-- =====================================================================
-- Lib: text rotations (rot13, rot18).
-- No XOR here on purpose: the xor "duplicates" found in three plugins are
-- internals of hmac-sha256 / AES-GCM and disappear with the Kotlin APIs,
-- the only standalone str-xor (en/hianimes.lua) stays inline in the plugin.
-- Loaded via require_lib("text"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- ROT13 over Latin letters. Bodies of the three copies were equivalent:
-- libs/voe.lua:15, ar/anime4up.lua:383, en/novelhi.lua:33 (the guard for
-- nil/empty comes from novelhi).
function M.rot13(s)
    if not s or s == "" then return "" end
    return (s:gsub("[%a]", function(c)
        local b = c:byte()
        local base = (b < 97) and 65 or 97
        return string.char(base + ((b - base + 13) % 26))
    end))
end

-- Kodik rotation: +18 over letters only, digits untouched — this is NOT
-- the classic ROT13+ROT5 pair, digits must survive as-is or the base64
-- after decoding breaks (sole copy: ru/yummyanime.lua:511 kodikDecode).
function M.rot18(s)
    if not s or s == "" then return "" end
    local t = {}
    for i = 1, #s do
        local b = s:byte(i)
        if b >= 65 and b <= 90 then
            b = b + 18
            if b > 90 then b = b - 26 end
        elseif b >= 97 and b <= 122 then
            b = b + 18
            if b > 122 then b = b - 26 end
        end
        t[#t + 1] = string.char(b)
    end
    return table.concat(t)
end

return M
