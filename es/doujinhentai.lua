-- DoujinHentai.net plugin for NoveLA
-- Spanish manga/doujinshi source

id = "doujinhentai"
name = "DoujinHentai"
version = "1.0.1"
baseUrl = "https://doujinhentai.net/"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/doujinhentai.png"
language = "es"
content_type = "manga"

-- ── Хелперы ──

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end
    local r = http_get(url)
    if not r.success then
        sleep(500)
        r = http_get(url)
    end
    if not r.success then return nil end
    _pageCache[url] = r.body
    return r.body
end

local function getSlug(bookUrl)
    return string.match(bookUrl, "/manga%-hentai/([^/]+)")
end

local function extractJsonFromScript(html, typeAttr)
    local selector = "script[type='" .. typeAttr .. "']"
    local el = html_select_first(html, selector)
    if el then
        return el.html
    end
    return nil
end

-- ── Каталог ──

function getCatalogList(index)
    local page = (index or 0) + 1
    local url = baseUrl .. "lista-manga-hentai/?orderby=last&page=" .. page
    local html = fetchPage(url)
    if not html then return { items = {}, hasNext = false } end

    local items = {}
    local cards = html_select(html, "div.group.bg-white.rounded-2xl")
    for _, card in ipairs(cards) do
        local href = html_attr(card.html, "a.block[href]", "href") or ""
        local titleEl = html_select_first(card.html, "h3.font-bold")
        local cover = html_attr(card.html, "img", "src") or ""
        local title = titleEl and string_clean(html_text(titleEl)) or ""
        if href ~= "" and title ~= "" then
            table.insert(items, {
                title = title,
                url = absUrl(href),
                cover = absUrl(cover)
            })
        end
    end

    return {
        items = items,
        hasNext = #items >= 18
    }
end

function getCatalogSearch(index, query)
    local url = baseUrl .. "search-live?query=" .. url_encode(query or "")
    local r = http_get(url)
    if not r.success then
        sleep(500)
        r = http_get(url)
    end
    if not r.success then return { items = {}, hasNext = false } end

    local ok, data = pcall(json_parse, r.body)
    if not ok or not data or not data.results then
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, result in ipairs(data.results) do
        if result.url and result.name then
            table.insert(items, {
                title = string_clean(result.name),
                url = absUrl(result.url),
                cover = absUrl(result.cover or "")
            })
        end
    end

    return {
        items = items,
        hasNext = false
    }
end

-- ── Фильтры ──

function getFilterList()
    return {
        {
            key = "genre",
            label = "Género",
            type = "select",
            options = {
                { label = "Todos", value = "" },
                { label = "Ecchi", value = "ecchi" },
                { label = "Yaoi", value = "yaoi" },
                { label = "Yuri", value = "yuri" },
                { label = "Anal", value = "anal" },
                { label = "Tetonas", value = "tetonas" },
                { label = "Escolares", value = "escolares" },
                { label = "Incesto", value = "incesto" },
                { label = "Virgenes", value = "virgenes" },
                { label = "Masturbacion", value = "masturbacion" },
                { label = "Maduras", value = "maduras" },
                { label = "Lolicon", value = "lolicon" },
                { label = "Bikini", value = "bikini" },
                { label = "Sirvientas", value = "sirvientas" },
                { label = "Enfermera", value = "enfermera" },
                { label = "Embarazada", value = "embarazada" },
                { label = "Ahegao", value = "ahegao" },
                { label = "Casadas", value = "casadas" },
                { label = "Chica con Pene", value = "chica-con-pene" },
                { label = "Juguetes Sexuales", value = "juguetes-sexuales" },
                { label = "Orgias", value = "orgias" },
                { label = "Harem", value = "harem" },
                { label = "Romance", value = "romance" },
                { label = "Profesores", value = "profesores" },
                { label = "Tentaculos", value = "tentaculos" },
                { label = "Mamadas", value = "mamadas" },
                { label = "Shota", value = "shota" },
                { label = "Interracial", value = "interracial" },
                { label = "Full Color", value = "full-color" },
                { label = "Sin Censura", value = "sin-censura" },
                { label = "Futanari", value = "futanari" },
                { label = "Doble Penetracion", value = "doble-penetracion" },
                { label = "Cosplay", value = "cosplay" },
                { label = "Manga", value = "manga" },
                { label = "Doujinshi", value = "doujinshi" },
                { label = "Grandes Pechos", value = "grandes-pechos" },
                { label = "MILF", value = "milf" }
            }
        },
        {
            key = "sort",
            label = "Ordenar",
            type = "select",
            options = {
                { label = "Últimos Agregados", value = "last" },
                { label = "Más Vistos", value = "views" },
                { label = "A-Z", value = "" }
            }
        }
    }
end

function getCatalogFiltered(index, filters)
    local page = (index or 0) + 1
    local genreValue = (filters and filters["genre"]) or ""
    local sortValue = (filters and filters["sort"]) or "last"

    local url
    if genreValue ~= "" then
        url = baseUrl .. "lista-manga-hentai/category/" .. genreValue .. "?page=" .. page
    else
        if sortValue ~= "" then
            url = baseUrl .. "lista-manga-hentai/?orderby=" .. sortValue .. "&page=" .. page
        else
            url = baseUrl .. "lista-manga-hentai/?page=" .. page
        end
    end

    local html = fetchPage(url)
    if not html then return { items = {}, hasNext = false } end

    local items = {}
    local cards = html_select(html, "div.group.bg-white.rounded-2xl")
    for _, card in ipairs(cards) do
        local href = html_attr(card.html, "a.block[href]", "href") or ""
        local titleEl = html_select_first(card.html, "h3.font-bold")
        local cover = html_attr(card.html, "img", "src") or ""
        local title = titleEl and string_clean(html_text(titleEl)) or ""
        if href ~= "" and title ~= "" then
            table.insert(items, {
                title = title,
                url = absUrl(href),
                cover = absUrl(cover)
            })
        end
    end

    return {
        items = items,
        hasNext = #items >= 18
    }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return "" end

    local titleEl = html_select_first(html, "h1")
    if titleEl then
        return string_clean(html_text(titleEl))
    end
    return ""
