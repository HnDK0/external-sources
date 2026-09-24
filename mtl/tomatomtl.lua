-- ═══════════════════════════════════════════════════════════════════════════
-- TomatoMTL plugin for NoveLA
-- Китайские новеллы с MTL-переводом (tomatomtl.com). Главы зашифрованы
-- AES-128-CBC — ключ/iv/шифртекст в base64 прямо в HTML страницы главы.
-- ── Metadata ───────────────────────────────────────────────────────────────
id = "tomatomtl"
name = "TomatoMTL"
version = "1.0.0"
baseUrl = "https://tomatomtl.com"
language = "MTL"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/tomatomtl.png"

-- ── Settings keys ──────────────────────────────────────────────────────────
local PREF_MODE = "tomatomtl_mode" -- "raw" | "google" | "cina"

-- ── Helpers ────────────────────────────────────────────────────────────────

local _pageCache = {} -- кэш HTML страниц книг

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- Упрощённый стандартный прогон контента: нормализация → вырезание строк
-- с доменом сайта (водяные знаки/реклама) → trim.
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?im)^[^\\n\\r]*tomatomtl\\.com[^\\n\\r]*\\n?", "")
    return string_trim(text)
end

-- ── Перевод названий ─────────────────────────────────────────────────────────
-- Режим перевода: raw = всё китайское; google/cina = всё на английском.

local function getMode()
    local mode = get_preference(PREF_MODE)
    if mode == "" then mode = "google" end
    return mode
end

-- Потолок пачки — по РАЗМЕРУ закодированного URL: сайт/движок тянет до 8к
-- символов, режем на 7000 с запасом. Число строк в пачке плавающее.
local NAMES_CHUNK_CHARS = 7000

-- Google Translate (публичный ключ/URL с сайта tomatomtl.com)
local function translateGoogleUrl(chunk)
    return "https://translate-pa.googleapis.com/v1/translate?params.client=gtx" ..
        "&query.source_language=zh-CN&query.target_language=en&query.display_language=en-US" ..
        "&data_types=TRANSLATION&key=AIzaSyDLEeFI5OtFBwYBIoK_jj5m32rZK5CkCXA&query.text=" ..
        url_encode(chunk)
end

local function translateGoogle(chunk)
    local r = http_get(translateGoogleUrl(chunk))
    if not r.success then
        return nil
    end
    local data = json_parse(r.body)
    if not data or type(data.translation) ~= "string" or data.translation == "" then
        return nil
    end
    return data.translation
end

