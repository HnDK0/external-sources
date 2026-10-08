-- Anime4Up — видео-плагин NoveLA (content_type = "video")

content_type = "video"
id           = "anime4up"
name         = "Anime4Up"
version      = "1.0.2"
baseUrl      = "https://w1.anime4up.rest"
language     = "ar"
icon         = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/anime4up.png"
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
-- таймаута (замерено 2026-10-05, curl). Пропускаются до похода в сеть — это
-- и есть «жёсткий таймаут»: с 2026-10-02 в http_get есть timeout/HEAD, но skip
-- остаётся первым рубежом — не ходить к заведомо мёртвому хосту вовсе.
-- Референс Anime4Up.kt (extractVideos) этих хостов также не обрабатывает.
-- Хосты, чьи схемы раскрыты резолверами ниже (ok.ru, videa.hu, dailymotion,
-- drive.google, uqload, vidmoly, vkvideo, mail.ru, share4max, hgcloud,
-- seekplayer/streamwish, dood/playmogo), из списка убраны.
local SKIP_HOSTS = {
    -- dsvplay — зеркало DoodStream: dood/playmogo раскрыты resolveDood ниже
    -- (CF обходит движок), но у этого домена не поднимается TLS.
    { pattern = "dsvplay",             reason = "TLS-хендшейк не проходит (curl rc=35) — проверено и с браузерным UA (живьём 2026-10-07)" },
    { pattern = "gdriveplayer",        reason = "JS-плеер (file.js) на стороне gdriveplayer — сам Google Drive обрабатывается отдельно" },
    { pattern = "mega%.nz",            reason = "поток зашифрован AES-CTR и отдаётся чанками с Range — в движке нет крипто и частичных запросов" },
    -- Ниже — TLS/DNS живы, но HTTP-обмена нет (замерено 2026-10-05):
    { pattern = "rubyvidhub",          reason = "CF «чёрная дыра»: TLS жив, HTTP не отвечает (живьём 2026-10-05)" },
    { pattern = "streamruby",          reason = "CF «чёрная дыра»: TLS жив, HTTP не отвечает (живьём 2026-10-05)" },
    { pattern = "uptostream",          reason = "DNS/TLS жив, HTTP не отвечает (живьём 2026-10-05)" },
    { pattern = "larhu",               reason = "парковка parklogic, а CDN fav.larhu.website без DNS-записи A/AAAA (живьём 2026-10-05)" },
    { pattern = "vadbam",              reason = "парковка parklogic: embed отдаёт страницу редиректа router.parklogic.com (живьём 2026-10-05)" },
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
-- UA на самой выдаче CDN не важен — 200 с любым/без UA. Тот же десктопный
-- Chrome шлём в seekplayer API: без браузерного UA сервер отвечает 400
-- (живьём 2026-10-05).
local BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
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
            headers = { ["User-Agent"] = BROWSER_UA },
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

-- ============ Порты резолверов из ar/witanime.lua + новые хосты ============
-- ok.ru, uqload, vkvideo и mail.ru проверены живьём 2026-10-05 (curl):
-- ok.ru отдаёт hlsManifestUrl + видео, uqload.vc — распакованный jwplayer,
-- vk.com/video_ext.php — mp4_*, my.mail.ru/+/video/meta — mp4 (206 по Range).

-- Заголовок ответа: у CF/VK имена регистрозависимы.
local function headerValue(headers, name)
    local v = headers and (headers[name] or headers[string.lower(name)])
    if type(v) == "table" then return v[1] end
    if type(v) == "string" then return v end
    return nil
end

-- XOR двух байтов (0..255) без библиотеки bit — семантика LuaJ/Lua 5.1.
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

-- base64 → таблица байтов: base64_decode движка отдаёт строку, а RC4
-- считает байты.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function base64Bytes(s)
    s = (s or ""):gsub("%s+", "")
    local out, buf, bits = {}, 0, 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch == "=" then break end
        local v = B64_INDEX[ch]
        if v ~= nil then
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = math.floor(buf / 2 ^ bits) % 256
                buf = buf % 2 ^ bits
            end
        end
    end
    return out
end

local function rc4(key, data)
    local S, j = {}, 0
    for i = 0, 255 do S[i] = i end
    for i = 0, 255 do
        j = (j + S[i] + key:byte((i % #key) + 1)) % 256
        S[i], S[j] = S[j], S[i]
    end
    local a, b = 0, 0
    local out = {}
    for n = 1, #data do
        a = (a + 1) % 256
        b = (b + S[a]) % 256
        S[a], S[b] = S[b], S[a]
        out[n] = xb(data[n], S[(S[a] + S[b]) % 256])
    end
    return out
end

-- Кандидат: без медиа-расширения это HLS-источник — с mime = "hls"
-- media3 не гадает по URL (см. комментарий у hasMediaExt).
-- Ветка, а не `and/or`: `hasMediaExt(url) and nil or "hls"` из-за ловушки
-- and/or давало бы "hls" и для .mp4 (nil из and затирается or).
local function pushCandidate(candidates, url, quality, referer, headers)
    if type(url) ~= "string" or url == "" then return false end
    local mime
    if not hasMediaExt(url) then mime = "hls" end
    candidates[#candidates + 1] = {
        url = url, quality = quality, referer = referer, headers = headers,
        mime = mime,
    }
    return true
end

-- ---- ok.ru: data-options → flashvars.metadata ----
local function resolveOkRu(body, entry, candidates)
    local opts = body:match('data%-options="([^"]+)"')
    if not opts then
        log_error("Anime4Up: " .. entry.quality .. " — ok.ru: нет data-options")
        return 0
    end
    opts = opts:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<")
        :gsub("&gt;", ">"):gsub("&amp;", "&")
    local ok, data = pcall(json_parse, opts)
    local meta = ok and type(data) == "table" and data.flashvars
        and data.flashvars.metadata or nil
    if type(meta) == "string" then
        local mok, m = pcall(json_parse, meta)
        meta = mok and m or nil
    end
    if type(meta) ~= "table" then
        log_error("Anime4Up: " .. entry.quality .. " — ok.ru: нет metadata")
        return 0
    end
    local added = 0
    if type(meta.hlsManifestUrl) == "string" and meta.hlsManifestUrl ~= "" then
        if pushCandidate(candidates, meta.hlsManifestUrl, "ok.ru · HLS", "https://ok.ru/") then
            added = added + 1
        end
    end
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            local name = type(v) == "table" and type(v.name) == "string" and v.name or nil
            if u and u ~= "" then
                local q = name and ("ok.ru · " .. name) or ("ok.ru · " .. entry.quality)
                if pushCandidate(candidates, u, q, "https://ok.ru/") then added = added + 1 end
            end
        end
    end
    if added == 0 then log_error("Anime4Up: " .. entry.quality .. " — ok.ru: пустая metadata") end
    return added
end

-- ---- dailymotion: player/metadata → master m3u8 ----
-- Живьём 2026-10-05: metadata отдаётся без ts/v1st (нужен только id), а вот
-- сам master с этой сети закрыт CF (403 E005) — поэтому при неудаче пробы
-- возвращаем master как есть: media3 откроет его с теми же заголовками.
local DM_URL = "https://www.dailymotion.com"

local function dmHeaders(referer)
    return {
        ["Accept"]  = "*/*",
        ["Referer"] = referer or (DM_URL .. "/"),
        ["Origin"]  = DM_URL,
    }
end

local function resolveDailymotion(entry, candidates)
    local id = entry.link:match("[?&]video=([^&#]+)")
    if not id then
        local path = (entry.link:match("^[^?#]*") or ""):gsub("/+$", "")
        id = path:match("([^/]+)$")
    end
    if not id or id == "" then
        log_error("Anime4Up: " .. entry.quality .. " — dailymotion: нет id видео")
        return 0
    end
    local r = http_get(DM_URL .. "/player/metadata/video/" .. url_encode(id) .. "?locale=en-US",
        { headers = dmHeaders(entry.link), timeout = 10000 })
    local meta = r.success and json_parse(r.body) or nil
    local auto = type(meta) == "table" and meta.qualities and meta.qualities.auto or nil
    local master = type(auto) == "table" and type(auto[1]) == "table" and auto[1].url or nil
    if type(master) ~= "string" or master == "" then
        log_error("Anime4Up: " .. entry.quality .. " — dailymotion: в metadata нет qualities.auto")
        return 0
    end
    if not pushCandidate(candidates, master, "Dailymotion · HLS", entry.link, dmHeaders(entry.link)) then
        return 0
    end
    return 1
end

-- ---- videa.hu: обфускация _xt → XML (RC4 + base64) → ссылки с md5 ----
-- Порт resolveVidea из ar/witanime.lua (там же — источник схемы).
local VIDEA_O = "xHb0ZvME5q8CBcoQi6AngerDu3FGO9fkUlwPmLVY_RTzj2hJIS4NasXWKy1td7p"
local VIDEA_R = { "e", "a", "g", "j", "d", "c", "h", "i", "b", "f" }
local VIDEA_RR = { "f", "h", "c", "b", "i" }

local function videaToken(xt)
    local c = {}
    for i = 1, #xt do
        local i0 = i - 1
        local k = VIDEA_R[math.floor(i0 / 8) + 2]
        if not k then return nil end
        if i0 % 8 == 0 then c[k] = "" end
        c[k] = (c[k] or "") .. xt:sub(i, i)
    end
    local d = (c.a or "") .. (c.g or "") .. (c.j or "") .. (c.d or "")
    local u = (c.c or "") .. (c.h or "") .. (c.i or "") .. (c.b or "")
    -- обе половинки обязаны быть собраны целиком, иначе токен неверный
    if d == "" or u == "" then return nil end
    local m = {}
    for i = 1, #d do
        local oi = VIDEA_O:find(d:sub(i, i), 1, true)
        if not oi then return nil end
        local at = i - (oi - 32)
        if at < 1 or at > #u then return nil end
        m[i] = u:sub(at, at)
    end
    local mm = table.concat(m)
    c = {}
    for i = 1, #mm do
        local i0 = i - 1
        local k = VIDEA_RR[math.floor(i0 / 8) + 2]
        if k then
            if i0 % 8 == 0 then c[k] = "" end
            c[k] = (c[k] or "") .. mm:sub(i, i)
        end
    end
    c.f = ""
    return { t = (c.h or "") .. (c.c or ""), k = (c.b or "") .. (c.i or "") }
end

local function resolveVidea(body, entry, candidates)
    local vcode = entry.link:match("[?&]v=([%w]+)")
    if not vcode then
        log_error("Anime4Up: " .. entry.quality .. " — videa: в ссылке нет v=")
        return 0
    end
    local xt = body:match('_xt%s*=%s*"([^"]+)"') or body:match("_xt%s*=%s*'([^']+)'")
    if not xt then
        log_error("Anime4Up: " .. entry.quality .. " — videa: не найден _xt")
        return 0
    end
    local parts = videaToken(xt)
    if not parts then
        log_error("Anime4Up: " .. entry.quality .. " — videa: не удалось разобрать _xt")
        return 0
    end
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local rnd = {}
    for i = 1, 8 do
        local n = math.random(#chars)
        rnd[i] = chars:sub(n, n)
    end
    rnd = table.concat(rnd)
    local xmlUrl = "https://videa.hu/player/xml?v=" .. url_encode(vcode)
        .. "&_t=" .. url_encode(parts.t)
        .. "&_s=" .. url_encode(rnd)
        .. "&platform=desktop&lang=en&start=0"
    local r = http_get(xmlUrl, { headers = { ["Referer"] = entry.link }, timeout = 10000 })
    if not r.success then
        log_error("Anime4Up: " .. entry.quality .. " — videa: XML HTTP " .. tostring(r.code))
        return 0
    end
    local contentType = headerValue(r.headers, "content-type") or ""
    local xml
    if string_starts_with(contentType, "text/xml") then
        xml = r.body
    else
        local xs = headerValue(r.headers, "x-videa-xs") or ""
        local bytes = rc4(parts.k .. rnd .. xs, base64Bytes(r.body))
        local p = {}
        for i = 1, #bytes do p[i] = string.char(bytes[i]) end
        xml = table.concat(p)
    end
    local err = xml:match("<error[^>]*>([^<]*)</error>")
    if err then
        log_error("Anime4Up: " .. entry.quality .. " — videa: " .. err)
        return 0
    end
    local exp = xml:match('<video_sources[^>]*exp="(%d+)"')
        or xml:match('<video_source[^>]*exp="(%d+)"')
    if not exp then
        log_error("Anime4Up: " .. entry.quality .. " — videa: в XML нет exp")
        return 0
    end
    local hashes = {}
    for name, h in xml:gmatch("<hash_value_([^>]+)>([^<]+)</hash_value_>") do
        hashes[name] = h
    end
    local added = 0
    for name, path in xml:gmatch('<video_source name="([^"]+)"[^>]*>([^<]+)</video_source>') do
        local md5 = hashes[name]
        if md5 then
            local u = "https:" .. path .. "?md5=" .. md5 .. "&expires=" .. exp
            if pushCandidate(candidates, u, "videa · " .. name, "https://videa.hu/") then
                added = added + 1
            end
        end
    end
    if added == 0 then log_error("Anime4Up: " .. entry.quality .. " — videa: в XML нет источников") end
    return added
end

-- ---- drive.google: usercontent/download (порт из ar/animephoenix.lua) ----
-- Живьём 2026-10-03: usercontent с confirm=t отдаёт 206 без единого заголовка.
-- ponytail: playback-API-фоллбэк для «download disabled» (403 + UA-биндинг)
-- не делаем — ставим, если на сайте реально встретятся залоченные ссылки.
local function driveDirectUrl(link)
    local host = (link:match("^https?://([^/]+)"):gsub("^www%.", "")):lower()
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

-- ---- Packed-JS: eval(function(p,a,c,k,e,d){…}('…',62,N,'a|b|c'.split('|'))) ----
-- Словарь символов разворачивается обратно в строку payload. Порт unpack.py
-- из mediaflow-proxy; проверено на uqload.vc живьём 2026-10-05.

local function baseN(tok, radix)
    local v = 0
    for i = 1, #tok do
        local c = tok:byte(i)
        local d
        if c >= 48 and c <= 57 then d = c - 48
        elseif c >= 97 and c <= 122 then d = c - 87
        elseif c >= 65 and c <= 90 then d = c - 29
        else return nil end
        if d >= radix then return nil end
        v = v * radix + d
    end
    return v
end

local function unpackPacked(body)
    if not body:find("p,a,c,k,e,d", 1, true) then return "" end
    local payload, radix, _, syms = body:match("}%('(.-)',(%d+),(%d+),'([^']*)'%.split%('|'%)")
    if not payload then
        payload, radix, _, syms = body:match("%('(.-)',(%d+),(%d+),'([^']*)'%.split%('|'%)")
    end
    if not payload then return "" end
    local b = tonumber(radix)
    if not b or b < 2 then return "" end
    local dict, i = {}, 1
    for tok in (syms .. "|"):gmatch("(.-)|") do
        dict[i] = tok
        i = i + 1
    end
    return (payload:gsub("%w+", function(tok)
        local v = baseN(tok, b)
        local s = v and dict[v + 1] or nil
        if type(s) == "string" and s ~= "" then return s end
        return tok
    end))
end

-- Ссылки на поток из тела плеера: распакованный текст + исходный. Конфиг
-- jwplayer лежит в распакованном виде, поэтому голый sources:-паттерн по телу
-- не матчит. В file:"…" лежат и сабы/логотипы — берём только media-суффикс.
local function packedMediaUrls(body)
    local text = body
    local un = unpackPacked(body)
    if un ~= "" then text = un .. "\n" .. body end
    local out, seen = {}, {}
    local function add(u)
        if seen[u] or not string_starts_with(u, "http") then return end
        if not hasMediaExt(u) then return end
        seen[u] = true
        out[#out + 1] = u:gsub("\\/", "/"):gsub("&amp;", "&")
    end
    for u in text:gmatch('file:%s*"([^"]+)"') do add(u) end
    for u in text:gmatch("file:%s*'([^']+)'") do add(u) end
    for u in text:gmatch('"file"%s*:%s*"([^"]+)"') do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.m3u8[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.mp4[^"'%s<>\\]*]]) do add(u) end
    return out
end

-- ---- uqload: embed (301 → uqload.vc) → packed-JS → jwplayer sources ----
-- Живьём 2026-10-05: /embed-<id>.html отдаёт распакованный
-- jwplayer("vplayer").setup({sources:[{file:"…/master.m3u8?…"}]}).
local function resolveUqload(body, entry, candidates)
    local urls = packedMediaUrls(body)
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "uqload · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — uqload: нет источников в packed-JS")
    end
    return added
end

-- ---- vidmoly: window.location.replace → редирект на плеер ----
-- UNVERIFIED: живьём 2026-10-05 embed отдал 495 байт с window.location.replace,
-- а следующий шаг (Cherami/Express) плеера не отдал — с этой сети схема до
-- конца не доходит. Реализация по референсу; на живой ссылке сработает ли —
-- проверить не удалось.
local function resolveVidmoly(body, entry, candidates)
    local target = body:match("window%.location%.replace%(%s*['\"]([^'\"]+)['\"]")
    local embId = entry.link:match("embed%-([%w_%-]+)") or ""
    local heads = {
        ["Referer"] = entry.link,
        ["Sec-Fetch-Dest"] = "iframe",
        ["Sec-Fetch-Mode"] = "navigate",
        ["Sec-Fetch-Site"] = "same-site",
    }
    -- Turnstile-демо-кука vidmoly: без неё следующий шаг отдаёт заглушку.
    if embId ~= "" then
        heads["Cookie"] = "cf_turnstile_demo_pass_" .. embId .. "=1"
    end
    if target and target ~= "" then
        local r = http_get(absUrl(target), { headers = heads, timeout = 10000 })
        if r.success and type(r.body) == "string" and r.body ~= "" then
            body = r.body
        end
    end
    local added = 0
    for _, u in ipairs(packedMediaUrls(body)) do
        if pushCandidate(candidates, u, "vidmoly · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — vidmoly: после редиректа нет источников")
    end
    return added
end

-- ---- mail.ru: embed → metadataUrl → /+/video/meta/<id> → mp4 ----
-- Живьём 2026-10-05: embed отдаёт "metadataUrl":"//my.mail.ru/+/video/meta/<id>",
-- meta-JSON — videos[].url, mp4 отвечает 206 на Range с Referer'ом эмбеда.
local function resolveMailRu(body, entry, candidates)
    local meta = body:match('metadataUrl":"([^"]+)')
    if not meta then
        log_error("Anime4Up: " .. entry.quality .. " — mail.ru: в embed нет metadataUrl")
        return 0
    end
    local r = http_get((meta:gsub("^//", "https://")), {
        headers = {
            ["Referer"] = entry.link,
            ["X-Requested-With"] = "XMLHttpRequest",
        },
        timeout = 10000,
    })
    if not r.success then
        log_error("Anime4Up: " .. entry.quality .. " — mail.ru: meta HTTP " .. tostring(r.code))
        return 0
    end
    local data = json_parse(r.body)
    local videos = type(data) == "table" and data.videos or nil
    if type(videos) ~= "table" then
        log_error("Anime4Up: " .. entry.quality .. " — mail.ru: в meta нет videos[]")
        return 0
    end
    local added = 0
    for _, v in ipairs(videos) do
        local u = type(v) == "table" and v.url or nil
        local key = type(v) == "table" and type(v.key) == "string" and v.key or nil
        if type(u) == "string" and u ~= "" then
            local q = key and ("Mail.ru · " .. key) or ("Mail.ru · " .. entry.quality)
            if pushCandidate(candidates, u:gsub("^//", "https://"), q, entry.link) then
                added = added + 1
            end
        end
    end
    if added == 0 then log_error("Anime4Up: " .. entry.quality .. " — mail.ru: в videos[] нет ссылок") end
    return added
end

-- ---- share4max: Inertia-приложение → partial-ответ files/mirror/video ----
-- UNVERIFIED: живую ссылку на файл получить не удалось (главная без листингов,
-- robots.txt = Disallow: /, все угаданные пути — 404), схема перенесена из
-- референса (Animerco.kt / Share4maxInertiaResponse). Значение version берётся
-- из <script data-page="app"> страницы, потоки — из props.streams частичного
-- ответа; адреса зеркал уходят на повторную диспетчеризацию.
-- Версия Inertia лежит в <script data-page="app" type="application/json">:
-- {"component":…,"props":{…},"version":"a601a2d0…"} (проверено на главной
-- share4max.com живьём 2026-10-05).
local function share4maxVersion(body)
    local payload = body:match('data%-page="app"[^>]*>(.-)</script>')
    if not payload then return nil end
    return payload:match('"version":"([^"]+)"')
end

local function resolveShare4max(body, entry, candidates, followups)
    local version = share4maxVersion(body)
    if not version then
        local r = http_get(entry.link, { timeout = 10000 })
        version = r.success and share4maxVersion(r.body) or nil
    end
    if not version then
        log_error("Anime4Up: " .. entry.quality .. " — share4max: не найдена версия Inertia")
        return 0
    end
    local r = http_get(entry.link, {
        headers = {
            ["X-Inertia"] = "true",
            ["X-Requested-With"] = "XMLHttpRequest",
            ["X-Inertia-Version"] = version,
            ["X-Inertia-Partial-Component"] = "files/mirror/video",
            ["X-Inertia-Partial-Data"] = "streams",
            ["Referer"] = entry.link,
        },
        timeout = 10000,
    })
    if not r.success then
        log_error("Anime4Up: " .. entry.quality .. " — share4max: partial HTTP " .. tostring(r.code))
        return 0
    end
    local ok, data = pcall(json_parse, r.body)
    local props = ok and type(data) == "table" and data.props or nil
    local streams = type(props) == "table" and props.streams or nil
    if type(streams) ~= "table" then
        log_error("Anime4Up: " .. entry.quality .. " — share4max: в partial-ответе нет props.streams")
        return 0
    end
    local added, queued = 0, 0
    for _, s in ipairs(streams) do
        if type(s) == "table" then
            local u = type(s.url) == "string" and s.url
                or (type(s.src) == "string" and s.src)
                or (type(s.link) == "string" and s.link) or nil
            if u and u ~= "" then
                local name = type(s.name) == "string" and s.name
                    or (type(s.server) == "string" and s.server) or nil
                local label = name and ("share4max · " .. name) or "share4max"
                if hasMediaExt(u) then
                    if pushCandidate(candidates, u, label, entry.link) then added = added + 1 end
                else
                    followups[#followups + 1] = { link = absUrl(u), quality = label }
                    queued = queued + 1
                end
            end
        end
    end
    if added == 0 and queued == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — share4max: пустой props.streams")
    end
    return added
end

-- ---- vkvideo: video_ext.php → files.mp4_* (живьём 2026-10-05, 2026-10-07) ----
-- Схема: id из ссылки (video-<oid>_<id> / clip-<oid>_<id> / ?oid=&id=) →
-- https://vk.com/video_ext.php?oid=&id=[&hash=] → JSON-подобный блок "files"
-- с mp4_144…mp4_1080.
-- Живьём 2026-10-07 (серия One Piece 1180 → vkvideo.ru/video_ext.php):
-- * сами ссылки files — okcdn БЕЗ медиа-расширения (https://vkvd559.okcdn.ru/
--   ?expires=…), тело — mp4-байты (206 по Range, magic ftypisom);
--   pushCandidate поставил бы mime = "hls" (нет расширения) и media3 падал
--   ParserException'ом «Input does not start with the #EXTM3U header» →
--   поэтому здесь mime = "mp4" задаётся явно (см. resolveDood: тот же случай);
-- * подпись srcAg в URL берётся из UA запроса video_ext: движок шлёт Chrome
--   Android, и okcdn отвечает 206 на UA плеера (ExoPlayer/Android/curl)
--   независимо от Referer; URL, подписанный десктопным Chrome, принимает
--   только десктопный Chrome — поэтому UA в video_ext не перебиваем.
-- vkvideo.ru сам в редирект-цикле на login.vk.ru, поэтому ходим на vk.com.
local function resolveVkVideo(entry, candidates)
    local oid, vid = entry.link:match("/video_(-?%d+)_(-?%d+)")
        or entry.link:match("/clip_(-?%d+)_(-?%d+)")
    if not oid then
        oid = entry.link:match("[?&]oid=(-?%d+)")
        vid = entry.link:match("[?&]id=(-?%d+)")
    end
    if not (oid and vid) then
        log_error("Anime4Up: " .. entry.quality .. " — vkvideo: не найдены oid/id")
        return 0
    end
    local url = "https://vk.com/video_ext.php?oid=" .. oid .. "&id=" .. vid
    local hash = entry.link:match("[?&]hash=([%w_%-]+)")
    if hash then url = url .. "&hash=" .. hash end
    local r = http_get(url, {
        headers = { ["Referer"] = "https://vk.com/" },
        charset = "windows-1251",
        timeout = 10000,
    })
    if not r.success then
        log_error("Anime4Up: " .. entry.quality .. " — vkvideo: video_ext HTTP " .. tostring(r.code))
        return 0
    end
    local files = r.body:match('"files":{(.-)}')
    if not files then
        log_error("Anime4Up: " .. entry.quality .. " — vkvideo: в video_ext нет files{}")
        return 0
    end
    local variants = {}
    for q, u in files:gmatch('"mp4_(%d+)":"([^"]+)"') do
        variants[#variants + 1] = { q = tonumber(q) or 0, u = u:gsub("\\/", "/") }
    end
    table.sort(variants, function(a, b) return a.q > b.q end)
    local added = 0
    for _, v in ipairs(variants) do
        -- Прямая вставка вместо pushCandidate: URL без расширения, но тело —
        -- mp4, mime "hls" сломало бы воспроизведение (см. заголовок ветки).
        candidates[#candidates + 1] = {
            url     = v.u,
            quality = "VK · " .. v.q .. "p",
            referer = "https://vk.com/",
            mime    = "mp4",
        }
        added = added + 1
    end
    if added == 0 then log_error("Anime4Up: " .. entry.quality .. " — vkvideo: в files нет mp4") end
    return added
end

-- ---- hgcloud: страница /e/<id> → зеркало с packed-конфигом ----
-- Живьём 2026-10-06: HTTP-редиректа на зеркало НЕТ — hgcloud.to/e/<id> отдаёт
-- 452 байта заглушки с <script src="/main.js?v=1.1.9">, и переход на случайное
-- зеркало делает клиентский main.js (домен собирается в рантайме, статически не
-- извлекается) → зеркала перебираем сами, путь эмбеда берём из исходного URL.
-- На зеркале лежит packed-конфиг: ссылки в links = {hls2:…, hls3:…}, а setup
-- берёт file: links.hls4||links.hls3||links.hls2 — голый file:"…" не матчит,
-- поэтому тут свой сбор URL.
-- Зеркала ротатора hgcloud.to (main.js, наблюдение 2026-10-06); если
-- перестанут отдавать конфиг — обновить по main.js ротатора.
local HGCLOUD_MIRRORS = { "hanerix.com", "vibuxer.com", "audinifer.com" }

local function hgcloudMediaUrls(body)
    local text = body
    local un = unpackPacked(body)
    if un ~= "" then text = un .. "\n" .. body end
    local out, seen = {}, {}
    local function add(u)
        if seen[u] then return end
        seen[u] = true
        out[#out + 1] = u:gsub("\\/", "/"):gsub("&amp;", "&")
    end
    -- Порядок = приоритет: первый кандидат — master.txt (hls3 из hls4||hls3).
    for u in text:gmatch([[https?://[^"'%s<>\\]+master%.txt[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+master%.m3u8[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.m3u8[^"'%s<>\\]*]]) do add(u) end
    return out
end

-- Входное тело уже получено диспетчером (он же переходит по 3xx): если хост
-- начнёт отдавать контент или редирект напрямую — разбирается здесь же.
-- Таймаут 8 с на каждый запрос, максимум 3 зеркала.
local function resolveHgcloud(body, entry, candidates)
    local finalRef = entry.link
    local urls = hgcloudMediaUrls(body)
    -- Заглушка? Путь эмбеда (/e/<id>) сохраняем из исходного URL.
    local path = body:find("/main.js", 1, true)
        and entry.link:match("^https?://[^/]+(/[^?#]*)") or nil
    local tried = {}
    for i = 1, #HGCLOUD_MIRRORS do
        if not path or #urls > 0 then break end
        local mirror = HGCLOUD_MIRRORS[i]
        local ref = "https://" .. mirror .. "/"
        local url = "https://" .. mirror .. path
        local r = http_get(url, { headers = { ["Referer"] = ref }, timeout = 8000 })
        local code = (r and r.code) or -1
        local b = (r and type(r.body) == "string") and r.body or ""
        tried[#tried + 1] = tostring(code) .. " " .. url
        local mu = hgcloudMediaUrls(b)
        if #mu > 0 then urls, finalRef = mu, ref end
    end
    if #urls == 0 then
        -- finalRef = страница, с которой взят конфиг: без неё master.txt и
        -- сегменты отдают 404 (живьём 2026-10-06).
        log_error("Anime4Up: " .. entry.quality .. " — hgcloud: нет packed-конфига; "
            .. (path and ("ответы: " .. table.concat(tried, ", "))
                or "входная страница без packed и без main.js: " .. entry.link))
        return 0
    end
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "hgcloud · " .. entry.quality, finalRef) then
            added = added + 1
        end
    end
    return added
end

-- ============ seekplayer (клон StreamWish) ============
-- Хостер-метка streamwish и сам seekplayer.vip отдают SPA: конфиг плеера в JS,
-- в HTML потоков нет. Источники — в ответе /api/v1/video?id=…: hex-блоб,
-- расшифровываемый AES-128-CBC (ключ/IV — фиксированные ASCII-константы
-- бандла te()/oe()); aes_decrypt ждёт шифртекст в base64, поэтому hex
-- переводится посчитанной hexToBase64 — бинарная строка (байты ≥0x80) не
-- создаётся. Ответ /api/v1/info?id= — только метаданные, источников не несёт.
-- Сервер принимает только браузерный User-Agent: curl-UA → HTTP 400
-- (живьём 2026-10-05), поэтому шлём BROWSER_UA.
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
-- (строка → повторный json_parse), без него — порядок по умолчанию; относительный
-- URL (Tiktok) резолвится в origin эмбеда, /hls/ переписывается в
-- /hlsmod/<домен>/ по adjust.<имя>.domain, params добавляются в query.
-- Прямой cf (.txt на cdn) всегда отдаёт 403 — не берём; приоритет за cfNative.
-- Возвращает число добавленных кандидатов, каждая ошибка — log_error + 0
-- (ветки диспетчера ниже ведут себя так же).
local function resolveSeekplayer(entry, candidates)
    local link = entry.link
    local origin = link:match("^(https?://[^/]+)")
    local path = link:match("^https?://[^/]+/([^?#]*)")
    local id = path and path:match("^([^&]+)") or nil
    if not origin or not id or #id <= 1 then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: в embed нет id")
        return 0
    end
    local refHost = (link:match("^https?://([^/]+)"):gsub("^www%.", ""))
    local url = origin .. "/api/v1/video?id=" .. id .. "&w=1920&h=1080&r=" .. refHost
    local r = http_get(url, {
        headers = {
            ["Referer"]    = origin .. "/",
            ["User-Agent"] = BROWSER_UA,
        },
        timeout = 8000,
    })
    local body = (r and r.success and type(r.body) == "string") and r.body or ""
    if body == "" then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: /api/v1/video — HTTP "
            .. tostring(r and r.code or -1))
        return 0
    end
    local hex = body:gsub("%s", ""):lower()
    if #hex == 0 or #hex % 2 ~= 0 or hex:match("[^%x]") then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: ответ не hex")
        return 0
    end
    local plain = aes_decrypt(hexToBase64(hex), SP_KEY, SP_IV)
    if type(plain) ~= "string" or plain == "" then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: AES-расшифровка не удалась")
        return 0
    end
    local data = json_parse(plain)
    if type(data) ~= "table" then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: расшифрованный ответ не JSON")
        return 0
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
    local added = 0
    for _, name in ipairs(order) do
        local u = map[name]
        local adj = type(adjust[name]) == "table" and adjust[name] or {}
        if type(u) == "string" and u ~= "" and not adj.disabled then
            local abs = url_resolve(origin, u)
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
            candidates[#candidates + 1] = {
                url = abs, quality = entry.quality, referer = origin, mime = "hls",
            }
            added = added + 1
        end
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: в JSON нет ни одного источника")
    end
    return added
end

-- ============ dood / playmogo ============
-- Схема (референс DoodExtractor, docs/hoster-implementations.md): в embed есть
-- путь /pass_md5/<...>, тело которого — начало финального URL; к нему
-- дописываются 10 случайных символов и "?token=<последний сегмент>&expiry=".
-- expiry = Date.now() в МИЛЛИСЕКУНДАХ — проверено по inline-коду плеера
-- playmogo.com/e/yx3yl4w4y9br (живьём 2026-10-07), os_time() в NoveLA тоже
-- миллисекунды. Финал — mp4 на cloudatacdn.com (без расширения → mime = "mp4"),
-- Referer потока = origin embed (без него CDN отвечает 302). Капча-вариант
-- embed отдаётся без /pass_md5 — тогда ветка логирует отказ.
local RANDOM_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function resolveDood(body, entry, candidates)
    local md5 = type(body) == "string" and body:match("(/pass_md5/[^'\"]+)") or nil
    local origin = entry.link:match("^(https?://[^/]+)")
    if not md5 or not origin then
        log_error("Anime4Up: " .. entry.quality .. " — dood: в embed нет /pass_md5")
        return 0
    end
    local token = md5:match("([^/]+)$")
    local r = http_get(origin .. md5, {
        headers = { ["Referer"] = entry.link }, timeout = 8000,
    })
    local start = r and r.success and type(r.body) == "string"
        and r.body:match("^%s*(https?://.-)%s*$") or nil
    if not start then
        local b = r and type(r.body) == "string" and r.body or ""
        log_error("Anime4Up: " .. entry.quality .. " — dood: /pass_md5 — "
            .. (b:find("RELOAD", 1, true) and "RELOAD"
                or ("HTTP " .. tostring(r and r.code or -1))))
        return 0
    end
    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd)
        .. "?token=" .. token .. "&expiry=" .. tostring(os_time())
    candidates[#candidates + 1] = {
        url = url, quality = entry.quality, referer = origin .. "/", mime = "mp4",
    }
    return 1
end

-- Диспетчер по хосту (порты extractVideos из Anime4Up.kt + новые ветки).
-- Возвращает число добавленных кандидатов; адреса, которые сами по себе не
-- поток (зеркала-плееры share4max), кладёт в followups на повторный проход.
-- directLinks (общий скан mp4upload/sendvid/…) вызывается вызывающим кодом
-- как фоллбэк — здесь только хосты со своим форматом.
local function dispatchHost(e, body, candidates, followups)
    local low = e.link:lower()
    if low:find("voe%.") then
        return resolveVoe(body, e, candidates)
    elseif low:find("vidyard") then
        return resolveVidYard(e, candidates)
    elseif low:find("shared") then
        return resolveShared(body, e, candidates)
    elseif isVidbomLink(e.link) then
        return resolveVidbom(body, e, candidates)
    elseif low:find("ok%.ru") or low:find("okru") then
        return resolveOkRu(body, e, candidates)
    elseif low:find("uqload") then
        return resolveUqload(body, e, candidates)
    elseif low:find("vidmoly") then
        return resolveVidmoly(body, e, candidates)
    elseif low:find("videa%.hu") then
        return resolveVidea(body, e, candidates)
    elseif low:find("dailymotion") then
        return resolveDailymotion(e, candidates)
    elseif low:find("mail%.ru") then
        return resolveMailRu(body, e, candidates)
    elseif low:find("share4max") then
        return resolveShare4max(body, e, candidates, followups)
    elseif low:find("vkvideo") or low:find("vk%.com") or low:find("vk%.ru") then
        return resolveVkVideo(e, candidates)
    elseif low:find("hgcloud", 1, true) then
        return resolveHgcloud(body, e, candidates)
    elseif low:find("dood") or low:find("playmogo") or low:find("dsvplay") then
        return resolveDood(body, e, candidates)
    elseif low:find("seekplayer", 1, true) or low:find("streamwish", 1, true) then
        -- Обе метки ведут в один и тот же SPA: API делает сам (body не нужен).
        return resolveSeekplayer(e, candidates)
    end
    return 0
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
    local batchUrls, batchEntries, candidates, followups = {}, {}, {}, {}
    for _, e in ipairs(entries) do
        local reason = skipReason(e.link)
        -- Не and/or: при reason функция всё равно бы вычислялась (ловушка Lua).
        local drive
        if not reason then drive = driveDirectUrl(e.link) end
        if reason then
            log_error("Anime4Up: " .. e.quality .. " — пропущен: " .. reason)
        elseif drive then
            -- usercontent-ссылка уже прямая (проверено живьём 2026-10-03).
            candidates[#candidates + 1] = {
                url = drive, quality = e.quality, referer = "https://drive.google.com/",
            }
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
                local added = dispatchHost(e, body, candidates, followups)
                local urls = directLinks(body)
                if #urls == 0 and added == 0 and #followups == 0 then
                    log_error("Anime4Up: " .. e.quality .. " — нет прямой ссылки (плеер требует JS)")
                end
                for _, u in ipairs(urls) do
                    -- cdn-класс (cdn1/cdn2 ?token=): HLS без расширения.
                    -- Без mime media3 берёт прогрессивный источник и падает
                    -- с UnrecognizedInputFormatException; с mime = "hls"
                    -- Source.Factory уже не гадает по URL. Ветка, а не
                    -- `and/or` — иначе "hls" получил бы и .mp4.
                    local mime
                    if not hasMediaExt(u) then mime = "hls" end
                    candidates[#candidates + 1] = {
                        url = u, quality = e.quality, referer = e.link,
                        mime = mime,
                    }
                end
            end
        end
    end

    -- 2. Повторная диспетчеризация: share4max отдаёт не потоки, а адреса
    --    зеркал-плееров — их тела грузим и разбираем тем же диспетчером.
    --    Два круга достаточно: зеркало ведёт либо в файл, либо в другой embed.
    for _ = 1, 2 do
        if #followups == 0 then break end
        local nextRound = {}
        for _, f in ipairs(followups) do
            local reason = skipReason(f.link)
            if reason then
                log_error("Anime4Up: " .. f.quality .. " — пропущен: " .. reason)
            else
                local r2 = http_get(f.link, {
                    headers = { ["Referer"] = episodeUrl }, timeout = 8000,
                })
                local body = (r2.success and type(r2.body) == "string") and r2.body or ""
                if body == "" then
                    log_error("Anime4Up: " .. f.quality .. " — зеркало-плеер недоступно")
                else
                    local entry = { link = f.link, quality = f.quality }
                    local added = dispatchHost(entry, body, candidates, nextRound)
                    for _, u in ipairs(directLinks(body)) do
                        -- та же ветка, что в pushCandidate/батче: без ловушки
                        -- and/or, иначе .mp4 получил бы mime = "hls".
                        local mime
                        if not hasMediaExt(u) then mime = "hls" end
                        candidates[#candidates + 1] = {
                            url = u, quality = f.quality, referer = f.link,
                            mime = mime,
                        }
                    end
                    if added == 0 and #nextRound == 0 then
                        log_error("Anime4Up: " .. f.quality .. " — в зеркале нет прямой ссылки")
                    end
                end
            end
        end
        followups = nextRound
    end

    -- 3. Дедупликация по URL.
    local sources, seen = {}, {}
    for _, c in ipairs(candidates) do
        pushSource(sources, seen, {
            url        = c.url,
            quality    = c.quality,
            mime       = c.mime,
            headers    = c.headers or { ["Referer"] = c.referer },
            subtitles  = c.subtitles,
        })
    end
    if #sources == 0 then return nil end
    return sources
end
