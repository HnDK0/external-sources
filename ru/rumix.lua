id       = "rumix"
name     = "RuManga"
version  = "1.1.0"
baseUrl  = "https://rumix.me"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/rumix.png"
content_type = "manga"

-- RuManga (GroupLe) — манга на русском, siteId=5.
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
                { value = "NAME", label = "По алфавиту" },
                { value = "YEAR", label = "По году" },
                { value = "POPULARITY", label = "По популярности" },
                { value = "USER_RATING", label = "По оценке" },
                { value = "DATE_CREATE", label = "Новинки" },
            },
        },
        {
            type = "select",
            key = "genre",
            label = "Жанр",
            defaultValue = "",
            options = {
                { value = "", label = "Все" },
                { value = "2131", label = "Фэнтези" },
                { value = "2155", label = "Боевик" },
                { value = "2136", label = "Комедия" },
                { value = "2121", label = "Романтика" },
                { value = "2118", label = "Драма" },
                { value = "2119", label = "История" },
                { value = "2152", label = "Детектив" },
                { value = "2130", label = "Приключения" },
                { value = "2134", label = "Сёнэн" },
                { value = "2138", label = "Сэйнэн" },
                { value = "2142", label = "Гарем" },
                { value = "2158", label = "Дзёсэй" },
                { value = "2122", label = "Сёдзё" },
                { value = "2133", label = "Научная фантастика" },
                { value = "2144", label = "Психология" },
                { value = "2150", label = "Триллер" },
                { value = "2125", label = "Ужасы" },
                { value = "2127", label = "Школа" },
                { value = "2149", label = "Этти" },
                { value = "2129", label = "Спорт" },
                { value = "2151", label = "Постапокалиптика" },
                { value = "2153", label = "Трагедия" },
                { value = "2156", label = "Гендерная интрига" },
                { value = "2137", label = "Кодомо" },
                { value = "8032", label = "Киберпанк" },
                { value = "9450", label = "Исэкай" },
                { value = "9514", label = "Музыка" },
                { value = "9524", label = "Пародия" },
                { value = "2159", label = "Сверхъестественное" },
                { value = "10196", label = "Женщины" },
                { value = "10197", label = "Мужчины" },
                { value = "2143", label = "Боевые искусства" },
            },
        },
        {
            type = "select",
            key = "category",
            label = "Категория",
            defaultValue = "",
            options = {
                { value = "", label = "Все" },
                { value = "9451", label = "Манга" },
                { value = "3001", label = "Манхва" },
                { value = "3002", label = "Маньхуа" },
                { value = "2141", label = "Додзинси" },
                { value = "3515", label = "Комикс" },
                { value = "2161", label = "Ёнкома" },
                { value = "9577", label = "OEL-манга" },
                { value = "5685", label = "Арт" },
            },
        },
        {
            type = "select",
            key = "productionStatus",
            label = "Статус выхода",
            defaultValue = "",
            options = {
                { value = "", label = "Любые" },
                { value = "PROGRESS", label = "Продолжается" },
                { value = "FINISHED", label = "Завершён" },
                { value = "PLANNED", label = "Запланирован" },
                { value = "POSTPONED", label = "Приостановлен" },
                { value = "CANCELED", label = "Отменён" },
                { value = "NON_FINISHED", label = "Не окончен" },
            },
        },
        {
            type = "select",
            key = "translationStatus",
            label = "Статус перевода",
            defaultValue = "",
            options = {
                { value = "", label = "Любые" },
                { value = "PROGRESS", label = "Продолжается" },
                { value = "FINISHED", label = "Завершён" },
                { value = "STARTED", label = "Начат" },
                { value = "POSTPONED", label = "Приостановлен" },
                { value = "NONE", label = "Отсутствует" },
                { value = "NO_NEED", label = "Нет необходимости" },
            },
        },
        {
            type = "sort",
            key = "year",
            label = "Год",
            defaultValue = "",
            options = {
                { value = "", label = "Любой" },
                { value = "2025,2025", label = "2025" },
                { value = "2024,2024", label = "2024" },
                { value = "2023,2023", label = "2023" },
                { value = "2020,2025", label = "2020-2025" },
                { value = "2015,2019", label = "2015-2019" },
                { value = "2010,2014", label = "2010-2014" },
                { value = "2000,2009", label = "2000-2009" },
                { value = "1990,1999", label = "1990-1999" },
                { value = "1980,1989", label = "1980-1989" },
            },
        },
    }
