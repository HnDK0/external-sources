-- ── Метаданные ──

id       = "komiku"
name     = "Komiku"
version  = "1.0.0"
baseUrl  = "https://komiku.org/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/komiku.png"
content_type = "manga"

-- ── Константы ──

local API_BASE = "https://api.komiku.org"

-- ── Хелперы ──

local _pageCache = {}

local function absUrl(href)
    if not href or href == "" then return "" end
    if href:find("^http") then return href end
    if href:find("^//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function fetchBookPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

local function cleanTitle(title)
    if not title then return "" end
    title = title:gsub("^%s+", ""):gsub("%s+$", "")
    title = title:gsub("^Komik%s+", "")
    return title
end

local function stripQuery(url)
    if not url then return "" end
    return url:gsub("%?.*$", "")
end

-- Парсинг карточек каталога (общий для list/search/filtered)
local function parseCatalogItems(body)
    local cards = html_select(body, "div.bge")
    local items = {}
    for _, card in ipairs(cards) do
        local titleEl = html_select_first(card, "h3")
        local linkEl = html_select_first(card, "a:has(h3)")
        local imgEl = html_select_first(card, "img")
        if titleEl and linkEl then
            local href = linkEl.href or ""
            local cover = ""
            if imgEl then
                cover = stripQuery(imgEl.src or "")
            end
            table.insert(items, {
                title = cleanTitle(titleEl.text),
                url   = absUrl(href),
                cover = cover,
            })
        end
    end
    return items, #cards >= 10
end

-- ── Каталог ──

function getCatalogList(index)
    local page = index + 1
    local url = API_BASE .. "/manga/"
    if page > 1 then url = url .. "page/" .. page .. "/" end
    url = url .. "?orderby=modified"

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items, hasNext = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    local page = index + 1
    local url = API_BASE .. "/manga/"
    if page > 1 then url = url .. "page/" .. page .. "/" end
    url = url .. "?s=" .. url_encode(query) .. "&orderby=modified"

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items, hasNext = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNext }
end

-- ── Фильтры ──

function getFilterList()
    return {
        { type = "select", key = "tipe", label = "Tipe", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "manga", label = "Manga" },
            { value = "manhua", label = "Manhua" },
            { value = "manhwa", label = "Manhwa" },
        }},
        { type = "select", key = "orderby", label = "Order", defaultValue = "modified", options = {
            { value = "modified", label = "Chapter Terbaru" },
            { value = "date", label = "Komik Terbaru" },
            { value = "meta_value_num", label = "Peringkat" },
            { value = "rand", label = "Acak" },
        }},
        { type = "select", key = "genre", label = "Genre 1", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "action", label = "Action" },
            { value = "adventure", label = "Adventure" },
            { value = "comedy", label = "Comedy" },
            { value = "cooking", label = "Cooking" },
            { value = "demons", label = "Demons" },
            { value = "drama", label = "Drama" },
            { value = "ecchi", label = "Ecchi" },
            { value = "fantasy", label = "Fantasy" },
            { value = "game", label = "Game" },
            { value = "gender-bender", label = "Gender Bender" },
            { value = "gore", label = "Gore" },
            { value = "harem", label = "Harem" },
            { value = "historical", label = "Historical" },
            { value = "horror", label = "Horror" },
            { value = "isekai", label = "Isekai" },
            { value = "josei", label = "Josei" },
            { value = "magic", label = "Magic" },
            { value = "martial-arts", label = "Martial Arts" },
            { value = "mature", label = "Mature" },
            { value = "mecha", label = "Mecha" },
            { value = "medical", label = "Medical" },
            { value = "military", label = "Military" },
            { value = "mystery", label = "Mystery" },
            { value = "one-shot", label = "One Shot" },
            { value = "psychological", label = "Psychological" },
            { value = "reincarnation", label = "Reincarnation" },
            { value = "romance", label = "Romance" },
            { value = "school", label = "School" },
            { value = "sci-fi", label = "Sci-fi" },
            { value = "seinen", label = "Seinen" },
            { value = "shoujo", label = "Shoujo" },
            { value = "shoujo-ai", label = "Shoujo Ai" },
            { value = "shounen", label = "Shounen" },
            { value = "shounen-ai", label = "Shounen Ai" },
            { value = "slice-of-life", label = "Slice of Life" },
            { value = "sports", label = "Sports" },
            { value = "super-power", label = "Super Power" },
            { value = "supernatural", label = "Supernatural" },
            { value = "thriller", label = "Thriller" },
            { value = "tragedy", label = "Tragedy" },
            { value = "vampire", label = "Vampire" },
            { value = "webtoon", label = "Webtoon" },
            { value = "xianxia", label = "Xianxia" },
            { value = "xuanhuan", label = "Xuanhuan" },
            { value = "yuri", label = "Yuri" },
        }},
        { type = "select", key = "genre2", label = "Genre 2", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "action", label = "Action" },
            { value = "adventure", label = "Adventure" },
            { value = "comedy", label = "Comedy" },
            { value = "cooking", label = "Cooking" },
            { value = "demons", label = "Demons" },
            { value = "drama", label = "Drama" },
            { value = "ecchi", label = "Ecchi" },
            { value = "fantasy", label = "Fantasy" },
            { value = "game", label = "Game" },
            { value = "gender-bender", label = "Gender Bender" },
            { value = "gore", label = "Gore" },
            { value = "harem", label = "Harem" },
            { value = "historical", label = "Historical" },
            { value = "horror", label = "Horror" },
            { value = "isekai", label = "Isekai" },
            { value = "josei", label = "Josei" },
            { value = "magic", label = "Magic" },
            { value = "martial-arts", label = "Martial Arts" },
            { value = "mature", label = "Mature" },
            { value = "mecha", label = "Mecha" },
            { value = "medical", label = "Medical" },
            { value = "military", label = "Military" },
            { value = "mystery", label = "Mystery" },
            { value = "one-shot", label = "One Shot" },
            { value = "psychological", label = "Psychological" },
            { value = "reincarnation", label = "Reincarnation" },
            { value = "romance", label = "Romance" },
            { value = "school", label = "School" },
            { value = "sci-fi", label = "Sci-fi" },
            { value = "seinen", label = "Seinen" },
            { value = "shoujo", label = "Shoujo" },
            { value = "shoujo-ai", label = "Shoujo Ai" },
            { value = "shounen", label = "Shounen" },
            { value = "shounen-ai", label = "Shounen Ai" },
            { value = "slice-of-life", label = "Slice of Life" },
            { value = "sports", label = "Sports" },
            { value = "super-power", label = "Super Power" },
            { value = "supernatural", label = "Supernatural" },
            { value = "thriller", label = "Thriller" },
            { value = "tragedy", label = "Tragedy" },
            { value = "vampire", label = "Vampire" },
            { value = "webtoon", label = "Webtoon" },
            { value = "xianxia", label = "Xianxia" },
            { value = "xuanhuan", label = "Xuanhuan" },
            { value = "yuri", label = "Yuri" },
        }},
        { type = "select", key = "statusmanga", label = "Status", defaultValue = "", options = {
            { value = "", label = "Semua" },
            { value = "ongoing", label = "Ongoing" },
            { value = "end", label = "Tamat" },
        }},
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local url = API_BASE .. "/manga/"
    if page > 1 then url = url .. "page/" .. page .. "/" end

    local params = {}
    local orderby = filters["orderby"] or "modified"
    if orderby ~= "" then table.insert(params, "orderby=" .. orderby) end

    local tipe = filters["tipe"] or ""
    if tipe ~= "" then table.insert(params, "tipe=" .. tipe) end

    local genre = filters["genre"] or ""
    if genre ~= "" then table.insert(params, "genre=" .. genre) end

    local genre2 = filters["genre2"] or ""
    if genre2 ~= "" then table.insert(params, "genre2=" .. genre2) end

    local status = filters["statusmanga"] or ""
    if status ~= "" then table.insert(params, "statusmanga=" .. status) end

    if #params > 0 then
        url = url .. "?" .. table.concat(params, "&")
    else
        url = url .. "?orderby=modified"
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items, hasNext = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, "h1")
    return el and cleanTitle(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, "div.ims img") or html_select_first(html, "img[itemprop=image]")
    if el then
        return stripQuery(el.src or "")
    end
    return nil
