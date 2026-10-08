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
version      = "1.0.1"
baseUrl      = "https://anichin.moe"
language     = "id"
content_type = "video"
-- Иконка — favicon сайта (проверен 200): она квадратная (150x150),
-- в отличие от логотипа 270x50.
icon        = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/anichin.png"

local CATALOG = baseUrl .. "/anime/"
local SEARCH  = baseUrl .. "/?s="
local BATCH_TIMEOUT = 10000

local function absUrl(href)
    if type(href) ~= "string" or href == "" then return "" end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if href:find("^https?://") then return href end
    if href:sub(1, 1) == "/" then return baseUrl .. href end
    return baseUrl .. "/" .. href
end

local function hostOf(url)
    return (url:match("^https?://([^/?#]+)") or ""):lower()
end

-- origin хоста (scheme://host/) — из него берём Referer для потоков.
local function originOf(url)
    local scheme, host = url:match("^(https?)://([^/?#]+)")
    if not scheme or not host then return nil end
    return scheme .. "://" .. host .. "/"
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
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".bixbox.synp .entry-content")
    if not el then return nil end
    local text = string_trim(html_text(el.html))
    return text ~= "" and text or nil
end

-- .spe — плоский список «Метка: значение», значения сайта: Ongoing / Completed.
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".spe")
    if not el then return nil end
    local status = string_clean(html_text(el.html)):match("Status:%s*([%w]+)")
    if not status or status == "" then return nil end
    return status
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local value = html_attr(body, 'meta[itemprop="ratingValue"]', "content")
    if type(value) ~= "string" then return nil end
    value = string_clean(value)
    if not tonumber(value) then return nil end
    return "Rating: " .. value .. "/10"
end

function getBookGenres(bookUrl)
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

