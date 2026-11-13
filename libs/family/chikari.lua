-- =====================================================================
-- Lib: chikari family — shared engine for chikari.moe novels and comics.
-- Loaded via require_lib("chikari"); uses urls/meta/catalog/content.
--
-- Both sections share one list endpoint (GET /api/series with repeated
-- type=); only detail/chapter routes differ:
--   novel: /api/novels/<slug>, /api/novels/<slug>/chapters/<n>/read -> body
--   manga: /api/series/<slug>, /api/series/<slug>/chapters/<n> -> pages[]
-- Config (every M.* takes it first):
--   id       string  log prefix (required)
--   baseUrl  string  site origin with trailing slash (required)
--   mode     string  "novel" | "manga" (required)
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")
local meta = require_lib("meta")
local catalog = require_lib("catalog")
local content = require_lib("content")

local M = {}

local MODES = {
    novel = {
        types = { "novel" },
        site = "novel/",
        detail = "api/novels/",
        chapters = "api/novels/",
        read = "/read",
        kind = "text",
    },
    manga = {
        types = { "manhwa", "manhua", "manga" },
        site = "series/",
        detail = "api/series/",
        chapters = "api/series/",
        read = "",
        kind = "pages",
    },
}

local function logErr(msg)
    if type(log_error) == "function" then log_error("chikari: " .. msg) end
end

local function base(cfg)
    return (cfg.baseUrl:gsub("/$", "")) .. "/"
end

local function headers(cfg)
    -- The SPA sends Origin with every fetch; Cloudflare treats a bare request
    -- as a bot request (30s SocketTimeout / HTTP2 stream reset).
    return {
        Accept = "application/json",
        Origin = (cfg.baseUrl:gsub("/$", "")),
    }
end

local function fetchJson(cfg, url)
    for attempt = 1, 3 do
        local r = http_get(url, { headers = headers(cfg) })
        if r.success then
            local ok, data = pcall(json_parse, r.body)
            if ok and type(data) == "table" then return data end
            logErr("bad JSON " .. url)
            return nil
        end
        logErr("HTTP " .. tostring(r.code) .. " " .. url .. " attempt=" .. attempt)
        if attempt < 3 then sleep(500) end
    end
    return nil
end

local function slugOf(bookUrl)
    return (bookUrl or ""):match("([^/?#]+)/?$")
end

local function numberString(n)
    local v = tonumber(n) or 0
    if v % 1 == 0 then return tostring(math.floor(v)) end
    return tostring(v)
end

local function ratingString(v)
    local n = tonumber(v)
    if not n or n <= 0 then return nil end
    return string.format("%.1f", n) .. "/10"
end

-- Shared list item -> CatalogItem.
local function buildItems(cfg, d)
    local m = MODES[cfg.mode]
    local items = {}
    if type(d) ~= "table" or type(d.items) ~= "table" then return items end
    for _, it in ipairs(d.items) do
        local slug = it.slug
        if type(slug) == "string" and slug ~= "" then
            items[#items + 1] = {
                title  = string_clean(it.title or ""),
                url    = base(cfg) .. m.site .. slug,
                cover  = it.cover_url or "",
                rating = ratingString(it.rating),
            }
        end
    end
    return items
end

