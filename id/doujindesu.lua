-- Doujindesu (Indonesia) - Manga plugin for NoveLA
-- API-only source: HTML routes answer 404, every JSON payload comes
-- encrypted as { "_enc_resp_": "<hex>" }.

id         = "doujindesu"
name       = "Doujindesu"
version    = "1.0.0"
baseUrl    = "https://doujin.desu.xxx"
language   = "id"
content_type = "manga"
icon       = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/doujindesu.png"
referer    = "https://doujin.desu.xxx/"

local LIMIT = 24

-- UNVERIFIED: salt from the site bundle, may rotate
local SO = "doujindesu-scrapers-cannot-read-this-super-secret-salt-2026-v2"

-- Percent decoding (decodeURIComponent emulation)
local function url_decode(s)
    if type(s) ~= "string" then return nil end
    return (s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- JS ToInt32 coercion
local function to_int32(v)
    v = v % 4294967296
    if v >= 2147483648 then
        v = v - 4294967296
    end
    return v
end

-- 32-char key for one hour bucket
local function bs(a)
    local s = SO .. "_" .. tostring(a)
    local l = 0
    for i = 1, #s do
        l = to_int32(l * 32 - l + string.byte(s, i))
    end
    local c = math.abs(l)
    if c == 0 then c = 123456789 end
    local out = {}
    for i = 1, 32 do
        c = (c * 1664525 + 1013904223) % 4294967296
        out[i] = string.char(33 + c % 93)
    end
    return table.concat(out)
end

-- Keys for the current hour first (usual case), then neighbours: a wrong
-- key makes json_parse throw, which the engine logs as an error line.
local function keys()
    local hour = math.floor(os_time() / 3600000)
    return { bs(hour), bs(hour - 1), bs(hour + 1) }
end

-- XOR the hex payload with the key. No <<, ~, &, | in LuaJ: bit32 only.
local function lo(hex, key)
    local bytes = {}
    for i = 1, #hex, 2 do
        local w = tonumber(hex:sub(i, i + 1), 16)
        if w then bytes[#bytes + 1] = w end
    end
    local out = {}
    local n = 42
    local klen = #key
    for x = 0, #bytes - 1 do
        local w = bytes[x + 1]
        local p = bit32.bxor(w, string.byte(key, (x % klen) + 1), x * 13, n)
        out[#out + 1] = string.char(p % 256)
        n = (n + w) % 256
    end
    return table.concat(out)
end

-- Response body -> table: JSON parse, then decrypt _enc_resp_ with all
-- three keys until one of them yields valid JSON.
local function decrypt_body(body)
    if type(body) ~= "string" or body == "" then return nil end
    local ok, obj = pcall(json_parse, body)
    if not ok or type(obj) ~= "table" then return nil end
    local hex = obj._enc_resp_
    if type(hex) ~= "string" then return obj end
    for _, k in ipairs(keys()) do
        local ok2, data = pcall(function()
            return json_parse(url_decode(lo(hex, k)))
        end)
        if ok2 and type(data) == "table" then return data end
    end
    return nil
end

-- GET <baseUrl><path> + decrypt; nil on network or decrypt failure
local function api_get(path)
    local r = http_get(baseUrl .. path)
    if not r or not r.success then return nil end
    return decrypt_body(r.body)
end

local _bookCache = {}

-- Book details are shared by every getBook* call
local function fetch_book(slug)
    if _bookCache[slug] then return _bookCache[slug] end
    local d = api_get("/api/manga/" .. url_encode(slug))
    if d then _bookCache[slug] = d end
    return d
end

-- ── Catalog ────────────────────────────────────────────────────────────────

-- Empty filters are omitted: the API filters on a supplied key as-is.
local function catalog_url(index, search, genre, status, mtype, sort)
    local params = {
        "limit=" .. LIMIT,
        "offset=" .. (index or 0) * LIMIT,
        "sort=" .. url_encode(sort or "latest_chapter"),
    }
    if search and search ~= "" then
        params[#params + 1] = "search=" .. url_encode(search)
    end
    if genre and genre ~= "" then
        params[#params + 1] = "genre=" .. url_encode(genre)
    end
    if status and status ~= "" then
        params[#params + 1] = "status=" .. status
    end
    if mtype and mtype ~= "" then
        params[#params + 1] = "type=" .. mtype
    end
    return baseUrl .. "/api/manga?" .. table.concat(params, "&")
end

local function has_next(r, count, index)
    local h = r.headers and r.headers["x-total-count"]
    if h and h[1] then
        local total = tonumber(h[1])
        if total then return (index or 0) + 1 < total / LIMIT end
    end
    return count >= LIMIT
end

local function catalog_items(data)
    local items = {}
    if type(data) ~= "table" then return items end
    for _, it in ipairs(data) do
        if type(it) == "table" and it.slug then
            local item = {
                title = it.title or "",
                url = baseUrl .. "/manga/" .. it.slug,
                cover = it.cover_url or "",
            }
            if it.rating then item.rating = tostring(it.rating) .. "/10" end
            items[#items + 1] = item
        end
    end
    return items
end

local function fetch_catalog(url, index)
    local r = http_get(url)
    if not r or not r.success then return { items = {}, hasNext = false } end
    local items = catalog_items(decrypt_body(r.body))
    return { items = items, hasNext = has_next(r, #items, index) }
end

function getCatalogList(index)
    index = index or 0
    return fetch_catalog(catalog_url(index), index)
end

function getCatalogSearch(index, query)
    index = index or 0
    if not query or query == "" then return getCatalogList(index) end
    return fetch_catalog(catalog_url(index, query), index)
end

-- ── Filters ────────────────────────────────────────────────────────────────

local _genreOptions = nil

-- 150 genres: fetched lazily, one request per session
local function genre_options()
    if not _genreOptions then
        local opts = {}
        local data = api_get("/api/terms?taxonomy=genre")
        if type(data) == "table" then
            for _, g in ipairs(data) do
                if g.slug and g.name then
                    opts[#opts + 1] = { value = g.slug, label = g.name }
                end
            end
        end
        _genreOptions = opts
    end
    return _genreOptions
end

function getFilterList()
    local list = {
        { type = "select", key = "sort", label = "Sort By", defaultValue = "latest_chapter", options = {
            { value = "latest_chapter", label = "Latest Chapter" },
            { value = "newest", label = "Newest" },
            { value = "oldest", label = "Oldest" },
            { value = "rating", label = "Rating" },
            { value = "title_asc", label = "Title A-Z" },
        }},
        { type = "select", key = "status", label = "Status", defaultValue = "", options = {
            { value = "", label = "Any" },
            { value = "ongoing", label = "Ongoing" },
            { value = "publishing", label = "Publishing" },
            { value = "completed", label = "Completed" },
            { value = "hiatus", label = "Hiatus" },
        }},
        { type = "select", key = "type", label = "Type", defaultValue = "", options = {
            { value = "", label = "Any" },
            { value = "manga", label = "Manga" },
            { value = "manhwa", label = "Manhwa" },
            { value = "doujinshi", label = "Doujinshi" },
        }},
    }
    -- Genre list is dropped when the terms endpoint is unreachable:
    -- a select/checkbox without options would break the filter screen.
    local genres = genre_options()
    if genres and #genres > 0 then
        list[#list + 1] = { type = "checkbox", key = "genre", label = "Genre", options = genres }
    end
    return list
end

function getCatalogFiltered(index, filters)
    index = index or 0
    filters = filters or {}
    local genre = filters["genre_included"] or filters["genre"] or ""
    if type(genre) == "table" then genre = table.concat(genre, ",") end
    local url = catalog_url(
        index,
        filters["query"] or "",
        genre,
        filters["status"] or "",
        filters["type"] or "",
        filters["sort"] or "latest_chapter"
    )
    return fetch_catalog(url, index)
end

-- ── Book details ───────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    return d and d.title or nil
end

function getBookCoverImageUrl(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    return d and d.cover_url or nil
end

function getBookDescription(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    if not d then return nil end
    return d.description or ""
end

function getBookStatus(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    if not d then return nil end
    local s = d.status
    if s == "ongoing" or s == "publishing" then return "Ongoing" end
    if s == "completed" then return "Completed" end
    if s == "hiatus" then return "Hiatus" end
    return nil
end

function getBookRating(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    if not d or type(d.rating) ~= "number" then return nil end
    -- string.format ignores specifiers on this engine
    return tostring(d.rating) .. "/10"
end

function getBookGenres(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    if not d or type(d.manga_genres) ~= "table" then return {} end
    local g = {}
    for _, mg in ipairs(d.manga_genres) do
        if mg.genres and mg.genres.name then g[#g + 1] = mg.genres.name end
    end
    return g
end

function getBookLastUpdate(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return nil end
    local d = fetch_book(slug)
    if not d or type(d.updated_at) ~= "string" then return nil end
    -- site sends ISO-8601 UTC, e.g. "2026-10-08T10:08:16.349Z"
    return d.updated_at:sub(1, 10)
end

-- ── Chapters ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return {} end
    local d = fetch_book(slug)
    if not d or type(d.chapters) ~= "table" then return {} end

    local chapters = {}
    for _, ch in ipairs(d.chapters) do chapters[#chapters + 1] = ch end
    table.sort(chapters, function(a, b)
        local na = tonumber(a.chapter_number) or 0
        local nb = tonumber(b.chapter_number) or 0
        return na < nb
    end)

    local list = {}
    for _, ch in ipairs(chapters) do
        if ch.id then
            local num = ch.chapter_number
            local title = ch.title
            local text
            if title and title ~= "" and num ~= nil then
                text = tostring(num) .. " — " .. title
            elseif title and title ~= "" then
                text = title
            else
                text = "Chapter " .. tostring(num or "?")
            end
            list[#list + 1] = {
                title = text,
                url = baseUrl .. "/api/chapters/" .. ch.id,
                uploaded = ch.created_at and ch.created_at:sub(1, 10) or nil,
            }
        end
    end
    return list
end

function getChapterListHash(bookUrl)
    -- Direct http_get, never fetch_book: the hash must notice new chapters
    local slug = bookUrl:match("/manga/([^/]+)")
    if not slug then return "" end
    local r = http_get(baseUrl .. "/api/manga/" .. url_encode(slug))
    if not r or not r.success then return "" end
    local d = decrypt_body(r.body)
    if type(d) ~= "table" then return "" end
    local count = 0
    if type(d.chapters) == "table" then count = #d.chapters end
    return tostring(d.updated_at or "") .. "#" .. count
end

-- ── Pages ──────────────────────────────────────────────────────────────────

function getPageList(html, url)
    local ok, pages = pcall(function()
        local data = decrypt_body(html)
        if (not data or not data.content_urls) and url then
            local r = http_get(url)
            if r and r.success then data = decrypt_body(r.body) end
        end
        if type(data) == "table" and type(data.content_urls) == "table" then
            return data.content_urls
        end
        return {}
    end)
    if ok and type(pages) == "table" then return pages end
    return {}
end

function getChapterText(html, url)
    local imgs = getPageList(html, url)
    if #imgs == 0 then return "" end
    local parts = {}
    for _, im in ipairs(imgs) do
        parts[#parts + 1] = '<img src="' .. im .. '">'
    end
    return table.concat(parts, "\n")
end
