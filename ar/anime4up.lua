-- Anime4Up — видео-плагин NoveLA (content_type = "video")

content_type = "video"
id           = "anime4up"
name         = "Anime4Up"
version      = "1.0.0"
baseUrl      = "https://w1.anime4up.rest"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/anime4up.png"
-- Обход Cloudflare включён для всех запросов к базовому домену:
-- движок решает челлендж в скрытом WebView и печёт cf_clearance.
cf_options   = { whitelist = false }

-- Путь каталога — байты из ссылок самого сайта (сегмент на арабском).
local CATALOG_PATH = "/%d9%82%d8%a7%d8%a6%d9%85%d8%a9-%d8%a7%d9%84%d8%a7%d9%86%d9%85%d9%8a/"

-- Кэш страниц тайтлов (title/cover/description/genres — 4 вызова на одну загрузку).
local _detailCache = {}

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function catalogUrl(page)
    local url = baseUrl .. CATALOG_PATH
    if page > 1 then url = url .. "page/" .. page .. "/" end
    return url
end

local function hasNextPage(body)
    return html_select_first(body, "a.next.page-numbers") ~= nil
end

-- Общая карточка каталога/поиска/фильтров: обложка и ссылка лежат в .hover,
-- заголовок — в alt у обложки (в h3 за пределами .hover).
local function parseCards(body)
    local items = {}
    for _, card in ipairs(html_select(body, "div.anime-card-poster > div.hover")) do
        local link = html_select_first(card.html, "a")
        local img  = html_select_first(card.html, "img")
        local url  = link and absUrl(link.href) or ""
        if url ~= "" then
            local title = ""
            if img then title = string_clean(img.attr("alt")) end
            if title == "" and link then title = string_clean(link.text) end
            local cover = img and absUrl(img.src) or ""
            if title ~= "" then
                items[#items + 1] = { title = title, url = url, cover = cover }
            end
        end
    end
    return items
end

local function fetchList(url)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    return { items = parseCards(r.body), hasNext = hasNextPage(r.body) }
end

function getCatalogList(index)
    return fetchList(catalogUrl(index + 1))
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    return fetchList(baseUrl .. "/?search_param=animes&s=" .. url_encode(query))
end

-- ============ Фильтры ============
-- Сайт фильтрует одним taxonomy-путём: /anime-genre/<slug>/, /anime-type/<slug>/,
-- /anime-category/<slug>/ (slug — арабский, percent-encoded, дефисы вместо пробелов).
-- Списки slug'ов сверены с выпадающими списками на странице каталога.
-- Прежний статус /anime-status/<slug>/ (из Kotlin-референса) вживую отдаёт 404 —
-- его заменяет «القسم» (перевод/дубляж).
local FILTER_PATHS = {
    genre    = "anime-genre",
    type     = "anime-type",
    category = "anime-category",
}
local FILTER_ORDER = { "genre", "type", "category" }

-- value = slug из URL (пробелы в нём заменены дефисами), label = как на сайте.
local GENRE_OPTIONS = {
    { value = "",              label = "الكل" },
    { value = "أكشن",          label = "أكشن" },
    { value = "أطفال",         label = "أطفال" },
    { value = "إيتشي",         label = "إيتشي" },
    { value = "اثارة",         label = "اثارة" },
    { value = "العاب",         label = "العاب" },
    { value = "ايسيكاي",       label = "ايسيكاي" },
    { value = "بوليسي",        label = "بوليسي" },
    { value = "تاريخي",        label = "تاريخي" },
    { value = "جنون",          label = "جنون" },
    { value = "جوسي",          label = "جوسي" },
    { value = "حربي",          label = "حربي" },
    { value = "حريم",          label = "حريم" },
    { value = "خارق-للعادة",   label = "خارق للعادة" },
    { value = "خيال-علمي",     label = "خيال علمي" },
    { value = "دراما",         label = "دراما" },
    { value = "رعب",           label = "رعب" },
    { value = "رومانسي",       label = "رومانسي" },
    { value = "رياضي",         label = "رياضي" },
    { value = "ساموراي",       label = "ساموراي" },
    { value = "سباق",          label = "سباق" },
    { value = "سحر",           label = "سحر" },
    { value = "سينين",         label = "سينين" },
    { value = "شريحة-من-الحياة", label = "شريحة من الحياة" },
    { value = "شوجو",          label = "شوجو" },
    { value = "شوجو-اَي",      label = "شوجو اَي" },
    { value = "شونين",         label = "شونين" },
    { value = "شونين-اي",      label = "شونين اي" },
    { value = "شياطين",        label = "شياطين" },
    { value = "طبي",           label = "طبي" },
    { value = "غموض",          label = "غموض" },
    { value = "فضائي",         label = "فضائي" },
    { value = "فنتازيا",       label = "فنتازيا" },
    { value = "فنون-تعبيرية",  label = "فنون تعبيرية" },
    { value = "فنون-قتالية",   label = "فنون قتالية" },
    { value = "قوى-خارقة",     label = "قوى خارقة" },
    { value = "كوميدي",        label = "كوميدي" },
    { value = "محاكاة-ساخرة",  label = "محاكاة ساخرة" },
    { value = "مدرسي",         label = "مدرسي" },
    { value = "مصاصي-دماء",    label = "مصاصي دماء" },
    { value = "مغامرات",       label = "مغامرات" },
    { value = "موسيقي",        label = "موسيقي" },
    { value = "ميكا",          label = "ميكا" },
    { value = "نفسي",          label = "نفسي" },
}

local TYPE_OPTIONS = {
    { value = "",        label = "الكل" },
    { value = "movie-3", label = "Movie" },
    { value = "ona1",    label = "ONA" },
    { value = "ova1",    label = "OVA" },
    { value = "special1", label = "Special" },
    { value = "tv2",     label = "TV" },
}

local CATEGORY_OPTIONS = {
    { value = "",                  label = "الكل" },
    { value = "الأنمي-المترجم",   label = "الأنمي المترجم" },
    { value = "الانمي-المدبلج",   label = "الانمي المدبلج" },
}

function getFilterList()
    return {
        {
            type         = "select",
            key          = "genre",
            label        = "تصنيف الأنمي",
            defaultValue = "",
            options      = GENRE_OPTIONS,
        },
        {
            type         = "select",
            key          = "type",
            label        = "النوع",
            defaultValue = "",
            options      = TYPE_OPTIONS,
        },
        {
            type         = "select",
            key          = "category",
            label        = "القسم",
            defaultValue = "",
            options      = CATEGORY_OPTIONS,
        },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    -- Сайт умеет только один фильтр-путь за раз: берём первый выбранный.
    local path, slug
    for _, key in ipairs(FILTER_ORDER) do
        local v = filters and filters[key]
        if type(v) == "string" and v ~= "" then
            path = FILTER_PATHS[key]
            slug = v
            break
        end
    end

    local url
    if path then
        url = baseUrl .. "/" .. path .. "/" .. url_encode(slug) .. "/"
        -- Таксономии листаются query-параметром, не /page/N/.
        if page > 1 then url = url .. "?page=" .. page end
    else
        url = catalogUrl(page)
    end
    return fetchList(url)
end

-- ============ Карточка тайтла ============

local function fetchDetail(bookUrl)
    local cached = _detailCache[bookUrl]
    if cached then return cached end
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local detail = { body = r.body }
    _detailCache[bookUrl] = detail
    return detail
end

function getBookTitle(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local el = html_select_first(d.body, "h1.anime-details-title")
    if not el then return nil end
    local title = string_clean(el.text)
    if title == "" then return nil end
    return title
end

function getBookCoverImageUrl(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local el = html_select_first(d.body, "img.thumbnail")
    if not el then return nil end
    local cover = absUrl(el.src)
    if cover == "" then return nil end
    return cover
end

-- Описание: служебные строки div.anime-info (тип, год, число серий и т.п.)
-- плюс сюжет из p.anime-story — как на самом сайте.
function getBookDescription(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local lines = {}
    for _, info in ipairs(html_select(d.body, "div.anime-info")) do
        local t = string_clean(info.text)
        if t ~= "" then lines[#lines + 1] = t end
    end
    local story = html_select_first(d.body, "p.anime-story")
    if story then
        local t = string_clean(story.text)
        if t ~= "" then lines[#lines + 1] = t end
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

function getBookGenres(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return {} end
    local genres = {}
    for _, a in ipairs(html_select(d.body, "ul.anime-genres > li > a")) do
        local t = string_clean(a.text)
        if t ~= "" then genres[#genres + 1] = t end
    end
    return genres
end

-- ============ Серии ============

-- Три селектора: текущий дизайн (div.ep_num), карточки-плитки старого дизайна
-- (div.episodes-card-title) и боковой список на странице серии.
local CHAPTER_SELECTOR = "div.ep_num > a, div.episodes-card-title > h3 > a, ul.all-episodes-list li > a"

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end
    local links = {}
    local seen = {}
    for _, el in ipairs(html_select(r.body, CHAPTER_SELECTOR)) do
        local url = absUrl(el.href)
        if url ~= "" and not seen[url] then
            seen[url] = true
            links[#links + 1] = { title = string_clean(el.text), url = url }
        end
    end
    if #links == 0 then return {} end
    -- Сайт печатает серии от последней к первой — разворачиваем в хронологию.
    local out = {}
    for i = #links, 1, -1 do
        if links[i].title ~= "" then out[#out + 1] = links[i] end
    end
    return out
end

-- ============ Потоки: резолверы хостов ============

local function pushSource(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

-- Хосты, которые никогда не дают прямую ссылку чистым HTTP либо висят до полного
-- таймаута (проверено живьём 2026-10-01/02). Пропускаются до похода в сеть — это
-- и есть «жёсткий таймаут»: с 2026-10-02 в http_get есть timeout/HEAD, но skip
-- остаётся первым рубежом — не ходить к заведомо мёртвому хосту вовсе.
-- Референс Anime4Up.kt (extractVideos) этих хостов также не обрабатывает.
local SKIP_HOSTS = {
    { pattern = "dood",               reason = "Turnstile + в embed нет /pass_md5 — референс DoodExtractor даёт null (живьём 2026-10-02)" },
    { pattern = "playmogo",           reason = "Turnstile + в embed нет /pass_md5 — референс DoodExtractor даёт null (живьём 2026-10-02)" },
    { pattern = "streamwish",         reason = "JS-плеер" },
    { pattern = "vidmoly",            reason = "embed отдаёт 404/JS" },
    { pattern = "gdriveplayer",       reason = "JS (file.js)" },
    { pattern = "drive%.google",      reason = "JS (gdriveplayer)" },
    { pattern = "mega%.nz",           reason = "JS-API — в референсе тоже нет ветки" },
    { pattern = "ok%.ru",             reason = "данные не отдаются по HTTP" },
    -- Ниже — хосты без прямых ссылок / с зависанием (замерено 2026-10-01):
    { pattern = "rubyvidhub",         reason = "чёрная дыра: TCP есть, ответа нет до таймаута" },
    { pattern = "streamruby",         reason = "чёрная дыра: HTTP -1" },
    { pattern = "videa%.hu",          reason = "зависает до таймаута, прямой ссылки нет" },
    { pattern = "vkvideo",            reason = "редирект-цикл, прямой ссылки нет — в референсе тоже нет ветки" },
    { pattern = "dailymotion",        reason = "301/403-тупик без прямой ссылки" },
    { pattern = "share4max",          reason = "Inertia-приложение без прямых ссылок — в референсе тоже нет ветки" },
    { pattern = "uqload",             reason = "embed — только POST-форма /dl, sources/packed нет — референс UqloadExtractor даёт пусто (живьём 2026-10-02)" },
    -- Второй проход по хостам, замерено 2026-10-02 (curl, живые id страниц серий):
    { pattern = "dsvplay",            reason = "DoodStream переехал на dsvplay.com — паттерн dood его не матчил; в embed нет /pass_md5 (референс DoodExtractor даёт null), TLS-хендшейк не проходит (curl rc=35, 0 байт)" },
    { pattern = "file%-upload%.org",  reason = "embed отдаёт «File was deleted» (HTTP 200, 16 байт) на всех id — свежие и суточные (проверено 14 шт.); страница файла www.file-upload.org/<id> — 404 «File Not Found»" },
    { pattern = "larhu",              reason = "embed разбирается (jwplayer sources:[{file:…m3u8}]), но CDN fav.larhu.website без DNS-записи A/AAAA (dig 8.8.8.8/1.1.1.1 → NODATA) — поток недостижим; вернуть, если хост снова резолвится" },
    { pattern = "vadbam",             reason = "домен припаркован (parklogic): embed отдаёт страницу редиректа router.parklogic.com, а не плеер" },
    { pattern = "uptostream",         reason = "хост лежит: Cloudflare 522 (origin down), затем нет соединения (curl 000) — embed недоступен" },
}

local function skipReason(link)
    local low = link:lower()
    for _, h in ipairs(SKIP_HOSTS) do
        if low:find(h.pattern) then return h.reason end
    end
    return nil
end

-- Есть ли медиа-расширение в пути URL (до "?" / "#"). Без него media3 в NoveLA
-- типизирует поток как progressive и падает на HLS-теле (см. диагноз в шапке).
local function hasMediaExt(u)
    local base = u:match("^[^%?#]*") or u
    return base:match("%.m3u8$") ~= nil or base:match("%.mp4$") ~= nil
end

-- Извлечение прямой ссылки из страницы плеера:
-- 1) переменная streamUrl (собственный плеер anime4up-зеркал);
-- 2) явные .m3u8/.mp4 в разметке (например, mp4upload).
local function directLinks(body)
    local out, seen = {}, {}
    -- strict=true: только явные медиа-суффиксы, иначе хост вида www.mp4upload.com
    -- матчится паттерном ".mp4" и даёт ссылку на саму страницу плеера.
    local function add(u, strict)
        u = u:gsub("&amp;", "&")
        if seen[u] then return end
        if strict and not hasMediaExt(u) then return end
        seen[u] = true
        out[#out + 1] = u
    end
    -- streamUrl: на зеркалах VnxPlayer это cdn-токен без расширения —
    -- getVideoList выдаёт его с mime = "hls" (HLS-источник media3 читает
    -- плейлист по этому URL, см. заголовок файла).
    local stream = body:match('streamUrl%s*=%s*"([^"]+)"')
        or body:match("streamUrl%s*=%s*'([^']+)'")
    if stream then add(stream, false) end
    for u in body:gmatch('https?://[^"\'%s<>]+%.m3u8[^"\'%s<>]*') do add(u, true) end
    for u in body:gmatch('https?://[^"\'%s<>]+%.mp4[^"\'%s<>]*') do add(u, true) end
    return out
end

local function hostLabel(link)
    local host = link:match("^https?://([^/]+)") or link
    return host:gsub("^www%.", "")
end

-- ============ VOE (порт lib/voeextractor VoeExtractor.kt) ============

-- Литералы паттернов из референсного regex "@$|^^|~@|%?|*~|!!|#&" → "_",
-- записанные Lua-паттернами ( '%' — экранирование магии).
local VOE_PATTERNS = { "@%$", "%^%^", "~@", "%%%?", "%*~", "!!", "#&" }

-- VOE-зеркало подписывает токены под User-Agent запроса: мобильный Chrome
-- Android (дефолт рантайма) получает i=0.1 → CDN отвечает 403; десктопный
-- Chrome даёт рабочую подпись (живьём 2026-10-02, матрица mint×fetch).
-- UA на самой выдаче CDN не важен — 200 с любым/без UA.
local VOE_MIRROR_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    .. "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

-- decryptF7 из референса: rot13 → паттерны → убрать "_" → base64 →
-- сдвиг байт −3 → reverse → base64 → JSON {source, direct_access_url, captions}.
local function voeDecrypt(enc)
    local v = enc:gsub("[A-Za-z]", function(c)
        local base = c:byte() < 91 and 65 or 97
        return string.char((c:byte() - base + 13) % 26 + base)
    end)
    for _, p in ipairs(VOE_PATTERNS) do v = (v:gsub(p, "_")) end
    v = (v:gsub("_", ""))
    local raw = base64_decode(v)
    if type(raw) ~= "string" then return nil end
    raw = (raw:gsub(".", function(c)
        return string.char((string.byte(c) - 3) % 256)
    end))
    raw = raw:reverse()
    local js = base64_decode(raw)
    if type(js) ~= "string" then return nil end
    return json_parse(js)
end

-- Страница эмбеда → редирект window.location на зеркало → там
-- <script type="application/json">["<шифр>"]</script>.
-- Возвращает число добавленных кандидатов (master.m3u8 + прямой .mp4 + сабы).
local function resolveVoe(pageBody, entry, candidates)
    local body = pageBody
    local loc = body:match("window%.location%.href%s*=%s*'([^']+)'")
        or body:match('window%.location%.href%s*=%s*"([^"]+)"')
    if loc then
        local r = http_get(absUrl(loc), {
            headers = { ["User-Agent"] = VOE_MIRROR_UA },
        })
        if r.success then body = r.body end
    end
    local payload = body:match('<script[^>]*type=["\']application/json["\'][^>]*>(.-)</script>')
    -- Референс: substringAfter("[\"") + substringBeforeLast("\"]") → жадный
    -- захват до последней пары "], как в Kotlin.
    local enc = payload and payload:match('%["(.*)"]')
    if not enc then
        log_error("Anime4Up: " .. entry.quality .. " — VOE: на зеркале нет данных плеера")
        return 0
    end
    local data = voeDecrypt(enc)
    if type(data) ~= "table" then
        log_error("Anime4Up: " .. entry.quality .. " — VOE: данные не расшифрованы")
        return 0
    end
    local subs = {}
    if type(data.captions) == "table" then
        for _, c in ipairs(data.captions) do
            if type(c) == "table" and type(c.file) == "string" and c.file ~= "" then
                subs[#subs + 1] = {
                    url   = c.file,
                    label = type(c.label) == "string" and c.label or "Subtitle",
                }
            end
        end
    end
    local added = 0
    local src = data.source
    if type(src) == "string" and src ~= "" then
        candidates[#candidates + 1] = {
            url = src, quality = entry.quality, referer = entry.link,
            subtitles = subs,
        }
        added = added + 1
    end
    local mp4 = data.direct_access_url
    if type(mp4) == "string" and mp4 ~= "" then
        candidates[#candidates + 1] = {
            url = mp4, quality = entry.quality .. " · MP4", referer = entry.link,
            subtitles = subs,
        }
        added = added + 1
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — VOE: в JSON нет ни source, ни direct_access_url")
    end
    return added
end

-- ============ VidYard / 4shared / vidbom ============

-- ---- VidYard (порт VidYardExtractor.kt) ----
-- Страница эмбеда не читается: id берётся из самой ссылки (substringAfter("com/")
-- + substringBefore("?")), данные лежат в player/<id>.json.
local VIDYARD_URL = "https://play.vidyard.com"

local function resolveVidYard(entry, candidates)
    local pos = entry.link:find("com/", 1, true)
    local id = pos and entry.link:sub(pos + 4):match("^[^?]*") or ""
    if id == "" then
        log_error("Anime4Up: " .. entry.quality .. " — VidYard: в ссылке нет id")
        return 0
    end
    local r = http_get(VIDYARD_URL .. "/player/" .. id .. ".json", {
        headers = { ["Referer"] = VIDYARD_URL },
    })
    if not r.success then
        log_error("Anime4Up: " .. entry.quality .. " — VidYard: HTTP " .. tostring(r.code))
        return 0
    end
    -- Референс: substringAfter("hls\":[") → substringBefore("]") → разбиение
    -- по `profile":"` (alternation в Lua-паттернах не нужна — один литерал).
    local p = r.body:find('hls":[', 1, true)
    local data = p and r.body:sub(p + 6):match("^[^]]*") or nil
    if not data or data == "" then
        log_error("Anime4Up: " .. entry.quality .. " — VidYard: в ответе нет hls[]")
        return 0
    end
    local added = 0
    for profile, src in data:gmatch('profile":"([^"]+)".-url":"([^"]+)"') do
        if src ~= "" then
            candidates[#candidates + 1] = {
                url = src, quality = profile, referer = VIDYARD_URL,
            }
            added = added + 1
        end
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — VidYard: в hls[] нет источников")
    end
    return added
end

-- ---- 4shared (порт SharedExtractor.kt) ----
-- Эмбед уже загружен батчем: первый <source src> — и есть прямая ссылка.
local function resolveShared(body, entry, candidates)
    local src = html_attr(body, "source", "src")
    if type(src) ~= "string" or src == "" then
        log_error("Anime4Up: " .. entry.quality .. " — 4shared: в embed нет <source>")
        return 0
    end
    -- Референс отдаёт attr("src") как есть; абсолютным делаем только
    -- protocol-relative/относительные значения — иначе плеер их не откроет.
    if not string_starts_with(src, "http") then
        if string_starts_with(src, "//") then
            src = "https:" .. src
        else
            src = url_resolve(entry.link, src)
        end
    end
    candidates[#candidates + 1] = {
        url = src, quality = "4Shared: mirror", referer = entry.link,
    }
    return 1
end

-- ---- vidbom (порт VidBomExtractor.kt) ----
-- VIDBOM_REGEX из Anime4Up.kt: alternation (|) в Lua-паттернах нет, поэтому
-- вместо одного regex — список; как и в референсе, без якоря «//» — имя
-- хоста матчится где угодно в URL (в т.ч. поддомены), но только после точки.
local VIDBOM_PATTERNS = {
    "v[aie]d[bp][aoe]?m%.",      -- vidbom / vadbom / vedbam
    "myvii?d%.",                 -- myvid / myviid
    "segavid%.",                 -- segavid
    "v[aei][aei]?dshar[er]?%.",  -- vidshare / vidsharer
}

local function isVidbomLink(link)
    local low = link:lower()
    for _, p in ipairs(VIDBOM_PATTERNS) do
        if low:find(p) then return true end
    end
    return false
end

local function resolveVidbom(body, entry, candidates)
    -- Референс читает script:containsData(sources) и режет body по
    -- substringAfter("sources: [") + substringBefore("],").
    local p = body:find("sources: [", 1, true)
    local rest = p and body:sub(p + 10) or nil
    local data = rest and (rest:match("^(.-)%],") or rest) or nil
    if not data then
        log_error("Anime4Up: " .. entry.quality .. " — vidbom: в embed нет sources[]")
        return 0
    end
    local added = 0
    for src, label in data:gmatch('file:"([^"]+)".-label:"([^"]*)"') do
        -- Референс: "Vidbom: " + label, длиннее 15 символов → "Vidshare: 480p".
        local quality = "Vidbom: " .. label
        if #quality > 15 then quality = "Vidshare: 480p" end
        candidates[#candidates + 1] = {
            url = src, quality = quality, referer = entry.link,
        }
        added = added + 1
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — vidbom: в sources[] нет файлов")
    end
    return added
end

-- Живость источника НЕ проверяем: с 2026-10-02 timeout/HEAD в http_get есть
-- (см. гайд, «Работа с HTTP»), но сплошная проба каждой ссылки остаётся дорогой —
-- проверка мёртвой ссылки mp4upload (a3 отдаёт «чёрную дыру») при замере
-- 2026-10-01 без таймаутов съедала 15 с в тестере и до ~27 с в приложении на
-- КАЖДЫЙ битый файл: koori 4.0 с → 30.5 с, tensei 4.7 с → 26.2 с ради
-- выбрасывания одного мёртвого источника. Мёртвые файлы — проблема хоста,
-- лечится в skip-листе (хосты); точечная проверка одной ссылки — timeout+HEAD.

-- ============ Список серверов серии ============

-- Качество для подписи в UI: ранг — для сортировки (FHD сверху).
local function qualityRank(q)
    local low = q:lower()
    if low:find("fhd") or low:find("1080") then return 4 end
    if low:find("متعدد") then return 3 end
    if low:find("hd") or low:find("720") then return 2 end
    if low:find("sd") or low:find("480") or low:find("360") then return 1 end
    return 2
end

local function tierLabel(name, quality)
    if quality == "" then return name end
    if name == "" then return quality end
    return name .. " · " .. quality
end

-- Собираем кандидатов { link, quality, rank } со страницы серии.
local function collectWatchEntries(body)
    local entries = {}

    -- Текущий дизайн: ul#episode-servers li[data-watch] + имя/качество внутри.
    for _, li in ipairs(html_select(body, "#episode-servers li[data-watch]")) do
        local link = li.attr("data-watch")
        if type(link) == "string" and link ~= "" then
            local nameEl = html_select_first(li.html, ".watch-server-name")
            local qualEl = html_select_first(li.html, ".quality")
            local quality = qualEl and string_clean(qualEl.text) or ""
            local name = nameEl and string_clean(nameEl.text) or hostLabel(link)
            entries[#entries + 1] = {
                link    = absUrl(link),
                quality = tierLabel(name, quality),
                rank    = qualityRank(quality),
            }
        end
    end
    if #entries > 0 then return entries end

    -- Старый дизайн: base64-инпуты качества → JSON [{name, link, ...}].
    local tiers = {
        { input = "watch_fhd", tier = "FHD", rank = 4 },
        { input = "watch_hd",  tier = "HD",  rank = 2 },
        { input = "watch_SD",  tier = "SD",  rank = 1 },
    }
    for _, t in ipairs(tiers) do
        local raw = html_attr(body, "input[name='" .. t.input .. "']", "value")
        if type(raw) == "string" and raw ~= "" then
            local decoded = base64_decode(raw)
            local arr = decoded and json_parse(decoded) or nil
            if type(arr) == "table" then
                for _, rec in ipairs(arr) do
                    if type(rec) == "table" and type(rec.link) == "string" and rec.link ~= "" then
                        local name = type(rec.name) == "string" and rec.name or ""
                        entries[#entries + 1] = {
                            link    = absUrl(rec.link),
                            quality = tierLabel(name, t.tier),
                            rank    = t.rank,
                        }
                    end
                end
            end
        end
    end
    return entries
end

function getVideoList(episodeUrl)
    local r = http_get(episodeUrl)
    if not r.success then
        log_error("Anime4Up: страница серии — HTTP " .. tostring(r.code))
        return nil
    end

    local entries = collectWatchEntries(r.body)
    if #entries == 0 then
        log_error("Anime4Up: на странице серии не найдено ни одного сервера")
        return nil
    end

    -- Сортировка по рангу качества (FHD → … → SD), при равенстве — порядок сайта.
    table.sort(entries, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return false
    end)

    -- 1. Skip мёртвых хостов; embed-страницы — одним батчем (в приложении
    --    http_get_batch выполняет запросы параллельно, а не по одному).
    local batchUrls, batchEntries, candidates = {}, {}, {}
    for _, e in ipairs(entries) do
        local reason = skipReason(e.link)
        if reason then
            log_error("Anime4Up: " .. e.quality .. " — пропущен: " .. reason)
        elseif e.link:find("%.m3u8") or e.link:find("%.mp4") then
            -- Уже прямая ссылка на медиа — резолвер не нужен.
            candidates[#candidates + 1] = {
                url = e.link, quality = e.quality, referer = episodeUrl,
            }
        else
            batchUrls[#batchUrls + 1] = e.link
            batchEntries[#batchEntries + 1] = e
        end
    end

    if #batchUrls > 0 then
        local responses = http_get_batch(batchUrls, {})
        for i, e in ipairs(batchEntries) do
            local resp = responses[i]
            local body = type(resp) == "table" and resp.body or ""
            if type(body) ~= "string" or #body == 0 then
                log_error("Anime4Up: " .. e.quality .. " — embed-страница недоступна")
            else
                -- Диспетчер хостов (порты extractVideos из Anime4Up.kt):
                -- VOE — редирект-зеркало + шифрованный JSON (VoeExtractor.kt);
                -- VidYard — player/<id>.json (сам эмбед не нужен);
                -- 4shared — <source> в уже загруженном embed;
                -- vidbom — sources:[{file,…}] в embed. directLinks остаётся
                -- общим сканом (mp4upload, sendvid и прочие прямые ссылки).
                local added, low = 0, e.link:lower()
                if low:find("voe%.") then
                    added = resolveVoe(body, e, candidates)
                elseif low:find("vidyard") then
                    added = resolveVidYard(e, candidates)
                elseif low:find("shared") then
                    added = resolveShared(body, e, candidates)
                elseif isVidbomLink(e.link) then
                    added = resolveVidbom(body, e, candidates)
                end
                local urls = directLinks(body)
                if #urls == 0 and added == 0 then
                    log_error("Anime4Up: " .. e.quality .. " — нет прямой ссылки (плеер требует JS)")
                end
                for _, u in ipairs(urls) do
                    if hasMediaExt(u) then
                        candidates[#candidates + 1] = {
                            url = u, quality = e.quality, referer = e.link,
                        }
                    else
                        -- cdn-класс (cdn1/cdn2 ?token=): HLS без расширения.
                        -- Без mime media3 берёт прогрессивный источник и падает
                        -- с UnrecognizedInputFormatException; с mime = "hls"
                        -- Source.Factory уже не гадает по URL.
                        candidates[#candidates + 1] = {
                            url = u, quality = e.quality, referer = e.link,
                            mime = "hls",
                        }
                    end
                end
            end
        end
    end

    -- 2. Дедупликация по URL.
    local sources, seen = {}, {}
    for _, c in ipairs(candidates) do
        pushSource(sources, seen, {
            url        = c.url,
            quality    = c.quality,
            mime       = c.mime,
            headers    = { ["Referer"] = c.referer },
            subtitles  = c.subtitles,
        })
    end
    if #sources == 0 then return nil end
    return sources
end
