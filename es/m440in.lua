-- M440.in plugin for NoveLA
-- Испанский манга-сайт: каталог/книги через HTML, поиск через JSON API,
-- главы — постраничные изображения (content_type = "manga").

id       = "m440in"
name     = "M440"
version  = "1.0.0"
baseUrl  = "https://m440.in"
language = "es"
content_type = "manga"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/m440in.png"

-- ── Хелперы ──

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

local function getSlug(bookUrl)
    return string.match(bookUrl, "/manga/([^/]+)")
end

-- Достаёт последний номер страницы из .pagination (ссылка на последнюю страницу
-- — предпоследний элемент списка; последний — «»/след.стр.).
local function getTotalPages(body)
    local el = html_select_first(body, ".pagination li:nth-last-child(2) a")
    local n = el and tonumber(string_clean(el.text))
    return n or 1
end

-- Парсер карточек каталога (.col-sm-6 .media) — общий для каталога и фильтров.
local function parseCatalogItems(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".col-sm-6 .media")) do
        local url = html_attr(card.html, ".media-left a.thumbnail", "href")
        local title = html_attr(card.html, "a.chart-title", "title")
        if title == "" then
            local t = html_select_first(card.html, ".media-heading a")
            if t then title = string_clean(t.text) end
        end
        if url ~= "" and title ~= "" then
            table.insert(items, {
                title  = string_clean(title),
                url    = absUrl(url),
                cover  = absUrl(html_attr(card.html, ".media-left img", "src")),
                rating = html_select_first(card.html, ".label-info") and
                         string_clean(html_select_first(card.html, ".label-info").text) or nil,
            })
        end
    end
    return items
end

-- ── Крипто: расшифровка списка глав (как в exis.js) ─────────────────────────
-- Сайт шифрует JSON список глав: в HTML есть блоб UsaPoncho (JSON {ct, iv, s}),
-- exis.js на клиенте делает CryptoJS.AES.decrypt(UsaPoncho, ReturnStrg(), {format:
-- CryptoJSAesJson}) → двойной JSON (строка, внутри массив глав). Движковый
-- aes_decrypt не подходит (key/iv с байтами ≥0x80 ломаются на UTF-8 строках),
-- поэтому весь стек — на чистом Lua (подход mtl/wtrlab.lua).

local M440_PASSPHRASE = "X^Ib1O*HLVh%3W2t"  -- из exis.js: ReturnStrg()

-- 32-битные битовые операции (bit32 если есть, иначе арифметический fallback)
local B32 = {}
do
    if type(bit32) == "table" and type(bit32.band) == "function" then
        B32.band, B32.bor, B32.bnot, B32.bxor, B32.lrot = bit32.band, bit32.bor, bit32.bnot, bit32.bxor, bit32.lrotate
    else
        local function band(a, b)
            local r, p = 0, 1
            for _ = 1, 32 do
                if a % 2 == 1 and b % 2 == 1 then r = r + p end
                a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
            end
            return r
        end
        local function bor(a, b)
            local r, p = 0, 1
            for _ = 1, 32 do
                if a % 2 == 1 or b % 2 == 1 then r = r + p end
                a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
            end
            return r
        end
        local function bnot(a)
            local r, p = 0, 1
            for _ = 1, 32 do
                if a % 2 == 0 then r = r + p end
                a, p = math.floor(a / 2), p * 2
            end
            return r
        end
        local function lrot(x, c)
            -- c≥1; точнее на double: hi < 2^c, lo*2^c < 2^32 — без переполнения
            return (x % 2 ^ (32 - c)) * 2 ^ c + math.floor(x / 2 ^ (32 - c))
        end
        -- bxor через band/bnot/bor
        local function bxor(a, b)
            return bor(band(a, bnot(b)), band(bnot(a), b))
        end
        B32.band, B32.bor, B32.bnot, B32.bxor, B32.lrot = band, bor, bnot, bxor, lrot
    end
end

