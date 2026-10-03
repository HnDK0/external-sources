-- AnimePhoenix — видео-плагин NoveLA (content_type = "video")
-- Сайт: https://anime-phoenix.com — каталог аниме/фильмов, эпизоды, серверы плеера.

content_type = "video"
id           = "animephoenix"
name         = "Anime Phoenix"
version      = "1.0.0"
baseUrl      = "https://anime-phoenix.com"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/animephoenix.png"

local floor = math.floor

-- ============ Утилиты ============

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Безопасное число из JSON-значения: number | строка | иначе nil.
local function toNumber(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    return nil
end

-- Кэш страницы тайтла: title/cover/description/genres/rating/status — 6 вызовов
-- на одну страницу (см. гайд «Кэширование страниц (fetchPage)»).
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

-- Есть ли медиа-расширение в конце пути URL (до "?" / "#").
local function hasMediaExt(u)
    local base = u:match("^[^%?#]*") or u
    return base:match("%.m3u8$") ~= nil
        or base:match("%.mp4$") ~= nil
        or base:match("%.mkv$") ~= nil
end

-- Percent-декод пути URL для разбора имени файла: часть зеркал отдаёт ссылку
-- с %20, часть — с двойным %2520. Без декода qualityFromUrl матчил «20» из
-- «%20» и в подпись источника попадало «201080p» (баг 2026-10-03).
local function decodeUrlPath(u)
    local base = u:match("^[^%?#]*") or u
    for _ = 1, 2 do
        base = base:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
    end
    return base
end

-- Подпись качества для UI: "1080p" из имени файла в URL; нет паттерна → nil.
-- Кандидаты с неправдоподобным разрешением («201080p» и т.п.) пропускаются.
local function qualityFromUrl(u)
    for m in decodeUrlPath(u):gmatch("(%d+p)") do
        local n = tonumber(m:match("%d+"))
        if n and n >= 144 and n <= 4320 then return m end
    end
    return nil
end

-- Подпись источника: «<имя сервера> · <разрешение> · <языка/озвучка>».
-- Имя — из data-server JSON, разрешение и язык — из имени файла в URL
-- ([WebDL - 1080p - Ar - x265]). Всё, что не распознано, просто не
-- попадает в подпись; никаких догадок.
local function sourceLabel(name, u)
    local parts = {}
    if type(name) == "string" and name ~= "" then parts[#parts + 1] = name end
    local q = qualityFromUrl(u)
    if q then parts[#parts + 1] = q end
    -- ищем токен сразу после «<разрешение> - »: «1080p - Ar - x265»
    local s = decodeUrlPath(u)
    local lang = s:match("%d+p%s*%-%s*([%a][%w]*)%s*%-%s*x%d%d")
        or s:match("%d+p%s*%-%s*([%a][%w]*)%s*%]")
    if lang and lang ~= q then parts[#parts + 1] = lang end
    return table.concat(parts, " · ")
end

-- ============ Крипто: SHA-256 / HMAC (чистый Lua) ============
-- Подпись api/search.php — HMAC-SHA256. Кластер перенесён из ar/witanime.lua
-- (копия, не ссылка): LuaJ (семантика Lua 5.1), только math.floor, string.*, table.*.

-- 32-битные операции над беззнаковыми (0 .. 2^32-1), только арифметика ──

local function xb(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local x, y = a % 16, b % 16
        local n, q = 0, 1
        for _ = 1, 4 do
            local xa, ya = x % 2, y % 2
            if xa ~= ya then n = n + q end
            x, y, q = (x - xa) / 2, (y - ya) / 2, q * 2
        end
        r = r + n * p
        a, b, p = (a - a % 16) / 16, (b - b % 16) / 16, p * 16
    end
    return r
end

local function band(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local x, y = a % 16, b % 16
        local n, q = 0, 1
        for _ = 1, 4 do
            local xa, ya = x % 2, y % 2
            if xa == 1 and ya == 1 then n = n + q end
            x, y, q = (x - xa) / 2, (y - ya) / 2, q * 2
        end
        r = r + n * p
        a, b, p = (a - a % 16) / 16, (b - b % 16) / 16, p * 16
    end
    return r
end

local MOD32 = 4294967296
local MAX32 = 4294967295

local function bnot(a) return MAX32 - a end
local function rshift(a, n) return floor(a / 2 ^ n) end
local function ror(a, n)
    n = n % 32
    if n == 0 then return a end
    return floor(a / 2 ^ n) + (a % 2 ^ n) * 2 ^ (32 - n)
end

-- SHA-256 (FIPS 180-4) ──

local K256 = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function u32be(v)
    return string.char(floor(v / 16777216) % 256, floor(v / 65536) % 256,
                       floor(v / 256) % 256, v % 256)
end

local function sha256(msg)
    local ml = #msg
    local bits = ml * 8
    local padz = (55 - ml) % 64
    local hi = floor(bits / MOD32)
    local lo = bits % MOD32
    local raw = msg .. "\128" .. string.rep("\0", padz) .. u32be(hi) .. u32be(lo)

    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

    local w = {}
    for off = 1, #raw, 64 do
        for i = 0, 15 do
            local p = off + i * 4
            w[i + 1] = floor(raw:byte(p) * 16777216) + raw:byte(p + 1) * 65536
                     + raw:byte(p + 2) * 256 + raw:byte(p + 3)
        end
        for i = 17, 64 do
            local a15, a2 = w[i - 15], w[i - 2]
            local s0 = xb(xb(ror(a15, 7), ror(a15, 18)), rshift(a15, 3))
            local s1 = xb(xb(ror(a2, 17), ror(a2, 19)), rshift(a2, 10))
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD32
        end

        local a, b, c, d, e, f, g, hh = h0, h1, h2, h3, h4, h5, h6, h7
        for t = 1, 64 do
            local S1 = xb(xb(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = xb(band(e, f), band(bnot(e), g))
            local temp1 = (hh + S1 + ch + K256[t] + w[t]) % MOD32
            local S0 = xb(xb(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = xb(xb(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) % MOD32
            hh, g, f = g, f, e
            e = (d + temp1) % MOD32
            d, c, b = c, b, a
            a = (temp1 + temp2) % MOD32
        end
        h0 = (h0 + a) % MOD32
        h1 = (h1 + b) % MOD32
        h2 = (h2 + c) % MOD32
        h3 = (h3 + d) % MOD32
        h4 = (h4 + e) % MOD32
        h5 = (h5 + f) % MOD32
        h6 = (h6 + g) % MOD32
        h7 = (h7 + hh) % MOD32
    end

    return u32be(h0) .. u32be(h1) .. u32be(h2) .. u32be(h3)
        .. u32be(h4) .. u32be(h5) .. u32be(h6) .. u32be(h7)
end

-- HMAC-SHA256 (RFC 2104) + hex ──

local function xorBytes(a, b)
    local t = {}
    for i = 1, #a do
        t[i] = string.char(xb(string.byte(a, i), string.byte(b, i)))
    end
    return table.concat(t)
end

local function hmacSha256(key, msg)
    if #key > 64 then key = sha256(key) end
    if #key < 64 then key = key .. string.rep("\0", 64 - #key) end
    -- \54 = 0x36, \92 = 0x5c (десятичные эскейпы: \xXX в Lua 5.1 не работает).
    local kip = xorBytes(key, string.rep("\54", 64))
    local kop = xorBytes(key, string.rep("\92", 64))
    return sha256(kop .. sha256(kip .. msg))
end

-- Hex вручную: string.format на этом движке игнорирует спецификаторы (гайд).
local HEX_DIGITS = "0123456789abcdef"

local function hexEncode(raw)
    local t = {}
    for i = 1, #raw do
        local b = string.byte(raw, i)
        local hi, lo = floor(b / 16), b % 16
        t[i] = HEX_DIGITS:sub(hi + 1, hi + 1) .. HEX_DIGITS:sub(lo + 1, lo + 1)
    end
    return table.concat(t)
end

-- ============ Каталог / поиск: api/search.php ============
-- Старые пути мертвы (живая проверка 2026-10-03): /search?type=tvshow&sort=views
-- отдаёт 0 карточек, admin-ajax action=phoenix_search — пусто. Работает только
-- GET /api/search.php с подписью HMAC-SHA256 и заголовками X-PX-*.

-- PhoenixSearch.public_key из инлайн-скрипта
-- phoenix-search-dropdown-script-js-extra: hex-строка идёт в HMAC КАК UTF-8
-- байты (как JS enc.encode(keyHex)), НЕ hex-decode. Публичный ключ → хардкод.
local PX_PUBLIC_KEY = "c8052e98457156515d839dd050a95ac1b862437995778d89422a45f117478009"

local function emptyCatalog()
    return { items = {}, hasNext = false }
end

-- Целое число в строку без научной нотации: tostring() на этом движке
-- даёт «1.7910077E9» вместо «1791007748», подпись становится невалидной.
local function intToStr(n)
    n = math.floor(n)
    if n < 0 then return "-" .. intToStr(-n) end
    if n < 10 then return string.char(48 + n) end
    return intToStr(math.floor(n / 10)) .. string.char(48 + n % 10)
end

-- GET api/search.php → {items, hasNext}. Канон подписи (9 полей через «:»):
--   ts:q:type:genre:status:year:season:page:sort
-- и обязан ТОЧНО совпадать со значениями в URL. TTL подписи 60–119 с —
-- подпись считается непосредственно перед запросом, os.time() в секундах.
-- Порядок и состав параметров URL менять нельзя: живой прогон 2026-10-03
-- прошёл только с этим каноном (порядок из search-page.js), сама же JS
-- в браузере чужой порядок/лишний параметр даёт total:0 — фильтруем
-- только значения, не конфигурацию запроса.
local function apiCatalog(q, ctype, status, sort, page)
    q = q or ""
    ctype = ctype or "tvshow"
    status = status or ""
    sort = sort or "views"
    page = page or 1

    local ts = os.time()
    local tsStr = intToStr(ts)
    local msg = table.concat(
        { tsStr, q, ctype, "", status, "", "", tostring(page), sort }, ":")
    local sig = hexEncode(hmacSha256(PX_PUBLIC_KEY, msg))

    local url = baseUrl .. "/api/search.php"
        .. "?type=" .. url_encode(ctype)
        .. "&genre=&status=" .. url_encode(status) .. "&year=&season="
        .. "&sort=" .. url_encode(sort)
        .. "&q=" .. url_encode(q)
        .. "&page=" .. tostring(page)
        .. "&per_page=25&dropdown=0"
        -- "_" — обязательный cache-bust: без него CF-кеш отдаёт чужой ответ.
        .. "&_=" .. tsStr .. tostring(math.random(1000, 9999))

    -- Referer обязателен (без него запрос не проходит — замерено).
    local r = http_get(url, {
        headers = {
            ["X-PX-Timestamp"] = tsStr,
            ["X-PX-Signature"] = sig,
            ["Referer"]        = baseUrl .. "/search/",
        },
    })
    if not r.success then
        log_error("AnimePhoenix: api/search.php — HTTP " .. tostring(r.code))
        return emptyCatalog()
    end

    local ok, data = pcall(json_parse, r.body)
    if not ok or type(data) ~= "table" or not data.success then
        log_error("AnimePhoenix: api/search.php — битый ответ")
        return emptyCatalog()
    end
    local d = type(data.data) == "table" and data.data or nil
    local results = d and type(d.results) == "table" and d.results or nil
    if not results then
        log_error("AnimePhoenix: api/search.php — нет data.results")
        return emptyCatalog()
    end

    local items = {}
    for _, it in ipairs(results) do
        if type(it) == "table" then
            local title = it.title_ar
            if type(title) ~= "string" or title == "" then title = it.title_en end
            local u = type(it.url) == "string" and it.url or ""
            if type(title) == "string" and title ~= "" and u ~= "" then
                local cover = type(it.thumbnail_url) == "string" and it.thumbnail_url or ""
                items[#items + 1] = {
                    title = string_clean(title),
                    url   = absUrl(u),
                    cover = cover ~= "" and absUrl(cover) or nil,
                }
            end
        end
    end

    local totalPages = toNumber(d.total_pages) or 0
    local hasNext = #items > 0
    if totalPages > 0 then hasNext = page < totalPages end
    return { items = items, hasNext = hasNext }
end

function getCatalogList(index)
    return apiCatalog("", "tvshow", "", "views", index + 1)
end

-- ============ Фильтры ============
-- Каталог идёт через api/search.php (см. выше). Допустимые значения — только
-- те, что живой прогон 2026-10-03 подтвердил непустой выдачей: genre кроме
-- action, season spring/winter, year кроме 2026/2002, status upcoming,
-- type all/blog, склейка genre+status — на стороне сайта отдают total:0,
-- поэтому в фильтры не выносим.

function getFilterList()
    return {
        {
            type         = "select",
            key          = "type",
            label        = "النوع",
            defaultValue = "tvshow",
            options = {
                { value = "tvshow", label = "مسلسلات" },
                { value = "movie",  label = "أفلام" },
            },
        },
        {
            type         = "select",
            key          = "status",
            label        = "الحالة",
            defaultValue = "",
            options = {
                { value = "",           label = "الكل" },
                { value = "releasing",  label = "مستمر" },
                { value = "completed",  label = "مكتمل" },
            },
        },
        {
            type         = "select",
            key          = "sort",
            label        = "الترتيب",
            defaultValue = "views",
            options = {
                { value = "views",     label = "الأكثر مشاهدة" },
                { value = "date",      label = "الأحدث" },
                { value = "relevance", label = "الأكثر صلة" },
            },
        },
    }
end

-- Значения фильтра принимаются только из белого списка: мусор из filters
-- (или неизвестное значение) молча заменяется дефолтом, иначе подпись
-- разойдётся с URL и API ответит total:0.
local FILTER_DEFAULTS = { type = "tvshow", status = "", sort = "views" }

local function filterValue(filters, key, allowed)
    local v = filters and filters[key]
    if type(v) == "string" and allowed[v] then return v end
    return FILTER_DEFAULTS[key]
end

function getCatalogFiltered(index, filters)
    local ctype = filterValue(filters, "type", { tvshow = true, movie = true })
    local status = filterValue(filters, "status",
        { [""] = true, releasing = true, completed = true })
    local sort = filterValue(filters, "sort",
        { views = true, date = true, relevance = true })
    return apiCatalog("", ctype, status, sort, index + 1)
end

-- ============ Поиск ============
-- type=all + sort=relevance (q=naruto → total=10, живая проверка 2026-10-03).

function getCatalogSearch(index, query)
    if not query or query == "" then return emptyCatalog() end
    return apiCatalog(query, "all", "", "relevance", index + 1)
end

-- ============ Карточка тайтла ============

-- Все JSON-LD блоки страницы; нераспарсенные блоки пропускаются.
local function jsonLdBlocks(body)
    local out = {}
    for _, s in ipairs(html_select(body, "script[type='application/ld+json']")) do
        local raw = s.html
        if type(raw) == "string" and raw ~= "" then
            local ok, data = pcall(json_parse, raw)
            if ok and type(data) == "table" then out[#out + 1] = data end
        end
    end
    return out
end

-- Блок самого тайтла: TVSeries у сериалов, Movie у фильмов.
local function jsonLdTitle(body)
    for _, d in ipairs(jsonLdBlocks(body)) do
        if d["@type"] == "TVSeries" or d["@type"] == "Movie" then return d end
    end
    return nil
end

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1.FJ-Phoenix-Hero-Title")
        or html_select_first(body, "h1.FJ-CC-Title") -- фоллбэк из референса
    if el then
        local title = string_clean(el.text)
        if title ~= "" then return title end
    end
    -- Фоллбэк для фильма (/movies/…): h1 не подтверждён — <title>/og:title/JSON-LD.
    local show = jsonLdTitle(body)
    if show and type(show.name) == "string" then
        local title = string_clean(show.name)
        if title ~= "" then return title end
    end
    local og = html_attr(body, "meta[property='og:title']", "content")
    if type(og) == "string" and og ~= "" then return string_clean(og) end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local src = html_attr(body, ".FJ-Phoenix-Hero-Poster > img", "src")
    -- Фоллбэк для фильма: og:image подтверждён на /movies/…, h1-постер — нет.
    if type(src) ~= "string" or src == "" then
        src = html_attr(body, "meta[property='og:image']", "content")
    end
    if type(src) ~= "string" or src == "" then return nil end
    return absUrl(src)
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".FJ-Phoenix-Desc-Full")
    if not el then return nil end
    -- Длинный текст — string_trim по правилу из гайда.
    local text = string_trim(el.text)
    if text == "" then return nil end
    return text
end

-- getBookLastUpdate не реализована: надёжного источника даты обновления на
-- странице нет — не реализуем, чтобы не гадать.

-- Статус — ТОЛЬКО в div.FJ-Phoenix-Hero-Tags: ссылка /search/(completed|
-- releasing|upcoming), текст = Completed|Releasing|Upcoming. Ловушка: шапка и
-- футер на ЛЮБОЙ странице содержат такие же относительные ссылки, поэтому
-- фильтруем поэлементно внутри контейнера. Порядок тегов непредсказуем.
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, a in ipairs(html_select(body, "div.FJ-Phoenix-Hero-Tags a")) do
        local href = type(a.href) == "string" and a.href or ""
        -- regex_match (Java) — Lua-паттерны не умеют альтернацию.
        local m = regex_match(href, "/search/(completed|releasing|upcoming)")
        if m and m[1] then
            local text = string_clean(a.text)
            if text ~= "" then return text end
        end
    end
    return nil
end

-- Жанры: JSON-LD genre[] на всех типах страниц — чередование арабский/английский
-- ['أكشن','Action',…] → плагин на ar берёт каждый второй с 1-го (арабские).
function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local show = jsonLdTitle(body)
    local genre = show and show.genre
    if type(genre) == "table" then
        local out = {}
        for i = 1, #genre, 2 do
            if type(genre[i]) == "string" then
                local t = string_clean(genre[i])
                if t ~= "" then out[#out + 1] = t end
            end
        end
        if #out > 0 then return out end
    end

    -- Фоллбэк без JSON-LD: первый div.FJ-Modern-Tags внутри Hero-Tags — блок
    -- «الأقسام» (в нём только жанры; возможен мусор Bluray — примирись).
    local box = html_select_first(body, "div.FJ-Phoenix-Hero-Tags div.FJ-Modern-Tags")
    if not box then return {} end
    local out = {}
    for _, a in ipairs(html_select(box.html, "a")) do
        local t = string_clean(a.text)
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end

-- Рейтинг из JSON-LD aggregateRating (по шкале 10 → "Rating: N/10").
function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local show = jsonLdTitle(body)
    local agg = show and show.aggregateRating
    if type(agg) ~= "table" then return nil end
    local v = toNumber(agg.ratingValue)
    if not v then return nil end
    return "Rating: " .. tostring(v) .. "/10"
end

-- ============ Серии ============

local function watchButton(body)
    return html_select_first(body, "a.FJ-Btn-Watch")
end

-- AJAX-пагинация серий: на странице {url}/episodes лежит
-- fjPageData = {ajaxurl, token, sig}, счётчик страниц — div#pagination[data-total]
-- (18 карточек/стр). Всё через прямые http_get, без fetchPage (гайд).
local function episodesMeta(bookUrl)
    local url = bookUrl:gsub("/+$", "") .. "/episodes"
    local r = http_get(url)
    if not r.success then
        log_error("AnimePhoenix: страница серий — HTTP " .. tostring(r.code))
        return nil
    end
    local info = nil
    local blob = r.body:match("fjPageData%s*=%s*(%b{})")
    if blob then
        local ok, data = pcall(json_parse, blob)
        if ok and type(data) == "table" then info = data end
    end
    local pages = toNumber(html_attr(r.body, "#pagination", "data-total")) or 0
    return { url = url, body = r.body, info = info, pages = floor(pages) }
end

-- URL страницы AJAX-списка серий. page идёт ровно по data-total (сервер клампит
-- page > totalPages к последней — больше не запрашиваем).
local function episodesAjaxUrl(meta, page, sort)
    local a = meta.info
    if type(a) ~= "table" or type(a.ajaxurl) ~= "string" or a.ajaxurl == "" then
        return nil
    end
    local sep = a.ajaxurl:find("?", 1, true) and "&" or "?"
    return a.ajaxurl .. sep .. "action=fj_get_episodes"
        .. "&token=" .. url_encode(tostring(a.token or ""))
        .. "&sig=" .. url_encode(tostring(a.sig or ""))
        .. "&page=" .. tostring(page)
        .. "&sort=" .. sort
end

-- Карточка серии: заголовок — .FJ-Phoenix-Anastasia-EpCard-Name (string_clean),
-- URL — href карточки. Пустой заголовок → бейдж-номер / номер из суффикса
-- -episode-N. SSR-страница 1 и AJAX-ответ используют один и тот же разбор.
local function parseEpisodeCards(html, selector)
    local items = {}
    for _, card in ipairs(html_select(html, selector)) do
        local href = type(card.href) == "string" and card.href or ""
        if href ~= "" then
            local el = html_select_first(card.html, ".FJ-Phoenix-Anastasia-EpCard-Name")
            local title = el and string_clean(el.text) or ""
            if title == "" then
                local badge = html_select_first(card.html, ".badge-number")
                title = badge and string_clean(badge.text) or ""
            end
            if title == "" then
                local n = href:match("%-episode%-(%d+)")
                if n then title = "الحلقة " .. n end
            end
            if title ~= "" then
                items[#items + 1] = { title = title, url = absUrl(href) }
            end
        end
    end
    return items
end

-- Сериал: SSR-страница 1 (/episodes) + AJAX-страницы 2..total батчем.
-- sort=oldest уже даёт хронологический порядок (page1 = 1..18, page2 = 19..36) —
-- НЕ разворачиваем. Раньше список генерировался из numberOfEpisodes JSON-LD и
-- врал: у bleach его нет, у идущих тайтлов там запланированное число.
function getChapterList(bookUrl)
    -- Прямой запрос, не fetchPage: список глав не читается из кэша (гайд).
    local r = http_get(bookUrl)
    if not r.success then return {} end
    local body = r.body

    -- Фильм: одна «серия» — кнопка просмотра. Формат URL — единственный
    -- признак: у сериалов кнопка FJ-Btn-Watch тоже есть (ведёт на episode-1).
    local watch = watchButton(body)
    if bookUrl:find("/movies/", 1, true) then
        local url = watch and absUrl(watch.href) or ""
        if url == "" then
            -- Фоллбэк референса AnimePhoenixProvider: <url>/watch — сверить
            -- на устройстве, что кнопки у фильма действительно нет.
            url = bookUrl:gsub("/+$", "") .. "/watch"
        end
        return { { title = "الفيلم", url = url } }
    end

    local meta = episodesMeta(bookUrl)
    if not meta then return {} end
    if meta.pages <= 0 then return {} end -- серий нет

    local cards = parseEpisodeCards(meta.body, "#episodesGrid a.FJ-episode-wrap")
    if #cards == 0 then
        -- Обёртки #episodesGrid нет — пробуем плоский селектор на SSR-теле;
        -- если и он пуст, страница 1 уходит в AJAX ниже.
        cards = parseEpisodeCards(meta.body, "a.FJ-episode-wrap")
    end

    -- Страницы, которых нет в SSR-теле: 1 (если карточек не нашли) и 2..total.
    local pages = {}
    if #cards == 0 then pages[#pages + 1] = 1 end
    for p = 2, meta.pages do pages[#pages + 1] = p end

    if #pages > 0 then
        local urls = {}
        for _, p in ipairs(pages) do
            local u = episodesAjaxUrl(meta, p, "oldest")
            if not u then
                log_error("AnimePhoenix: нет fjPageData (ajaxurl/token/sig)")
                return cards
            end
            urls[#urls + 1] = u
        end
        local results = http_get_batch(urls, {
            headers = {
                ["Referer"]          = meta.url,
                ["X-Requested-With"] = "XMLHttpRequest",
            },
        })
        for i, res in ipairs(results) do
            local html = nil
            if res.success then
                local ok, data = pcall(json_parse, res.body)
                if ok and type(data) == "table" and type(data.data) == "table"
                    and type(data.data.html) == "string" then
                    html = data.data.html
                end
            end
            if type(html) == "string" and html ~= "" then
                -- Ответ AJAX — ПЛОСКИЙ фрагмент, обёртки #episodesGrid НЕТ.
                local batch = parseEpisodeCards(html, "a.FJ-episode-wrap")
                for _, it in ipairs(batch) do cards[#cards + 1] = it end
            else
                log_error("AnimePhoenix: episodes page " .. tostring(pages[i])
                    .. " — не удалось получить список (HTTP "
                    .. tostring(res.code) .. ")")
            end
        end
    end
    return cards
end

function getChapterListHash(bookUrl)
    -- Только прямой http_get: кэш сделал бы хэш неактуальным (гайд).
    local r = http_get(bookUrl)
    if not r.success then return nil end
    if bookUrl:find("/movies/", 1, true) then
        return "movie" -- список у фильма неизменяем (не по watch-кнопке:
        -- у сериалов она тоже есть и ведёт на episode-1)
    end

    local meta = episodesMeta(bookUrl)
    if not meta then return nil end
    if meta.pages <= 0 then return "0" end -- серий нет

    -- Хэш = номер последнего эпизода (меняется при каждом новом эпизоде):
    -- AJAX page=1&sort=newest → первая карточка = самый свежий эпизод.
    local u = episodesAjaxUrl(meta, 1, "newest")
    if u then
        local res = http_get(u, {
            headers = {
                ["Referer"]          = meta.url,
                ["X-Requested-With"] = "XMLHttpRequest",
            },
        })
        if res.success and type(res.body) == "string" then
            local ok, data = pcall(json_parse, res.body)
            local html = ok and type(data) == "table" and type(data.data) == "table"
                and data.data.html or nil
            if type(html) == "string" and html ~= "" then
                local card = html_select_first(html, "a.FJ-episode-wrap")
                local href = card and card.href or ""
                local n = type(href) == "string" and href:match("%-episode%-(%d+)") or nil
                if n then return tostring(n) end
            end
        end
    end
    -- Фоллбэк при упавшем AJAX: число страниц списка (меняется реже).
    return tostring(meta.pages)
end

-- ============ Потоки ============

local function pushSource(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

-- Хосты, которые никогда не дают прямую ссылку чистым HTTP (JS-превью) —
-- пропускаются до похода в сеть, включая причину (гайд «Стандарт getVideoList»).
local SKIP_HOSTS = {
    { pattern = "docs%.google",  reason = "Google Docs: превью на JS" },
    { pattern = "mega%.nz",      reason = "mega.nz: работает только через JS-API" },
    -- Ниже — хосты, embed которых не отдаёт плеер (замерено живьём):
    { pattern = "vidbem",        reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа, а не плеер (живьём 2026-10-03)" },
    { pattern = "fembed",        reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа, а не плеер (живьём 2026-10-03)" },
    { pattern = "vup",           reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа, а не плеер (живьём 2026-10-03)" },
    { pattern = "uqload",        reason = "embed — только POST-форма /dl, sources/packed нет — референс UqloadExtractor даёт пусто (живьём 2026-10-02)" },
    { pattern = "uptostream",    reason = "хост лежит: Cloudflare 522 (origin down), затем нет соединения (curl 000) — embed недоступен" },
}

-- Таймаут батча эмбедов (мс): бюджет одной попытки вместо лестницы ретраев
-- клиента (3+3+3+3+15 с) — один мёртвый embed не тормозит весь батч (гайд
-- «Стандарт getVideoList»; как в ru/yummyanime.lua).
local BATCH_TIMEOUT = 8000

local function skipReason(link)
    local low = link:lower()
    for _, h in ipairs(SKIP_HOSTS) do
        if low:find(h.pattern) then return h.reason end
    end
    return nil
end

local function hostLabel(link)
    local host = link:match("^https?://([^/]+)") or link
    return (host:gsub("^www%.", ""))
end

-- Google Drive → прямой поток (проверено живьём 2026-10-03): usercontent с
-- confirm=t отдаёт 206 без единого заголовка, для файлов >100 МБ хватает
-- confirm=t (интерстишл с формой #download-form на практике не встречался).
-- ponytail: playback-API-фоллбэк для «download disabled» (403 + UA-биндинг)
-- не делаем — ставим, если на сайте реально встретятся залоченные ссылки.
local function driveDirectUrl(link)
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

-- URL-декод содержимого data-server: percent-последовательности, «+» — пробел
-- (форм-семантика, как у URLDecoder в референсе AnimePhoenixProvider).
local function percentDecode(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("+", " ")
    return (s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- data-server = base64(URI-кодированный JSON {name, type, link, date}).
local function decodeServer(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local packed = (raw:gsub("%s+", ""))
    local decoded = base64_decode(packed)
    if type(decoded) ~= "string" or decoded == "" then return nil end
    local json = percentDecode(decoded)
    if not json then return nil end
    local ok, data = pcall(json_parse, json)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

-- Прямые ссылки из страницы плеера: переменная streamUrl (собственный плеер),
-- явные .m3u8/.mp4/.mkv в разметке. strict=true — только явные медиа-суффиксы,
-- иначе хост вида mp4upload.com матчится паттерном ".mp4" и даёт ссылку на
-- саму страницу плеера.
local function directLinks(body)
    local out, seen = {}, {}
    local function add(u, strict)
        u = u:gsub("&amp;", "&")
        if seen[u] then return end
        if strict and not hasMediaExt(u) then return end
        seen[u] = true
        out[#out + 1] = u
    end
    local stream = body:match('streamUrl%s*=%s*"([^"]+)"')
        or body:match("streamUrl%s*=%s*'([^']+)'")
    if stream then add(stream, false) end
    for u in body:gmatch('https?://[^"\'%s<>]+%.m3u8[^"\'%s<>]*') do add(u, true) end
    for u in body:gmatch('https?://[^"\'%s<>]+%.mp4[^"\'%s<>]*') do add(u, true) end
    -- Сайт раздаёт MKV — сканируем и его.
    for u in body:gmatch('https?://[^"\'%s<>]+%.mkv[^"\'%s<>]*') do add(u, true) end
    return out
end

-- ---- ok.ru: data-options → flashvars.metadata (порт из ar/witanime.lua) ----
-- Embed уже загружен батчем — тело берём отсюда, без второго http_get.
local function resolveOkRu(body, link)
    local opts = body:match('data%-options="([^"]+)"')
    if not opts then
        log_error("AnimePhoenix: ok.ru — нет data-options (" .. link .. ")")
        return nil
    end
    opts = opts:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<")
        :gsub("&gt;", ">"):gsub("&amp;", "&")
    local ok, data = pcall(json_parse, opts)
    if not ok or type(data) ~= "table" then
        log_error("AnimePhoenix: ok.ru — data-options не разобрался (" .. link .. ")")
        return nil
    end
    local meta = data.flashvars and data.flashvars.metadata
    if type(meta) == "string" then
        local mok, m = pcall(json_parse, meta)
        meta = mok and m or nil
    end
    if type(meta) ~= "table" then
        log_error("AnimePhoenix: ok.ru — нет metadata (" .. link .. ")")
        return nil
    end

    local out = {}
    if type(meta.hlsManifestUrl) == "string" and meta.hlsManifestUrl ~= "" then
        out[#out + 1] = meta.hlsManifestUrl
    end
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            if type(u) == "string" and u ~= "" then out[#out + 1] = u end
        end
    end
    if #out == 0 then
        log_error("AnimePhoenix: ok.ru — пустая metadata (" .. link .. ")")
        return nil
    end
    return out
end

-- ---- 4shared (порт SharedExtractor.kt из ar/anime4up.lua) ----
-- Embed уже загружен батчем: первый <source src> — и есть прямая ссылка.
local function resolveShared(body, link)
    local src = html_attr(body, "source", "src")
    if type(src) ~= "string" or src == "" then
        log_error("AnimePhoenix: 4shared — в embed нет <source> (" .. link .. ")")
        return nil
    end
    -- Референс отдаёт attr("src") как есть; абсолютным делаем только
    -- protocol-relative/относительные значения — иначе плеер их не откроет.
    if not string_starts_with(src, "http") then
        if string_starts_with(src, "//") then
            src = "https:" .. src
        else
            src = url_resolve(link, src)
        end
    end
    return { src }
end

-- type == "iframe": link содержит HTML <iframe …> — вытаскиваем src.
local function iframeSrc(html)
    local el = html_select_first(html, "iframe")
    if not el then return nil end
    local src = el.src
    if type(src) ~= "string" or src == "" then return nil end
    return absUrl(src)
end

function getVideoList(episodeUrl)
    local page = http_get(episodeUrl)
    if not page.success then
        log_error("AnimePhoenix: страница эпизода — HTTP " .. tostring(page.code))
        return nil
    end

    -- Серверы: только a[data-server] несёт полезную нагрузку;
    -- .FJ-DL-Server-Btn (data-server-hash) — голый хэш, не берётся.
    local candidates, batchUrls, batchEntries = {}, {}, {}

    for _, el in ipairs(html_select(page.body, "a[data-server]")) do
        local info = decodeServer(el:attr("data-server"))
        if info then
            local link = type(info.link) == "string" and info.link or ""
            if info.type == "iframe" and link:find("<iframe", 1, true) then
                link = iframeSrc(link) or ""
            end
            if link ~= "" then
                local name = type(info.name) == "string" and info.name or ""
                if name == "" then name = hostLabel(link) end
                local reason = skipReason(link)
                local drive = driveDirectUrl(link)
                if reason then
                    log_error("AnimePhoenix: " .. name .. " — пропущен: " .. reason)
                elseif drive then
                    -- Без mime: контейнер (mp4/mkv) media3 распознает сниффером.
                    candidates[#candidates + 1] = {
                        url      = drive,
                        quality  = sourceLabel(name, link),
                        referer  = "https://drive.google.com/",
                    }
                elseif hasMediaExt(link) then
                    -- Уже прямая ссылка на медиа — резолвер не нужен.
                    candidates[#candidates + 1] = {
                        url      = link,
                        quality  = sourceLabel(name, link),
                        referer  = baseUrl,
                    }
                elseif info.type == "direct" then
                    -- Проверено живьём 2026-10-03: все direct-серверы отдают
                    -- один MKV на *.workers.dev. Расширения нет → mime,
                    -- иначе media3 откроет поток прогрессивным источником.
                    candidates[#candidates + 1] = {
                        url      = link,
                        quality  = sourceLabel(name, link),
                        mime     = "video/x-matroska",
                        referer  = baseUrl,
                    }
                else
                    -- Embed: все страницы одним батчем (гайд: один http_get_batch).
                    batchUrls[#batchUrls + 1] = link
                    batchEntries[#batchEntries + 1] = { name = name, link = link }
                end
            end
        end
    end

    if #batchUrls > 0 then
        local responses = http_get_batch(batchUrls, { timeout = BATCH_TIMEOUT })
        for i, e in ipairs(batchEntries) do
            local resp = responses[i]
            local body = type(resp) == "table" and resp.body or ""
            if type(body) ~= "string" or #body == 0 then
                log_error("AnimePhoenix: " .. e.name .. " — embed-страница недоступна")
            else
                -- Диспетчер по хосту: ok.ru и 4shared разбираются по своему
                -- формату, directLinks остаётся общим сканом-фоллбэком.
                local urls, low = nil, e.link:lower()
                if low:find("ok%.ru") then
                    urls = resolveOkRu(body, e.link)
                elseif low:find("4shared") then
                    urls = resolveShared(body, e.link)
                end
                if not urls or #urls == 0 then
                    urls = directLinks(body)
                end
                if #urls == 0 then
                    log_error("AnimePhoenix: " .. e.name .. " — нет прямой ссылки (плеер требует JS)")
                end
                for _, u in ipairs(urls) do
                    local c = {
                        url     = u,
                        quality = sourceLabel(e.name, u),
                        referer = e.link,
                    }
                    -- streamUrl без расширения — HLS-фоллбэк (как в anime4up);
                    -- медиа-расширение есть → mime не нужен.
                    if not hasMediaExt(u) then c.mime = "hls" end
                    candidates[#candidates + 1] = c
                end
            end
        end
    end

    -- Дедупликация по URL: все серверы отдают один и тот же файл —
    -- pushSource оставит первый.
    local sources, seen = {}, {}
    for _, c in ipairs(candidates) do
        pushSource(sources, seen, {
            url     = c.url,
            quality = c.quality,
            mime    = c.mime,
            headers = { ["Referer"] = c.referer },
        })
    end
    if #sources == 0 then return nil end

    -- Отсеивание мёртвых: HEAD-проба одним батчем (гайд: method="HEAD" +
    -- timeout — живость по HTTP-коду, тело файла не скачивается).
    -- Если ни одна проба не прошла (серверы режут HEAD) — список не трогаем:
    -- ложный отказ хуже, чем мёртвая ссылка, которую покажет плеер.
    local items = {}
    for _, s in ipairs(sources) do
        items[#items + 1] = { url = s.url, headers = s.headers }
    end
    local probes = http_get_batch(items, { method = "HEAD", timeout = 3000 })
    local kept, anyAlive = {}, false
    for i, s in ipairs(sources) do
        local r = probes[i]
        -- 405/501 — сервер жив, просто не принимает HEAD; не отсекаем.
        if type(r) == "table"
            and (r.success or r.code == 405 or r.code == 501) then
            anyAlive = true
            kept[#kept + 1] = s
        end
    end
    if anyAlive and #kept > 0 then return kept end
    return sources
end
