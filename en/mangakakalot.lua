-- ── Метаданные ────────────────────────────────────────────────────────────────
id           = "mangakakalot"
name         = "MangaKakalot"
version      = "1.0.1"
baseUrl      = "https://www.mangakakalot.gg"
language     = "en"
icon         = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/mangakakalot.png"
content_type = "manga"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Нормализуем ссылку на серию к baseUrl (на сайте бывают зеркала/без www).
-- Возвращает nil, если это не страница серии (например, ссылка на главу).
local function seriesUrl(href)
    local u = absUrl(href)
    local slug = string.match(u, "^https?://[^/]+/manga/([^/?#]+)/?$")
    if not slug then return nil end
    return baseUrl .. "/manga/" .. slug
end

local function slugOf(bookUrl)
    return string.match(bookUrl, "/manga/([^/?#]+)")
end

local MONTHS = { Jan = "01", Feb = "02", Mar = "03", Apr = "04", May = "05", Jun = "06",
                 Jul = "07", Aug = "08", Sep = "09", Oct = "10", Nov = "11", Dec = "12" }

-- Кэш страницы книги (движок зовёт detail-функции параллельно).
-- getChapterListHash его НЕ использует — ему нужен свежий ответ.
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

-- Значение поля из строки инфо-блока вида "Status: Ongoing".
-- Основной путь (проверено 2026-10-02): div.info-wrap > div — label и value
-- в отдельных <p>, текст строки = label + ":" + value.
-- Фолбэк: <li> "Status : ..." (страховка на возможную другую вёрстку).
local function infoField(body, label)
    local function scan(rows)
        for _, row in ipairs(rows) do
            local t = string_clean(row.text)
            if string_starts_with(t, label) then
                local rest = string.sub(t, #label + 1)
                rest = regex_replace(rest, "^\\s*:\\s*", "")
                rest = string_trim(rest)
                if rest ~= "" then return rest, row end
            end
        end
        return nil, nil
    end
    local v, el = scan(html_select(body, "div.info-wrap > div"))
    if v then return v, el end
    return scan(html_select(body, "li"))
end

local function imgSrc(img)
    if not img then return "" end
    local src = img.src
    if not src or src == "" then src = img:attr("data-src") end
    if not src or src == "" then src = img:attr("data-original") end
    return src or ""
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

-- Порядок селекторов: первый, что сматчился, выигрывает.
-- Проверено 2026-10-02: каталог (/genre/all) — div.list-comic-item-wrap (24 шт),
-- поиск (/search/story/...) — div.story_item (20 шт); на странице поиска
-- list-comic-item-wrap отсутствует, на каталоге story_item отсутствует.
local CARD_SELECTORS = {
    "div.list-comic-item-wrap",
    "div.story_item",
}

-- Собирает серии из набора <a href="/manga/slug">. Обложка и заголовок на сайте
-- часто в разных <a> с одним href → склеиваем по url.
local function collectSeries(scopeHtml, items, index)
    for _, a in ipairs(html_select(scopeHtml, "a[href*='/manga/']")) do
        local url = seriesUrl(a.href)
        if url then
            local e = index[url]
            if not e then
                e = { title = "", url = url, cover = "" }
                index[url] = e
                table.insert(items, e)
            end
            local img = html_select_first(a.html, "img")
            if img then
                if e.cover == "" then e.cover = absUrl(imgSrc(img)) end
                if e.title == "" then
                    local alt = string_clean(img:attr("alt") or "")
                    if alt ~= "" then e.title = alt end
                end
            end
            -- Текст ссылки приоритетнее alt: в поисковых карточках alt приходит
            -- с незакрытой кавычкой ("... class="), и guard здесь только заморозит
            -- мусор. "Read more" (ссылка-раскрытие описания, стоит последней в
            -- карточке) просто не берём — тогда h3-заголовок не затирается.
            -- Plain-find, не Lua-паттерн: см. asurascans.lua:300-304.
            local t = string_clean(a.text or "")
            if t ~= "" and not string.find(t, "Read more", 1, true) then
                e.title = t
            end
            if e.title == "" then
                local tt = string_clean(a.title or "")
                if tt ~= "" and not string.find(tt, "Read more", 1, true) then
                    e.title = tt
                end
            end
        end
    end
end

local function parseCatalog(body)
    local items, index = {}, {}
    local used = false
    for _, sel in ipairs(CARD_SELECTORS) do
        local cards = html_select(body, sel)
        if #cards > 0 then
            used = true
            for _, card in ipairs(cards) do
                collectSeries(card.html, items, index)
            end
            break
        end
    end
    if not used then
        -- Generic-фолбэк: все серии на странице. Может захватить боковые виджеты
        -- (Popular и т.п.) — поэтому лог, чтобы подобрать точный селектор.
        log_info("mangakakalot: no card container matched, using generic anchors")
        collectSeries(body, items, index)
    end
    local out = {}
    for _, e in ipairs(items) do
        if e.title ~= "" then
            local item = { title = e.title, url = e.url }
            if e.cover ~= "" then item.cover = e.cover end
            table.insert(out, item)
        end
    end
    return out
end

local function fetchCatalog(url)
    local r = http_get(url)
    if not r.success then
        log_error("mangakakalot: catalog request failed code=" .. tostring(r.code) .. " " .. url)
        return { items = {}, hasNext = false }
    end
    local items = parseCatalog(r.body)
    -- Страница за последней пустая → пагинация останавливается.
    return { items = items, hasNext = #items > 0 }
end

function getCatalogList(index)
    local page = index + 1
    return fetchCatalog(baseUrl .. "/genre/all?type=latest&state=all&page=" .. tostring(page))
end

-- Поиск: /search/story/<запрос с подчёркиваниями>?page=N  (проверено 2026-10-02)
function getCatalogSearch(index, query)
    local page = index + 1
    local q = string.lower(string_clean(query or ""))
    q = regex_replace(q, "[^\\p{L}\\p{N}\\s]", "")
    q = regex_replace(q, "\\s+", "_")
    if q == "" then return { items = {}, hasNext = false } end
    return fetchCatalog(baseUrl .. "/search/story/" .. url_encode(q) .. "?page=" .. tostring(page))
end

-- ── Фильтры ───────────────────────────────────────────────────────────────────

local GENRES = {
    { "all", "All" }, { "action", "Action" }, { "adaptation", "Adaptation" },
    { "adventure", "Adventure" }, { "boys-love", "Boys Love" }, { "comedy", "Comedy" },
    { "demons", "Demons" }, { "drama", "Drama" }, { "fantasy", "Fantasy" },
    { "full-color", "Full Color" }, { "gender-bender", "Gender bender" },
    { "harem", "Harem" }, { "heartwarming", "Heartwarming" }, { "historical", "Historical" },
    { "isekai", "Isekai" }, { "josei", "Josei" }, { "long-strip", "Long Strip" },
    { "magic", "Magic" }, { "manga", "Manga" }, { "manhua", "Manhua" },
    { "manhwa", "Manhwa" }, { "martial-arts", "Martial arts" }, { "mature", "Mature" },
    { "mecha", "Mecha" }, { "monsters", "Monsters" }, { "mystery", "Mystery" },
    { "office-workers", "Office Workers" }, { "one-shot", "One shot" },
    { "psychological", "Psychological" }, { "reincarnation", "Reincarnation" },
    { "revenge", "Revenge" }, { "romance", "Romance" }, { "school-life", "School life" },
    { "shoujo", "Shoujo" }, { "shounen", "Shounen" }, { "slice-of-life", "Slice of life" },
    { "super-power", "Super Power" }, { "supernatural", "Supernatural" },
    { "survival", "Survival" }, { "time-travel", "Time Travel" }, { "tragedy", "Tragedy" },
    { "transmigration", "Transmigration" }, { "vampires", "Vampires" },
    { "villainess", "Villainess" }, { "webtoons", "Webtoons" }, { "yaoi", "Yaoi" },
    { "yuri", "Yuri" },
}

function getFilterList()
    local genreOptions = {}
    for _, g in ipairs(GENRES) do
        table.insert(genreOptions, { value = g[1], label = g[2] })
    end
    return {
        {
            type = "select", key = "type", label = "Order by", defaultValue = "latest",
            options = {
                { value = "latest",  label = "Latest" },
                { value = "newest",  label = "Newest" },
                { value = "topview", label = "Top read" },
            }
        },
        {
            type = "select", key = "state", label = "Status", defaultValue = "all",
            options = {
                { value = "all",       label = "All" },
                { value = "ongoing",   label = "Ongoing" },
                { value = "completed", label = "Completed" },
            }
        },
        {
            type = "select", key = "genre", label = "Genre", defaultValue = "all",
            options = genreOptions
        },
    }
end

function getCatalogFiltered(index, filters)
    local page  = index + 1
    local typ   = filters["type"] or "latest"
    local state = filters["state"] or "all"
    local genre = filters["genre"] or "all"
    local url = baseUrl .. "/genre/" .. genre
        .. "?type=" .. typ .. "&state=" .. state .. "&page=" .. tostring(page)
    return fetchCatalog(url)
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local h1 = html_select_first(body, "h1")
    if h1 then
        local t = string_clean(h1.text)
        if t ~= "" then return t end
    end
    local og = html_attr(body, "meta[property='og:title']", "content")
    if og ~= "" then
        og = regex_replace(og, "^Read\\s+", "")
        og = regex_replace(og, "\\s+Latest Chapter.*$", "")
        return string_clean(og)
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local src = html_attr(body, "meta[property='og:image']", "content")
    return src ~= "" and absUrl(src) or nil
end

-- Описание: блок div#contentBox "<Title> summary:", обрезаем до "SHOW MORE"/"Comments".
-- Plain-find (без Lua-паттернов с '-'), см. примечание в asurascans.lua.
function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local full = html_text(body)
    local s, e = string.find(full, "summary:", 1, true)
    if not s then return nil end
    local rest = string.sub(full, e + 1)
    local cut = #rest
    for _, marker in ipairs({ "SHOW MORE", "Comments" }) do
        local p = string.find(rest, marker, 1, true)
        if p and p - 1 < cut then cut = p - 1 end
    end
    local desc = string_trim(string.sub(rest, 1, cut))
    return desc ~= "" and desc or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres, seen = {}, {}
    for _, a in ipairs(html_select(body, "div.genre-list a")) do
        local t = string_clean(a.text)
        if t ~= "" and not seen[t] then
            seen[t] = true
            table.insert(genres, t)
        end
    end
    return genres
end

-- "Rating: ... 4.90 / 5 - 47 votes" → "4.90" (шкала 0-5).
-- Фолбэк: div.rating[data-default="4.90"], если regex по тексту не сработал.
function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local v = infoField(body, "Rating")
    if v then
        local m = regex_match(v, "(\\d+(?:\\.\\d+)?)\\s*/\\s*5")
        if m and m[1] then return m[1] end
    end
    local def = html_attr(body, "div.rating", "data-default")
    local n = tonumber(def)
    if n and n >= 0 and n <= 5 then return def end
    return nil
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local v = infoField(body, "Status")
    return v
end

-- "Last updated: Oct-02-2026 05:38:46 AM" → "2026-10-02"
-- regex_match возвращает ЦЕЛОЕ совпадение, группы не экспонируются
-- (проверено движком тестера, см. royal_road.lua:236) → m[2]/m[3] = nil,
-- поэтому дату вырезаем string.match'ом; '-' в Lua-паттерне — как '%-'.
function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local v = infoField(body, "Last updated")
    if not v then return nil end
    local mon, day, year = string.match(v, '(%a%a%a)%-(%d%d)%-(%d%d%d%d)')
    if mon and day and year and MONTHS[mon] then
        return year .. "-" .. MONTHS[mon] .. "-" .. day
    end
    return nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

-- Схема проверена 2026-10-02: { success=true, data={ chapters=[...],
-- pagination={total,limit,offset} } }. Порядок ответа — новые сверху.
local function extractList(data)
    if type(data) ~= "table" then return nil, nil end
    local d = data.data
    if type(d) ~= "table" or type(d.chapters) ~= "table" then return nil, nil end
    return d.chapters, d.pagination
end

local function fetchChaptersApi(bookUrl, slug)
    local cfg = {
        headers = {
            ["Accept"] = "application/json, text/plain, */*",
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"] = bookUrl,
        }
    }
    -- limit=-1 отдаёт ВСЕ главы одним запросом; page сервер игнорирует
    -- (проверено: 1379 глав одним GET, offset всегда 0) → цикла нет.
    local url = baseUrl .. "/api/manga/" .. slug .. "/chapters?limit=-1&page=1"
    local r = http_get(url, cfg)
    if not r.success then
        log_error("mangakakalot: chapters api failed code=" .. tostring(r.code))
        return {}
    end
    local data = json_parse(r.body)
    local list, pag = extractList(data)
    if not list or #list == 0 then
        log_error("mangakakalot: chapters api: unexpected json shape: "
            .. string.sub(tostring(r.body), 1, 300))
        return {}
    end
    local all, seen = {}, {}
    for _, ch in ipairs(list) do
        local cslug = ch.chapter_slug
        if cslug and cslug ~= "" and not seen[cslug] then
            seen[cslug] = true
            local title = string_clean(tostring(ch.chapter_name or ""))
            if title == "" then title = "Chapter " .. tostring(ch.chapter_num or cslug) end
            table.insert(all, {
                title = title,
                url   = baseUrl .. "/manga/" .. slug .. "/" .. cslug,
            })
        end
    end
    -- Защита: если сервер когда-нибудь введёт лимит — заметим обрезку в логах.
    local total = pag and tonumber(pag.total)
    if total and #all < total then
        log_error("mangakakalot: chapters truncated " .. #all .. "/" .. total)
    end
    return all
end

function getChapterList(bookUrl)
    local slug = slugOf(bookUrl)
    if not slug then
        log_error("mangakakalot: cannot extract slug from " .. tostring(bookUrl))
        return {}
    end
    local chapters = fetchChaptersApi(bookUrl, slug)
    -- Порядок API — новые сверху, движку нужны старые → новые: простой реверс
    -- (Вариант 1, lua-plugin-guide.md, раздел «Неправильный порядок глав»).
    local out = {}
    for i = #chapters, 1, -1 do
        table.insert(out, chapters[i])
    end
    return out
end

-- Хэш для детекта обновлений: ссылка "Newest Chapter" + "Last updated".
-- ВАЖНО: прямой http_get, не fetchPage.
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local newest = ""
    for _, a in ipairs(html_select(r.body, "a[href*='/chapter']")) do
        if string.find(string.lower(string_clean(a.text)), "newest", 1, true) then
            newest = a.href
            break
        end
    end
    local upd = infoField(r.body, "Last updated") or ""
    local h = newest .. "|" .. upd
    if h == "|" then return nil end
    return h
end

-- ── Страницы главы ────────────────────────────────────────────────────────────

local function isPageImage(src)
    if src == "" then return false end
    local l = string.lower(src)
    if string.find(l, "loadingimg", 1, true) then return false end
    if string.find(l, "/thumb/", 1, true) then return false end
    if string.find(l, "logo", 1, true) then return false end
    if string.find(l, ".svg", 1, true) then return false end
    return true
end

local function extractPages(body)
    local pages, seen = {}, {}
    local function add(img)
        local src = string_trim(absUrl(imgSrc(img)))
        if isPageImage(src) and not seen[src] then
            seen[src] = true
            table.insert(pages, src)
        end
    end
    -- Основной путь (проверено 2026-10-02): контейнер ридера, src прямой.
    -- Селектор по alt не использовать: alt в одинарных кавычках с апострофом
    -- в названии → парсер обрезает атрибут, "page N" в alt не находится.
    for _, img in ipairs(html_select(body, "div.container-chapter-reader img")) do
        add(img)
    end
    -- Запасной путь: другие контейнеры ридера (на сайте не проверялись, безвредны).
    if #pages == 0 then
        local containers = {
            "#chapter-content img", ".chapter-content img",
        }
        for _, sel in ipairs(containers) do
            local imgs = html_select(body, sel)
            if #imgs > 0 then
                for _, img in ipairs(imgs) do add(img) end
                if #pages > 0 then break end
            end
        end
    end
    return pages
end

function getPageList(html, url)
    local body = html
    if not body or body == "" then
        local r = http_get(url)
        if not r.success then return {} end
        body = r.body
    end
    local pages = extractPages(body)
    if #pages == 0 then
        log_error("mangakakalot: no page images found for " .. tostring(url))
    end
    return pages
end

-- Легаси-фолбэк для сборок приложения без поддержки getPageList.
function getChapterText(html, url)
    local body = html
    if not body or body == "" then
        local r = http_get(url)
        if not r.success then return "" end
        body = r.body
    end
    local out = {}
    for _, src in ipairs(extractPages(body)) do
        -- & → &amp;: jsoup декодирует атрибуты при разборе <img>
        table.insert(out, '<img src="' .. src:gsub("&", "&amp;") .. '">')
    end
    return table.concat(out, "\n")
end
