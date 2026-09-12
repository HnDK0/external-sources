id       = "voratoon"
name     = "VoraToon"
version  = "1.0.0"
baseUrl  = "https://v2.voratoon.com/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/voratoon.webp"
content_type = "manga"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local API_BASE = "https://api.voratoon.com"

-- Возвращает data.data и data.meta отдельно (meta нужен для пагинации)
local function apiGet(path, params)
    local url = API_BASE .. path
    if params then
        local sep = "?"
        for k, v in pairs(params) do
            if v ~= nil and v ~= "" then
                url = url .. sep .. k .. "=" .. url_encode(tostring(v))
                sep = "&"
            end
        end
    end
    local r = http_get(url)
    if not r.success then return nil, nil end
    local ok, resp = pcall(json_parse, r.body)
    if not ok or not resp or resp.status ~= 200 then return nil, nil end
    return resp.data, resp.meta
end

-- Извлекает slug из URL книги (относительный или абсолютный)
local function slugFromUrl(bookUrl)
    return bookUrl:match("/series/([^/]+)")
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local data, meta = apiGet("/series", { take = 30, page = page, sort = "latest", sortOrder = "desc" })
    if not data then return { items = {}, hasNext = false } end
    local items = {}
    for _, s in ipairs(data) do
        local d = s.data or {}
        local slug = d.slug or tostring(s.id)
        table.insert(items, {
            title = d.title or "Untitled",
            url   = baseUrl .. "series/" .. slug,
            cover = d.coverImage or "",
        })
    end
    local lastPage = (meta and meta.lastPage) or 1
    return { items = items, hasNext = page < lastPage }
end

function getCatalogSearch(index, query)
    local page = index + 1
    local data, meta = apiGet("/series", { take = 30, page = page, sort = "latest", sortOrder = "desc", title = query })
    if not data then return { items = {}, hasNext = false } end
    local items = {}
    for _, s in ipairs(data) do
        local d = s.data or {}
        local slug = d.slug or tostring(s.id)
        table.insert(items, {
            title = d.title or "Untitled",
            url   = baseUrl .. "series/" .. slug,
            cover = d.coverImage or "",
        })
    end
    local lastPage = (meta and meta.lastPage) or 1
    return { items = items, hasNext = page < lastPage }
end

-- ── Фильтры ───────────────────────────────────────────────────────────────────

