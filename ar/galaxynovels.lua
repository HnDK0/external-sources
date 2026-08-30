id       = "galaxynovels"
name     = "Galaxy Novels"
version  = "1.0.0"
baseUrl  = "https://galaxynovels.com/"
language = "ar"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/galaxynovels.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────

local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then _pageCache[url] = r.body end
    return r.success and r.body or nil
end

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Обложка: data-src (ленивая загрузка) или src.
-- Атрибуты с дефисом (data-*) недоступны как поля элемента — берём через html_attr.
local function coverOf(imgEl)
    if not imgEl then return nil end
    local ds = html_attr(imgEl.html, "img", "data-src")
    if ds and ds ~= "" and not string_starts_with(ds, "data:") then return ds end
    local src = imgEl["src"] or ""
    if src == "" or string_starts_with(src, "data:") then return nil end
    return src
end

-- Список глав: из статического JSON-манифеста сайта (wor-reader-cache).
-- Возвращает { chapters = { {title, url}, ... }, latest_url } или nil.
local function loadChapters(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then log_error("GN: loadChapters: no book page for " .. bookUrl); return nil end
    -- Атрибут с дефисом (data-*) недоступен как поле элемента — берём через html_attr
    local manifestUrl = html_attr(body, "[data-wor-chapters-container]", "data-manifest-url")
    if not manifestUrl or manifestUrl == "" then log_error("GN: loadChapters: no manifest url"); return nil end
    manifestUrl = absUrl(manifestUrl)

    local rm = http_get(manifestUrl)
    if not rm.success then log_error("GN: loadChapters: manifest http " .. tostring(rm.code)); return nil end
    local manifest = json_parse(rm.body)
    if not manifest then log_error("GN: loadChapters: manifest json fail"); return nil end
    if not manifest["pack_url"] then log_error("GN: loadChapters: no pack_url in manifest"); return nil end

    local packUrl = manifest["pack_url"]
    local latestUrl = manifest["latest_url"]
    packUrl = absUrl(packUrl)

    local rp = http_get(packUrl)
    if not rp.success then log_error("GN: loadChapters: pack http " .. tostring(rp.code)); return nil end
    local pack = json_parse(rp.body)
    if not pack or not pack["chapters"] then log_error("GN: loadChapters: pack json fail"); return nil end

    local chapters = {}
    for _, ch in ipairs(pack["chapters"]) do
        local label = string_clean(ch["label"] or "")
        local title = ch["title"] or ""
        local name = label
        if title ~= "" then name = label .. ": " .. string_clean(title) end
        local url = absUrl(ch["url"] or "")
        if name ~= "" and url ~= "" then
            table.insert(chapters, { title = name, url = url })
        end
    end
    return { chapters = chapters, latest_url = latestUrl }
end

-- ── Фильтры ───────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            key = "sort",
            label = "Sort By",
            type = "select",
            defaultValue = "popular",
            options = {
                { label = "Most Popular", value = "popular" },
                { label = "Newest", value = "new" },
                { label = "Recently Updated", value = "recent" },
            }
        },
        {
            key = "period",
            label = "Period",
            type = "select",
            defaultValue = "month",
            options = {
                { label = "Month", value = "month" },
                { label = "Week", value = "week" },
                { label = "All Time", value = "all" },
            }
        }
    }
end

-- Строит URL каталога по выбранной сортировке и периоду.
local function browseUrl(page, sort, period)
    sort = sort or "popular"
    local url = baseUrl .. "novels/?sort=" .. sort
    if sort == "popular" then
        url = url .. "&period=" .. (period or "month")
    end
    url = url .. "&page=" .. page
    return url
end

-- hasNext: сравниваем запрошенную страницу с максимальной из пагинации.
local function parseCatalog(html, page)
    local items = {}
    for _, card in ipairs(html_select(html, "article.wor-novel-card")) do
        local a = html_select_first(card.html, "a.wor-novel-card__cover")
        local link = a and a.href or nil
        local img = html_select_first(card.html, "img.wor-cover-img")
        local h3 = html_select_first(card.html, "h3 a")
        local title = h3 and string_clean(h3.text) or ""
        if title ~= "" and link ~= "" then
            table.insert(items, {
                title = title,
                url   = absUrl(link),
                cover = coverOf(img)
            })
        end
    end

    local maxPage = 0
    for _, a in ipairs(html_select(html, "a.page-numbers")) do
        local href = a.href or ""
        local n = tonumber(href:match("/novels/page/(%d+)/"))
        if n and n > maxPage then maxPage = n end
    end

    return { items = items, hasNext = maxPage > page }
end

function getCatalogList(index)
    local page = index + 1
    local r = http_get(browseUrl(page, "popular", "month"))
    if not r.success then return { items = {}, hasNext = false } end
    return parseCatalog(r.body, page)
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local sort = filters and filters["sort"] or "popular"
    local period = filters and filters["period"] or "month"
    local r = http_get(browseUrl(page, sort, period))
    if not r.success then return { items = {}, hasNext = false } end
    return parseCatalog(r.body, page)