end

function getBookCoverImageUrl(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return "" end

    -- Try LD+JSON first
    local jsonStr = extractJsonFromScript(html, "application/ld+json")
    if jsonStr then
        local ok, data = pcall(json_parse, jsonStr)
        if ok and data and data.image then
            return absUrl(data.image)
        end
    end

    -- Fallback to CDN URL
    local slug = getSlug(bookUrl)
    if slug then
        return "https://s4.zx89.site/uploads/manga/" .. slug .. "/cover/cover_250x350.jpg"
    end
    return ""
end

function getBookDescription(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return "" end

    -- LD+JSON provides description
    local jsonStr = extractJsonFromScript(html, "application/ld+json")
    if jsonStr then
        local ok, data = pcall(json_parse, jsonStr)
        if ok and data and data.description and data.description ~= "" then
            return string_clean(data.description)
        end
    end
    return ""
end

function getBookGenres(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return {} end

    -- LD+JSON provides genres
    local jsonStr = extractJsonFromScript(html, "application/ld+json")
    if jsonStr then
        local ok, data = pcall(json_parse, jsonStr)
        if ok and data and data.genre then
            if type(data.genre) == "table" then
                return data.genre
            elseif type(data.genre) == "string" then
                return { data.genre }
            end
        end
    end
    return {}
end

function getBookStatus(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return "" end

    local el = html_select_first(html, "span[aria-label*='Estado']")
    if el then
        return string_clean(html_text(el))
    end
    return ""
end

function getBookRating(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return "" end

    local jsonStr = extractJsonFromScript(html, "application/ld+json")
    if jsonStr then
        local ok, data = pcall(json_parse, jsonStr)
        if ok and data and data.aggregateRating then
            local rating = data.aggregateRating.ratingValue
            if rating then
                return tostring(rating)
            end
        end
    end
    return ""
end

function getBookLastUpdate(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return "" end

    -- Date format on page: "10 Sep. 2026" inside span.font-medium
    local dateEl = html_select_first(html, "span.font-medium")
    if dateEl then
        local dateStr = html_text(dateEl)
        local day, monthStr, year = string.match(dateStr, "(%d+)%s+(%w+)%s*%.?%s*(%d+)")
        local months = {
            Jan = "01", Feb = "02", Mar = "03", Apr = "04",
            May = "05", Jun = "06", Jul = "07", Aug = "08",
            Sep = "09", Oct = "10", Nov = "11", Dec = "12"
        }
        local month = months[monthStr]
        if month and day and year then
            return year .. "-" .. month .. "-" .. string.format("%02d", tonumber(day))
        end
    end
    return ""
end

-- ── Список глав ──

function getChapterList(bookUrl)
    local html = fetchPage(bookUrl)
    if not html then return {} end

    local slug = getSlug(bookUrl)
    if not slug then return {} end

    local chapters = {}
    local seen = {}
    local pattern = "/manga%-hentai/" .. string.gsub(slug, "%-", "%%-") .. "/(%d+)"

    local links = html_select(html, "a[href*=\"/manga-hentai/" .. slug .. "/\"]")
    for _, link in ipairs(links) do
        local href = link.href or ""
        local chapterNum = string.match(href, pattern)
        if chapterNum and not seen[chapterNum] then
            seen[chapterNum] = true
            table.insert(chapters, {
                title = "Capítulo " .. chapterNum,
                url = absUrl(href),
                volume = "",
                uploaded = ""
            })
        end
    end

    -- Sort by chapter number ascending
    table.sort(chapters, function(a, b)
        local numA = tonumber(string.match(a.url, "/(%d+)$")) or 0
        local numB = tonumber(string.match(b.url, "/(%d+)$")) or 0
        return numA < numB
    end)

    return chapters
end

-- ── Текст главы ──

function getPageList(html, url)
    local pages = {}

    -- Try to extract pageUrls from JavaScript variable
    local jsBlock = string.match(html, "const pageUrls = ({[^;]+})")
    if jsBlock then
        -- Parse JSON object: {"1":"url1","2":"url2",...}
        local ok, data = pcall(json_parse, jsBlock)
        if ok and data then
            -- Sort by numeric keys
            local keys = {}
            for k in pairs(data) do
                table.insert(keys, tonumber(k) or k)
            end
            table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
            for _, k in ipairs(keys) do
                if data[tostring(k)] then
                    table.insert(pages, absUrl(data[tostring(k)]))
                end
            end
            return pages
        end
    end

    -- Fallback: look for img.manga-image (single page mode)
    local imgEl = html_select_first(html, "img.manga-image")
    if imgEl then
        local src = imgEl.src or ""
        if src ~= "" then
            table.insert(pages, absUrl(src))
        end
    end

    return pages
end

function getChapterText(html, url)
    return ""
end