local function pageResult(cfg, d, offset)
    local items = buildItems(cfg, d)
    local total = tonumber(d and d.total) or 0
    return { items = items, hasNext = (offset + #items) < total }
end

local function listUrl(cfg, index, query, extra)
    local m = MODES[cfg.mode]
    local limit = 60
    local offset = (index or 0) * limit
    local parts = {
        "limit=" .. limit,
        "offset=" .. offset,
        "sort=" .. catalog.urlEncode("popular"),
    }
    for _, t in ipairs(m.types) do
        parts[#parts + 1] = "type=" .. catalog.urlEncode(t)
    end
    if query and query ~= "" then
        parts[#parts + 1] = "q=" .. catalog.urlEncode(query)
    end
    for _, part in ipairs(extra or {}) do
        parts[#parts + 1] = part
    end
    return base(cfg) .. "api/series?" .. table.concat(parts, "&"), offset
end

function M.list(cfg, index)
    local url, offset = listUrl(cfg, index)
    return pageResult(cfg, fetchJson(cfg, url), offset)
end

function M.search(cfg, index, query)
    local url, offset = listUrl(cfg, index, query)
    return pageResult(cfg, fetchJson(cfg, url), offset)
end

function M.filtered(cfg, index, filters)
    filters = filters or {}
    local extra = {}
    local sort = filters["sort"]
    if sort and sort ~= "" then
        extra[#extra + 1] = "sort=" .. catalog.urlEncode(sort)
    end
    local status = filters["status"]
    if status and status ~= "" then
        extra[#extra + 1] = "status=" .. catalog.urlEncode(status)
    end
    for _, g in ipairs(filters["genres_included"] or {}) do
        if g and g ~= "" then
            extra[#extra + 1] = "genre=" .. catalog.urlEncode(g)
        end
    end
    local url, offset = listUrl(cfg, index, nil, extra)
    return pageResult(cfg, fetchJson(cfg, url), offset)
end

-- ── Filter schema (same on both plugins) ─────────────────────────────

local GENRES = {
    { value = "action",        label = "Action" },
    { value = "adventure",     label = "Adventure" },
    { value = "comedy",        label = "Comedy" },
    { value = "drama",         label = "Drama" },
    { value = "ecchi",         label = "Ecchi" },
    { value = "fantasy",       label = "Fantasy" },
    { value = "gender_bender", label = "Gender Bender" },
    { value = "harem",         label = "Harem" },
    { value = "historical",    label = "Historical" },
    { value = "horror",        label = "Horror" },
    { value = "josei",         label = "Josei" },
    { value = "martial_arts",  label = "Martial Arts" },
    { value = "mature",        label = "Mature" },
    { value = "mecha",         label = "Mecha" },
    { value = "mystery",       label = "Mystery" },
    { value = "psychological", label = "Psychological" },
    { value = "romance",       label = "Romance" },
    { value = "school_life",   label = "School Life" },
    { value = "sci-fi",        label = "Sci-Fi" },
    { value = "seinen",        label = "Seinen" },
    { value = "shoujo",        label = "Shoujo" },
    { value = "shoujo_ai",     label = "Shoujo Ai" },
    { value = "shounen",       label = "Shounen" },
    { value = "shounen_ai",    label = "Shounen Ai" },
    { value = "slice_of_life", label = "Slice of Life" },
    { value = "sports",        label = "Sports" },
    { value = "supernatural",  label = "Supernatural" },
    { value = "tragedy",       label = "Tragedy" },
    { value = "yaoi",          label = "Yaoi" },
    { value = "yuri",          label = "Yuri" },
}

function M.filters()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "popular",
            options = {
                { value = "popular",         label = "Popular" },
                { value = "trending",        label = "Trending" },
                { value = "top_rated",       label = "Top Rated" },
                { value = "updated",         label = "Recently Updated" },
                { value = "added",           label = "Recently Added" },
                { value = "most_bookmarked", label = "Most Bookmarked" },
            },
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "",
            options = {
                { value = "",          label = "All" },
                { value = "releasing", label = "Ongoing" },
                { value = "completed", label = "Completed" },
                { value = "hiatus",    label = "On Hiatus" },
                { value = "cancelled", label = "Cancelled" },
            },
        },
        {
            type        = "checkbox",
            key         = "genres",
            label       = "Genres",
            multiselect = true,
            options     = GENRES,
        },
    }
end

-- ── Book detail ──────────────────────────────────────────────────────

local _detail = {}

function M.detail(cfg, bookUrl)
    local slug = slugOf(bookUrl)
    if not slug then return nil end
    local key = cfg.mode .. ":" .. slug
    if _detail[key] ~= nil then return _detail[key] or nil end
    local m = MODES[cfg.mode]
    local d = fetchJson(cfg, base(cfg) .. m.detail .. slug)
    _detail[key] = d or false
    return d
end

local function detail(cfg, bookUrl)
    return M.detail(cfg, bookUrl)
end

function M.title(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    return d and string_clean(d.title or "") or nil
end

function M.cover(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    return d and d.cover_url or nil
end

function M.description(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    return d and d.description or nil
end

function M.genres(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    if not d or type(d.genres) ~= "table" then return {} end
    local names = {}
    for _, g in ipairs(d.genres) do
        if type(g.name) == "string" and g.name ~= "" then names[#names + 1] = g.name end
    end
    return names
end

local STATUS = {
    releasing = "Ongoing",
    completed = "Completed",
    hiatus    = "On Hiatus",
    cancelled = "Cancelled",
}

function M.status(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    if not d or not d.status then return nil end
    return STATUS[d.status] or d.status
end

function M.rating(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    return d and ratingString(d.rating) or nil
end

function M.lastUpdate(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    if not d or not d.last_chapter_at then return nil end
    return meta.normalizeDate(d.last_chapter_at)
end

function M.author(cfg, bookUrl)
    local d = detail(cfg, bookUrl)
    if not d or type(d.authors) ~= "table" then return nil end
    local names = {}
    for _, a in ipairs(d.authors) do
        if a.role == "author" and type(a.name) == "string" and a.name ~= "" then
            names[#names + 1] = a.name
        end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

-- ── Chapters ─────────────────────────────────────────────────────────

function M.chapters(cfg, bookUrl)
    local m = MODES[cfg.mode]
    local slug = slugOf(bookUrl)
    if not slug then return {} end
    local limit = 500
    local offset = 0
    local chapters = {}
    while true do
        local url = base(cfg) .. m.chapters .. slug .. "/chapters?order=asc&limit="
            .. limit .. "&offset=" .. offset
        local d = fetchJson(cfg, url)
        if not d or type(d.items) ~= "table" then break end
        for _, ch in ipairs(d.items) do
            local number = numberString(ch.number)
            local title = string_clean(ch.title or "")
            if title == "" then title = "Chapter " .. number end
            chapters[#chapters + 1] = {
                title = title,
                url = base(cfg) .. m.chapters .. slug .. "/chapters/" .. number .. m.read,
            }
        end
        if #d.items < limit then break end
        offset = offset + limit
        sleep(100)
    end
    return chapters
end

-- ── Chapter content ──────────────────────────────────────────────────

local function chapterData(cfg, html, url)
    if type(html) == "string" and html:sub(1, 1) == "{" then
        local ok, data = pcall(json_parse, html)
        if ok and type(data) == "table" then return data end
    end
    return fetchJson(cfg, url)
end

function M.chapterText(cfg, html, url)
    local data = chapterData(cfg, html, url)
    if not data or type(data.body) ~= "string" or data.body == "" then return "" end
    return content.standardTransforms(data.body, { domain = cfg.baseUrl, lang = "en" })
end

function M.pageList(cfg, html, url)
    local data = chapterData(cfg, html, url)
    if not data or type(data.pages) ~= "table" then return {} end
    local pages, seen = {}, {}
    for _, p in ipairs(data.pages) do
        local abs = urls.absUrl(cfg.baseUrl, p)
        if abs ~= "" and not seen[abs] then
            seen[abs] = true
            pages[#pages + 1] = abs
        end
    end
    return pages
end

return M