end

-- ── Поиск ─────────────────────────────────────────────────────────────────
-- Сайт держит статический JSON-индекс новелл (wor-reader-cache/search).
-- Фильтруем локально по заголовку/оригинальному названию/описанию.
function getCatalogSearch(index, query)
    query = string_clean(query or ""):lower()
    local page = index + 1
    local manifestUrl = baseUrl .. "wp-content/uploads/wor-reader-cache/search/manifest.json"
    local rm = http_get(manifestUrl)
    if not rm.success then return { items = {}, hasNext = false } end
    local manifest = json_parse(rm.body)
    if not manifest or not manifest["index"] then
        return { items = {}, hasNext = false }
    end
    local ri = http_get(absUrl(manifest["index"]))
    if not ri.success then return { items = {}, hasNext = false } end
    local idx = json_parse(ri.body)
    if not idx or not idx["items"] then return { items = {}, hasNext = false } end

    local matched = {}
    for _, n in ipairs(idx["items"]) do
        local t = (n["t"] or ""):lower()
        local o = (n["o"] or ""):lower()
        local s = (n["s"] or ""):lower()
        if t:find(query, 1, true) or o:find(query, 1, true) or s:find(query, 1, true) then
            local c = n["c"] or ""
            if not string_starts_with(c, "http") then c = absUrl(c) end
            table.insert(matched, {
                title = n["t"] or "",
                url   = absUrl(n["u"] or ""),
                cover = c ~= "" and c or nil
            })
        end
    end

    local pageSize = 20
    local total = #matched
    local start = (page - 1) * pageSize + 1
    local items = {}
    for i = start, math.min(start + pageSize - 1, total) do
        table.insert(items, matched[i])
    end
    return { items = items, hasNext = (page * pageSize) < total }
end

-- ── Детали книги ──────────────────────────────────────────────────────────

local function bookSelectors(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    return body
end

function getBookTitle(bookUrl)
    local body = bookSelectors(bookUrl)
    if not body then return nil end
    local h = html_select_first(body, "h1")
    return h and string_clean(h.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = bookSelectors(bookUrl)
    if not body then return nil end
    local img = html_select_first(body, "img.wor-cover-img")
    return coverOf(img)
end

function getBookDescription(bookUrl)
    local body = bookSelectors(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".wor-single-summary__text")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = bookSelectors(bookUrl)
    if not body then return nil end
    local genres = {}
    for _, a in ipairs(html_select(body, "a.wor-tag-pill")) do
        local g = string_clean(a.text)
        if g ~= "" then table.insert(genres, g) end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = bookSelectors(bookUrl)
    if not body then return nil end
    for _, el in ipairs(html_select(body, "[class*='rating']")) do
        local m = el.text:match("(%d+%.?%d*)")
        if m then return m end
    end
    return nil
end

function getBookStatus(bookUrl)
    local body = bookSelectors(bookUrl)
    if not body then return nil end
    local st = html_select_first(body, "span.wor-cover-status")
    if not st then return nil end
    local t = string_clean(st.text)
    local map = {
        ["مستمرة"] = "Ongoing",
        ["مكتملة"] = "Completed",
        ["متوقفة"] = "On Hiatus"
    }
    return map[t] or "Unknown"
end

-- ── Список глав ───────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local data = loadChapters(bookUrl)
    if not data then return {} end
    return data.chapters
end

function getChapterListHash(bookUrl)
    -- Прямой http_get (не fetchPage): хеш должен отражать актуальное состояние.
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local manifestUrl = html_attr(body, "[data-wor-chapters-container]", "data-manifest-url")
    if not manifestUrl or manifestUrl == "" then return nil end
    local rm = http_get(absUrl(manifestUrl))
    if not rm.success then return nil end
    local manifest = json_parse(rm.body)
    if not manifest then return nil end
    local latest = manifest["latest_url"]
    return (latest and latest ~= "") and latest or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────

function getChapterText(html, url)
    if not html or html == "" then return "" end
    local cleaned = html_remove(html, "script", "style", "noscript")
    local cont = html_select_first(cleaned, ".wor-reader-text-surface")
    if not cont then return "" end

    local parts = {}
    for _, p in ipairs(html_select(cont.html, "p")) do
        local t = html_text(p.html)
        t = string_trim(t)
        if t ~= "" then table.insert(parts, t) end
    end

    -- Первый абзац на сайте — повторное название главы ("الفصل N: title").
    -- Выкидываем его, чтобы не дублировался в тексте.
    if #parts > 0 and string_starts_with(parts[1], "الفصل") then
        table.remove(parts, 1)
    end

    local text = table.concat(parts, "\n\n")
    text = string_normalize(text)
    text = string_trim(text)
    return text
end
