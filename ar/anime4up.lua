-- Anime4Up — видео-плагин NoveLA (content_type = "video")

content_type = "video"
id           = "anime4up"
name         = "Anime4Up"
version      = "1.1.0"
baseUrl      = "https://w1.anime4up.rest"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/anime4up.png"
-- Обход Cloudflare включён для всех запросов к базовому домену:
-- движок решает челлендж в скрытом WebView и печёт cf_clearance.
cf_options   = { whitelist = false }

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
local DM = tryLib("dailymotion")
local DOOD = tryLib("dood")
local VOE = tryLib("voe")
local SHARED = tryLib("shared")
local VIDBOM = tryLib("vidbom")
local VIDEA = tryLib("videa")
local UQLOAD = tryLib("uqload")
local MAILRU = tryLib("mailru")
local HGCLOUD = tryLib("hgcloud")
local SEEK = tryLib("seekplayer")
local VK = tryLib("vk")
local SHARE4MAX = tryLib("share4max")
local VIDMOLY = tryLib("vidmoly")
local VIDYARD = tryLib("vidyard")

local function ensureEngine()
    local missing = {}
    if rawget(_G, "rc4") == nil then missing[#missing + 1] = "rc4" end
    if rawget(_G, "aes_decrypt") == nil then missing[#missing + 1] = "aes_decrypt" end
    if rawget(_G, "base64_decode") == nil then missing[#missing + 1] = "base64_decode" end
    if rawget(_G, "base64_decode_bytes") == nil then missing[#missing + 1] = "base64_decode_bytes" end
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
    if not URLS or not HLS or not OKRU or not DM or not DOOD or not VOE or not SHARED
        or not VIDBOM or not VIDEA or not UQLOAD or not MAILRU or not HGCLOUD or not SEEK then
        show_error("Libraries not loaded",
            "Open the extensions screen and tap update, then restart the app. " .. (libErr or ""))
        error("Shared libraries not loaded", 0)
    end
end

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
    ensureEngine()
    return fetchList(catalogUrl(index + 1))
end

function getCatalogSearch(index, query)
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local el = html_select_first(d.body, "h1.anime-details-title")
    if not el then return nil end
    local title = string_clean(el.text)
    if title == "" then return nil end
    return title
end

function getBookCoverImageUrl(bookUrl)
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
-- Общая либа hls (union копий: +.mkv из animephoenix — progressive тоже).
-- Обёртка, не алиас: top-level обращение к полю nil-либы упало бы до
-- ensureEngine (плагин молча исчезает — инцидент фазы 1).
local function hasMediaExt(u)
    return HLS.hasMediaExt(u)
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
-- Расшифровка и сбор кандидатов — общая либа voe (decodeJson: rot13 →
-- паттерны → убрать "_" → base64 → сдвиг −3 → reverse → base64 → JSON;
-- extractSources: хоп с BROWSER_UA, сабтитры, source + прямой mp4).

-- VOE-зеркало подписывает токены под User-Agent запроса: мобильный Chrome
-- Android (дефолт рантайма) получает i=0.1 → CDN отвечает 403; десктопный
-- Chrome даёт рабочую подпись (живьём 2026-10-02, матрица mint×fetch).
-- UA на самой выдаче CDN не важен — 200 с любым/без UA. Тот же десктопный
-- Chrome шлём в seekplayer API: без браузерного UA сервер отвечает 400
-- (живьём 2026-10-05).
local BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    .. "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

-- Страница эмбеда → редирект window.location на зеркало → там
-- <script type="application/json">["<шифр>"]</script>.
-- Возвращает число добавленных кандидатов (master.m3u8 + прямой .mp4 + сабы).
local function resolveVoe(pageBody, entry, candidates)
    local list, err = VOE.extractSources(entry.link, pageBody)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — VOE: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        candidates[#candidates + 1] = {
            url        = s.url,
            quality    = entry.quality .. (s.direct and " · MP4" or ""),
            referer    = entry.link,
            subtitles  = s.subtitles,
        }
        added = added + 1
    end
    return added
end

-- ============ VidYard / 4shared / vidbom ============

-- ---- VidYard (порт VidYardExtractor.kt через libs/hosters/vidyard.lua) ----
-- Страница эмбеда не читается: id берётся из самой ссылки, данные лежат
-- в player/<id>.json — разбор и HTTP в либе.
local function pushVidyard(entry, candidates)
    local list, err = VIDYARD.resolve(entry.link)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — VidYard: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        candidates[#candidates + 1] = {
            url = s.url, quality = s.quality, referer = s.referer,
        }
        added = added + 1
    end
    return added
end

-- ---- 4shared (SharedExtractor.kt через libs/hosters/shared.lua) ----
-- Эмбед уже загружен батчем: первый <source src> — и есть прямая ссылка.
local function resolveShared(body, entry, candidates)
    local src = SHARED.extract(body, entry.link)
    if not src then
        log_error("Anime4Up: " .. entry.quality .. " — 4shared: в embed нет <source>")
        return 0
    end
    candidates[#candidates + 1] = {
        url = src, quality = "4Shared: mirror", referer = entry.link,
    }
    return 1
end

-- ---- vidbom (VidBomExtractor.kt через libs/hosters/vidbom.lua) ----
-- isLink/разбор sources[] — в либе (паттерны собраны union'ом из Anime4Up
-- и Witanime, см. отчёт).
local function pushVidbom(body, entry, candidates)
    local list, err = VIDBOM.parseSources(body)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — vidbom: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        -- Референс: "Vidbom: " + label, длиннее 15 символов → "Vidshare: 480p".
        local quality = "Vidbom: " .. (s.quality or "")
        if #quality > 15 then quality = "Vidshare: 480p" end
        candidates[#candidates + 1] = {
            url = s.url, quality = quality, referer = entry.link,
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
-- Разбор — общая либа okru (body уже загружен батчем); логи/подписи — здесь.
local function resolveOkRu(body, entry, candidates)
    local list = OKRU.resolveOkRu(body)
    local added = 0
    for _, s in ipairs(list) do
        local q = s.name and ("ok.ru · " .. s.name) or ("ok.ru · " .. entry.quality)
        if pushCandidate(candidates, s.url, q, s.referer) then
            added = added + 1
        end
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — ok.ru: нет источников")
    end
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
    -- Резолв — общая либа dailymotion (metadata + подписанный fallback);
    -- заголовки кандидата — локальные (CDN закрыт CF, см. комментарий выше).
    local list = DM.resolveDailymotion(entry.link)
    if #list == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — dailymotion: нет источников")
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        if pushCandidate(candidates, s.url, "Dailymotion · HLS", entry.link, dmHeaders(entry.link)) then
            added = added + 1
        end
    end
    return added
end

-- ---- videa.hu: обфускация _xt → XML (RC4 + base64) → ссылки с md5 ----
-- Токен/разбор XML — общая либа videa; HTTP остаётся здесь (свой Referer,
-- таймаут 10s, как в порте resolveVidea из ar/witanime.lua).
local function pushVidea(body, entry, candidates)
    local req, err = VIDEA.request(entry.link, body)
    if not req then
        log_error("Anime4Up: " .. entry.quality .. " — videa: " .. err)
        return 0
    end
    local r = http_get(req.url, { headers = { ["Referer"] = entry.link }, timeout = 10000 })
    if not r.success then
        log_error("Anime4Up: " .. entry.quality .. " — videa: XML HTTP " .. tostring(r.code))
        return 0
    end
    local list, perr = VIDEA.parse(req, r)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — videa: " .. perr)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        if pushCandidate(candidates, s.url, "videa · " .. s.name, "https://videa.hu/") then
            added = added + 1
        end
    end
    if added == 0 then log_error("Anime4Up: " .. entry.quality .. " — videa: в XML нет источников") end
    return added
end

-- ---- drive.google: usercontent/download (либа urls: driveDirectUrl) ----
-- Живьём 2026-10-03: usercontent с confirm=t отдаёт 206 без единого заголовка.
-- ponytail: playback-API-фоллбэк для «download disabled» (403 + UA-биндинг)
-- не делаем — ставим, если на сайте реально встретятся залоченные ссылки.

-- ---- Packed-JS: eval(function(p,a,c,k,e,d){…}('…',62,N,'a|b|c'.split('|'))) ----
-- Распаковка и ссылки из тела плеера — общая либа uqload (packedMediaUrls,
-- там же — комментарии про jwplayer/mediа-суффиксы); engine API unpack_packed
-- проверяется в ensureEngine.

-- ---- uqload: embed (301 → uqload.vc) → packed-JS → jwplayer sources ----
-- Живьём 2026-10-05: /embed-<id>.html отдаёт распакованный
-- jwplayer("vplayer").setup({sources:[{file:"…/master.m3u8?…"}]}).
local function pushUqload(body, entry, candidates)
    local urls, err = UQLOAD.packedMediaUrls(body)
    if not urls then
        log_error("Anime4Up: " .. entry.quality .. " — uqload: " .. err)
        return 0
    end
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
-- конца не доходит. Реализация по референсу; ход на зеркало и packed-JS —
-- общая либа vidmoly (комментарий о непроверке — там же).
local function pushVidmoly(body, entry, candidates)
    local list, err = VIDMOLY.resolve(body, entry.link)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — vidmoly: " .. err)
        return 0
    end
    local added = 0
    for _, u in ipairs(list) do
        if pushCandidate(candidates, u, "vidmoly · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    return added
end

-- ---- mail.ru: embed → metadataUrl → /+/video/meta/<id> → mp4 ----
-- Живьём 2026-10-05: embed отдаёт "metadataUrl":"//my.mail.ru/+/video/meta/<id>",
-- meta-JSON — videos[].url, mp4 отвечает 206 на Range с Referer'ом эмбеда.
-- Разбор и meta-запрос — общая либа mailru.
local function pushMailRu(body, entry, candidates)
    local list, err = MAILRU.resolve(body, entry.link, "Mail.ru · " .. entry.quality)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — mail.ru: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        if pushCandidate(candidates, s.url, s.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then log_error("Anime4Up: " .. entry.quality .. " — mail.ru: в videos[] нет ссылок") end
    return added
end

-- ---- share4max: Inertia-приложение → partial-ответ files/mirror/video ----
-- UNVERIFIED: живую ссылку на файл получить не удалось (главная без листингов,
-- robots.txt = Disallow: /, все угаданные пути — 404), схема перенесена из
-- референса (Animerco.kt / Share4maxInertiaResponse). Версия Inertia и
-- partial-запрос — общая либа share4max; адреса зеркал уходят на повторную
-- диспетчеризацию (followups).
local function pushShare4max(body, entry, candidates, followups)
    local list, err = SHARE4MAX.resolve(body, entry.link)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — share4max: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        if s.direct then
            if pushCandidate(candidates, s.url, s.quality, entry.link) then
                added = added + 1
            end
        else
            -- Зеркало-плеер: его тело загрузит повторная диспетчеризация.
            followups[#followups + 1] = { link = s.url, quality = s.quality }
        end
    end
    return added
end

-- ---- vkvideo: video_ext.php → files.mp4_* (живьём 2026-10-05, 2026-10-07) ----
-- Схема и HTTP (Referer vk.com, windows-1251, 10s) — общая либа vk.
-- Живьём 2026-10-07 (серия One Piece 1180 → vkvideo.ru/video_ext.php):
-- * сами ссылки files — okcdn БЕЗ медиа-расширения (https://vkvd559.okcdn.ru/
--   ?expires=…), тело — mp4-байты (206 по Range, magic ftypisom);
--   pushCandidate поставил бы mime = "hls" (нет расширения) и media3 падал
--   ParserException'ом «Input does not start with the #EXTM3U header» →
--   поэтому в либе mime = "mp4" задаётся явно (см. resolveDood: тот же случай);
-- * подпись srcAg в URL берётся из UA запроса video_ext: движок шлёт Chrome
--   Android, и okcdn отвечает 206 на UA плеера (ExoPlayer/Android/curl)
--   независимо от Referer; URL, подписанный десктопным Chrome, принимает
--   только десктопный Chrome — поэтому UA в video_ext не перебиваем.
-- vkvideo.ru сам в редирект-цикле на login.vk.ru, поэтому ходим на vk.com.
local function pushVkVideo(entry, candidates)
    local list, err = VK.resolve(entry.link)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — vkvideo: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        -- Прямая вставка вместо pushCandidate: URL без расширения, но тело —
        -- mp4, mime "hls" сломало бы воспроизведение (см. заголовок ветки).
        candidates[#candidates + 1] = {
            url     = s.url,
            quality = s.quality,
            referer = s.referer,
            mime    = s.mime,
        }
        added = added + 1
    end
    return added
end

-- ---- hgcloud: страница /e/<id> → зеркало с packed-конфигом ----
-- Живьём 2026-10-06: HTTP-редиректа на зеркало НЕТ — hgcloud.to/e/<id> отдаёт
-- 452 байта заглушки с <script src="/main.js?v=1.1.9">, и переход на случайное
-- зеркало делает клиентский main.js (домен собирается в рантайме, статически не
-- извлекается) → зеркала перебираем сами, путь эмбеда берём из исходного URL.
-- Разбор packed-конфига и обход зеркал — общая либа hgcloud; HTTP (таймаут 8 с
-- на запрос, максимум 3 зеркала) отдаём колбэком.
local function pushHgcloud(body, entry, candidates)
    local urls, finalRef, tried, path = HGCLOUD.resolve(body, entry.link,
        function(url, ref)
            local r = http_get(url, { headers = { ["Referer"] = ref }, timeout = 8000 })
            return (r and type(r.body) == "string") and r.body or "", (r and r.code) or -1
        end)
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
-- (живьём 2026-10-05), поэтому шлём BROWSER_UA. Расшифровка hex-блоба
-- (hexToBase64 + AES-128-CBC + streamingConfig) — общая либа seekplayer;
-- HTTP остаётся здесь.
local function pushSeekplayer(entry, candidates)
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
    local list, err = SEEK.decode(body, origin)
    if not list then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: " .. err)
        return 0
    end
    local added = 0
    for _, s in ipairs(list) do
        candidates[#candidates + 1] = {
            url = s.url, quality = entry.quality, referer = origin, mime = "hls",
        }
        added = added + 1
    end
    if added == 0 then
        log_error("Anime4Up: " .. entry.quality .. " — seekplayer: в JSON нет ни одного источника")
    end
    return added
end

-- ============ dood / playmogo ============
-- Разбор pass_md5 — общая либа dood (embed уже загружен батчем, http_get
-- /pass_md5 — на стороне либы). Капча-вариант embed отдаётся без /pass_md5 —
-- тогда ветка логирует отказ.
local function resolveDood(body, entry, candidates)
    local url, mime, origin = DOOD.resolveDood(entry.link, body)
    if not url then
        log_error("Anime4Up: " .. entry.quality .. " — dood: не удалось получить ссылку")
        return 0
    end
    candidates[#candidates + 1] = {
        url = url, quality = entry.quality, referer = origin, mime = mime,
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
        return pushVidyard(e, candidates)
    elseif low:find("shared") then
        return resolveShared(body, e, candidates)
    elseif VIDBOM.isLink(e.link) then
        return pushVidbom(body, e, candidates)
    elseif low:find("ok%.ru") or low:find("okru") then
        return resolveOkRu(body, e, candidates)
    elseif low:find("uqload") then
        return pushUqload(body, e, candidates)
    elseif low:find("vidmoly") then
        return pushVidmoly(body, e, candidates)
    elseif low:find("videa%.hu") then
        return pushVidea(body, e, candidates)
    elseif low:find("dailymotion") then
        return resolveDailymotion(e, candidates)
    elseif low:find("mail%.ru") then
        return pushMailRu(body, e, candidates)
    elseif low:find("share4max") then
        return pushShare4max(body, e, candidates, followups)
    elseif low:find("vkvideo") or low:find("vk%.com") or low:find("vk%.ru") then
        return pushVkVideo(e, candidates)
    elseif low:find("hgcloud", 1, true) then
        return pushHgcloud(body, e, candidates)
    elseif low:find("dood") or low:find("playmogo") or low:find("dsvplay") then
        return resolveDood(body, e, candidates)
    elseif low:find("seekplayer", 1, true) or low:find("streamwish", 1, true) then
        -- Обе метки ведут в один и тот же SPA: API делает сам (body не нужен).
        return pushSeekplayer(e, candidates)
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
    ensureEngine()
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
        if not reason then drive = URLS.driveDirectUrl(e.link) end
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
