-- Anichin (anichin.moe) — видео-плагин для NoveLA (content_type = "video")
-- WordPress, тема AnimeStream. Каталог — /anime/?page=N (30 карточек на страницу),
-- карточки ведут на страницу серии /<slug>/. Эпизод —
-- /<slug>-episode-N-subtitle-indonesia/, сервер-лист эпизода — статичный
-- <select class="mirror">: значение option — base64 от <iframe src="...">,
-- сайт раскодирует его через atob (тот же приём, что в animexin).
--
-- Разведка и проверка резолверов — 2026-10-05 (см. комментарии по хостам).

id           = "anichin"
name         = "Anichin"
version      = "1.1.0"
baseUrl      = "https://anichin.moe"
language     = "id"
content_type = "video"
-- Иконка — favicon сайта (проверен 200): она квадратная (150x150),
-- в отличие от логотипа 270x50.
icon        = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/anichin.png"

local CATALOG = baseUrl .. "/anime/"
local SEARCH  = baseUrl .. "/?s="
local BATCH_TIMEOUT = 10000

-- ============ Guard: engine-API + общие либы (новые сборки NoveLA) ============
-- Top-level обязан загрузиться без require_lib (иначе плагин молча исчезает из
-- списка источников) — pcall-tryLib-паттерн latanime (M9): ошибка сохраняется
-- в libErr и докладывается в ensureEngine. Канон (гайд «Паттерн guard»):
-- проверяем только реально используемые API.
local libErr = nil
local HAS_LIBS = type(require_lib) == "function"

local function tryLib(name)
    if not HAS_LIBS then return nil end
    local ok, res = pcall(require_lib, name)
    if not ok then libErr = tostring(res) return nil end
    return res
end

local URLS = tryLib("urls")
local OKRU = tryLib("okru")
local DM = tryLib("dailymotion")
local DOOD = tryLib("dood")
local DTUBE = tryLib("dtube")
local MIRRORS = tryLib("mirrors")

