-- Animexin (animexin.dev) — video plugin for NoveLA (content_type = "video")
-- WordPress-сайт. Серия = каталоговая карточка (страница /<slug>/), эпизод = страница
-- /<slug>-episode-N-indonesia-english-sub/. Сервер-лист эпизода — статический
-- <select class="mirror">: value каждого option — base64 от <iframe src="...">.

id           = "animexin"
name         = "Animexin"
version      = "1.0.0"
baseUrl      = "https://animexin.dev"
language     = "id"
content_type = "video"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/animexin.png"

local CATALOG = baseUrl .. "/anime/"
local SEARCH  = baseUrl .. "/?s="

local function absUrl(href)
    if type(href) ~= "string" or href == "" then return "" end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if href:find("^https?://") then return href end
    if href:sub(1, 1) == "/" then return baseUrl .. href end
    return baseUrl .. "/" .. href
end

-- getBookTitle/Cover/Description/Status/Rating/ChapterList читают одну страницу
-- серии; кэш держит один http_get на весь вызов движка.
local _pageCache = {}

local function fetchPage(url)
    local cached = _pageCache[url]
    if cached ~= nil then return cached end
    local r = http_get(url, { timeout = 15000 })
    if not r.success then
        log_error("Animexin: page request failed (HTTP " .. tostring(r.code) .. ") " .. url)
        return nil
    end
    _pageCache[url] = r.body
    return r.body
end

-- ─── Каталог ────────────────────────────────────────────────────────────────
-- /anime/?page=N — 30 карточек article.bs на страницу. Пагинация: в блоке
-- .hpage ссылка «Next» помечена class="r" (проверено вживую). Важно: /anime/page/2/
-- отдаёт первую страницу — рабочий переход только через ?page=N.

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
    if img then
        local src = img.src
        if type(src) == "string" and src ~= "" then book.cover = absUrl(src) end
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

-- «Next» в .hpage — единственный признак следующей страницы каталога.
local function catalogHasNext(body)
    local hpage = html_select_first(body, ".hpage")
    if not hpage then return false end
    return html_select_first(hpage.html, "a.r") ~= nil
end

function getCatalogList(index)
    index = tonumber(index) or 0
    local url = CATALOG .. "?page=" .. (index + 1)
    local body = fetchPage(url)
    if not body then return { items = {}, hasNext = false } end
    return { items = collectBooks(body), hasNext = catalogHasNext(body) }
end

-- ─── Фильтры каталога ───────────────────────────────────────────────────────
-- Форма /anime/: чекбоксы жанров name="genre[]" (несколько сразу — каждый
-- повторяется как genre[]=slug) + select name="order". Значение жанра —
-- slug с сайта (проверено вживую: регистр в URL не важен, пробелы вместо
-- дефисов ломают фильтр), label — читаемая форма.

