-- =====================================================================
-- Lib: Alloha (borth: ZU/Zx/ZQ permutations from dec_app) -> POST
--      alloha.yani.tv/bnsi/movies/<id> -> hlsSource quality list.
-- Extracted from ru/yummyanime.lua (borth helpers + resolveAlloha), a
-- port of borth_core.js.
-- Loaded via require_lib("alloha"). No dependencies on other libs.
--
-- The borth ports are byte-verified against the node reference: 170
-- inputs (1..513 chars, real viewporti) match byte for byte. Zf is always
-- false in the reference, so the final string rotations are dead code
-- and are absent here too.
--
-- The embed HTML is already in hand (the caller loads it with its
-- batch), only /bnsi/movies/<id> is a POST done here.
-- =====================================================================
local version = "1.0.0"

local M = {}

local function borthBits(len)
    local bits = 0
    while 2 ^ bits < len do bits = bits + 1 end
    return bits
end

local function borthGroupU(v)
    local n = 0
    while v > 0 do
        n = n + 1
        v = math.floor(v / 2)
    end
    return n
end

local function borthGroupX(v, bits)
    if v == 0 then return bits end
    local n = 0
    while v % 2 == 0 do
        n = n + 1
        v = math.floor(v / 2)
    end
    return n
end

local function borthU(s)
    local len = #s
    if len <= 1 then return s end
    local bits = borthBits(len)
    local counts = {}
    for g = 0, bits do counts[g] = 0 end
    for i = 0, len - 1 do
        local g = borthGroupU(i)
        counts[g] = counts[g] + 1
    end
    local chunks, pos = {}, 0
    for g = bits, 0, -1 do              -- slice the input by groups, top down
        local n = counts[g]
        chunks[g] = s:sub(pos + 1, pos + n)
        pos = pos + n
    end
    local used = {}
    for g = 0, bits do used[g] = 0 end
    local out = {}
    for i = 0, len - 1 do
        local g = borthGroupU(i)
        local o = used[g]
        used[g] = o + 1
        out[i + 1] = chunks[g]:sub(o + 1, o + 1)
    end
    return table.concat(out)
end

local function borthX(s)
    local len = #s
    if len <= 1 then return s end
    local bits = borthBits(len)
    local counts = {}
    for g = 0, bits do counts[g] = 0 end
    for i = 0, len - 1 do
        local g = borthGroupX(i, bits)
        counts[g] = counts[g] + 1
    end
    local chunks, pos = {}, 0
    for g = 0, bits do                  -- slice the input by groups, bottom up
        local n = counts[g]
        chunks[g] = s:sub(pos + 1, pos + n)
        pos = pos + n
    end
    local used = {}
    for g = 0, bits do used[g] = 0 end
    local out = {}
    for i = 0, len - 1 do
        local g = borthGroupX(i, bits)
        local o = used[g]
        used[g] = o + 1
        out[i + 1] = chunks[g]:sub(o + 1, o + 1)
    end
    return table.concat(out)
end

local function isPrime(n)
    if n < 2 then return false end
    if n % 2 == 0 then return n == 2 end
    local d = 3
    while d * d <= n do
        if n % d == 0 then return false end
        d = d + 2
    end
    return true
end

local function borthQ(s)
    local len = #s
    if len <= 1 then return s end
    local p = len + 1
    while not isPrime(p) do p = p + 1 end
    local taken, order, cur = {}, {}, 0
    while #order < len do
        cur = (cur + 2) % p
        if cur < len and not taken[cur + 1] then
            taken[cur + 1] = true
            order[#order + 1] = cur
        end
    end
    local out = {}
    for m = 0, len - 1 do
        out[order[m + 1] + 1] = s:sub(m + 1, m + 1)
    end
    return table.concat(out)
end

local function borthPayload(viewporti)
    return borthQ(borthX(borthU(viewporti)))
end

-- Qualities in descending order: JSON keys come in arbitrary order.
local function sortedQualityKeys(quals)
    local keys = {}
    for k in pairs(quals) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb and na ~= nb then return na > nb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local ALLOHA_ORIGIN = "https://alloha.yani.tv"

-- page — the shared http_get_batch response for this iframe (see
-- batchPlayers in the plugin).
-- Returns a list of { url, quality, headers } or nil.
function M.resolve(iframeUrl, dubbing, page)
    if type(page) ~= "table" or not page.success then
        log_error("alloha: iframe " .. tostring(page and page.code))
        return nil
    end
    local html = page.body
    local viewporti = html:match('<meta name="viewporti" content="([^"]+)"')
    local token     = html:match("token:%s*'([0-9a-f]+)'")
    local activeId  = html:match('"active"%s*:%s*{%s*"id"%s*:%s*(%d+)')
    if not viewporti or not token or not activeId then
        log_error("alloha: player page parse failed")
        return nil
    end
    -- fp (sha256 fingerprint) is not verified by the server: on the live
    -- site zeros and a real sha256 both answer 200, and the sandbox has
    -- no hash function anyway.
    local borth = string.rep("0", 64) .. "|" .. borthPayload(viewporti)
    local body = "token=" .. token .. "&av1=true&autoplay=0&audio=&subtitle="
    local pr = http_post(ALLOHA_ORIGIN .. "/bnsi/movies/" .. activeId, body, {
        headers = {
            ["Referer"]          = iframeUrl,
            ["Origin"]           = ALLOHA_ORIGIN,
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Borth"]            = borth,
        },
    })
    if not pr.success then
        log_error("alloha: /bnsi " .. tostring(pr.code))
        return nil
    end
    local data = json_parse(pr.body)
    local tracks = data and data.hlsSource
    if type(tracks) ~= "table" then return nil end
    -- the vkvideo CDN answers 403 without Origin → the source headers are
    -- mandatory
    local headers = { ["Referer"] = iframeUrl, ["Origin"] = ALLOHA_ORIGIN }
    local out = {}
    for _, track in ipairs(tracks) do
        local quals = type(track) == "table" and track.quality or nil
        if type(quals) == "table" then
            for _, k in ipairs(sortedQualityKeys(quals)) do
                local u = quals[k]
                if type(u) == "string" and u ~= "" then
                    out[#out + 1] = {
                        url     = u,
                        quality = "Alloha · " .. dubbing .. " · " .. tostring(k) .. "p",
                        headers = headers,
                    }
                end
            end
        end
    end
    return out
end

return M