end

function getBookDescription(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, "#Sinopsis > p") or html_select_first(html, "p.desc[itemprop=description]")
    return el and el.text or nil
end

function getBookGenres(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local els = html_select(html, "ul.genre li.genre a span")
    local genres = {}
    for _, el in ipairs(els) do
        local g = el.text
        if g and g ~= "" then table.insert(genres, g) end
    end
    return #genres > 0 and genres or nil
end

function getBookStatus(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local rows = html_select(html, "table.inftable tr")
    for _, row in ipairs(rows) do
        local tds = html_select(row, "td")
        if #tds >= 2 then
            local key = tds[1].text
            if key and key:find("Status") then
                return tds[2].text
            end
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local rows = html_select(html, "table.inftable tr")
    for _, row in ipairs(rows) do
        local tds = html_select(row, "td")
        if #tds >= 2 then
            local key = tds[1].text
            if key and key:find("Update") then
                local val = tds[2].text
                -- Формат dd/mm/yyyy
                local d, m, y = val:match("(%d%d)/(%d%d)/(%d%d%d%d)")
                if d and m and y then return y .. "-" .. m .. "-" .. d end
            end
        end
    end
    return nil
end

-- ── Список глав ──

function getChapterList(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return {} end
    local rows = html_select(html, "#Daftar_Chapter tr:has(td.judulseries)")
    local chapters = {}
    for _, row in ipairs(rows) do
        local a = html_select_first(row, "a")
        if a then
            local title = a.text
            local href = a.href or ""
            if title and href ~= "" then
                table.insert(chapters, {
                    title = title,
                    url   = absUrl(href),
                })
            end
        end
    end
    -- Гайд: getChapterList возвращает в хронологическом порядке (старые → новые).
    -- Сайт отдаёт новые сверху — разворачиваем.
    local reversed = {}
    for i = #chapters, 1, -1 do
        table.insert(reversed, chapters[i])
    end
    return reversed
end

function getChapterListHash(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return "" end
    local rows = html_select(html, "#Daftar_Chapter tr:has(td.judulseries)")
    if #rows == 0 then return "" end
    -- Первая глава в HTML = самая новая
    local a = html_select_first(rows[1], "a")
    if a then
        local href = a.href or ""
        if href ~= "" then return absUrl(href) end
    end
    return ""
end

-- ── Текст главы ──

function getChapterText(html, url)
    -- Для content_type = "manga" — заглушка, движок использует getPageList
    return ""
end

function getPageList(html, url)
    local imgs = html_select(html, "#Baca_Komik img")
    local pages = {}
    for _, img in ipairs(imgs) do
        local src = img.src or ""
        -- Фильтруем промо-изображения
        if not src:find("komiku%-promosi") and src ~= "" then
            table.insert(pages, src)
        end
    end
    return pages
end