local GENRE_OPTIONS = {
    { value = "action", label = "Action" },
    { value = "adventure", label = "Adventure" },
    { value = "chinese-horror", label = "Chinese Horror" },
    { value = "chinese-style", label = "Chinese Style" },
    { value = "comedy", label = "Comedy" },
    { value = "comic-adaptation", label = "Comic Adaptation" },
    { value = "cultivation", label = "Cultivation" },
    { value = "dark-humor", label = "Dark Humor" },
    { value = "demon", label = "Demon" },
    { value = "demons", label = "Demons" },
    { value = "drama", label = "Drama" },
    { value = "encouraging", label = "Encouraging" },
    { value = "fantasy", label = "Fantasy" },
    { value = "folklore", label = "Folklore" },
    { value = "game", label = "Game" },
    { value = "historical", label = "Historical" },
    { value = "inspiring", label = "Inspiring" },
    { value = "isekai", label = "Isekai" },
    { value = "magic", label = "Magic" },
    { value = "man", label = "Man" },
    { value = "martial-arts", label = "Martial Arts" },
    { value = "monsters", label = "Monsters" },
    { value = "mystery", label = "Mystery" },
    { value = "mythology", label = "Mythology" },
    { value = "novel", label = "Novel" },
    { value = "novel-adaptation", label = "Novel Adaptation" },
    { value = "over-power", label = "Over Power" },
    { value = "reincarnation", label = "Reincarnation" },
    { value = "romance", label = "Romance" },
    { value = "school", label = "School" },
    { value = "sci-fi", label = "Sci-Fi" },
    { value = "sci-fi-urban-cultivation", label = "Sci-Fi (Urban Cultivation)" },
    { value = "shounen", label = "Shounen" },
    { value = "slice-of-life", label = "Slice of Life" },
    { value = "super-power", label = "Super Power" },
    { value = "supernatural", label = "Supernatural" },
    { value = "time-travel", label = "Time Travel" },
    { value = "vitality-themed", label = "Vitality Themed" },
    { value = "war", label = "War" },
    { value = "wuxia", label = "Wuxia" },
    { value = "xianxia", label = "Xianxia" },
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

-- Поиск: 10 результатов на страницу. Первая — /?s=q, дальше /page/N/?s=q
-- (проверено вживую на «a»: 27 страниц, ссылка «Next» — a.next.page-numbers).
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
    -- На первой странице блок пагинации может отсутствовать (10 результатов
    -- ровно на страницу) — тогда пустой следующий запрос просто остановит цикл.
    if not hasNext and index == 0 then hasNext = #items > 0 end
    return { items = items, hasNext = hasNext }
end

-- ─── Страница серии ─────────────────────────────────────────────────────────

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
    local url = html_attr(body, 'meta[property="og:image"]', "content")
    if type(url) ~= "string" or url == "" then
        local img = html_select_first(body, "img.ts-post-image")
        if img then url = img.src end
    end
    if type(url) ~= "string" or url == "" then return nil end
    return absUrl(url)
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".bixbox.synp .entry-content")
    if not el then return nil end
    local text = string_clean(html_text(el.html))
    return text ~= "" and text or nil
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".spe")
    if not el then return nil end
    -- .spe — плоский список «Метка: значение», поэтому берём одно слово после
    -- «Status:» (значения сайта: Ongoing / Completed).
    local status = string_clean(html_text(el.html)):match("Status:%s*(%S+)")
    if not status or status == "" then return nil end
    return status
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local value = html_attr(body, 'meta[itemprop="ratingValue"]', "content")
    value = tonumber(value)
    if not value then return nil end
    return "Rating: " .. tostring(value) .. "/10"
end

-- Эпизоды = .eplister li a. Список на странице полный (проверено: 161 эпизод
-- серии из 161 без пагинации) и отсортирован от новых к старым — разворачиваем.
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
                if not label or label == "" then
                    label = string_clean(link.text)
                end
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

-- ─── Хостеры ────────────────────────────────────────────────────────────────
-- Ссылка хостера → то, что реально надо забрать из сети, + Referer/заголовки.
-- Всё, что можно, уходит в один http_get_batch (см. getVideoList).

-- Хостеры без рабочей схемы: отсекаются ДО сети.
--   mega.nz              — поток зашифрован AES-CTR, ссылку не отдать.
--   odysee.com           — embed отдаёт SPA-оболочку, LBRY-метод get требует
--                          подпись (проверено: "missing required signature param",
--                          с подписью — "could not validate the signature").
local SKIP_HOSTS = {
    ["mega.nz"]                  = "encrypted AES-CTR stream, no direct link",
    ["odysee.com"]               = "SPA shell; LBRY get requires a valid signature",
}

local BATCH_TIMEOUT = 10000

local function hostOf(url)
    return (url:match("^https?://([^/?#]+)") or ""):lower()
end