end

function getCatalogFiltered(index, filters)
    local sort = filters["sort"] or "DATE_UPDATE"
    local offset = 50 * index
    local params = "offset=" .. offset .. "&sortType=" .. sort
    
    local genre = filters["genre"] or ""
    if genre ~= "" then
        params = params .. "&includeElementIds=" .. genre
    end
    
    local category = filters["category"] or ""
    if category ~= "" then
        params = params .. "&includeElementIds=" .. category
    end
    
    local prodStatus = filters["productionStatus"] or ""
    if prodStatus ~= "" then
        params = params .. "&includeProductionStatuses=" .. prodStatus
    end
    
    local transStatus = filters["translationStatus"] or ""
    if transStatus ~= "" then
        params = params .. "&includeTranslationStatuses=" .. transStatus
    end
    
    local year = filters["year"] or ""
    if year ~= "" then
        params = params .. "&years=" .. year
    end
    
    local body = fetch(baseUrl .. "/api/catalog/search?" .. params)
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
    src = body:match('og:image"%s+content="([^"]+)"')
    if src then return absUrl(src) end
    src = body:match('content="([^"]+)"%s+property="og:image"')
    if src then return absUrl(src) end
    for tag in body:gmatch('<img[^>]+>') do
        if tag:find("poster") or tag:find("cover") or tag:find("uploads/pics") then
            local s = tag:match('src="([^"]+)"') or tag:match("src='([^']+)'")
            if s then return absUrl(s) end
        end
    end
    for tag in body:gmatch('<img[^>]+>') do
        local s = tag:match('src="([^"]+)"') or tag:match("src='([^']+)'")
        if s and s:find("uploads/pics") then return absUrl(s) end
    end
    return ""
end

function getBookDescription(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local desc = body:match('itemprop="description"%s+content="([^"]*)"')
    if desc then return string_trim(desc) end
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
                vol = tonumber(vol),
                num = tonumber(num),
            })
        end
    end
    table.sort(chapters, function(a, b)
        if a.vol ~= b.vol then return a.vol < b.vol end
        return a.num < b.num
    end)
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
    local riStart = html:find("readerInit(", 1, true)
    if not riStart then return {} end
    local arrStart = html:find("[", riStart, true)
    if not arrStart then return {} end
    local depth = 0
    local pos = arrStart
    local arrEnd = nil
    while pos <= #html do
        local c = html:sub(pos, pos)
        if c == "[" then depth = depth + 1
        elseif c == "]" then
            depth = depth - 1
            if depth == 0 then arrEnd = pos; break end
        end
        pos = pos + 1
    end
    if not arrEnd then return {} end
    local pageArray = html:sub(arrStart + 1, arrEnd - 1)
    local entryStart = 1
    while entryStart <= #pageArray do
        local s = pageArray:find("[", entryStart, true)
        if not s then break end
        local e = pageArray:find("]", s + 1, true)
        if not e then break end
        local entry = pageArray:sub(s + 1, e - 1)
        local a, b, c = entry:match("['\"]([^'\"]*)['\"]%s*,%s*['\"]([^'\"]*)['\"]%s*,%s*['\"]([^'\"]*)['\"]")
        if a and b and c then
            local imageUrl = a .. b .. c
            if not imageUrl:find("://") then
                imageUrl = "https:" .. imageUrl
            end
            table.insert(pages, imageUrl)
        end
        entryStart = e + 1
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