-- MD5 (RFC 1321)
local function md5(message)
    local len = #message
    local bitlen = len * 8
    local padded = message .. "\128" .. string.rep("\0", (56 - (len + 1) % 64 + 64) % 64)
    for i = 1, 8 do
        padded = padded .. string.char(math.floor(bitlen / 256 ^ (i - 1)) % 256)
    end
    local K = {}
    for i = 1, 64 do K[i] = math.floor(math.abs(math.sin(i)) * 4294967296) % 4294967296 end
    local S = {
        7,12,17,22,  7,12,17,22,  7,12,17,22,  7,12,17,22,
        5, 9,14,20,  5, 9,14,20,  5, 9,14,20,  5, 9,14,20,
        4,11,16,23,  4,11,16,23,  4,11,16,23,  4,11,16,23,
        6,10,15,21,  6,10,15,21,  6,10,15,21,  6,10,15,21,
    }
    local a0, b0, c0, d0 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476
    for chunk = 1, #padded, 64 do
        local M = {}
        for i = 0, 15 do
            local off = chunk + i * 4
            M[i + 1] = string.byte(padded, off)
                + string.byte(padded, off + 1) * 256
                + string.byte(padded, off + 2) * 65536
                + string.byte(padded, off + 3) * 16777216
        end
        local A, B, C, D = a0, b0, c0, d0
        for i = 0, 63 do
            local F, g
            if i < 16 then
                F = B32.bor(B32.band(B, C), B32.band(B32.bnot(B), D))
                g = i
            elseif i < 32 then
                F = B32.bor(B32.band(D, B), B32.band(B32.bnot(D), C))
                g = (5 * i + 1) % 16
            elseif i < 48 then
                F = B32.bxor(B, B32.bxor(C, D))
                g = (3 * i + 5) % 16
            else
                F = B32.bxor(C, B32.bor(B, B32.bnot(D)))
                g = (7 * i) % 16
            end
            F = (F + A + K[i + 1] + M[g + 1]) % 4294967296
            A, D, C, B = D, C, B, (B + B32.lrot(F, S[i + 1])) % 4294967296
        end
        a0, b0, c0, d0 = (a0 + A) % 4294967296, (b0 + B) % 4294967296, (c0 + C) % 4294967296, (d0 + D) % 4294967296
    end
    local out = {}
    for _, v in ipairs({ a0, b0, c0, d0 }) do
        for i = 0, 3 do
            out[#out + 1] = string.char(math.floor(v / 256 ^ i) % 256)
        end
    end
    return table.concat(out)
end

-- base64 → байты (бинарно-безопасно, как в wtrlab)
local B64DEC = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #chars do B64DEC[string.byte(chars, i)] = i - 1 end
end
local function b64ToBytes(s)
    s = string.gsub(s, "%s", "")
    s = string.gsub(s, "=", "")
    local out, len, i = {}, #s, 1
    while i + 3 <= len do
        local a, b, c, d = B64DEC[string.byte(s, i)], B64DEC[string.byte(s, i + 1)], B64DEC[string.byte(s, i + 2)], B64DEC[string.byte(s, i + 3)]
        if not (a and b and c and d) then return nil end
        out[#out + 1] = string.char(a * 4 + math.floor(b / 16), (b % 16) * 16 + math.floor(c / 4), (c % 4) * 64 + d)
        i = i + 4
    end
    if i + 2 == len then
        local a, b, c = B64DEC[string.byte(s, i)], B64DEC[string.byte(s, i + 1)], B64DEC[string.byte(s, i + 2)]
        if not (a and b and c) then return nil end
        out[#out + 1] = string.char(a * 4 + math.floor(b / 16), (b % 16) * 16 + math.floor(c / 4))
    elseif i + 1 == len then
        local a, b = B64DEC[string.byte(s, i)], B64DEC[string.byte(s, i + 1)]
        if not (a and b) then return nil end
        out[#out + 1] = string.char(a * 4 + math.floor(b / 16))
    end
    local bytes = {}
    local n = 0
    for j = 1, #out do
        for k = 1, #out[j] do
            n = n + 1
            bytes[n] = string.byte(out[j], k)
        end
    end
    return bytes
end

local function fromHex(s)
    return (s:gsub("%x%x", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- AES-256-CBC (декрипт)
local SBOX = {
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76,
    0xCA,0x82,0xC9,0x7D,0xFA,0x59,0x47,0xF0,0xAD,0xD4,0xA2,0xAF,0x9C,0xA4,0x72,0xC0,
    0xB7,0xFD,0x93,0x26,0x36,0x3F,0xF7,0xCC,0x34,0xA5,0xE5,0xF1,0x71,0xD8,0x31,0x15,
    0x04,0xC7,0x23,0xC3,0x18,0x96,0x05,0x9A,0x07,0x12,0x80,0xE2,0xEB,0x27,0xB2,0x75,
    0x09,0x83,0x2C,0x1A,0x1B,0x6E,0x5A,0xA0,0x52,0x3B,0xD6,0xB3,0x29,0xE3,0x2F,0x84,
    0x53,0xD1,0x00,0xED,0x20,0xFC,0xB1,0x5B,0x6A,0xCB,0xBE,0x39,0x4A,0x4C,0x58,0xCF,
    0xD0,0xEF,0xAA,0xFB,0x43,0x4D,0x33,0x85,0x45,0xF9,0x02,0x7F,0x50,0x3C,0x9F,0xA8,
    0x51,0xA3,0x40,0x8F,0x92,0x9D,0x38,0xF5,0xBC,0xB6,0xDA,0x21,0x10,0xFF,0xF3,0xD2,
    0xCD,0x0C,0x13,0xEC,0x5F,0x97,0x44,0x17,0xC4,0xA7,0x7E,0x3D,0x64,0x5D,0x19,0x73,
    0x60,0x81,0x4F,0xDC,0x22,0x2A,0x90,0x88,0x46,0xEE,0xB8,0x14,0xDE,0x5E,0x0B,0xDB,
    0xE0,0x32,0x3A,0x0A,0x49,0x06,0x24,0x5C,0xC2,0xD3,0xAC,0x62,0x91,0x95,0xE4,0x79,
    0xE7,0xC8,0x37,0x6D,0x8D,0xD5,0x4E,0xA9,0x6C,0x56,0xF4,0xEA,0x65,0x7A,0xAE,0x08,
    0xBA,0x78,0x25,0x2E,0x1C,0xA6,0xB4,0xC6,0xE8,0xDD,0x74,0x1F,0x4B,0xBD,0x8B,0x8A,
    0x70,0x3E,0xB5,0x66,0x48,0x03,0xF6,0x0E,0x61,0x35,0x57,0xB9,0x86,0xC1,0x1D,0x9E,
    0xE1,0xF8,0x98,0x11,0x69,0xD9,0x8E,0x94,0x9B,0x1E,0x87,0xE9,0xCE,0x55,0x28,0xDF,
    0x8C,0xA1,0x89,0x0D,0xBF,0xE6,0x42,0x68,0x41,0x99,0x2D,0x0F,0xB0,0x54,0xBB,0x16
}
local INV_SBOX = {}
do
    for i = 1, 256 do INV_SBOX[SBOX[i] + 1] = i - 1 end
end
local RCON = {0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36,0x6C,0xD8,0xAB,0x4D}

local function gmul(a, b)
    local p = 0
    for _ = 1, 8 do
        if b % 2 == 1 then p = B32.bxor(p, a) end
        local h = a >= 128 and 1 or 0
        a = a * 2
        if a >= 256 then a = a - 256 end
        if h == 1 then a = B32.bxor(a, 27) end
        b = math.floor(b / 2)
    end
    return p
end

local function aesExpandKey(keyBytes)
    local w = {}
    for i = 1, 8 do w[i] = { keyBytes[i * 4 - 3], keyBytes[i * 4 - 2], keyBytes[i * 4 - 1], keyBytes[i * 4] } end
    for i = 9, 60 do
        local t = { w[i - 1][1], w[i - 1][2], w[i - 1][3], w[i - 1][4] }
        if (i - 1) % 8 == 0 then
            t = { t[2], t[3], t[4], t[1] }
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
            local rcon = RCON[(i - 1) / 8 + 1 > 14 and 14 or (i - 1) / 8]
            t[1] = B32.bxor(t[1], rcon)
        elseif (i - 1) % 8 == 4 then
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
        end
        local prev = w[i - 8]
        w[i] = { B32.bxor(prev[1], t[1]), B32.bxor(prev[2], t[2]), B32.bxor(prev[3], t[3]), B32.bxor(prev[4], t[4]) }
    end
    local rk = {}
    for round = 0, 14 do
        for j = 1, 4 do
            local word = w[round * 4 + j]
            for b = 1, 4 do rk[round * 16 + (j - 1) * 4 + b] = word[b] end
        end
    end
    return rk
end

local function aesDecryptBlock(state, rk)
    for i = 1, 16 do state[i] = B32.bxor(state[i], rk[14 * 16 + i]) end
    for round = 13, 1, -1 do
        local t
        t = state[14]; state[14] = state[10]; state[10] = state[6]; state[6] = state[2]; state[2] = t
        t = state[3];  state[3]  = state[11]; state[11] = t
        t = state[7];  state[7]  = state[15]; state[15] = t
        t = state[4];  state[4]  = state[8];  state[8]  = state[12]; state[12] = state[16]; state[16] = t
        for i = 1, 16 do state[i] = INV_SBOX[state[i] + 1] end
        local off = round * 16
        for i = 1, 16 do state[i] = B32.bxor(state[i], rk[off + i]) end
        for c = 0, 3 do
            local i1 = c * 4 + 1
            local a0, a1, a2, a3 = state[i1], state[i1 + 1], state[i1 + 2], state[i1 + 3]
            state[i1]     = B32.bxor(B32.bxor(gmul(a0, 14), gmul(a1, 11)), B32.bxor(gmul(a2, 13), gmul(a3, 9)))
            state[i1 + 1] = B32.bxor(B32.bxor(gmul(a0, 9), gmul(a1, 14)), B32.bxor(gmul(a2, 11), gmul(a3, 13)))
            state[i1 + 2] = B32.bxor(B32.bxor(gmul(a0, 13), gmul(a1, 9)), B32.bxor(gmul(a2, 14), gmul(a3, 11)))
            state[i1 + 3] = B32.bxor(B32.bxor(gmul(a0, 11), gmul(a1, 13)), B32.bxor(gmul(a2, 9), gmul(a3, 14)))
        end
    end
    local t
    t = state[14]; state[14] = state[10]; state[10] = state[6]; state[6] = state[2]; state[2] = t
    t = state[3];  state[3]  = state[11]; state[11] = t
    t = state[7];  state[7]  = state[15]; state[15] = t
    t = state[4];  state[4]  = state[8];  state[8]  = state[12]; state[12] = state[16]; state[16] = t
    for i = 1, 16 do state[i] = INV_SBOX[state[i] + 1] end
    for i = 1, 16 do state[i] = B32.bxor(state[i], rk[i]) end
    return state
end

local function aesCbcDecrypt(ct, key, iv)
    local rk = aesExpandKey(key)
    local out = {}
    local prev = iv
    for start = 1, #ct, 16 do
        local blk = {}
        for i = 1, 16 do blk[i] = ct[start + i - 1] end
        local dec = aesDecryptBlock({ blk[1], blk[2], blk[3], blk[4], blk[5], blk[6], blk[7], blk[8],
            blk[9], blk[10], blk[11], blk[12], blk[13], blk[14], blk[15], blk[16] }, rk)
        for i = 1, 16 do out[#out + 1] = string.char(B32.bxor(dec[i], prev[i])) end
        prev = blk
    end
    local pt = table.concat(out)
    local pad = string.byte(pt, #pt)
    if pad and pad >= 1 and pad <= 16 then pt = pt:sub(1, #pt - pad) end
    return pt
end

-- EvpKDF (OpenSSL EVP_BytesToKey, MD5, 1 iter) → key 32B, iv 16B
local function evpKdf(pass, salt)
    local keyPart = ""
    local prev = ""
    while #keyPart < 48 do
        prev = md5(prev .. pass .. salt)
        keyPart = keyPart .. prev
    end
    return keyPart:sub(1, 32), keyPart:sub(33, 48)
end

-- Достаёт JS-строку UsaPoncho из HTML и снимает экранирование (\" \\ \/)
local function extractUsaPoncho(body)
    local s = string.find(body, "UsaPoncho%s*=%s*\"")
    if not s then return nil end
    local start = string.find(body, "\"", s)
    local out, i = {}, start + 1
    while i <= #body do
        local c = body:sub(i, i)
        if c == "\\" then
            out[#out + 1] = body:sub(i + 1, i + 1)
            i = i + 2
        elseif c == '"' then
            break
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Расшифровывает UsaPoncho → массив глав (или nil)
local function decryptChapters(body)
    local jsonText = extractUsaPoncho(body)
    if not jsonText then return nil end
    local ok, poncho = pcall(json_parse, jsonText)
    if not ok or type(poncho) ~= "table" or not poncho.ct then return nil end
    local salt = fromHex(poncho.s or "")
    local key, iv = evpKdf(M440_PASSPHRASE, salt)
    local ct = b64ToBytes(poncho.ct)
    if not ct or #ct == 0 or #ct % 16 ~= 0 then return nil end
    local keyB, ivB = {}, {}
    for i = 1, 32 do keyB[i] = string.byte(key, i) end
    for i = 1, 16 do ivB[i] = string.byte(iv, i) end
    local pt = aesCbcDecrypt(ct, keyB, ivB)
    if not pt or pt == "" then return nil end
    -- двойной JSON: plaintext = JSON-строка, внутри массив глав
    local ok1, s1 = pcall(json_parse, pt)
    if not ok1 or type(s1) ~= "string" then return nil end
    local ok2, data = pcall(json_parse, s1)
    if not ok2 or type(data) ~= "table" then return nil end
    local out = {}
    for k = #data, 1, -1 do
        local ch = data[k]
        local vol = ch.volume or ""
        if vol == "0" or vol == "" then vol = nil end
        table.insert(out, {
            title = "#" .. ch.number .. " " .. string_clean(ch.name or ""),
            url   = "",
            volume = vol and ("Vol. " .. vol) or nil,
            id     = tostring(ch.id),
            slug   = ch.slug,
            created_at = tostring(ch.created_at or ""),
        })
    end
    return out
end

-- Ищет на странице книги список глав. Основной путь — расшифровка UsaPoncho
-- (AES, как делает exis.js). Запасной путь — открытый JS-массив
-- var/let/const NAME = [...]. Поля: id, slug, name, number, volume, created_at.
-- Порядок на сайте — DESC (новые сверху), возвращаем хронологический.
local function parseChapters(body)
    local dec = decryptChapters(body)
    if dec and #dec > 0 then return dec end
    local patterns = {
        "var%s+%w+%s*=%s*%[",
        "let%s+%w+%s*=%s*%[",
        "const%s+%w+%s*=%s*%[",
        "jschaptertemp%s*=%s*%[",  -- window.jschaptertemp / без var — тоже
    }
    for _, pat in ipairs(patterns) do
        local pos = 1
        while true do
            local s, e = string.find(body, pat, pos)
            if not s then break end
            -- Находим парную закрывающую скобку (учёт вложенности)
            local depth, i = 0, e
            while i <= #body do
                local c = body:sub(i, i)
                if c == "[" then depth = depth + 1
                elseif c == "]" then
                    depth = depth - 1
                    if depth == 0 then break end
                end
                i = i + 1
            end
            pos = i
            if depth ~= 0 then break end
            local ok, data = pcall(json_parse, body:sub(e, i - 1))
            if ok and type(data) == "table" and data[1]
               and data[1].slug and data[1].number then
                local out = {}
                for k = #data, 1, -1 do
                    local ch = data[k]
                    local vol = ch.volume or ""
                    if vol == "0" or vol == "" then vol = nil end
                    table.insert(out, {
                        title = "#" .. ch.number .. " " .. string_clean(ch.name or ""),
                        url   = "",
                        volume = vol and ("Vol. " .. vol) or nil,
                        id     = tostring(ch.id),
                        slug   = ch.slug,
                        created_at = tostring(ch.created_at or ""),
                    })
                end
                return out
            end
        end
    end
    return nil
end

-- ── Каталог ──

function getCatalogList(index)
    local page = (index or 0) + 1
    local r = http_get(baseUrl .. "/manga-list?page=" .. page)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = page < getTotalPages(r.body) }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local r = http_get(baseUrl .. "/search?q=" .. url_encode(query))
    if not r.success then return { items = {}, hasNext = false } end
    local data = json_parse(r.body)
    if type(data) ~= "table" then return { items = {}, hasNext = false } end

    local items = {}
    for _, m in ipairs(data) do
        local title = m.value or ""
        local slug = m.data or ""
        if title ~= "" and slug ~= "" then
            table.insert(items, {
                title = string_clean(title),
                url   = baseUrl .. "/manga/" .. slug,
                cover = absUrl(html_attr(m.label or "", "img", "src")),
            })
        end
    end
    return { items = items, hasNext = false }
end

function getFilterList()
    local cats = {
        { value = "1",  label = "Action" },          { value = "2",  label = "Adventure" },
        { value = "3",  label = "Comedy" },          { value = "4",  label = "Doujinshi" },
        { value = "5",  label = "Drama" },           { value = "6",  label = "Ecchi" },
        { value = "7",  label = "Fantasy" },         { value = "8",  label = "Gender Bender" },
        { value = "9",  label = "Harem" },           { value = "10", label = "Historical" },
        { value = "11", label = "Horror" },          { value = "12", label = "Josei" },
        { value = "13", label = "Martial Arts" },    { value = "14", label = "Mature" },
        { value = "15", label = "Mecha" },           { value = "16", label = "Mystery" },
        { value = "17", label = "One Shot" },        { value = "18", label = "Psychological" },
        { value = "19", label = "Romance" },         { value = "20", label = "School Life" },
        { value = "21", label = "Sci-fi" },          { value = "22", label = "Seinen" },
        { value = "23", label = "Shoujo" },          { value = "24", label = "Shoujo Ai" },
        { value = "25", label = "Shounen" },         { value = "26", label = "Shounen Ai" },
        { value = "27", label = "Slice of Life" },   { value = "28", label = "Sports" },
        { value = "29", label = "Supernatural" },    { value = "30", label = "Tragedy" },
        { value = "31", label = "Yaoi" },            { value = "32", label = "Yuri" },
        { value = "33", label = "Hentai" },          { value = "34", label = "Smut" },
    }
    local alpha = {}
    for _, ch in ipairs({ "A","B","C","D","E","F","G","H","I","J","K","L","M",
                          "N","O","P","Q","R","S","T","U","V","W","X","Y","Z" }) do
        table.insert(alpha, { value = ch, label = ch })
    end
    table.insert(alpha, { value = "Other", label = "Other" })

    return {
        { type = "select", key = "sortBy", label = "Sort By", defaultValue = "name",
          options = {
              { value = "name",       label = "Name (A-Z)" },
              { value = "views",      label = "Most Viewed" },
              { value = "updated_at", label = "Last Updated" },
              { value = "created_at", label = "Newest" },
          } },
        { type = "checkbox", key = "cat", label = "Categories", options = cats },
        { type = "select", key = "alpha", label = "Alphabet", defaultValue = "A",
          options = alpha },
        { type = "text", key = "author", label = "Author", defaultValue = "" },
        { type = "text", key = "tag", label = "Tag", defaultValue = "" },
        { type = "text", key = "artist", label = "Artist", defaultValue = "" },
    }
end

function getCatalogFiltered(index, filters)
    local page = (index or 0) + 1
    local sortBy = filters["sortBy"] or "name"
    local asc    = filters["sortBy_ascending"] or "true"

    local url = baseUrl .. "/filterList?page=" .. page
        .. "&sortBy=" .. url_encode(sortBy) .. "&asc=" .. asc

    local cats = filters["cat_included"] or {}
    for _, v in ipairs(cats) do url = url .. "&cat=" .. url_encode(v) end

    local alpha = filters["alpha"] or ""
    if alpha ~= "" then url = url .. "&alpha=" .. url_encode(alpha) end
    for _, k in ipairs({ "author", "tag", "artist" }) do
        local v = filters[k] or ""
        if v ~= "" then url = url .. "&" .. k .. "=" .. url_encode(v) end
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = page < getTotalPages(r.body) }
end

-- ── Страница книги ──

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h2.widget-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img[src*='cover']", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".well")
    if el then
        local parts = {}
        for _, p in ipairs(html_select(el.html, "p")) do
            local t = string_trim(p.text)
            if t ~= "" then table.insert(parts, t) end
        end
        if #parts > 0 then return table.concat(parts, "\n") end
    end
    local meta = html_attr(body, "meta[name='description']", "content")
    if meta ~= "" then return string_trim(meta) end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, "a[href*='/manga-list/category/']")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".label-danger")
    return el and string_clean(el.text) or nil
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local n = string.match(body, "Rating:%s*([%d%.]+)")
    return n or nil
end

function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local chapters = parseChapters(body)
    if not chapters or #chapters == 0 then return nil end
    -- Новейшая глава — последняя в хронологическом порядке
    local newest = chapters[#chapters]
    local y, m, d = string.match(newest.created_at or "", "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end

-- ── Главы ──

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local slug = getSlug(bookUrl)
    local chapters = parseChapters(body)
    if chapters then
        for i, ch in ipairs(chapters) do
            ch.url = absUrl(baseUrl .. "/manga/" .. slug .. "/" .. ch.slug)
            ch.slug = nil
            ch.created_at = nil
            ch.id = nil
        end
        return chapters
    end

    -- Fallback: парсинг DOM по ссылкам на /manga/{slug}/{chapter}
    local out, seen = {}, {}
    for _, a in ipairs(html_select(body, 'a[href*="/manga/' .. slug .. '/"]')) do
        local href = a.href or ""
        if href:match("/manga/" .. slug .. "/[^/]+$") and not seen[href] then
            seen[href] = true
            table.insert(out, { title = string_clean(a.text), url = absUrl(href) })
        end
    end
    -- DOM тоже DESC — разворачиваем в хронологический
    local rev = {}
    for i = #out, 1, -1 do table.insert(rev, out[i]) end
    return rev
end

function getChapterListHash(bookUrl)
    -- Всегда прямой http_get (не fetchPage): кэш даст устаревший хэш
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local chapters = parseChapters(r.body)
    if not chapters or #chapters == 0 then return nil end
    local newest = chapters[#chapters]
    return newest.slug .. "|" .. newest.created_at
end

-- Глава: все картинки страниц лежат в одном HTML в data-src читалки
-- (img[data-src*='chapters/'], порядок = порядок страниц). Один запрос.
function getPageList(html, url)
    local body = html
    if not body or body == "" then
        local r = http_get(url)
        if not r.success then return {} end
        body = r.body
    end

    local pages, seen = {}, {}
    for _, img in ipairs(html_select(body, "img[data-src*='chapters/']")) do
        local src = img:attr("data-src")
        src = absUrl(src)
        if src ~= "" and not seen[src] then
            seen[src] = true
            table.insert(pages, src)
        end
    end
    return pages
end

function getChapterText(html, url)
    return ""  -- манга: картинки через getPageList
end