-- Реестр хостеров: embed-ссылка → { url = что забрать, headers = {} }.
-- Четыре резолвера (dailymotion, play.d.tube, ok.ru, rumble) вызываются на
-- теле ответа общего батча.
--
-- dailymotion: embed geo.dailymotion.com/player/xhojl.html?video=<id> — сам
-- embed не нужен, метаданные отдают подписанный m3u8. Референс 2026-10:
-- GET https://www.dailymotion.com/player/metadata/video/<id> → JSON с
-- qualities.auto[].url (application/x-mpegURL). Так и забираем.
local function planDailymotion(embed)
    -- формы: /embed/video/<id> (основное зеркало) и ?video=<id> (geo-плеер)
    local id = embed:match("/embed/video/([^/?&]+)") or embed:match("[?&]video=([^&]+)")
    if not id then return nil end
    return {
        url = "https://www.dailymotion.com/player/metadata/video/" .. id,
        headers = { ["Referer"] = "https://www.dailymotion.com/" },
        hoster = "dailymotion",
    }
end

-- play.d.tube: SPA, но JSON-обложка открыта — /videos/<id> → video_url (master.m3u8).
local function planDTube(embed)
    local id = embed:match("[?&]v=([^&#]+)")
    if not id then return nil end
    return {
        url = "https://api.d.tube/videos/" .. id,
        headers = { ["Referer"] = "https://play.d.tube/" },
        hoster = "dtube",
    }
end

-- ok.ru: нужен сам embed и Referer ok.ru (без него манифест 400).
-- Проверено: okcdn.ru отдаёт 400 также на UA не из браузера — движок шлёт свой
-- пользовательский UA, поэтому отдельный хардкод не нужен.
local function planOkRu(embed)
    return {
        url = embed,
        headers = { ["Referer"] = "https://ok.ru/" },
        hoster = "okru",
    }
end

-- rumble: embed отдаёт jwplayer-конфиг с прямыми ссылками.
local function planRumble(embed)
    return {
        url = embed,
        headers = { ["Referer"] = "https://rumble.com/" },
        hoster = "rumble",
    }
end

-- seekplayer (клон StreamWish): SPA, id эпизода — первый сегмент пути embed
-- (в плеере G() читает location.pathname.slice(1)). Источники лежат в ответе
-- /api/v1/video — там hex-блоб с AES-128-CBC (см. resolveSeekplayer).
-- Сервер принимает только браузерный User-Agent (curl/… → HTTP 400); движок
-- шлёт свой глобальный UA, отдельный пресет не нужен.
local function planSeekplayer(embed)
    local origin = embed:match("^(https?://[^/]+)")
    local path = embed:match("^https?://[^/]+/([^?#]*)")
    local id = path and path:match("^([^&]+)") or nil
    if not origin or not id or #id <= 1 then return nil end
    local refHost = (hostOf(embed):gsub("^www%.", ""))
    return {
        url = origin .. "/api/v1/video?id=" .. id .. "&w=1920&h=1080&r=" .. refHost,
        headers = { ["Referer"] = origin .. "/" },
        hoster = "seekplayer",
        origin = origin,
    }
end

-- gdriveplayer: embed2.php отдаёт страницу с инлайн-скриптом, тело которого
-- лежит в atob() и XOR-шифруется ключом `var k="..."`. В расшифрованном JS
-- константой задан относительный путь HLS="hlsplaylist.php?s=…&idhls=….m3u8",
-- который отдаёт media playlist (segments на стороннем CDN). Расшифровка —
-- resolveGdriveplayer; здесь только GET embed.
local function planGdriveplayer(embed)
    local origin = embed:match("^(https?://[^/]+)")
    if not origin then return nil end
    return {
        url = embed,
        headers = { ["Referer"] = origin .. "/" },
        hoster = "gdriveplayer",
        origin = origin,
    }
end

local PLANNERS = {
    ["geo.dailymotion.com"]     = planDailymotion,
    ["dailymotion.com"]         = planDailymotion,
    ["gdriveplayer.to"]         = planGdriveplayer,
    ["play.d.tube"]             = planDTube,
    ["ok.ru"]                   = planOkRu,
    ["rumble.com"]              = planRumble,
    ["animexinfansub.seekplayer.vip"] = planSeekplayer,
}