-- Разбор маркеров [i] по ВСЕМУ ответу, а не построчно: google склеивает
-- строки (в одну запись попадала смесь глав), меняет переводы строк и
-- теряет маркеры. Берём текст между соседними маркерами; повторный
-- маркер с тем же номером не перетирает первый. Внутренние переводы
-- строк схлопываем в пробел — заголовок не должен быть многострочным.
local function parseMarkers(translated, n)
    local marks = {}
    for s, idx, e in translated:gmatch("()%[%s*(%d+)%s*%]()") do
        local i = tonumber(idx)
        if i >= 0 and i < n then
            marks[#marks + 1] = { s = s, e = e, i = i }
        end
    end
    local map = {}
    for k, m in ipairs(marks) do
        if map[m.i] == nil then
            local stop = marks[k + 1] and (marks[k + 1].s - 1) or #translated
            local text = translated:sub(m.e + 1, stop)
            text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then
                map[m.i] = text
            end
        end
    end
    return map
end

-- Один проход перевода по списку индексов lines: нарезка пачек по бюджету
-- URL → маркируем → один http_get_batch → разбор по маркерам.
-- Возвращает got[i]=перевод и failed — индексы без перевода.
local function translatePass(lines, idxs)
    local chunks, cur, curSize = {}, {}, 0
    for _, i in ipairs(idxs) do
        -- маркер "[i] " + сама строка; +16 — запас на percent-кодировку
        local enc = #url_encode(lines[i]) + 16
        if #cur > 0 and curSize + enc > NAMES_CHUNK_CHARS then
            chunks[#chunks + 1] = cur
            cur, curSize = {}, 0
        end
        cur[#cur + 1] = i
        curSize = curSize + enc
    end
    if #cur > 0 then chunks[#chunks + 1] = cur end

    local urls = {}
    for ci, ch in ipairs(chunks) do
        local marked = {}
        for k, i in ipairs(ch) do
            marked[k] = "[" .. tostring(k - 1) .. "] " .. lines[i]
        end
        urls[ci] = translateGoogleUrl(table.concat(marked, "\n"))
    end
    local results = http_get_batch(urls)

    local got, failed = {}, {}
    for ci, ch in ipairs(chunks) do
        local translated = nil
        local res = results[ci]
        if res and res.success then
            local data = json_parse(res.body)
            if data and type(data.translation) == "string" and data.translation ~= "" then
                translated = data.translation
            end
        end
        local map = translated and parseMarkers(translated, #ch) or nil
        for k, i in ipairs(ch) do
            local t = map and map[k - 1]
            if t then
                got[i] = t
            else
                failed[#failed + 1] = i
            end
        end
    end
    return got, failed
end

-- Переводит массив названий батчем, как сайт: join('\n') → запрос →
-- разбор по маркерам. Пачки режутся по РАЗМЕРУ закодированного URL
-- (NAMES_CHUNK_CHARS), а не по числу строк, и шлются все разом через
-- http_get_batch (параллельная загрузка движка, как в en/novelfull.lua).
-- Непереведённые после первого прохода (сбой пачки/потерянные маркеры)
-- повторяются ОДИН раз — только они, не весь список. Остаток → оригинал.
local function translateNamesBatch(lines)
    if #lines == 0 then return {} end
    local all = {}
    for i = 1, #lines do all[i] = i end

    local got, failed = translatePass(lines, all)
    if #failed > 0 then
        local got2, failed2 = translatePass(lines, failed)
        for i, t in pairs(got2) do got[i] = t end
        failed = failed2
    end
    if #failed > 0 then
        log_error("tomatomtl: " .. #failed .. " названий не перевелись, возвращаю оригиналы")
    end

    local out = {}
    for i, line in ipairs(lines) do
        out[i] = got[i] or line
    end
    return out
end

-- Переводит названия в списке записей (каталог/поиск/главы), если режим
-- не raw. Названия ВСЕГДА google-батчем (на сайте названия google-ом;
-- cina медленный). Мутирует item.title на месте, остальное не трогает.
local function applyTitleTranslation(items)
    local mode = getMode()
    if mode == "raw" or #items == 0 then
        return items
    end
    local titles = {}
    for _, item in ipairs(items) do
        titles[#titles + 1] = item.title
    end
    local translated = translateNamesBatch(titles)
    for i, item in ipairs(items) do
        item.title = translated[i] or item.title
    end
    return items
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Pure-Lua AES-128-CBC decryption (адаптация криптостека es/m440in.lua,
-- который, в свою очередь, — из mtl/wtrlab.lua). Движковый base64_decode
-- ломает байты ≥0x80 (возвращает Java-строку UTF-8), поэтому всё —
-- на чистом Lua. Глобальные tc_-функции (для тестируемости через dofile;
-- движку лишние глобалы не мешают — у каждого плагина отдельный LuaState).
-- ═══════════════════════════════════════════════════════════════════════════

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
            return (x % 2 ^ (32 - c)) * 2 ^ c + math.floor(x / 2 ^ (32 - c))
        end
        local function bxor(a, b)
            return bor(band(a, bnot(b)), band(bnot(a), b))
        end
        B32.band, B32.bor, B32.bnot, B32.bxor, B32.lrot = band, bor, bnot, bxor, lrot
    end
end

-- base64 → байты (бинарно-безопасно, как в wtrlab)
local B64DEC = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #chars do
        B64DEC[string.byte(chars, i)] = i - 1
    end
end

function tc_b64ToBytes(s)
    s = string.gsub(s, "%s", "")
    s = string.gsub(s, "=", "")
    local out = {}
    local len = #s
    local i = 1
    while i + 3 <= len do
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        local c = B64DEC[string.byte(s, i + 2)]
        local d = B64DEC[string.byte(s, i + 3)]
        if not (a and b and c and d) then return nil end
        out[#out + 1] = string.char(
            a * 4 + math.floor(b / 16),
            (b % 16) * 16 + math.floor(c / 4),
            (c % 4) * 64 + d
        )
        i = i + 4
    end
    if i + 2 == len then
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        local c = B64DEC[string.byte(s, i + 2)]
        if not (a and b and c) then return nil end
        out[#out + 1] = string.char(
            a * 4 + math.floor(b / 16),
            (b % 16) * 16 + math.floor(c / 4)
        )
        i = i + 3
    elseif i + 1 == len then
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        if not (a and b) then return nil end
        out[#out + 1] = string.char(a * 4 + math.floor(b / 16))
        i = i + 2
    end
    -- Висячий символ (len % 4 == 1) не декодируется ни в один байт —
    -- отбрасываем (лязг Chromium/сайтового декодера), не роняя всю строку.
    if i == len then
        i = i + 1
    end
    if i ~= len + 1 then return nil end
    local bytes = {}
    local n = 0
    for j = 1, #out do
        local part = out[j]
        for k = 1, #part do
            n = n + 1
            bytes[n] = string.byte(part, k)
        end
    end
    return bytes
end

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

-- Таблицы умножения в GF(2^8) для InvMixColumns: вместо 64 вызовов gmul
-- на блок (8 итераций каждый) — 64 обращения к таблице. Строются один раз
-- при загрузке плагина (1024 gmul).
local MUL9, MUL11, MUL13, MUL14 = {}, {}, {}, {}
for v = 0, 255 do
    MUL9[v] = gmul(v, 9)
    MUL11[v] = gmul(v, 11)
    MUL13[v] = gmul(v, 13)
    MUL14[v] = gmul(v, 14)
end

-- AES-128 key expansion → плоский массив 11 round-keys (0..10), 16 байт каждый.
-- Та же схема слов/эндиана, что в m440in (aesExpandKey для AES-256),
-- меняются только числа: Nk=4, w[1..44], rcon-шаг при (i-1)%4==0,
-- sbox-шаг на (i-1)%Nk==4 для 128-бит не существует.
function tc_aesExpandKey128(keyBytes)
    local w = {}
    for i = 1, 4 do
        w[i] = { keyBytes[i * 4 - 3], keyBytes[i * 4 - 2], keyBytes[i * 4 - 1], keyBytes[i * 4] }
    end
    for i = 5, 44 do
        local t = { w[i - 1][1], w[i - 1][2], w[i - 1][3], w[i - 1][4] }
        if (i - 1) % 4 == 0 then
            -- RotWord + SubWord + Rcon
            t = { t[2], t[3], t[4], t[1] }
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
            t[1] = B32.bxor(t[1], RCON[(i - 1) / 4])
        end
        local prev = w[i - 4]
        w[i] = {
            B32.bxor(prev[1], t[1]),
            B32.bxor(prev[2], t[2]),
            B32.bxor(prev[3], t[3]),
            B32.bxor(prev[4], t[4])
        }
    end
    local rk = {}
    for round = 0, 10 do
        for j = 1, 4 do
            local word = w[round * 4 + j]
            for b = 1, 4 do
                rk[round * 16 + (j - 1) * 4 + b] = word[b]
            end
        end
    end
    return rk
end

-- AES-128 decrypt одного 16-байтного блока (state мутируется на месте),
-- 10 раундов, как в m440in для 256-бит (там 14).
function tc_aesDecryptBlock(state, rk)
    -- AddRoundKey(10)
    for i = 1, 16 do state[i] = B32.bxor(state[i], rk[10 * 16 + i]) end

    for round = 9, 1, -1 do
        -- InvShiftRows
        local t
        t = state[14]; state[14] = state[10]; state[10] = state[6]; state[6] = state[2]; state[2] = t
        t = state[3];  state[3]  = state[11]; state[11] = t
        t = state[7];  state[7]  = state[15]; state[15] = t
        t = state[4];  state[4]  = state[8];  state[8]  = state[12]; state[12] = state[16]; state[16] = t
        -- InvSubBytes
        for i = 1, 16 do state[i] = INV_SBOX[state[i] + 1] end
        -- AddRoundKey(round)
        local off = round * 16
        for i = 1, 16 do state[i] = B32.bxor(state[i], rk[off + i]) end
        -- InvMixColumns (через предвычисленные таблицы MUL*)
        for c = 0, 3 do
            local i1 = c * 4 + 1
            local a0, a1, a2, a3 = state[i1], state[i1 + 1], state[i1 + 2], state[i1 + 3]
            local b0, b1, b2, b3 = MUL14[a0], MUL11[a1], MUL13[a2], MUL9[a3]
            state[i1]     = B32.bxor(B32.bxor(b0, b1), B32.bxor(b2, b3))
            b0, b1, b2, b3 = MUL9[a0], MUL14[a1], MUL11[a2], MUL13[a3]
            state[i1 + 1] = B32.bxor(B32.bxor(b0, b1), B32.bxor(b2, b3))
            b0, b1, b2, b3 = MUL13[a0], MUL9[a1], MUL14[a2], MUL11[a3]
            state[i1 + 2] = B32.bxor(B32.bxor(b0, b1), B32.bxor(b2, b3))
            b0, b1, b2, b3 = MUL11[a0], MUL13[a1], MUL9[a2], MUL14[a3]
            state[i1 + 3] = B32.bxor(B32.bxor(b0, b1), B32.bxor(b2, b3))
        end
    end

    -- Финальный раунд (без InvMixColumns)
    local t
    t = state[14]; state[14] = state[10]; state[10] = state[6]; state[6] = state[2]; state[2] = t
    t = state[3];  state[3]  = state[11]; state[11] = t
    t = state[7];  state[7]  = state[15]; state[15] = t
    t = state[4];  state[4]  = state[8];  state[8]  = state[12]; state[12] = state[16]; state[16] = t
    for i = 1, 16 do state[i] = INV_SBOX[state[i] + 1] end
    for i = 1, 16 do state[i] = B32.bxor(state[i], rk[i]) end
    return state
end

-- AES-128-CBC decrypt → строка байтов (string.char), CBC-XOR, PKCS7-unpad.
-- Буферы (state/ct) выделяются один раз: на каждый 16-байтный блок раньше
-- создавались 2 таблицы + 16 одно-байтовых строк.
function tc_aesCbcDecrypt128(ctBytes, keyBytes, ivBytes)
    local bxor = B32.bxor
    local rk = tc_aesExpandKey128(keyBytes)
    local prev = { ivBytes[1], ivBytes[2], ivBytes[3], ivBytes[4],
        ivBytes[5], ivBytes[6], ivBytes[7], ivBytes[8],
        ivBytes[9], ivBytes[10], ivBytes[11], ivBytes[12],
        ivBytes[13], ivBytes[14], ivBytes[15], ivBytes[16] }
    local ct, state = {}, {}
    local out, nout = {}, 0
    for start = 1, #ctBytes, 16 do
        for i = 1, 16 do
            local b = ctBytes[start + i - 1]
            ct[i] = b
            state[i] = b
        end
        tc_aesDecryptBlock(state, rk)
        nout = nout + 1
        out[nout] = string.char(
            bxor(state[1], prev[1]),   bxor(state[2], prev[2]),
            bxor(state[3], prev[3]),   bxor(state[4], prev[4]),
            bxor(state[5], prev[5]),   bxor(state[6], prev[6]),
            bxor(state[7], prev[7]),   bxor(state[8], prev[8]),
            bxor(state[9], prev[9]),   bxor(state[10], prev[10]),
            bxor(state[11], prev[11]), bxor(state[12], prev[12]),
            bxor(state[13], prev[13]), bxor(state[14], prev[14]),
            bxor(state[15], prev[15]), bxor(state[16], prev[16]))
        -- следующий prev — шифроблок этого шага; меняемся буферами
        prev, ct = ct, prev
    end
    local pt = table.concat(out)
    local pad = string.byte(pt, #pt)
    if pad and pad >= 1 and pad <= 16 then
        pt = pt:sub(1, #pt - pad)
    end
    return pt
end

-- ── Settings schema ──────────────────────────────────────────────────────────

function getSettingsSchema()
    return {{
        key = PREF_MODE,
        type = "select",
        label = "Translation mode",
        current = "google",
        options = {{
            value = "raw",
            label = "Raw (Chinese)"
        }, {
            value = "google",
            label = "Google Translate (fast)"
        }, {
            value = "cina",
            label = "CinaNMT"
        }}
    }}
end

-- ── Каталог ─────────────────────────────────────────────────────────────────

-- Подписи x-signature у обложек fanqie-explorer живут считанные минуты, а
-- ответ сервера бывает отдан с уже протухшим x-expires — тогда CDN отдаёт 403.
-- Сайт в этом случае грузит картинку через wsrv.nl (tomato.js, link_cover):
-- срезаем query и "~..."-суффикс, хост меняем на p6-novel.byteimg.com/origin.
local function cover_via_proxy(cover)
    local u = cover:gsub("^https://", ""):gsub("^http://", "")
    local parts = {}
    for seg in u:gmatch("[^/]+") do
        local part = seg
        if part:find("[?~]") then
            part = part:match("^[^~]*")
        end
        parts[#parts + 1] = part
    end
    -- как в link_cover: первый сегмент (хост) заменяется на origin-заглушку
    parts[1] = "https://wsrv.nl/?url=https://p6-novel.byteimg.com/origin"
    return table.concat(parts, "/") .. "&w=225&h=300&fit=cover&output=webp"
end

local function buildCatalogItem(book)
    local cover = book.thumb_url or ""
    if cover ~= "" then
        cover = cover:gsub("/origin/origin/", "/origin/")
        -- поисковый API отдаёт обложки по http — CDN отвечает 301 text/html
        cover = cover:gsub("^http://", "https://")
        -- 10с запас на сетевую латентность; при протухшей подписи — wsrv
        local exp = cover:match("x%-expires=(%d+)")
        if exp and tonumber(exp) <= os.time() + 10 then
            cover = cover_via_proxy(cover)
        end
    end
    local item = {
        title = string_clean(book.book_name or ""),
        url = baseUrl .. "/book/" .. tostring(book.book_id)
    }
    if cover ~= "" then
        item.cover = cover
    end
    local score = book.score or ""
    if score ~= "" then
        item.rating = "Rating: " .. score .. "/10"
    end
    return item
end

-- ── Фильтры (эндпоинт /fanqie-explorer, параметры как у сайта) ──────────────

function getFilterList()
    return {
        {
            type = "select",
            key = "gender",
            label = "Gender",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
                { value = "1", label = "Male" },
                { value = "0", label = "Female" },
            }
        },
        {
            type = "select",
            key = "category",
            label = "Category",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
            { value = "1317", label = "Theme: Historical Romance & Political Intrigue" },
            { value = "1169", label = "Theme: Suspense Romance" },
            { value = "1012", label = "Theme: Pure Love" },
            { value = "1079", label = "Theme: Derivative / Fanfiction" },
            { value = "558", label = "Theme: Political Journey" },
            { value = "1058", label = "Theme: Comprehensive Film And TV Works" },
            { value = "658", label = "Theme: Natural Disaster" },
            { value = "871", label = "Theme: First-person Perspective" },
            { value = "873", label = "Theme: Cyberpunk" },
            { value = "855", label = "Theme: The Fourth Calamity" },
            { value = "851", label = "Theme: Rule-based Horror Stories" },
            { value = "758", label = "Theme: Ancient Times" },
            { value = "10", label = "Theme: Suspense" },
            { value = "705", label = "Theme: Cthulhu" },
            { value = "516", label = "Theme: Urban Superpowers" },
            { value = "515", label = "Theme: Post-Apocalyptic Survival" },
            { value = "514", label = "Theme: Spiritual Recovery" },
            { value = "513", label = "Theme: High-level Martial Arts World" },
            { value = "512", label = "Theme: Otherworldly Continent" },
            { value = "511", label = "Theme: Eastern Fantasy" },
            { value = "507", label = "Theme: Spy Warfare" },
            { value = "503", label = "Theme: Qing Dynasty" },
            { value = "501", label = "Theme: Song Dynasty" },
            { value = "500", label = "Theme: Breaking The Mold" },
            { value = "497", label = "Theme: Military General" },
            { value = "496", label = "Theme: National Destiny" },
            { value = "485", label = "Theme: Workplace And Business Battles" },
            { value = "481", label = "Theme: Angsty Deep Love" },
            { value = "474", label = "Theme: Love Over Time" },
            { value = "473", label = "Theme: Prestigious Families" },
            { value = "465", label = "Theme: Comprehensive Manga" },
            { value = "464", label = "Theme: Otherworldly Transmigration" },
            { value = "460", label = "Theme: Exclusive Doting" },
            { value = "453", label = "Theme: Starting Plot" },
            { value = "452", label = "Theme: Alternate History/Fictional Setting" },
            { value = "259", label = "Theme: Fantasy Xianxia" },
            { value = "1", label = "Theme: Metropolis" },
            { value = "3", label = "Theme: Modern Romance" },
            { value = "5", label = "Theme: Ancient Romance" },
            { value = "7", label = "Theme: Fantasy" },
            { value = "12", label = "Theme: History" },
            { value = "15", label = "Theme: Sports" },
            { value = "16", label = "Theme: Martial arts/Wuxia" },
            { value = "32", label = "Theme: Fantasy Romance" },
            { value = "29", label = "Roles: CEO" },
            { value = "91", label = "Roles: Multiple Female Heroine" },
            { value = "25", label = "Roles: Live-in Son-in-law" },
            { value = "865", label = "Roles: Loyal And Devoted Partner" },
            { value = "856", label = "Roles: Almighty" },
            { value = "853", label = "Roles: White On The Outside, Black On The Inside" },
            { value = "849", label = "Roles: Two Grade-A-student" },
            { value = "1456", label = "Roles: High Status, Great Power" },
            { value = "521", label = "Roles: Drama Queen" },
            { value = "520", label = "Roles: Big Boss (Influential Figure)" },
            { value = "519", label = "Roles: Young Lady" },
            { value = "518", label = "Roles: Agent" },
            { value = "509", label = "Roles: Gaming Streamer" },
            { value = "506", label = "Roles: Detective" },
            { value = "502", label = "Roles: Royalty And Nobility" },
            { value = "498", label = "Roles: Emperor" },
            { value = "492", label = "Roles: General (Military)" },
            { value = "491", label = "Roles: Poisonous Doctor" },
            { value = "490", label = "Roles: Female Chefs" },
            { value = "488", label = "Roles: Lawyer" },
            { value = "487", label = "Roles: Doctor" },
            { value = "486", label = "Roles: Celebrity" },
            { value = "470", label = "Roles: Stand-In" },
            { value = "469", label = "Roles: Dual Personality" },
            { value = "468", label = "Roles: Iceberg" },
            { value = "459", label = "Roles: Quirky And Witty" },
            { value = "455", label = "Roles: Match Made In Heaven" },
            { value = "454", label = "Roles: Both Cool And Sweet" },
            { value = "392", label = "Roles: No Romantic Pairings" },
            { value = "389", label = "Roles: Single Female Heroine" },
            { value = "385", label = "Roles: Campus Belle" },
            { value = "391", label = "Roles: No Female Heroine" },
            { value = "380", label = "Roles: Yandere" },
            { value = "378", label = "Roles: Empress (Female Emperor)" },
            { value = "375", label = "Roles: Special Forces" },
            { value = "369", label = "Roles: Villain" },
            { value = "28", label = "Roles: Adorable Baby" },
            { value = "26", label = "Roles: Divine Doctor" },
            { value = "30", label = "Roles: Spoiling The Wife" },
            { value = "42", label = "Roles: Stay-at-Home Dad" },
            { value = "82", label = "Roles: Academic Genius" },
            { value = "83", label = "Roles: Princess" },
            { value = "84", label = "Roles: Empress" },
            { value = "85", label = "Roles: Princess Consort" },
            { value = "86", label = "Roles: Strong Female Lead" },
            { value = "87", label = "Roles: Imperial Uncle" },
            { value = "88", label = "Roles: Legitimate Daughter" },
            { value = "89", label = "Roles: Pokemon" },
            { value = "90", label = "Roles: Genius" },
            { value = "92", label = "Roles: Cunning And Manipulative" },
            { value = "93", label = "Roles: Playing Dumb To Outsmart Others" },
            { value = "94", label = "Roles: Group Favorite" },
            { value = "747", label = "Plot: Female-Targeted Mystery" },
            { value = "1141", label = "Plot: Western Fantasy" },
            { value = "1140", label = "Plot: Eastern Xianxia" },
            { value = "1139", label = "Plot: Ancient-Style Social Realism" },
            { value = "8", label = "Plot: Post-apocalyptic Sci-Fi" },
            { value = "1016", label = "Plot: Male-oriented Derivative Works" },
            { value = "1015", label = "Plot: Female-Oriented Derivatives" },
            { value = "1017", label = "Plot: Romance In The Republic Of China Era" },
            { value = "1014", label = "Plot: Urban High-level Martial Arts" },
            { value = "751", label = "Plot: Suspense And Supernatural" },
            { value = "539", label = "Plot: Creative Suspense" },
            { value = "504", label = "Plot: Resistance And Espionage During War" },
            { value = "749", label = "Plot: Youthful Sweet Romance" },
            { value = "275", label = "Plot: Two Male Leads" },
            { value = "253", label = "Plot: Creative Ancient Romance" },
            { value = "273", label = "Plot: Ancient History" },
            { value = "272", label = "Plot: Creative Take On History" },
            { value = "267", label = "Plot: Modern Brainstorming" },
            { value = "263", label = "Plot: Urban Farming" },
            { value = "262", label = "Plot: Urban Brainstorming" },
            { value = "261", label = "Plot: Urban Daily Life" },
            { value = "257", label = "Plot: Fantasy Brainstorming" },
            { value = "248", label = "Plot: Fantasy Romance" },
            { value = "246", label = "Plot: Palace Intrigue And Family Struggles" },
            { value = "748", label = "Plot: Elite CEO" },
            { value = "27", label = "Plot: Warlord As A Live-In Son-in-Law" },
            { value = "718", label = "Plot: Anime Derivatives" },
            { value = "745", label = "Plot: Glittering Stardom" },
            { value = "746", label = "Plot: Gaming And Sports" },
            { value = "750", label = "Plot: Workplace Romance" },
            { value = "704", label = "Plot: Two Female Leads" },
            { value = "258", label = "Plot: Traditional Fantasy" },
            { value = "124", label = "Plot: Urban Cultivation" },
            { value = "79", label = "Plot: Era-Based" },
            { value = "23", label = "Plot: Farm" },
            { value = "24", label = "Plot: Quick Transmigration" },
            { value = "1458", label = "Plot: Substitute Marriage" },
            { value = "1459", label = "Plot: Romancing the Villain" },
            { value = "1455", label = "Plot: Feng Shui Secret Arts" },
            { value = "1062", label = "Plot: God Slayer Derivatives" },
            { value = "1060", label = "Plot: Ten Days Derivative" },
            { value = "373", label = "Plot: Journey To The West Derivative Works" },
            { value = "1037", label = "Plot: Derivatives Of Public Domain Works" },
            { value = "1036", label = "Plot: Dream Of The Red Chamber Derivative Works" },
            { value = "1035", label = "Plot: Zhen Huan Derivative Works" },
            { value = "1034", label = "Plot: Ruyi's Royal Love In The Palace Derivatives" },
            { value = "1460", label = "Plot: Urban Jianghu" },
            { value = "1457", label = "Plot: Second Male Lead Becomes the ML" },
            { value = "537", label = "Plot: Thriller Games" },
            { value = "872", label = "Plot: Pursuing A Husband" },
            { value = "874", label = "Plot: Card Games" },
            { value = "875", label = "Plot: Classic Of Mountains And Seas" },
            { value = "876", label = "Plot: Transmigration Before Birth" },
            { value = "867", label = "Plot: Ghost Hunting" },
            { value = "868", label = "Plot: Sword Cultivation" },
            { value = "869", label = "Plot: Post-Apocalyptic" },
            { value = "860", label = "Plot: Mutual Redemption" },
            { value = "861", label = "Plot: Spoiling The Husband" },
            { value = "864", label = "Plot: Instances Dungeons" },
            { value = "854", label = "Plot: Black Technology" },
            { value = "850", label = "Plot: Pure Enjoyment Without Depth" },
            { value = "852", label = "Plot: Soul Transmigration" },
            { value = "845", label = "Plot: Master Descends The Mountain" },
            { value = "846", label = "Plot: Dark Transformation" },
            { value = "847", label = "Plot: Raising Children" },
            { value = "848", label = "Plot: Age Gap" },
            { value = "843", label = "Plot: Self-delusion Comedy" },
            { value = "844", label = "Plot: Real And Fake Heiresses" },
            { value = "839", label = "Plot: Reunion After A Long Separation" },
            { value = "840", label = "Plot: Rags To Riches" },
            { value = "838", label = "Plot: No Harem" },
            { value = "835", label = "Plot: Upbringing" },
            { value = "836", label = "Plot: Mutual Pampering" },
            { value = "837", label = "Plot: Struggle For Supremacy" },
            { value = "834", label = "Plot: 1v1" },
            { value = "830", label = "Plot: Level-Up Style" },
            { value = "831", label = "Plot: Soul Swap" },
            { value = "832", label = "Plot: Imperial Examinations" },
            { value = "829", label = "Plot: Younger Partner" },
            { value = "34", label = "Plot: Marriage And Romance" },
            { value = "731", label = "Plot: Investiture Of The Gods" },
            { value = "495", label = "Plot: Courtyard Dwellings (Hutongs)" },
            { value = "508", label = "Plot: Esports" },
            { value = "524", label = "Plot: Double Reincarnation" },
            { value = "523", label = "Plot: Past And Present Lives" },
            { value = "702", label = "Plot: Mutual Purity" },
            { value = "616", label = "Plot: Regretful ML" },
            { value = "11", label = "Plot: Countryside" },
            { value = "557", label = "Plot: Escaping Famine" },
            { value = "538", label = "Plot: Doujin" },
            { value = "522", label = "Plot: Face-Slapping" },
            { value = "505", label = "Plot: Solving Cases" },
            { value = "494", label = "Plot: Stockpiling Supplies" },
            { value = "493", label = "Plot: Fishing" },
            { value = "484", label = "Plot: Happy Ending" },
            { value = "483", label = "Plot: Enemies to Lovers" },
            { value = "482", label = "Plot: Secret Crush" },
            { value = "480", label = "Plot: Runaway Marriage" },
            { value = "479", label = "Plot: Pregnant And Running Away" },
            { value = "478", label = "Plot: Strong Vs. Strong" },
            { value = "477", label = "Plot: Love At First Sight" },
            { value = "476", label = "Plot: Mutual Effort In Love" },
            { value = "475", label = "Plot: Reuniting After Separation" },
            { value = "471", label = "Plot: Arranged Marriage" },
            { value = "467", label = "Plot: Hidden Marriage" },
            { value = "466", label = "Plot: Flash Marriage" },
            { value = "463", label = "Plot: Modern To Ancient Time-Travel" },
            { value = "462", label = "Plot: Ancient-to-Modern Time Travel" },
            { value = "461", label = "Plot: Group Transmigration" },
            { value = "458", label = "Plot: Protective Of Loved Ones" },
            { value = "457", label = "Plot: Tormenting Scumbags" },
            { value = "456", label = "Plot: Exclusive Love" },
            { value = "266", label = "Plot: Alternate Identity" },
            { value = "265", label = "Plot: Married First, Love Later" },
            { value = "247", label = "Plot: Medical Skills" },
            { value = "372", label = "Plot: Online Game" },
            { value = "367", label = "Plot: Ultraman Doujin" },
            { value = "379", label = "Plot: Survival" },
            { value = "388", label = "Plot: Woman Disguised As A Man" },
            { value = "387", label = "Plot: Childhood Sweethearts" },
            { value = "384", label = "Plot: Invincible" },
            { value = "390", label = "Plot: Republic Of China Era" },
            { value = "383", label = "Plot: Uncle Nine" },
            { value = "382", label = "Plot: Transmigration Into A Book" },
            { value = "381", label = "Plot: Chat Group" },
            { value = "377", label = "Plot: Qin Dynasty" },
            { value = "376", label = "Plot: Dragon Ball" },
            { value = "374", label = "Plot: Marvel" },
            { value = "371", label = "Plot: Pokémon" },
            { value = "370", label = "Plot: Pirates/One Piece" },
            { value = "368", label = "Plot: Naruto" },
            { value = "127", label = "Plot: Workplace" },
            { value = "126", label = "Plot: Ming Dynasty" },
            { value = "125", label = "Plot: Family" },
            { value = "67", label = "Plot: Three Kingdoms" },
            { value = "68", label = "Plot: Eschatology" },
            { value = "69", label = "Plot: Livestreaming" },
            { value = "70", label = "Plot: Infinite Flow" },
            { value = "71", label = "Plot: Myriad Worlds And Realms" },
            { value = "72", label = "Plot: Beast World" },
            { value = "73", label = "Plot: Tang Dynasty" },
            { value = "74", label = "Plot: Pets" },
            { value = "75", label = "Plot: Food Delivery" },
            { value = "76", label = "Plot: Qing Dynasty Transmigration" },
            { value = "77", label = "Plot: Interstellar" },
            { value = "78", label = "Plot: Cuisine" },
            { value = "80", label = "Plot: Way Of The Sword" },
            { value = "81", label = "Plot: Tomb Raiding" },
            { value = "95", label = "Plot: Angsty Stories" },
            { value = "96", label = "Plot: Sweet Pet" },
            { value = "100", label = "Plot: Supernatural" },
            { value = "4", label = "Plot: School Life" },
            { value = "17", label = "Plot: Antique Appraisal" },
            { value = "19", label = "Plot: System" },
            { value = "20", label = "Plot: Divine Tycoon" },
            { value = "36", label = "Plot: Rebirth" },
            { value = "37", label = "Plot: Transmigration" },
            { value = "39", label = "Plot: Anime/2D Culture" },
            { value = "40", label = "Plot: Islands" },
            { value = "43", label = "Plot: Entertainment Industry" },
            { value = "44", label = "Plot: Space/Dimension" },
            { value = "61", label = "Plot: Mystery And Deduction" },
            { value = "66", label = "Plot: Ancient World" },
            }
        },
        {
            type = "select",
            key = "creation_status",
            label = "Status",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
                { value = "0", label = "Completed" },
                { value = "1", label = "Ongoing" },
            }
        },
        {
            type = "select",
            key = "word_count",
            label = "Word Count",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All" },
                { value = "0", label = "Below 300k" },
                { value = "1", label = "300k-500k" },
                { value = "2", label = "500k-1M" },
                { value = "3", label = "1M-2M" },
                { value = "4", label = "Above 2M" },
            }
        },
        {
            type = "select",
            key = "sort",
            label = "Sort By",
            defaultValue = "0",
            options = {
                { value = "0", label = "Most Popular" },
                { value = "1", label = "Latest" },
                { value = "2", label = "Word Count" },
            }
        },
    }
end

-- Общий запрос к ajax-эндпоинту fanqie-explorer (page_index с 0, как в JS сайта)
local function fetchExplorer(index, params)
    local url = baseUrl .. "/fanqie-explorer?ajax=1&page_index=" .. tostring(index) ..
        "&page_count=18" ..
        "&gender=" .. (params and params.gender or "-1") ..
        "&creation_status=" .. (params and params.creation_status or "-1") ..
        "&word_count=" .. (params and params.word_count or "-1") ..
        "&sort=" .. (params and params.sort or "0") ..
        "&category_id=" .. (params and params.category_id or "-1")
    local r = http_get(url)
    if not r.success then
        log_error("tomatomtl: fanqie-explorer failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if not data or not data.books then
        log_error("tomatomtl: cannot parse fanqie-explorer JSON")
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, book in ipairs(data.books) do
        table.insert(items, buildCatalogItem(book))
    end
    return { items = applyTitleTranslation(items), hasNext = (data.has_more == true) }
end

function getCatalogList(index)
    return fetchExplorer(index, nil)
end

function getCatalogFiltered(index, filters)
    return fetchExplorer(index, {
        gender = filters["gender"],
        category_id = filters["category"],
        creation_status = filters["creation_status"],
        word_count = filters["word_count"],
        sort = filters["sort"],
    })
end

-- ── Поиск ───────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    if index > 0 then
        return { items = {}, hasNext = false }
    end
    local r = http_post(baseUrl .. "/api/search-proxy.php", json_stringify({
        query = query,
        page_index = index,
        page_count = 10,
        query_type = 0
    }), {
        headers = {
            ["Referer"] = baseUrl .. "/search?q=" .. url_encode(query)
        }
    })
    if not r.success then
        log_error("tomatomtl: getCatalogSearch failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if not data or not data.search_tabs or not data.search_tabs[1] then
        log_error("tomatomtl: cannot parse search JSON")
        return { items = {}, hasNext = false }
    end
    local items = {}
    local tab = data.search_tabs[1]
    for _, entry in ipairs(tab.data or {}) do
        for _, book in ipairs(entry.book_data or {}) do
            table.insert(items, buildCatalogItem(book))
        end
    end
    return { items = applyTitleTranslation(items), hasNext = (#items >= 10) }
end

-- ── Детали книги ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- og:title серверный и надёжный; h1.book-title в raw-curl пуст (заполняется JS)
    local title = html_attr(body, "meta[property='og:title']", "content")
    if title == "" then
        local el = html_select_first(body, "h1.book-title")
        if el then
            title = string_clean(el.text)
        end
    end
    if title == "" then return nil end
    if getMode() == "raw" then
        return title
    end
    local translated = translateGoogle(title)
    if translated then
        return translated
    end
    log_error("tomatomtl: перевод названия книги не удался, возвращаю оригинал")
    return title
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img.book-cover", "src")
    if cover == "" then
        cover = html_attr(body, "img.book-cover", "data-src")
    end
    return cover ~= "" and cover or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local desc = html_attr(body, "meta[name=description]", "content")
    return desc ~= "" and desc or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local genres = {}
    for _, el in ipairs(html_select(body, "a[href*='categories']")) do
        local g = string_clean(el.text)
        if g ~= "" then
            table.insert(genres, g)
        end
    end
    return genres
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, ".book-meta-item")) do
        local status = el.text and el.text:match("Status:%s*([^|]+)")
        if status then
            local s = string_clean(status)
            if s ~= "" then
                return s
            end
        end
    end
    return nil
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, ".book-meta-item")) do
        local score = el.text and el.text:match("Score:%s*([%d%.]+)")
        if score then
            return "Rating: " .. score .. "/10"
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, ".book-meta-item")) do
        local iso = el.text and el.text:match("Last Updated:%s*([%d%-]+T[%d:]+)")
        if iso then
            return string.sub(iso, 1, 10)
        end
    end
    return nil
end

-- ── Список глав ─────────────────────────────────────────────────────────────

local _chapterTitlesCache = {} -- кэш переведённого списка глав по bookUrl

function getChapterList(bookUrl)
    if getMode() ~= "raw" and _chapterTitlesCache[bookUrl] then
        return _chapterTitlesCache[bookUrl]
    end
    local bookId = string.match(bookUrl, "/book/(%d+)")
    if not bookId then
        log_error("tomatomtl: cannot extract book id from " .. tostring(bookUrl))
        return {}
    end
    local r = http_get(baseUrl .. "/catalog/" .. bookId)
    if not r.success then
        log_error("tomatomtl: chapters API failed code=" .. tostring(r.code))
        return {}
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" then
        log_error("tomatomtl: cannot parse chapters JSON")
        return {}
    end
    local chapters = {}
    for _, ch in ipairs(data) do
        local title = string_clean(ch.title or "")
        if title ~= "" and ch.id then
            table.insert(chapters, {
                title = title,
                url = baseUrl .. "/book/" .. bookId .. "/" .. tostring(ch.id) .. "/"
            })
        end
    end
    -- Пост-фильтр: главы с пустым/пробельным названием (google может потерять
    -- маркер/строку, в сырых данных тоже встречаются пустые) и дубликаты по url
    local filtered = {}
    local seen = {}
    for _, ch in ipairs(chapters) do
        local title = ch.title or ""
        if title ~= "" and not string.match(title, "^%s*$") and not seen[ch.url] then
            seen[ch.url] = true
            filtered[#filtered + 1] = ch
        end
    end
    chapters = filtered
    -- Перевод названий глав (google-батч) вне raw-режима
    if getMode() ~= "raw" and #chapters > 0 then
        chapters = applyTitleTranslation(chapters)
        _chapterTitlesCache[bookUrl] = chapters
    end
    return chapters
end

-- NOTE: намеренно НЕ через fetchPage — хэш должен отражать свежее состояние
function getChapterListHash(bookUrl)
    local bookId = string.match(bookUrl, "/book/(%d+)")
    if not bookId then
        return nil
    end
    local r = http_get(baseUrl .. "/catalog/" .. bookId)
    if not r.success then
        return nil
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" then
        return nil
    end
    return tostring(#data)
end

-- ── Текст главы ─────────────────────────────────────────────────────────────

local TRANSLATE_CHUNK_SIZE = 4500

local function translateCina(chunk)
    local r = http_post("https://cina.tomatomtl.com/translate?token=tomatomtl",
        json_stringify({
            text = chunk,
            target_lang = "EN",
            source_lang = "ZH"
        }), {
        headers = {
            ["Authorization"] = "Bearer tomatomtl"
        }
    })
    if not r.success then
        return nil
    end
    local data = json_parse(r.body)
    if not data or data.code ~= 200 or not data.data or data.data == "" then
        return nil
    end
    return data.data
end

function getChapterText(html, url)
    local uc = html:match('unlock_code%s*=%s*"([^"]+)"')
    if not uc then
        show_error("Chapter load error", "Unable to find the decryption key on the page.")
        return nil
    end

    -- encryptedData есть только у залогиненного; у анонима — заглушка Login Required.
    -- Через json_parse, а не регэксп: сайт сериализует JSON с экранированием «\/»,
    -- и сырой захват оставляет бэкслэш внутри base64 → декодер падает.
    local blk = html:match('encryptedData%s*=%s*(%b{})')
    local obj = blk and json_parse(blk)
    local iv = obj and obj.iv
    local enc = obj and obj.enc
    if not blk or not iv or not enc then
        show_error("Login required",
            "Chapter content requires a tomatomtl.com account. Tap \"Open in browser\" to log in, then retry.",
            baseUrl .. "/user/login")
        return nil
    end

    local keyFull = tc_b64ToBytes(uc)
    local keyBytes = {}
    if keyFull then
        for _, b in ipairs(keyFull) do
            if #keyBytes >= 16 then break end
            keyBytes[#keyBytes + 1] = b
        end
    end
    local ctBytes = tc_b64ToBytes(enc)
    local ivBytes = tc_b64ToBytes(iv)
    if not keyBytes or #keyBytes < 16 or not ctBytes or not ivBytes then
        local kst = keyBytes and tostring(#keyBytes) or "nil"
        local cst = ctBytes and tostring(#ctBytes) or "nil"
        local ist = ivBytes and tostring(#ivBytes) or "nil"
        show_error("Chapter decrypt error", "Unable to decrypt chapter content.\n\nDIAG key#" .. kst
            .. " ct#" .. cst .. " iv#" .. ist
            .. "\nuc# " .. #uc .. " uc=" .. uc
            .. "\niv=" .. (iv or "nil")
            .. "\nenc# " .. (enc and #enc or -1) .. " head=" .. (enc and enc:sub(1, 24) or "nil"))
        return nil
    end

    local text = tc_aesCbcDecrypt128(ctBytes, keyBytes, ivBytes)

    -- Честные причины отказа вместо общего «corrupted»:
    -- крошечный текст = глава-заголовок/разделитель без содержания,
    -- отсутствие китайского = расшифровка дала мусор.
    if not text or #text < 40 then
        local n = text and #text or 0
        show_error("Chapter has no content",
            "Decrypted only " .. n .. " characters — this looks like a title/divider page with no readable text.")
        return nil
    end
    local hasCJK = false
    for i = 1, #text do
        local b = string.byte(text, i)
        if b >= 228 and b <= 233 then
            hasCJK = true
            break
        end
    end
    if not hasCJK then
        show_error("Chapter decrypt failed",
            "Decrypted text contains no Chinese characters — the result is garbage, not a valid chapter.")
        return nil
    end

    text = applyStandardContentTransforms(text)

    local mode = getMode()
    if mode == "raw" then
        return text
    end

    local translate = (mode == "cina") and translateCina or translateGoogle

    -- Чанкинг по ~4500 байт, но НЕ разрезая UTF-8 символы (китайский = 3 байта):
    -- если байт сразу за границей — продолжение символа (0x80..0xBF), откатываемся.
    local chunks = {}
    local pos = 1
    while pos <= #text do
        local last = math.min(pos + TRANSLATE_CHUNK_SIZE - 1, #text)
        while last > pos and last < #text and string.byte(text, last + 1) >= 128 and string.byte(text, last + 1) <= 191 do
            last = last - 1
        end
        chunks[#chunks + 1] = text:sub(pos, last)
        pos = last + 1
    end

    local results = {}
    for _, chunk in ipairs(chunks) do
        local translated = translate(chunk)
        if translated then
            results[#results + 1] = translated
        else
            -- Не маскируем сбой: пользователь выбрал перевод и ждёт результат
            show_error("Translation failed",
                "Translation failed. Switch to Raw mode or use the built-in translator.")
            return nil
        end
    end
    return table.concat(results, "\n")
end