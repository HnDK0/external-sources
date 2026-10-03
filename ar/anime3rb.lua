-- Anime3rb — видео-плагин NoveLA (content_type = "video")
-- Сайт: https://anime3rb.com — каталог аниме, эпизоды с плеером vid3rb.
-- Разбор сверен живьём 2026-10-03 с сырыми ответами сайта: карточки .title-card,
-- страница тайтла (JSON-LD TVSeries/Movie), список эпизодов в HTML и цепочка
-- «эпизод → wire:snapshot → player → video_sources».
-- ВАЖНО: baseUrl без www. www.anime3rb.com отдаёт 301 на https://anime3rb.com/
-- с потерью пути — запрос каталога уходил на корень, получал 403-челлендж
-- Cloudflare и каждый раз запускал обход CF заново (лишние окна WebView).

content_type = "video"
id           = "anime3rb"
name         = "Anime3rb"
version      = "1.0.0"
baseUrl      = "https://anime3rb.com"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/anime3rb.png"

-- ============ Каталог ============

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Рейтинг карточки лежит в span.badge.gap-1 рядом с sr-only «التقييم»;
-- шкала сайта — 10, отдаём в формате, понятном приложению.
local function cardRating(card)
    local badge = html_select_first(card.html, "p > span.badge.gap-1")
    if not badge then return nil end
    local n = string_clean(badge.text):match("%d+%.?%d*")
    if not n then return nil end
    return "Rating: " .. n .. "/10"
end

-- Разметка карточки .title-card одинакова в каталоге и в поиске.
-- Второй селектор — страховка на случай абсолютного href с www или относительных
-- ссылок (проверенный вид ссылки — https://anime3rb.com/titles/...).
local function parseCards(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".title-card")) do
        local link = html_select_first(card.html,
            "a.btn[href^='https://anime3rb.com/titles/'], a[href*='/titles/']")
        local url = link and absUrl(link.href) or ""
        if url ~= "" then
            local h2 = html_select_first(card.html, "h2.title-name")
            local title = h2 and string_clean(h2.text) or ""
            if title ~= "" then
                items[#items + 1] = {
                    title  = title,
                    url    = url,
                    cover  = absUrl(html_attr(card.html, "img", "src")),
                    rating = cardRating(card),
                }
            end
        end
    end
    return items
end