local function ensureEngine()
    local missing = {}
    -- base64_decode декодирует значения option зеркал (либа mirrors);
    -- unpack_packed — packed-JS в общем page-резолвере.
    if rawget(_G, "unpack_packed") == nil then missing[#missing + 1] = "unpack_packed" end
    if rawget(_G, "base64_decode") == nil then missing[#missing + 1] = "base64_decode" end
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
    if not URLS or not OKRU or not DM or not DOOD or not DTUBE or not MIRRORS then
        show_error("Libraries not loaded",
            "Open the extensions screen and tap update, then restart the app. " .. (libErr or ""))
        error("Shared libraries not loaded", 0)
    end
end

local function absUrl(href)
    if type(href) ~= "string" or href == "" then return "" end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if href:find("^https?://") then return href end
    if href:sub(1, 1) == "/" then return baseUrl .. href end
    return baseUrl .. "/" .. href
end

-- hostOf/origin — общая либа urls (origin хоста (scheme://host/) берётся
-- как Referer для потоков). Обёртки, не алиасы: top-level обращение к полю
-- nil-либы упало бы до ensureEngine (инцидент фазы 1).
local function hostOf(url)
    return URLS.hostOf(url)
end

local function originOf(url)
    return URLS.origin(url)
end

-- Поиск в таблице: точное совпадение хоста или его суффикс (www.geo.поддомен).
local function lookup(map, host)
    local value = map[host]
    if value ~= nil then return value end
    for key, val in pairs(map) do
        if #host > #key + 1 and host:sub(-#key - 1) == "." .. key then
            return val
        end
    end
    return nil
end

------------------------------------------------------------------------------
-- Страница книги/каталога (один http_get на весь вызов движка)
------------------------------------------------------------------------------

local _pageCache = {}

local function fetchPage(url)
    local cached = _pageCache[url]
    if cached ~= nil then return cached end
    local r = http_get(url, { timeout = 15000 })
    if not r.success then
        log_error("Anichin: page request failed (HTTP " .. tostring(r.code) .. ") " .. url)
        return nil
    end
    _pageCache[url] = r.body
    return r.body
end

------------------------------------------------------------------------------
-- Каталог и поиск
------------------------------------------------------------------------------

-- Карточка: <a href="/<slug>/" itemprop="url" title="Название серии">.
local function itemToBook(html)
    local link = html_select_first(html, ".bsx a[itemprop=url]")
    if not link then return nil end
    local href = link.href
    local title = link.title
    if type(href) ~= "string" or href == "" then return nil end
    if type(title) ~= "string" or title == "" then title = html_text(link.html) end
    if type(title) ~= "string" or title == "" then return nil end
    local book = { title = string_clean(title), url = absUrl(href) }
    local img = html_select_first(html, "img.ts-post-image")
    if img and type(img.src) == "string" and img.src ~= "" then
        book.cover = absUrl(img.src)
    end
    return book
end

local function collectBooks(body)
    local items = {}
    if type(body) ~= "string" then return items end
    for _, art in ipairs(html_select(body, "article.bs")) do
        local book = itemToBook(art.html)
        if book then table.insert(items, book) end
    end
    return items
end

-- «Next» в .hpage — <a href="?page=2" class="r">Selanjutnya</a>.
local function catalogHasNext(body)
    local hpage = html_select_first(body, ".hpage")
    if not hpage then return false end
    return html_select_first(hpage.html, "a.r") ~= nil
end

function getCatalogList(index)
    ensureEngine()
    index = tonumber(index) or 0
    local body = fetchPage(CATALOG .. "?page=" .. (index + 1))
    if not body then return { items = {}, hasNext = false } end
    return { items = collectBooks(body), hasNext = catalogHasNext(body) }
end

------------------------------------------------------------------------------
-- Фильтры каталога
------------------------------------------------------------------------------

-- Форма /anime/: чекбоксы жанров name="genre[]" (несколько сразу — каждый
-- повторяется как genre[]=slug) + select name="order". Значение жанра —
-- slug с сайта (проверено вживую: регистр в URL не важен, пробелы вместо
-- дефисов ломают фильтр), label — читаемая форма.

local GENRE_OPTIONS = {
    { value = "a", label = "A" },
    { value = "action", label = "Action" },
    { value = "actions", label = "Actions" },
    { value = "adven", label = "Adven" },
    { value = "adventure", label = "Adventure" },
    { value = "blood", label = "Blood" },
    { value = "comedy", label = "Comedy" },
    { value = "crossdressing", label = "Crossdressing" },
    { value = "cultivation", label = "Cultivation" },
    { value = "demons", label = "Demons" },
    { value = "drama", label = "Drama" },
    { value = "ecchi", label = "Ecchi" },
    { value = "fantasy", label = "Fantasy" },
    { value = "friendship", label = "Friendship" },
    { value = "game", label = "Game" },
    { value = "gore", label = "Gore" },
    { value = "gourmet", label = "Gourmet" },
    { value = "guoman", label = "Guoman" },
    { value = "harem", label = "Harem" },
    { value = "historical", label = "Historical" },
    { value = "horror", label = "Horror" },
    { value = "isekai", label = "Isekai" },
    { value = "life", label = "Life" },
    { value = "magic", label = "Magic" },
    { value = "martial-arts", label = "Martial Arts" },
    { value = "mecha", label = "Mecha" },
    { value = "military", label = "Military" },
    { value = "music", label = "Music" },
    { value = "mystery", label = "Mystery" },
    { value = "psychological", label = "Psychological" },
    { value = "reincaranation", label = "Reincaranation" },
    { value = "reincarnation", label = "Reincarnation" },
    { value = "romance", label = "Romance" },
    { value = "school", label = "School" },
    { value = "sci-fi", label = "Sci-Fi" },
    { value = "shoujo", label = "Shoujo" },
    { value = "shounen", label = "Shounen" },
    { value = "slice", label = "Slice" },
    { value = "slice-of-life", label = "Slice of Life" },
    { value = "space", label = "Space" },
    { value = "sports", label = "Sports" },
    { value = "super-power", label = "Super Power" },
    { value = "supernatural", label = "Supernatural" },
    { value = "suspence", label = "Suspence" },
    { value = "suspense", label = "Suspense" },
    { value = "thriller", label = "Thriller" },
    { value = "time-travel", label = "Time Travel" },
    { value = "urban-fantasy", label = "Urban Fantasy" },
    { value = "vampire", label = "Vampire" },
    { value = "video-game", label = "Video Game" },
    { value = "youth", label = "Youth" },
}

function getFilterList()
    ensureEngine()
    return {
        {
            type         = "select",
            key          = "order",
            label        = "Order by",
            defaultValue = "",
            options      = {
                { value = "",             label = "Default" },
                { value = "title",        label = "A-Z" },
                { value = "titlereverse", label = "Z-A" },
                { value = "update",       label = "Latest Update" },
                { value = "latest",       label = "Latest Added" },
                { value = "popular",      label = "Popular" },
                { value = "rating",       label = "Rating" },
            },
        },
        {
            type    = "checkbox",
            key     = "genre",
            label   = "Genre",
            options = GENRE_OPTIONS,
        },
    }
end

-- Мультивыбор чекбоксов приходит ключом <key>_included (таблица-массив строк).
function getCatalogFiltered(index, filters)
    ensureEngine()
    index = tonumber(index) or 0
    local page = index + 1
    local params = { "page=" .. page }
    local genres = filters and filters["genre_included"] or {}
    if type(genres) == "table" then
        for _, v in ipairs(genres) do
            if type(v) == "string" and v ~= "" then
                params[#params + 1] = "genre%5B%5D=" .. url_encode(v)
            end
        end
    end
    local order = filters and filters["order"] or ""
    if type(order) == "string" and order ~= "" then
        params[#params + 1] = "order=" .. url_encode(order)
    end
    local body = fetchPage(CATALOG .. "?" .. table.concat(params, "&"))
    if not body then return { items = {}, hasNext = false } end
    return { items = collectBooks(body), hasNext = catalogHasNext(body) }
end

-- Поиск: 10 результатов на страницу, первая — /?s=q, дальше /page/N/?s=q
-- (проверено вживую: ссылка «Next» — a.next.page-numbers).
function getCatalogSearch(index, query)
    ensureEngine()
    index = tonumber(index) or 0
    if type(query) ~= "string" or query == "" then
        return { items = {}, hasNext = false }
    end
    local q = url_encode(query)
    local url = SEARCH .. q
    if index > 0 then url = baseUrl .. "/page/" .. (index + 1) .. "/?s=" .. q end
    local body = fetchPage(url)
    if not body then return { items = {}, hasNext = false } end
    local items = collectBooks(body)
    local hasNext = string.find(body, 'class="next page-numbers"', 1, true) ~= nil
    -- На первой странице блок пагинации может отсутствовать — тогда пустой
    -- следующий запрос просто остановит цикл.
    if not hasNext and index == 0 then hasNext = #items > 0 end
    return { items = items, hasNext = hasNext }
end

------------------------------------------------------------------------------
-- Страница серии
------------------------------------------------------------------------------

function getBookTitle(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1.entry-title")
    if el then
        local text = string_clean(html_text(el.html))
        if text ~= "" then return text end
    end
    local t = html_select_first(body, "title")
    if not t then return nil end
    local text = string_clean(html_text(t.html))
    return text ~= "" and text or nil
end

function getBookCoverImageUrl(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- og:image на этом сайте относительный ("/wp-content/uploads/...").
    local url = html_attr(body, 'meta[property="og:image"]', "content")
    if type(url) ~= "string" or url == "" then
        local img = html_select_first(body, ".thumb img")
        if img then url = img.src end
    end
    if type(url) ~= "string" or url == "" then return nil end
    local cover = absUrl(url)
    return cover ~= "" and cover or nil
end

function getBookDescription(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".bixbox.synp .entry-content")
    if not el then return nil end
    local text = string_trim(html_text(el.html))
    return text ~= "" and text or nil
end

-- .spe — плоский список «Метка: значение», значения сайта: Ongoing / Completed.
function getBookStatus(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".spe")
    if not el then return nil end
    local status = string_clean(html_text(el.html)):match("Status:%s*([%w]+)")
    if not status or status == "" then return nil end
    return status
end

function getBookRating(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local value = html_attr(body, 'meta[itemprop="ratingValue"]', "content")
    if type(value) ~= "string" then return nil end
    value = string_clean(value)
    if not tonumber(value) then return nil end
    return "Rating: " .. value .. "/10"
end

function getBookGenres(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, ".genxed a")) do
        local text = string_clean(html_text(a.html))
        if text ~= "" then table.insert(genres, text) end
    end
    return genres
end

-- Эпизоды: .eplister li a (список полный, от новых к старым — разворачиваем).
-- .epl-num — номер, .epl-date — дата релиза ("January 28, 2026").
function getChapterList(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local rows = {}
    for _, li in ipairs(html_select(body, ".eplister li")) do
        local link = html_select_first(li.html, "a[href]")
        if link then
            local href = link.href
            if type(href) == "string" and href ~= "" then
                local num = html_select_first(li.html, ".epl-num")
                local label = num and string_clean(html_text(num.html)) or nil
                if not label or label == "" then label = string_clean(link.text) end
                rows[#rows + 1] = {
                    title = "Episode " .. (label or tostring(#rows + 1)),
                    url   = absUrl(href),
                }
            end
        end
    end
    local chapters, seen = {}, {}
    for i = #rows, 1, -1 do
        local row = rows[i]
        if not seen[row.url] then
            seen[row.url] = true
            chapters[#chapters + 1] = row
        end
    end
    return chapters
end

------------------------------------------------------------------------------
-- Хостеры: план запроса → ссылки потока
------------------------------------------------------------------------------

-- Хосты без рабочей схемы — отсекаются ДО сетевого запроса (причина обязательна).
-- Проверено живьём 2026-10-05:
--   rubyvidhub.com / streamruby.com / rubystm.com — TCP не поднимается (0 байт).
--   turbovidhls.com — соединение не устанавливается вовсе (curl code 000).
--   mega.nz — поток зашифрован AES-CTR, прямую ссылку не отдать.
--   anichin.rpmvid.com (RPMShare) — SPA: ответы /api/v1/info?id= и
--      /api/v1/video?id=...&w=&h=&r= приходят шифрованными (hex), а расшифровка
--      в JS — AES-GCM через WebCrypto с IV от location.host + hash; в движке есть
--      только aes_decrypt (AES/CBC) — расшифровать нельзя.
--   abyssplayer.com / player.abyssplayer.com / short.icu / short.ink (New Player;
--      replace-domain.js переписывает short.* на abyssplayer/mobamark2021) —
--      в HTML base64-blob {slug, md5_id, media, ...}, поле media шифруется в
--      lite.bundle.js (iamcdn.net) — прямой ссылки в странице нет.
--   odysee.com — SPA-оболочка, подписи LBRY-запросов (как в animexin).
--   racaty.my.id — гейт-хостер, ответ 502 без содержимого.
--   short.icu / short.ink (New Player) — соединение не устанавливается (000).
--   listeamed.net (VidGuard) / strwish.com (StreamWish) — страница отдаёт
--      только JS-заглушку («Loading…» + main.js), прямой ссылки в HTML нет.
local SKIP_HOSTS = {
    ["rubyvidhub.com"]     = "TCP не отвечает (мертв)",
    ["streamruby.com"]     = "TCP не отвечает (мертв)",
    ["rubystm.com"]        = "TCP не отвечает (мертв)",
    ["turbovidhls.com"]    = "соединение не устанавливается (000)",
    ["mega.nz"]            = "шифрованный AES-CTR поток, прямой ссылки нет",
    ["anichin.rpmvid.com"] = "API отвечает AES-GCM (движок умеет только CBC)",
    ["abyssplayer.com"]    = "media в странице шифруется в lite.bundle.js",
    ["short.icu"]          = "соединение не устанавливается (000)",
    ["short.ink"]          = "соединение не устанавливается (000)",
    ["listeamed.net"]      = "JS-заглушка (VidGuard), прямой ссылки в HTML нет",
    ["strwish.com"]        = "JS-заглушка (StreamWish), прямой ссылки в HTML нет",
    ["odysee.com"]         = "SPA-оболочка, подписи LBRY недоступны",
    ["racaty.my.id"]       = "гейт-хостер, ответ 502",
}

-- Реестр резолверов по типу запроса. Всё уходит в один http_get_batch.
--   ok.ru       — embed c Referer https://ok.ru/ → data-options →
--                 flashvars.metadata → hlsManifestUrl + videos[].url.
--   dailymotion — player.nunadrama.sbs/index.php?video=<id> — это прокси
--                 dailymotion: сам embed отвечает 404 («Can't find object video»)
--                 на части id, но id в параметре совпадает с dailymotion-id
--                 (проверено: из страницы берётся ровно такой же iframe
--                 geo.dailymotion.com/player/...?video=<id>), поэтому метаданные
--                 запрашиваются напрямую: /player/metadata/video/<id> →
--                 qualities.auto[].url (application/x-mpegURL).
--   dtube       — play.d.tube — SPA, но api.d.tube/videos/<id> открыто →
--                 video_url (master.m3u8).
--   page        — прочие хосты: embed целиком, в теле ищем готовые m3u8/mp4,
--                 включая распаковку packed-JS (VidHide: eval(function(p,a,c…)).
local HOST_OKRU    = { ["ok.ru"] = true }
local HOST_DM      = { ["player.nunadrama.sbs"] = true, ["dailymotion.com"] = true }
local HOST_DTUBE   = { ["play.d.tube"] = true }

local function planRequest(embed)
    local host = hostOf(embed)

    if lookup(HOST_OKRU, host) then
        return {
            url      = embed,
            headers  = { ["Referer"] = "https://ok.ru/" },
            resolver = "okru",
            referer  = "https://ok.ru/",
        }
    end

    -- Nunadrama/Dailymotion: https://www.dailymotion.com/player/metadata/video/<id>
    local dmId = nil
    if lookup(HOST_DM, host) then
        dmId = embed:match("[?&]video=([^&]+)")
        if not dmId then dmId = embed:match("/video/([%w%-]+)") end
    end
    if dmId and dmId ~= "" then
        return {
            url      = "https://www.dailymotion.com/player/metadata/video/" .. dmId,
            headers  = { ["Referer"] = "https://www.dailymotion.com/" },
            resolver = "dailymotion",
            referer  = "https://www.dailymotion.com/",
        }
    end

    if lookup(HOST_DTUBE, host) then
        local id = embed:match("[?&]v=([^&#]+)")
        if id and id ~= "" then
            return {
                url      = "https://api.d.tube/videos/" .. id,
                headers  = { ["Referer"] = "https://play.d.tube/" },
                resolver = "dtube",
                referer  = "https://play.d.tube/",
            }
        end
    end

    -- dood/playmogo (Dood): зеркала меняют домен — матч по подстроке.
    -- Сам embed — источник pass_md5; Referer для pass_md5 и для финального
    -- потока — он же (job.referer уходит и в батч, и в headers источника).
    local low = embed:lower()
    if low:find("dood", 1, true) or low:find("playmogo", 1, true)
        or low:find("dsvplay", 1, true) then
        return { url = embed, resolver = "dood", referer = embed }
    end

    -- Всё остальное — просто страница embed; Referer для потока = её origin.
    return { url = embed, resolver = "page", referer = originOf(embed) }
end

------------------------------------------------------------------------------
-- Резолверы: тело ответа → { {url=..., mime?}, ... }
------------------------------------------------------------------------------
-- mime ставим только там, где расширения в URL нет: расширение .m3u8/.mp4
-- плеер распознаёт само (см. api-guide, «Видео-плагины» → mime).
------------------------------------------------------------------------------

-- ok.ru: data-options (entity-encoded) → JSON → flashvars.metadata —
-- общая либа okru; возвращает { {url, mime, name?}, ... }.
-- Обёртка, не алиас (см. комментарий у hostOf).
local function resolveOkRu(body)
    return OKRU.resolveOkRu(body)
end

-- dailymotion: body — metadata JSON из батча; разбор qualities.auto и
-- regex-фоллбэк — общая либа dailymotion (parseMetadata).
-- UNVERIFIED (воспроизведение): метаданные отдаются (200, URL извлекается), но
-- cdndirector.dailymotion.com отвечает 403 из тестовой сети при любом Referer —
-- подтвердить воспроизведение не удалось (та же ситуация, что в animexin).
-- Обёртка, не алиас (см. комментарий у hostOf).
local function resolveDailymotion(body)
    return DM.parseMetadata(body)
end

-- play.d.tube: {"video_url":"https://nas1.d.tube/videos/<uuid>/master.m3u8"}
-- — разбор JSON (video_url) — общая либа dtube.
-- Обёртка, не алиас (см. комментарий у hostOf).
local function resolveDTube(body)
    return DTUBE.resolve(body)
end

------------------------------------------------------------------------------
-- Packed JS (VidHide): eval(function(p,a,c,k,e,d){…}('payload',radix,count,
-- 'sym'.split('|'),0,0)) — Dean Edwards packer. Распаковка — engine API
-- unpack_packed: возвращает "", если упаковщика нет.
------------------------------------------------------------------------------

-- Прямая страница: ищем готовые ссылки (после разэкранирования \/), плюс
-- распаковываем packed-JS, если он есть (VidHide).
local function resolvePage(body)
    if type(body) ~= "string" then return {} end
    local flat = body:gsub("\\/", "/")
    local un = unpack_packed(flat)
    if un ~= "" then flat = flat .. "\n" .. un end
    local out, seen = {}, {}
    local function take(pattern)
        for url in flat:gmatch(pattern) do
            if not seen[url] then
                seen[url] = true
                out[#out + 1] = { url = url }
            end
        end
    end
    -- До расширения не должно быть `?`: иначе хвост вида
    -- file.tar?r_file=chunklist.m3u8 (Rumble) ловится как поток.
    take('https://[^"\'%s?]+%.m3u8[^"\'%s]*')
    take('https://[^"\'%s?]+%.mp4[^"\'%s]*')
    return out
end

-- dood/playmogo: body — embed (загружен батчем), embedUrl — Referer pass_md5.
-- Разбор /pass_md5 и http_get тела — общая либа dood (сигнатура
-- resolveDood(embedUrl, body) — аргументы местами, здесь адаптер).
-- Капча-вариант embed отдаётся без /pass_md5 — тогда возвращаем пусто.
local function resolveDood(body, embedUrl)
    local url, mime = DOOD.resolveDood(embedUrl, body)
    if not url then
        log_error("Anichin: dood: failed to resolve")
        return {}
    end
    return { { url = url, mime = mime } }
end

local RESOLVERS = {
    okru        = resolveOkRu,
    dailymotion = resolveDailymotion,
    dtube       = resolveDTube,
    dood        = resolveDood,
    page        = resolvePage,
}

------------------------------------------------------------------------------
-- Потоки эпизода
------------------------------------------------------------------------------

-- Значение option — base64 от <iframe src="..."> (atob на сайте). Метка option
-- («Okru», «VidHide [ADS]») уходит в quality варианта. Разбор (включая
-- regex-фоллбэки для регистра/кавычек) — общая либа mirrors; baseUrl нужен
-- либе для абсолютизации относительных embed.
function getVideoList(episodeUrl)
    ensureEngine()
    local r = http_get(episodeUrl, { timeout = 15000 })
    if not r.success then
        log_error("Anichin: episode request failed (HTTP " .. tostring(r.code) .. ")")
        return {}
    end
    local options = MIRRORS.mirrorOptions(r.body, baseUrl)
    if not options or #options == 0 then
        log_error("Anichin: no mirror list on " .. tostring(episodeUrl))
        return {}
    end

    -- Один батч на все embed, дедуп по URL запроса.
    local requests, jobs, seenRequest = {}, {}, {}
    for _, opt in ipairs(options) do
        local host = hostOf(opt.embed)
        local reason = lookup(SKIP_HOSTS, host)
        if reason then
            log_error("Anichin: skip " .. host .. " — " .. reason)
        else
            local plan = planRequest(opt.embed)
            if not seenRequest[plan.url] then
                seenRequest[plan.url] = true
                local item = { url = plan.url, timeout = BATCH_TIMEOUT }
                if plan.headers then item.headers = plan.headers end
                requests[#requests + 1] = item
                jobs[#jobs + 1] = {
                    resolver = plan.resolver,
                    label    = opt.label,
                    referer  = plan.referer,
                }
            end
            -- Дубли того же запроса пропускаются: URL у хостера встречается
            -- по одному разу на option, метка берётся от первого.
        end
    end
    if #requests == 0 then return {} end

    local responses = http_get_batch(requests, { timeout = BATCH_TIMEOUT })
    if type(responses) ~= "table" then return {} end

    local sources, seen = {}, {}
    local function push(src, job)
        if type(src) ~= "table" or type(src.url) ~= "string" or src.url == "" then return end
        if seen[src.url] then return end
        seen[src.url] = true
        local quality = job.label
        if src.name and src.name ~= "" then
            quality = (quality ~= "" and quality or job.resolver) .. " · " .. src.name
        end
        local source = { url = src.url, quality = quality ~= "" and quality or "Stream" }
        if src.mime then source.mime = src.mime end
        if job.referer then source.headers = { ["Referer"] = job.referer } end
        sources[#sources + 1] = source
    end

    for i, job in ipairs(jobs) do
        local res = responses[i]
        if type(res) == "table" and res.success and type(res.body) == "string" then
            local resolve = RESOLVERS[job.resolver]
            if not resolve then
                log_error("Anichin: unknown resolver " .. tostring(job.resolver))
            else
                -- dood берёт embed-URL вторым аргументом (Referer pass_md5);
                -- остальные резолверы лишний аргумент игнорируют.
                local ok, list = pcall(resolve, res.body, job.referer)
                if not ok then
                    log_error("Anichin: " .. tostring(job.resolver) .. " resolver error: " .. tostring(list))
                elseif type(list) == "table" then
                    if #list == 0 then
                        log_error("Anichin: no stream in " .. tostring(job.resolver) .. " response")
                    end
                    for _, src in ipairs(list) do push(src, job) end
                end
            end
        else
            local code = type(res) == "table" and res.code or "?"
            log_error("Anichin: " .. tostring(job.resolver) .. " request failed (HTTP " .. tostring(code) .. ")")
        end
    end
    return sources
end