-- dood/playmogo: домены-зеркала меняются (playmogo.com, dood.*, и т.д.),
-- поэтому матчим по подстроке host-а, а не по точному ключу PLANNERS.
-- `Referer = embed` в плане уходит и в батч-запрос, и в Referer финального
-- потока (push берёт его из job.item.headers); `origin = embed` — резолверу
-- нужен полный embed, чтобы построить абсолютный URL /pass_md5.
local function planDood(embed)
    return {
        url = embed,
        headers = { ["Referer"] = embed },
        hoster = "dood",
        origin = embed,
    }
end

local function planFor(host, embed)
    -- зеркала отдают www.dailymotion.com и т.п. — ищем без www-префикса
    local planner = PLANNERS[host] or PLANNERS[host:gsub("^www%.", "")]
    if planner then return planner(embed) end
    if host:find("dood", 1, true) or host:find("playmogo", 1, true)
        or host:find("dsvplay", 1, true) then
        return planDood(embed)
    end
    return nil
end

-- ─── Резолверы хостеров ─────────────────────────────────────────────────────
-- Каждый возвращает массив { {url, mime?}, ... } — плоских ссылок потока.

-- dailymotion: qualities.auto[].url (application/x-mpegURL). Запасной путь —
-- общий regex на m3u8, если схема метаданных изменится.
-- UNVERIFIED (partially): воспроизведение подтверждено в приложении
-- (Stellar S4 → dailymotion m3u8 играет, 2026-10-07), но часть видео
-- cdndirector.dailymotion.com отдаёт 403 (probe → «Недоступен») — тогда
-- пользователю нужно брать другое зеркало.
local function resolveDailymotion(body)
    if type(body) ~= "string" then return {} end
    local data = json_parse(body)
    local out = {}
    if type(data) == "table" and type(data.qualities) == "table" then
        local auto = data.qualities.auto
        if type(auto) == "table" then
            for _, q in ipairs(auto) do
                if type(q) == "table" and type(q.url) == "string" and q.url ~= "" then
                    out[#out + 1] = { url = q.url, mime = "hls" }
                end
            end
        end
    end
    if #out == 0 then
        -- В JSON слеши экранированы (application\/x-mpegURL), поэтому сначала
        -- разэкранируем, потом ищем по «auto»-схеме и общим regex.
        local flat = body:gsub("\\/", "/")
        local m = flat:match('"auto"%s*:%s*%[{%s*"type"%s*:%s*"application[^"]*mpegURL","url"%s*:%s*"([^"]+)"')
            or flat:match('(https://[^"]+%.m3u8[^"]*)')
        if m then out[#out + 1] = { url = m, mime = "hls" } end
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
    return { { url = url, mime = "hls" } }
end

-- ok.ru: data-options (entity-encoded) → JSON → flashvars.metadata (строка →
-- повторный json_parse) → hlsManifestUrl + videos[].url (name = качество).
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
        out[#out + 1] = { url = meta.hlsManifestUrl, mime = "hls" }
    end
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            if type(u) == "string" and u ~= "" then
                out[#out + 1] = {
                    url = u,
                    mime = "mp4",
                    name = type(v.name) == "string" and v.name or nil,
                }
            end
        end
    end
    return out
end

-- rumble: jwplayer-конфиг. Сначала muxed mp4 (AoG3A.Faa.mp4), иначе HLS
-- (hls-vod/.../playlist.m3u8) и cdn-m3u8. В JSON слеши экранированы (\/).
local function resolveRumble(body)
    if type(body) ~= "string" then return {} end
    local raw = body:gsub("\\/", "/")
    local out = {}
    local mp4 = raw:match('"url":"(https://hugh%.cdn%.rumble%.cloud/[^"]+%.mp4)"')
        or raw:match('(https://hugh%.cdn%.rumble%.cloud/[^"]+%.mp4)')
    if mp4 then out[#out + 1] = { url = mp4, mime = "mp4" } end
    local hls = raw:match('(https://rumble%.com/hls%-vod/[^"]+playlist%.m3u8)')
        or raw:match('(https://hugh%.cdn%.rumble%.cloud/[^"]+chunklist%.m3u8[^"]*)')
    if hls then out[#out + 1] = { url = hls, mime = "hls" } end
    return out
end

-- ── seekplayer: hex-блоб → AES-128-CBC → JSON с источниками ─────────────────
-- Ответ /api/v1/video — hex-строка. Ключ/IV — константы из бандла плеера
-- (функции te()/oe() в index-*.js): фиксированные ASCII-строки по 16 байт
-- ("kiemtienmua911ca" / "1234567890oiuytr"), зависят только от location.protocol
-- и наличия hash. aes_decrypt ждёт шифртекст в base64, поэтому hex переводим
-- в base64 посчитанной по цифрам — строка с бинарными байтами не создаётся
-- (байты ≥0x80 ломаются при конвертации в UTF-8, см. es/m440in.lua).
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

-- eu() плеера: порядок и параметры кандидатов лежат в streamingConfig
-- (строка → повторный json_parse), без него — порядок по умолчанию. Относительный
-- URL (Tiktok) резолвится в origin эмбеда, /hls/ переписывается в /hlsmod/<домен>/
-- по adjust.<имя>.domain.
-- UNVERIFIED (playback): три из четырёх кандидатов отдают 200/206 + #EXTM3U
-- (проверено вживую 2026-10-05), прямой cf (.txt на cdn) всегда 403.
local function resolveSeekplayer(body, origin)
    if type(body) ~= "string" then return {} end
    local hex = body:gsub("%s", ""):lower()
    if #hex == 0 or #hex % 2 ~= 0 or hex:match("[^%x]") then
        log_error("Animexin: seekplayer payload is not hex")
        return {}
    end
    local plain = aes_decrypt(hexToBase64(hex), SP_KEY, SP_IV)
    if type(plain) ~= "string" or plain == "" then
        log_error("Animexin: seekplayer AES decrypt failed")
        return {}
    end
    local data = json_parse(plain)
    if type(data) ~= "table" then
        log_error("Animexin: seekplayer decrypted payload is not JSON")
        return {}
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
        local url = map[name]
        local adj = type(adjust[name]) == "table" and adjust[name] or {}
        if type(url) == "string" and url ~= "" and not adj.disabled then
            local abs = type(origin) == "string" and origin ~= ""
                and url_resolve(origin, url) or url
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
        log_error("Animexin: dood: no /pass_md5 in embed")
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
        log_error("Animexin: dood: /pass_md5 — "
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

-- gdriveplayer: инлайн-скрипт embed2.php — `var k="…",b=atob("…")`; XOR байтов
-- тела ключом → расшифрованный JS с `HLS="hlsplaylist.php?s=…&idhls=….m3u8"`.
-- hlsplaylist.php отдаёт media playlist (mime application/vnd.apple.mpegurl) с
-- прямыми сегментами на стороннем CDN — возвращаем как hls.
local function bxor8(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local ab, bb = a % 2, b % 2
        if ab ~= bb then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

local function resolveGdriveplayer(body, origin)
    if type(body) ~= "string" then return {} end
    local key = body:match('var k="([^"]+)"')
    local blob = body:match('atob%("([^"]+)"%)')
    if not key or not blob or #key == 0 then
        log_error("Animexin: gdriveplayer — нет ключа/atob в embed")
        return {}
    end
    local raw = base64_decode(blob)
    if type(raw) ~= "string" or raw == "" then
        log_error("Animexin: gdriveplayer — atob не раскодировался")
        return {}
    end
    local chars = {}
    local klen = #key
    for i = 1, #raw do
        chars[i] = string.char(bxor8(raw:byte(i), key:byte((i - 1) % klen + 1)))
    end
    local decoded = table.concat(chars)
    local hls = decoded:match('HLS="([^"]+)"')
    if not hls then
        log_error("Animexin: gdriveplayer — HLS= не найден после расшифровки")
        return {}
    end
    hls = hls:gsub("\\/", "/")
    if hls:sub(1, 2) == "//" then
        hls = "https:" .. hls
    elseif hls:sub(1, 1) == "/" then
        hls = origin .. hls
    else
        hls = origin .. "/" .. hls
    end
    return { { url = hls, mime = "hls" } }
end

local RESOLVERS = {
    dailymotion  = resolveDailymotion,
    dood         = resolveDood,
    dtube        = resolveDTube,
    gdriveplayer = resolveGdriveplayer,
    okru         = resolveOkRu,
    rumble       = resolveRumble,
    seekplayer   = resolveSeekplayer,
}

-- ─── Потоки эпизода ────────────────────────────────────────────────────────

-- Значение option — base64 от <iframe src="...">. atob в JS сайта; здесь
-- base64_decode движка. Метка option («Hardsub English Dailymotion AX») идёт
-- в quality варианта.
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
                local src = decoded:match('src="([^"]+)"')
                if src then out[#out + 1] = { label = label, embed = absUrl(src) } end
            end
        end
    end
    return out
end

function getVideoList(episodeUrl)
    local r = http_get(episodeUrl, { timeout = 15000 })
    if not r.success then
        log_error("Animexin: episode request failed (HTTP " .. tostring(r.code) .. ")")
        return {}
    end
    local options = mirrorOptions(r.body)
    if not options or #options == 0 then
        log_error("Animexin: no mirror list on " .. tostring(episodeUrl))
        return {}
    end

    -- Планируем запросы, дедуп по URL, один батч на всё.
    local requests, seenReq, jobs = {}, {}, {}
    for _, opt in ipairs(options) do
        local host = hostOf(opt.embed)
        if not SKIP_HOSTS[host] then
            local plan = planFor(host, opt.embed)
            if plan then
                if not seenReq[plan.url] then
                    seenReq[plan.url] = true
                    local item = { url = plan.url, headers = plan.headers, timeout = BATCH_TIMEOUT }
                    requests[#requests + 1] = item
                    jobs[#jobs + 1] = {
                        item = item,
                        resolver = plan.hoster,
                        label = opt.label,
                        origin = plan.origin,
                    }
                end
            else
                log_error("Animexin: no resolver for " .. host)
            end
        end
    end
    if #requests == 0 then return {} end

    local responses = http_get_batch(requests, { timeout = BATCH_TIMEOUT })
    if type(responses) ~= "table" then return {} end

    local sources, seen = {}, {}
    local function push(src, label, referer)
        if type(src) ~= "table" or type(src.url) ~= "string" or src.url == "" then return end
        if seen[src.url] then return end
        seen[src.url] = true
        local quality = label
        if src.name and src.name ~= "" then
            quality = (quality ~= "" and quality or "Ok.ru") .. " · " .. src.name
        end
        local source = { url = src.url, quality = quality ~= "" and quality or "Stream" }
        if src.mime then source.mime = src.mime end
        if referer then source.headers = { ["Referer"] = referer } end
        sources[#sources + 1] = source
    end

    for i, job in ipairs(jobs) do
        local res = responses[i]
        if type(res) == "table" and res.success and type(res.body) == "string" then
            local resolve = RESOLVERS[job.resolver]
            local ok, list = pcall(resolve, res.body, job.origin)
            if not ok then
                log_error("Animexin: " .. job.resolver .. " resolver error: " .. tostring(list))
            elseif type(list) == "table" then
                local referer = job.item.headers and job.item.headers["Referer"] or nil
                for _, src in ipairs(list) do push(src, job.label, referer) end
            end
        else
            local code = type(res) == "table" and res.code or "?"
            log_error("Animexin: " .. job.resolver .. " request failed (HTTP " .. tostring(code) .. ")")
        end
    end
    return sources
end
