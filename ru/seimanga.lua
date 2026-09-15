id       = "seimanga"
name     = "SeiManga"
version  = "1.0.0"
baseUrl  = "https://1.seimanga.me"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/seimanga.png"
content_type = "manga"

-- SeiManga (GroupLe) — манга на русском, siteId=21.
-- Клон readmanga с другим доменом.

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local defaultHeaders = {
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36",
}

local function fetch(url)
    local r = http_get(url, { headers = defaultHeaders })
    if not r.success then return nil end
    return r.body
end

local function mangaSlug(bookUrl)
    return string.match(bookUrl, "/([^/?]+)__%d+") or string.match(bookUrl, "/(%d+)$") or string.match(bookUrl, "/([^/]+)$")
end

-- ── Каталог (JSON API) ──

function getCatalogList(index)
    local offset = 50 * index
    local body = fetch(baseUrl .. "/api/catalog/search?offset=" .. offset .. "&sortType=DATE_UPDATE")
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.list) do
        local title = m.name or ""
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName == "" then goto continue end
        local item = {
            title = title,
            url = baseUrl .. "/" .. linkName,
            cover = m.picUrl or "",
        }
        local rating = m.rating
        if type(rating) == "table" then rating = rating.rate or rating.value end
        if rating and type(rating) == "number" and rating > 0 then
            item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
        end
        table.insert(items, item)
        ::continue::
    end
    local hasNext = (data.offset or 0) + (data.limit or 50) < (data.total or 0)
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local offset = 50 * index
    local body = fetch(baseUrl .. "/api/catalog/search?offset=" .. offset .. "&q=" .. url_encode(query))
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.list) do
        local title = m.name or ""
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName == "" then goto continue end
        local item = {
            title = title,
            url = baseUrl .. "/" .. linkName,
            cover = m.picUrl or "",
        }
        local rating = m.rating
        if type(rating) == "table" then rating = rating.rate or rating.value end
        if rating and type(rating) == "number" and rating > 0 then
            item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
        end
        table.insert(items, item)
        ::continue::
    end
    return { items = items, hasNext = false }
end

-- ── Фильтры ──

function getFilterList()
    return {
        {
            type = "select",
            key = "sort",
            label = "Сортировка",
            defaultValue = "DATE_UPDATE",
            options = {
                { value = "RATING", label = "По рейтингу" },
                { value = "DATE_UPDATE", label = "По обновлению" },
            },
        },
    }
end

function getCatalogFiltered(index, filters)
    local sort = filters["sort"] or "DATE_UPDATE"
    local offset = 50 * index
    local body = fetch(baseUrl .. "/api/catalog/search?offset=" .. offset .. "&sortType=" .. sort)
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.list) do
        local title = m.name or ""
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName == "" then goto continue end
        local item = {
            title = title,
            url = baseUrl .. "/" .. linkName,
            cover = m.picUrl or "",
        }
        local rating = m.rating
        if type(rating) == "table" then rating = rating.rate or rating.value end
        if rating and type(rating) == "number" and rating > 0 then
            item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
        end
        table.insert(items, item)
        ::continue::
    end
    local hasNext = (data.offset or 0) + (data.limit or 50) < (data.total or 0)
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги (HTML парсинг) ──

local _mangaCache = {}

local function fetchMangaDetails(bookUrl)
    local slug = mangaSlug(bookUrl)
    if not slug then return nil end
    if _mangaCache[slug] then return _mangaCache[slug] end
    local body = fetch(bookUrl)
    if not body then return nil end
    _mangaCache[slug] = body
    return body
end

function getBookTitle(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local title = body:match('itemprop="name"%s+content="([^"]+)"')
    if title then return string_trim(title) end
    return ""
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local src = body:match('PICTURE_PREVIEWS_DATA%s*=%s*%{[^}]*"poster"%s*:%s*%[%s*\{[^}]*"src"%s*:%s*"([^"]+)"')
    if src then return absUrl(src) end
    src = body:match('cr-hero-poster__img"[^>]*src="([^"]+)"')
    if src then return absUrl(src) end
    for tag in body:gmatch('<img[^>]+>') do
        if tag:find("poster") or tag:find("cover") or tag:find("uploads/pics") then
            local s = tag:match('src="([^"]+)"')
            if s then return absUrl(s) end
        end
    end
    return ""
end

function getBookDescription(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local block = body:match('cr%-description__content"[^>]*>(.-)%s*</div>%s*</div>')
    if not block then block = body:match('cr%-description__content"[^>]*>(.-)</div>') end
    if block then
        local desc = block:gsub('<[^>]+>', ''):gsub('&nbsp;', ' '):gsub('&amp;', '&'):gsub('&quot;', '"'):gsub('&#39;', "'"):gsub('%s+', ' '):match('^%s*(.-)%s*$')
        if desc and desc ~= "" then return desc end
    end
    return ""
end

function getBookGenres(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return {} end
    local genres = {}
    local seen = {}
    for slug in body:gmatch('genre/([^/"]+)') do
        local name = slug:gsub("_", " ")
        if name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(genres, name)
        end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local v = body:match('cr-hero-rating__value[^>]*>([%d%.]+)')
    if v then
        local n = tonumber(v)
        if n and n > 0 then return v .. "/10" end
    end
    return ""
end

function getBookStatus(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local status = body:match('data-production-status="[^"]*">([^<]+)')
    if status then return string_trim(status) end
    return ""
end

function getBookLastUpdate(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local date = body:match('itemprop="datePublished"%s+content="([^"]*)"')
    if date then return string_trim(date) end
    return ""
end

function getChapterList(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return {} end
    local slug = mangaSlug(bookUrl)
    local chapters = {}
    local seen = {}
    for href in body:gmatch('href="(/' .. slug .. '/vol(%d+)/(%d+))"') do
        local vol, num = href:match('/vol(%d+)/(%d+)')
        if vol and num and not seen[vol .. num] then
            seen[vol .. num] = true
            table.insert(chapters, {
                title = "Том " .. vol .. " Глава " .. num,
                url = absUrl(href),
            })
        end
    end
    return chapters
end

function getChapterListHash(bookUrl)
    local chapters = getChapterList(bookUrl)
    if #chapters == 0 then return "" end
    return chapters[#chapters].url
end

-- ── Страницы главы (HTML + regex) ──

function getPageList(html, url)
    if not html or html == "" then
        local body = fetch(url)
        if not body then return {} end
        html = body
    end
    local pages = {}
    for match in string.gmatch(html, "%['(.-)'%],['(.-)'%],['(.-)'%]") do
        local host, middle, endPart = match:match("^(.-)\t(.-)\t(.-)$")
        if host and middle and endPart then
            local imageUrl
            if middle == "" and endPart:find("^/static/") then
                imageUrl = baseUrl .. endPart
            elseif middle:find("/manga/$") then
                imageUrl = host .. endPart
            else
                imageUrl = middle .. host .. endPart
            end
            if not imageUrl:find("://") then
                imageUrl = "https:" .. imageUrl
            end
            table.insert(pages, imageUrl)
        end
    end
    return pages
end

function getChapterText(html, url)
    local pages = getPageList(html, url)
    local out = {}
    for _, p in ipairs(pages) do
        table.insert(out, '<img src="' .. p .. '">')
    end
    return table.concat(out, "\n")
end