function getFilterList()
    return {
        { key = "sort", label = "Sort", type = "select", options = {
            { value = "latest", label = "Latest Update" },
            { value = "totalViews", label = "Popular" },
            { value = "rating", label = "Rating" },
            { value = "title", label = "A-Z" },
        }, defaultValue = "latest" },
        { key = "sortOrder", label = "Sort Order", type = "select", options = {
            { value = "desc", label = "Desc" },
            { value = "asc", label = "Asc" },
        }, defaultValue = "desc" },
        { key = "status", label = "Status", type = "select", options = {
            { value = "", label = "Any" },
            { value = "ongoing", label = "Ongoing" },
            { value = "completed", label = "Completed" },
            { value = "hiatus", label = "Hiatus" },
            { value = "cancelled", label = "Cancelled" },
        }, defaultValue = "" },
        { key = "format", label = "Format", type = "select", options = {
            { value = "", label = "Any" },
            { value = "manga", label = "Manga" },
            { value = "manhwa", label = "Manhwa" },
            { value = "manhua", label = "Manhua" },
            { value = "webtoon", label = "Webtoon" },
        }, defaultValue = "" },
        { key = "type", label = "Type", type = "select", options = {
            { value = "", label = "Any" },
            { value = "project", label = "Project" },
            { value = "mirror", label = "Mirror" },
        }, defaultValue = "" },
        { key = "genres", label = "Genres", type = "checkbox", options = {
            { value = "1", label = "Seinen" },
            { value = "2", label = "School Life" },
            { value = "3", label = "Yuri" },
            { value = "4", label = "Psychological" },
            { value = "5", label = "Thriller" },
            { value = "6", label = "Isekai" },
            { value = "7", label = "Cooking" },
            { value = "8", label = "Webtoons" },
            { value = "9", label = "Medical" },
            { value = "10", label = "Historical" },
            { value = "11", label = "4-Koma" },
            { value = "12", label = "Sports" },
            { value = "13", label = "Slice of Life" },
            { value = "14", label = "Reincarnation" },
            { value = "15", label = "Gore" },
            { value = "16", label = "Adventure" },
            { value = "17", label = "Game" },
            { value = "18", label = "Horror" },
            { value = "19", label = "Action" },
            { value = "20", label = "Mecha" },
            { value = "21", label = "Vampire" },
            { value = "22", label = "Comedy" },
            { value = "23", label = "Josei" },
            { value = "24", label = "Supernatural" },
            { value = "25", label = "Shounen Ai" },
            { value = "26", label = "Romance" },
            { value = "27", label = "Shoujo Ai" },
            { value = "28", label = "Fantasy" },
            { value = "29", label = "Drama" },
            { value = "30", label = "Shounen" },
            { value = "31", label = "Shoujo" },
            { value = "32", label = "Sci-Fi" },
            { value = "33", label = "One-Shot" },
            { value = "34", label = "Harem" },
            { value = "35", label = "Magic" },
            { value = "36", label = "Military" },
            { value = "37", label = "Mature" },
            { value = "38", label = "Tragedy" },
            { value = "39", label = "Mystery" },
            { value = "40", label = "Demons" },
            { value = "41", label = "Gender Bender" },
            { value = "42", label = "School" },
            { value = "43", label = "Police" },
            { value = "44", label = "Music" },
            { value = "45", label = "Super Power" },
            { value = "46", label = "Martial Arts" },
            { value = "47", label = "Ecchi" },
            { value = "49", label = "Adult" },
        } },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local params = { take = 30, page = page }

    -- Сортировка (query params, как в Tachiyomi)
    local sort = filters["sort"]
    if sort and sort ~= "" then params.sort = sort end
    local sortOrder = filters["sortOrder"]
    if sortOrder and sortOrder ~= "" then params.sortOrder = sortOrder end

    -- Фильтры через параметр filter (field==value через точку с запятой)
    local filterParts = {}
    local status = filters["status"]
    if status and status ~= "" then table.insert(filterParts, "status==" .. status) end
    local format = filters["format"]
    if format and format ~= "" then table.insert(filterParts, "format==" .. format) end
    local type = filters["type"]
    if type and type ~= "" then table.insert(filterParts, "type==" .. type) end

    -- Жанры — genreIds==ID через ; (multiselect, как в Tachiyomi)
    local genres = filters["genres_included"]
    if genres and #genres > 0 then
        for _, gid in ipairs(genres) do
            table.insert(filterParts, "genreIds==" .. gid)
        end
    end

    if #filterParts > 0 then params.filter = table.concat(filterParts, ";") end

    local data, meta = apiGet("/series", params)
    if not data then return { items = {}, hasNext = false } end
    local items = {}
    for _, s in ipairs(data) do
        local d = s.data or {}
        local slug = d.slug or tostring(s.id)
        table.insert(items, {
            title = d.title or "Untitled",
            url   = baseUrl .. "series/" .. slug,
            cover = d.coverImage or "",
        })
    end
    local lastPage = (meta and meta.lastPage) or 1
    return { items = items, hasNext = page < lastPage }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

local _seriesCache = {}

local function fetchSeries(slug)
    if _seriesCache[slug] then return _seriesCache[slug] end
    local data = apiGet("/series/" .. slug)
    if data then _seriesCache[slug] = data end
    return data
end

function getBookTitle(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local d = s.data or {}
    return d.title or nil
end

function getBookCoverImageUrl(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local d = s.data or {}
    return d.coverImage or nil
end

function getBookDescription(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local d = s.data or {}
    local text = d.synopsis
    if text and text ~= "" then return string_trim(text) end
    return nil
end

function getBookGenres(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return {} end
    local s = fetchSeries(slug)
    if not s then return {} end
    local d = s.data or {}
    local genres = {}
    if d.genres then
        for _, g in ipairs(d.genres) do
            local name = g.data and g.data.name or g.name
            if name and name ~= "" then table.insert(genres, name) end
        end
    end
    return genres
end

function getBookRating(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local d = s.data or {}
    local r = d.rating
    if r and r > 0 then return tostring(r) .. "/10" end
    return nil
end

function getBookStatus(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local d = s.data or {}
    local st = d.status
    if st and st ~= "" then
        return st:sub(1, 1):upper() .. st:sub(2)
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local updated = s.updatedAt
    if not updated or updated == "" then return nil end
    local y, m, d = updated:match("(%d%d%d%d)-(%d%d)-(%d%d)")
    if y then return y .. "-" .. m .. "-" .. d end
    return nil
end

function getBookChaptersCount(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return nil end
    local s = fetchSeries(slug)
    if not s then return nil end
    local d = s.data or {}
    local count = d.totalChapters
    if count and count ~= "" then return count end
    return nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return {} end
    local chapters = apiGet("/series/" .. slug .. "/chapters")
    if not chapters then return {} end
    local result = {}
    for _, ch in ipairs(chapters) do
        local d = ch.data or {}
        local idx = d.index or ch.chapterIndex or 0
        local title = d.title
        if not title or title == "" then title = "Chapter " .. tostring(idx) end
        table.insert(result, {
            title = title,
            url   = baseUrl .. "series/" .. slug .. "/chapters/" .. tostring(idx),
        })
    end
    -- Гайд: getChapterList возвращает в хронологическом порядке (старые → новые).
    -- API отдаёт новые сверху — разворачиваем.
    local reversed = {}
    for i = #result, 1, -1 do
        table.insert(reversed, result[i])
    end
    return reversed
end

function getChapterListHash(bookUrl)
    local slug = slugFromUrl(bookUrl)
    if not slug then return "" end
    local chapters = apiGet("/series/" .. slug .. "/chapters")
    if not chapters or #chapters == 0 then return "" end
    -- API отдаёт новые сверху — первая глава = самая новая
    local first = chapters[1]
    local d = first.data or {}
    local idx = d.index or first.chapterIndex or 0
    return baseUrl .. "series/" .. slug .. "/chapters/" .. tostring(idx)
end

-- ── Текст главы (картинки) ────────────────────────────────────────────────────

function getPageList(html, url)
    local parts = {}
    -- Извлекаем slug и индекс главы из URL (индекс может быть дробным, например 1.5)
    local slug = url:match("/series/([^/]+)")
    local idx = url:match("/chapters/([^.]+)$")
    if slug and idx then
        local chData = apiGet("/series/" .. slug .. "/chapters/" .. idx)
        -- API: resp.data.data.images (вложенный data)
        if chData then
            local inner = chData.data or {}
            if inner.images then
                for _, img in ipairs(inner.images) do
                    if img and img ~= "" then table.insert(parts, img) end
                end
            end
        end
    end
    return parts
end

function getChapterText(html, url)
    local pages = getPageList(html, url)
    local imgs = {}
    for _, p in ipairs(pages) do
        table.insert(imgs, '<img src="' .. p:gsub("&", "&amp;") .. '">')
    end
    return table.concat(imgs, "\n")
end