-- Сайт режет пачку быстрых запросов кодом 429 (~6-й подряд) — неудачу логируем.
local function fetchList(url)
    local r = http_get(url)
    if not r.success then
        log_error("Anime3rb: каталог — HTTP " .. tostring(r.code) .. " для " .. url)
        return { items = {}, hasNext = false }
    end
    local items = parseCards(r.body)
    return { items = items, hasNext = #items > 0 }
end

-- Серверная постраничка: 20 карточек на страницу, 321 страница.
function getCatalogList(index)
    return fetchList(baseUrl .. "/titles/list?page=" .. (index + 1))
end

-- Поиск пагинируется тем же ?page=N (сверено живьём: страницы 1 и 2 не пересекаются).
function getCatalogSearch(index, query)
    local url = baseUrl .. "/search?q=" .. url_encode(query)
    if index > 0 then url = url .. "&page=" .. (index + 1) end
    return fetchList(url)
end

-- ============ Фильтры каталога ============
-- Наборы опций сняты с живой панели фильтров 2026-10-03 (дамп tomselect-1..2).

local STATUS_OPTIONS = {
    { value = "finished", label = "منتهي" },
    { value = "running", label = "قيد البث" },
    { value = "upcomming", label = "قادم" },
}

local GENRE_OPTIONS = {
    { value = "action", label = "أكشن" },
    { value = "comedy", label = "كوميدي" },
    { value = "fantasy", label = "خيال" },
    { value = "adventure", label = "مغامرة" },
    { value = "drama", label = "دراما" },
    { value = "shounen", label = "شونين" },
    { value = "romance", label = "رومانسي" },
    { value = "school", label = "مدرسي" },
    { value = "sci-fi", label = "خيال علمي" },
    { value = "supernatural", label = "خارق للطبيعة" },
    { value = "seinen", label = "سينين" },
    { value = "mystery", label = "غموض" },
    { value = "adult-cast", label = "بطولة راشدين" },
    { value = "ecchi", label = "إيتشي" },
    { value = "historical", label = "تاريخي" },
    { value = "slice-of-life", label = "الحياة اليومية" },
    { value = "super-power", label = "قوى خارقة" },
    { value = "mecha", label = "ميكا" },
    { value = "harem", label = "حريم" },
    { value = "military", label = "عسكري" },
    { value = "sports", label = "رياضي" },
    { value = "isekai", label = "إيسيكاي" },
    { value = "suspense", label = "تشويق" },
    { value = "shoujo", label = "شوچو" },
    { value = "mythology", label = "أساطير" },
    { value = "psychological", label = "نفسي" },
    { value = "horror", label = "رعب" },
    { value = "music", label = "موسيقى" },
    { value = "gore", label = "دموي" },
    { value = "parody", label = "ساخر" },
    { value = "martial-arts", label = "قتالي" },
    { value = "detective", label = "بوليسي" },
    { value = "space", label = "فضاء" },
    { value = "cgdct", label = "كيوت" },
    { value = "award-winning", label = "حائز على جوائز" },
    { value = "team-sports", label = "رياضات جماعية" },
    { value = "gag-humor", label = "كوميديا حركية" },
    { value = "kids", label = "للأطفال" },
    { value = "iyashikei", label = "إياشيكي" },
    { value = "urban-fantasy", label = "خيال حضري" },
    { value = "reincarnation", label = "تناسخ و إعادة إحياء" },
    { value = "mahou-shoujo", label = "فتاة ساحرة" },
    { value = "workplace", label = "عمل" },
    { value = "anthropomorphic", label = "أنثروبولوجي" },
    { value = "vampire", label = "مصاصي دماء" },
    { value = "samurai", label = "ساموراي" },
    { value = "time-travel", label = "سفر عبر الزمن" },
    { value = "josei", label = "چوسي" },
    { value = "strategy-game", label = "استراتيجي" },
    { value = "love-polygon", label = "حب متعدد الأطراف" },
    { value = "otaku-culture", label = "ثقافة الأوتاكو" },
    { value = "idols-female", label = "أيدول إناث" },
    { value = "organized-crime", label = "جريمة منظمة" },
    { value = "video-game", label = "ألعاب فيديو" },
    { value = "gourmet", label = "طعام" },
    { value = "survival", label = "نجاة" },
    { value = "performing-arts", label = "فنون استعراضية" },
    { value = "racing", label = "سباق" },
    { value = "girls-love", label = "حب فتيات" },
    { value = "avant-garde", label = "ابتكاري" },
    { value = "reverse-harem", label = "عكس حريم" },
    { value = "combat-sports", label = "رياضات قتالية" },
    { value = "childcare", label = "رعاية أطفال" },
    { value = "visual-arts", label = "فنون بصرية" },
    { value = "love-status-quo", label = "حالة حب" },
    { value = "high-stakes-game", label = "ألعاب عالية المخاطر" },
    { value = "delinquents", label = "جانحون" },
    { value = "idols-male", label = "أيدول ذكور" },
    { value = "pets", label = "حيوانات أليفة" },
    { value = "crossdressing", label = "تنكر في ملابس الجنس الآخر" },
    { value = "medical", label = "طبي" },
    { value = "boys-love", label = "حب فتيان" },
    { value = "magical-sex-shift", label = "تبديل جنسي سحري" },
    { value = "showbiz", label = "صناعة الترفيه" },
    { value = "villainess", label = "شريرة" },
    { value = "erotica", label = "ايروتيكا" },
    { value = "educational", label = "تعليمية" },
}

local AGE_OPTIONS = {
    { value = "g-all-ages", label = "للجميع G" },
    { value = "pg-children", label = "للأطفال PG" },
    { value = "pg-13-teens-13-or-older", label = "للمراهقين من ١٣ عام PG-13" },
    { value = "r-17-violence-profanity", label = "عنف و ألفاظ خارجة R - 17+" },
    { value = "r-mild-nudity", label = "عري خفيف R+" },
    { value = "none", label = "-" },
}

-- Сортировка через URL не добавлена: проверено живьём 2026-10-03 — сервер
-- игнорирует sort_by (rate/name против базы идентичны), sort_dir=asc даёт
-- фиксированный прочий порядок; рабочая сортировка только через
-- Livewire-AJAX, не из GET.
function getFilterList()
    return {
        { type = "checkbox", key = "status",      label = "الحالة",              options = STATUS_OPTIONS },
        { type = "text",     key = "rate",        label = "التقييم (1-10)",      defaultValue = "" },
        { type = "text",     key = "release_year", label = "سنة الإصدار (1900-2026)", defaultValue = "" },
        { type = "text",     key = "videos_count", label = "عدد الحلقات (1-1100)", defaultValue = "" },
        { type = "checkbox", key = "genres",      label = "التصنيفات",           options = GENRE_OPTIONS },
        { type = "checkbox", key = "age_ratings", label = "التصنيفات العمرية",   options = AGE_OPTIONS },
    }
end

-- Параметры добавляются только при непустом значении, скобки в имени
-- параметра не кодируются, значения кодируются url_encode.
-- Семантика (проверена живьём 2026-10-03): множественные жанры — AND
-- (action+fantasy даёт пересечение); диапазоны rate/year/videos применяются
-- сервером (rate=8-10 → все ≥8.16, year=2000-2010 → все годы внутри,
-- videos=12-13 → только 12-13 серий); ?page=N с фильтрами работает;
-- неизвестный слаг age даёт пустую выдачу (фильтр применяется строго).
function getCatalogFiltered(index, filters)
    local url = baseUrl .. "/titles/list?page=" .. (index + 1)

    local function add(key, value)
        if value and value ~= "" then
            url = url .. "&" .. key .. "=" .. url_encode(value)
        end
    end

    local function addArr(key, arr)
        if type(arr) == "table" then
            for i, v in ipairs(arr) do add(key .. "[" .. (i - 1) .. "]", v) end
        end
    end

    add("rate", filters["rate"])
    add("year", filters["release_year"])
    add("videos", filters["videos_count"])
    addArr("status", filters["status_included"])
    addArr("genres", filters["genres_included"])
    addArr("age", filters["age_ratings_included"])

    return fetchList(url)
end

-- ============ Карточка тайтла ============

-- Страницу /titles/{slug}/ читают title/cover/description/genres/status/rating —
-- один HTTP-запрос на сеанс (см. гайд «Кэширование страниц»).
-- getChapterList и getChapterListHash ей НЕ пользуются: свои запросы должны
-- оставаться свежими.
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

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local span = html_select_first(body, "h1.text-2xl.font-bold.uppercase > span[dir='ltr']")
    local title = span and string_clean(span.text) or ""
    if title == "" then
        local h1 = html_select_first(body, "h1")
        title = h1 and string_clean(h1.text) or ""
    end
    return title ~= "" and title or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- Класс постера «max-w-[18rem]» содержит скобки, которые селектор не принимает,
    -- поэтому сравниваем строкой.
    for _, img in ipairs(html_select(body, "img")) do
        if tostring(img:attr("class")):find("max-w-[18rem]", 1, true) then
            local src = absUrl(img.src)
            if src ~= "" then return src end
        end
    end
    return nil
end

-- JSON-LD самого тайтла: у сериалов @type = TVSeries, у фильмов = Movie (оба
-- сверены живьём 2026-10-03). Берём его, а не DOM: первые p.synopsis и
-- .genres span на странице принадлежат чужим карточкам слайдера «похожие».
local function jsonLdTitle(body)
    for raw in body:gmatch('<script[^>]-application/ld%+json[^>]*>(.-)</script>') do
        local ok, data = pcall(json_parse, raw)
        if ok and type(data) == "table"
            and (data["@type"] == "TVSeries" or data["@type"] == "Movie") then
            return data
        end
    end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local d = jsonLdTitle(body)
    local text = type(d.description) == "string" and string_clean(d.description) or ""
    return text ~= "" and text or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local d = jsonLdTitle(body)
    local g = d and d.genre
    local genres = {}
    if type(g) == "table" then
        for _, v in ipairs(g) do
            if type(v) == "string" and v ~= "" then genres[#genres + 1] = v end
        end
    elseif type(g) == "string" and g ~= "" then
        genres[1] = g
    end
    return genres
end

local STATUS_LABEL = "الحالة"

-- Статус — строка таблицы: пара ячеек label/value; ищем ячейку с ярлыком
-- «الحالة» и возвращаем значение как есть (на языке сайта).
-- Ячейки берём плоским селектором "table td", а не перепарсиванием row.html:
-- jsoup выбрасывает голый <tr> при разборе фрагмента (проверено на jsoup 1.23 —
-- 0 td), и статус молча пропадал.
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local tds = html_select(body, "table td")
    for i, td in ipairs(tds) do
        if string_clean(td.text):find(STATUS_LABEL, 1, true) then
            local value = tds[i + 1]
            if value then
                local text = string_clean(value.text)
                if text ~= "" then return text end
            end
        end
    end
    return nil
end

-- Рейтинг из JSON-LD aggregateRating; шкала сайта — 10.
function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local d = jsonLdTitle(body)
    local agg = d and d.aggregateRating
    if type(agg) ~= "table" then return nil end
    local n = tostring(agg.ratingValue or ""):match("%d+%.?%d*")
    if not n then return nil end
    return "Rating: " .. n .. "/10"
end

-- ============ Эпизоды ============

local EPISODE_MARK = "الحلقة" -- «الحلقة» — так сайт подписывает эпизод

function getChapterList(bookUrl)
    -- Список эпизодов целиком лежит в HTML страницы тайтла — прямой http_get,
    -- не fetchPage (иначе список будет отставать от кэша).
    local r = http_get(bookUrl)
    if not r.success then return {} end
    -- Селектор по пути, а не по хосту: в проверенной разметке ссылки без www.
    local chapters, seen = {}, {}
    for _, a in ipairs(html_select(r.body, "a[href*='/episode/']")) do
        local url = absUrl(a.href)
        if url ~= "" and not seen[url] then
            seen[url] = true
            local name = html_select_first(a.html, ".video-data span")
            local title = name and string_clean(name.text) or ""
            if title == "" then
                -- Номер эпизода лежит в конце URL: /episode/{slug}/{N}.
                local n = url:match("/episode/[^/]+/(%d+)")
                if n then title = EPISODE_MARK .. " " .. n end
            end
            if title ~= "" then
                chapters[#chapters + 1] = { title = title, url = url }
            end
        end
    end
    if #chapters == 0 then return {} end
    -- Сервер печатает эпизоды по возрастанию (1 → N, сверено с дампом); реверс
    -- делает только Alpine по клику, в HTML его нет.
    return chapters
end

function getChapterListHash(bookUrl)
    -- ВАЖНО: прямой http_get, НЕ fetchPage — кэш сделал бы хэш неактуальным.
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local links = html_select(r.body, "a[href*='/episode/']")
    if #links == 0 then return nil end
    -- Счётчик ловит новый эпизод даже при смене порядка на странице, URL —
    -- любое изменение адресов.
    return #links .. ":" .. absUrl(links[1].href)
end

-- ============ Потоки эпизода ============
-- Цепочка (проверена живьём 2026-10-03):
--   эпизод → wire:snapshot компонента video.show-video →
--   https://video.vid3rb.com/player/… → var video_sources = [...] →
--   https://video.vid3rb.com/video/{uuid}?… → 302 на files-2.vid3rb.com/…/{q}.mp4.
-- Промежуточный 302 НЕ обходим сами: media3 следует по редиректу сам, а
-- дополнительный запрос здесь лишь тратит лимит 429. Заголовки не нужны —
-- CDN отдаёт файл без cookies/Referer.
-- SKIP_HOSTS/список хостов не нужен: эмбед-хостов на сайте нет, легальный
-- путь один (video.vid3rb.com), лишние URL отсекает сам regex.

local function pushSource(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

-- wire:snapshot — это JSON, HTML-экранированный (&quot;) плюс экранирование
-- строк самого JSON (\", \/, \u0026): приводим к обычному тексту.
local function decodeSnapshot(s)
    s = s:gsub("&quot;", '"')
    s = s:gsub("&amp;", "&")
    s = s:gsub("\\/", "/"):gsub('\\"', '"'):gsub("\\u0026", "&")
    return s
end

local function playerUrlFrom(body)
    -- 1) Проверенный путь: video_url внутри wire:snapshot.
    for snap in body:gmatch('wire:snapshot="([^"]*)"') do
        if snap:find("video_url", 1, true) then
            local url = decodeSnapshot(snap):match(
                '"video_url"%s*:%s*"(https://video%.vid3rb%.com/player/[^"]+)"')
            if url then return url end
        end
    end
    -- 2) Фоллбэк: статический src iframe (динамический :src Alpine не читается).
    local src = html_attr(body, "iframe[src^='https://video.vid3rb.com/player/']", "src")
    if src and src ~= "" then return absUrl(src) end
    return nil
end

-- Страница плеера: var video_sources = [{src, type, label, res, premium}, ...].
-- premium-строки пропускаем — у них пустой src (проверено: 1080p/720p/480p
-- плюс «1080p Premium» без файла). Субтитры не отдаём: из плеера известен
-- только thumbnails.vtt (полоса превью для перемотки), отдельных дорожек
-- субтитров в ответе не видено.
local function collectSources(body)
    local list, seen = {}, {}
    for arr in body:gmatch("var%s+video_sources%s*=%s*(%b[])") do
        local data = json_parse(arr)
        if type(data) == "table" then
            for _, e in ipairs(data) do
                if type(e) == "table" then
                    local premium = e.premium == true or e.premium == "true"
                    local src = type(e.src) == "string" and e.src or ""
                    src = src:gsub("\\/", "/"):gsub("&amp;", "&"):gsub("\\u0026", "&")
                    if not premium and src ~= "" then
                        pushSource(list, seen, {
                            url     = src,
                            quality = type(e.label) == "string" and e.label or nil,
                            mime    = "mp4", -- в URL нет расширения файла
                        })
                    end
                end
            end
        end
    end
    return list
end

function getVideoList(episodeUrl)
    local r = http_get(episodeUrl)
    if not r.success then
        log_error("Anime3rb: страница эпизода — HTTP " .. tostring(r.code))
        return nil
    end

    local player = playerUrlFrom(r.body)
    if not player then
        log_error("Anime3rb: на странице эпизода не найден плеер video.vid3rb.com")
        return nil
    end

    -- Сайт отдаёт 429 примерно на шестом запросе подряд — держим паузу
    -- между двумя последовательными запросами этой функции.
    sleep(math.random(400, 800))

    local p = http_get(player)
    if not p.success then
        log_error("Anime3rb: страница плеера — HTTP " .. tostring(p.code))
        return nil
    end

    local sources = collectSources(p.body)
    if #sources == 0 then
        log_error("Anime3rb: в video_sources нет ни одного источника")
        return nil
    end
    return sources
end
