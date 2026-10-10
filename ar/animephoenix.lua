-- AnimePhoenix — видео-плагин NoveLA (content_type = "video")
-- Сайт: https://anime-phoenix.com — каталог аниме/фильмов, эпизоды, серверы плеера.

content_type = "video"
id           = "animephoenix"
name         = "Anime Phoenix"
version      = "1.1.0"
baseUrl      = "https://anime-phoenix.com"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/animephoenix.png"

local floor = math.floor

-- ============ Guard: engine-API + общие либы (новые сборки NoveLA) ============
-- Top-level обязан загрузиться без require_lib (иначе плагин молча исчезает из
-- списка источников) — pcall-tryLib-паттерн latanime (M9): ошибка сохраняется
-- в libErr и докладывается в ensureEngine.
local libErr = nil
local HAS_LIBS = type(require_lib) == "function"

local function tryLib(name)
    if not HAS_LIBS then return nil end
    local ok, res = pcall(require_lib, name)
    if not ok then libErr = tostring(res) return nil end
    return res
end

local URLS = tryLib("urls")
local HLS = tryLib("hls")
local OKRU = tryLib("okru")
local SHARED = tryLib("shared")
local UQLOAD = tryLib("uqload")

-- Канон (гайд «Паттерн guard»): проверяем только реально используемые API.
-- На старых сборках show_error + error рвут вызов и просят обновить приложение.
local function ensureEngine()
    local missing = {}
    if rawget(_G, "hmac_sha256") == nil then missing[#missing + 1] = "hmac_sha256" end
    if rawget(_G, "unpack_packed") == nil then missing[#missing + 1] = "unpack_packed" end
    if #missing > 0 then
        show_error("NoveLA update required",
            "This plugin needs new functions (" .. table.concat(missing, ", ") ..
            "). Update the app to the latest version.")
        error("A newer version of the app is required: " .. table.concat(missing, ","), 0)
    end
    if not HAS_LIBS then
        show_error("NoveLA update required",
            "This plugin needs shared libraries (require_lib). Update the app to the latest version.")
        error("A newer version of the app is required: require_lib", 0)
    end
    if not URLS or not HLS or not OKRU or not SHARED or not UQLOAD then
        show_error("Libraries not loaded",
            "Open the extensions screen and tap update, then restart the app. " .. (libErr or ""))
        error("Shared libraries not loaded", 0)
    end
end

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
-- Общая либа hls (union копий, включая .mkv из этого плагина).
-- Обёртка, не алиас: top-level обращение к полю nil-либы упало бы до
-- ensureEngine (плагин молча исчезает — инцидент фазы 1).
local function hasMediaExt(u)
    return HLS.hasMediaExt(u)
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
    local sig = hexEncode(hmac_sha256(PX_PUBLIC_KEY, msg))

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
    ensureEngine()
    return apiCatalog("", "tvshow", "", "views", index + 1)
end

-- ============ Фильтры ============
-- Каталог идёт через api/search.php (см. выше). Допустимые значения — только
-- те, что живой прогон 2026-10-03 подтвердил непустой выдачей: genre кроме
-- action, season spring/winter, year кроме 2026/2002, status upcoming,
-- type all/blog, склейка genre+status — на стороне сайта отдают total:0,
-- поэтому в фильтры не выносим.

function getFilterList()
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
-- Замеры обновлены 2026-10-05; uqload из списка убран — его embed
-- распаковывается (см. resolveUqload ниже).
local SKIP_HOSTS = {
    { pattern = "docs%.google",  reason = "Google Docs: превью на JS" },
    { pattern = "mega%.nz",      reason = "поток зашифрован AES-CTR и отдаётся чанками с Range — в движке нет крипто и частичных запросов" },
    -- Ниже — хосты, embed которых не отдаёт плеер (замерено живьём):
    { pattern = "vidbem",        reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер (живьём 2026-10-05)" },
    { pattern = "fembed",        reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер (живьём 2026-10-05)" },
    { pattern = "vup",           reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер (живьём 2026-10-05)" },
    { pattern = "uptostream",    reason = "DNS/TLS жив, HTTP не отвечает (живьём 2026-10-05)" },
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
-- Сборка прямой ссылки — общая либа urls (driveDirectUrl).

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
-- Embed уже загружен батчем — разбор тела общей либой okru, без http_get.
local function resolveOkRu(body, link)
    local list = OKRU.resolveOkRu(body)
    if #list == 0 then
        log_error("AnimePhoenix: ok.ru — нет источников (" .. link .. ")")
        return nil
    end
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = s.url end
    return out
end

-- ---- 4shared (SharedExtractor.kt через libs/hosters/shared.lua) ----
-- Embed уже загружен батчем: первый <source src> — и есть прямая ссылка.
local function resolveShared(body, link)
    local src = SHARED.extract(body, link)
    if not src then
        log_error("AnimePhoenix: 4shared — в embed нет <source> (" .. link .. ")")
        return nil
    end
    return { src }
end

-- ---- uqload: embed (301 → uqload.vc) → packed-JS → jwplayer sources ----
-- Живьём 2026-10-05: /embed-<id>.html отдаёт распакованный
-- jwplayer("vplayer").setup({sources:[{file:"…/master.m3u8?…"}]}).
-- Раньше хост был в skip-листе («только POST-форма /dl, sources/packed нет») —
-- распаковка Packed-JS снимает этот отказ.
-- Распаковка и сбор ссылок — общая либа uqload (packedMediaUrls, там же —
-- комментарии про jwplayer/медиа-суффиксы); engine API unpack_packed
-- проверяется в ensureEngine.

local function uqloadSources(body, link)
    local urls, err = UQLOAD.packedMediaUrls(body)
    if not urls or #urls == 0 then
        log_error("AnimePhoenix: uqload — " .. (err or "нет источников в packed-JS") .. " (" .. link .. ")")
    end
    return urls or {}
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
    ensureEngine()
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
                local drive = URLS.driveDirectUrl(link)
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
                -- формату, uqload — распаковкой Packed-JS; directLinks
                -- остаётся общим сканом-фоллбэком.
                local urls, low = nil, e.link:lower()
                if low:find("ok%.ru") then
                    urls = resolveOkRu(body, e.link)
                elseif low:find("4shared") then
                    urls = resolveShared(body, e.link)
                elseif low:find("uqload") then
                    urls = uqloadSources(body, e.link)
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