-- ok.ru: data-options (entity-encoded) → JSON → flashvars.metadata
-- (строка → повторный json_parse) → hlsManifestUrl + videos[].url.
local function resolveOkRu(body)
    if type(body) ~= "string" then return {} end
    local opts = body:match('data%-options="([^"]+)"')
    if not opts then return {} end
    opts = opts:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<")
        :gsub("&gt;", ">"):gsub("&amp;", "&")
    local data = json_parse(opts)
    if type(data) ~= "table" or type(data.flashvars) ~= "table" then return {} end
    local meta = data.flashvars.metadata
    if type(meta) == "string" then meta = json_parse(meta) end
    if type(meta) ~= "table" then return {} end
    local out = {}
    if type(meta.hlsManifestUrl) == "string" and meta.hlsManifestUrl ~= "" then
        out[#out + 1] = { url = meta.hlsManifestUrl }
    end
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            if type(u) == "string" and u ~= "" then
                out[#out + 1] = { url = u, mime = "mp4", name = type(v.name) == "string" and v.name or nil }
            end
        end
    end
    return out
end

-- dailymotion: qualities.auto[].url. Запасной путь — общий regex на m3u8
-- (в JSON слеши экранированы: application\/x-mpegURL).
-- UNVERIFIED (воспроизведение): метаданные отдаются (200, URL извлекается), но
-- cdndirector.dailymotion.com отвечает 403 из тестовой сети при любом Referer —
-- подтвердить воспроизведение не удалось (та же ситуация, что в animexin).
local function resolveDailymotion(body)
    if type(body) ~= "string" then return {} end
    local data = json_parse(body)
    local out = {}
    if type(data) == "table" and type(data.qualities) == "table"
        and type(data.qualities.auto) == "table" then
        for _, q in ipairs(data.qualities.auto) do
            if type(q) == "table" and type(q.url) == "string" and q.url ~= "" then
                out[#out + 1] = { url = q.url }
            end
        end
    end
    if #out == 0 then
        local flat = body:gsub("\\/", "/")
        local m = flat:match('(https://[^"\'%s?]+%.m3u8[^"\'%s]*)')
        if m then out[#out + 1] = { url = m } end
    end
    return out
end

-- play.d.tube: {"video_url":"https://nas1.d.tube/videos/<uuid>/master.m3u8"}.
local function resolveDTube(body)
    if type(body) ~= "string" then return {} end
    local data = json_parse(body)
    if type(data) ~= "table" then return {} end
    local url = data.video_url
    if type(url) ~= "string" or url == "" then return {} end
    return { { url = url } }
end

------------------------------------------------------------------------------
-- Packed JS (VidHide): eval(function(p,a,c,k,e,d){…}('payload',radix,count,
-- 'sym'.split('|'),0,0)) — Dean Edwards packer. Распаковка: вырезаем вызов,
-- режем payload по escape-правилам, symtab делим на | (пустые слоты значимы),
-- каждый токен переводим из radix-нотации и подставляем из symtab.
------------------------------------------------------------------------------

local B64_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function unbase(word, radix)
    local value = 0
    for i = 1, #word do
        local pos = B64_DIGITS:find(word:sub(i, i), 1, true)
        if not pos then return nil end
        value = value * radix + (pos - 1)
    end
    return value
end

-- Разделение с сохранением пустых частей: в symtab индексация строгая.
local function splitPipes(text)
    local out, start = {}, 1
    while true do
        local bar = text:find("|", start, true)
        if not bar then
            out[#out + 1] = text:sub(start)
            return out
        end
        out[#out + 1] = text:sub(start, bar - 1)
        start = bar + 1
    end
end

local function unpackPackedJs(body)
    local callAt = body:find("eval(function(p,a,c", 1, true)
    if not callAt then return nil end
    local openAt = body:find("}('", callAt, true)
    if not openAt then return nil end

    local i = openAt + 3
    local payloadChunks = {}
    while i <= #body do
        local ch = body:sub(i, i)
        if ch == "\\" then
            payloadChunks[#payloadChunks + 1] = body:sub(i, i + 1)
            i = i + 2
        elseif ch == "'" then
            break
        else
            payloadChunks[#payloadChunks + 1] = ch
            i = i + 1
        end
    end
    if i > #body then return nil end
    local payload = table.concat(payloadChunks)

    -- Остаток: ",36,524,'sym|tab…'.split('|'),0,0))"
    local after = body:sub(i + 1)
    local radixStr = after:match("^,(%d+),")
    local radix = tonumber(radixStr)
    if not radix or radix < 2 then return nil end

    -- Ищем конец symtab — строку .split('|'); | собираем через string.char,
    -- потому что это plain-поиск (plain=true), а не Lua-паттерн.
    local splitNeedle = ".split('" .. string.char(124) .. "')"
    local splitAt = after:find(splitNeedle, 1, true)
    if not splitAt then return nil end
    local symOpen = after:find("'", 1, true)
    if not symOpen or symOpen > splitAt then return nil end
    local symtab = after:sub(symOpen + 1, splitAt - 1)
    if symtab:sub(-1) == "'" then symtab = symtab:sub(1, -2) end
    symtab = symtab:gsub("\\'", "'"):gsub("\\\\", "\\")
    local words = splitPipes(symtab)
    if #words == 0 then return nil end

    local unpacked = payload:gsub("[0-9A-Za-z]+", function(word)
        if #word > 7 then return word end
        local index = unbase(word, radix)
        if not index or index < 0 or index >= #words then return word end
        local replacement = words[index + 1]
        if type(replacement) == "string" and replacement ~= "" then return replacement end
        return word
    end)
    return unpacked
end

-- Прямая страница: ищем готовые ссылки (после разэкранирования \/), плюс
-- распаковываем packed-JS, если он есть (VidHide).
local function resolvePage(body)
    if type(body) ~= "string" then return {} end
    local flat = body:gsub("\\/", "/")
    if flat:find("eval(function(p,a,c", 1, true) then
        local ok, unpacked = pcall(unpackPackedJs, flat)
        if ok and type(unpacked) == "string" then
            flat = flat .. "\n" .. unpacked
        elseif not ok then
            log_error("Anichin: unpack failed: " .. tostring(unpacked))
        end
    end
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

-- dood/playmogo: body — embed, откуда берётся путь /pass_md5/<...>; тело
-- /pass_md5 — начало финального URL, к нему дописываются 10 случайных
-- символов и "?token=<последний сегмент>&expiry=".
-- expiry = Date.now() в МИЛЛИСЕКУНДАХ — проверено по inline-коду плеера
-- playmogo.com/e/yx3yl4w4y9br (живьём 2026-10-07), os_time() в NoveLA тоже
-- миллисекунды. Финал — mp4 на cloudatacdn.com, без расширения → mime = "mp4".
-- Капча-вариант embed отдаётся без /pass_md5 — тогда возвращаем пусто.
local RANDOM_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function resolveDood(body, embedUrl)
    if type(body) ~= "string" then return {} end
    local md5 = body:match("(/pass_md5/[^'\"]+)")
    local origin = type(embedUrl) == "string"
        and embedUrl:match("^(https?://[^/]+)") or nil
    if not md5 or not origin then
        log_error("Anichin: dood: в embed нет /pass_md5")
        return {}
    end
    local token = md5:match("([^/]+)$")
    local r = http_get(origin .. md5, {
        headers = { ["Referer"] = embedUrl }, timeout = BATCH_TIMEOUT,
    })
    local start = r.success and type(r.body) == "string"
        and r.body:match("^%s*(https?://.-)%s*$") or nil
    if not start then
        local b = type(r.body) == "string" and r.body or ""
        log_error("Anichin: dood: /pass_md5 — "
            .. (b:find("RELOAD", 1, true) and "RELOAD"
                or ("HTTP " .. tostring(r.code))))
        return {}
    end
    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd)
        .. "?token=" .. token .. "&expiry=" .. tostring(os_time())
    return { { url = url, mime = "mp4" } }
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
-- («Okru», «VidHide [ADS]») уходит в quality варианта. Разметка внутри бывает
-- в верхнем регистре (<IFRAME SRC=...>), поэтому src ищем regex'ом без учёта
-- регистра.
local function mirrorOptions(body)
    local select = html_select_first(body, "select.mirror")
    if not select then return nil end
    local out = {}
    for _, opt in ipairs(html_select(select.html, "option[value]")) do
        local value = opt:attr("value")
        if type(value) == "string" and value ~= "" then
            local label = string_clean(html_text(opt.html))
            local decoded = base64_decode(value)
            if type(decoded) == "string" and decoded ~= "" then
                -- regex_match возвращает ПОЛНЫЕ совпадения (m.value), а не
                -- группы: m[1] здесь = 'src="https://…"' с префиксом и кавычками.
                -- Вырезаем сам URL; если движок вернёт чистую группу — оставим.
                local m = regex_match(decoded, '(?i)src\\s*=\\s*"([^"]+)"')
                local src = m and m[1] or nil
                if src then src = src:match('^[^"]*"([^"]+)"') or src end
                if not src then src = decoded:match('src=([^%s>]+)') end
                if src then
                    src = src:gsub('^"', ""):gsub('"$', "")
                        :gsub("^'", ""):gsub("'$", "")
                    -- Кавычка/пробел внутри src = битый embed: он упал бы в
                    -- http_get_batch до сети (HTTP -1), поэтому не добавляем.
                    if not src:find("[%s\"'<>]") then
                        out[#out + 1] = { label = label, embed = absUrl(src) }
                    end
                end
            end
        end
    end
    return out
end

function getVideoList(episodeUrl)
    local r = http_get(episodeUrl, { timeout = 15000 })
    if not r.success then
        log_error("Anichin: episode request failed (HTTP " .. tostring(r.code) .. ")")
        return {}
    end
    local options = mirrorOptions(r.body)
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
