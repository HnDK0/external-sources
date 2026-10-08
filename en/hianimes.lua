-- Hianime — video plugin for NoveLA (content_type = "video")
-- Data source: https://animehot.cc/api (plain JSON, no Cloudflare).
-- hianimes.se itself serves empty Next.js shells, so none of its HTML is parsed.

id           = "hianimes"
name         = "Hianime"
version      = "1.0.0"
baseUrl      = "https://hianimes.se"
language     = "en"
content_type = "video"
icon         = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/hianimes.png"

local API = "https://animehot.cc/api"
-- Player config key: window.__P = base64(xor(json)) with this key.
local OBF_KEY = "otaku-embed-v1"

-- Absolute URL helper; relative paths resolve against baseUrl.
local function absUrl(href)
    if type(href) ~= "string" or href == "" then return "" end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if href:find("^https?://") then return href end
    if href:sub(1, 1) == "/" then return baseUrl .. href end
    return baseUrl .. "/" .. href
end

-- Cache of /api/anime/{slug}: title, cover, description, genres, status,
-- rating and chapter list all come from this single request.
local _animeCache = {}

local function fetchAnime(bookUrl)
    local slug = bookUrl:match("/watch/(.+)$")
    if type(slug) ~= "string" or slug == "" then return nil end
    local cached = _animeCache[slug]
    if cached ~= nil then return cached end
    local r = http_get(API .. "/anime/" .. slug)
    if not r.success then
        log_error("Hianime: anime request failed (HTTP " .. tostring(r.code) .. ")")
        return nil
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" or type(data.anime) ~= "table" then
        log_error("Hianime: unexpected anime response for " .. slug)
        return nil
    end
    _animeCache[slug] = data.anime
    return data.anime
end

-- Catalog and search items share the same shape.
local function itemToBook(item)
    if type(item) ~= "table" then return nil end
    if type(item.title) ~= "string" or item.title == "" then return nil end
    -- Catalog carries `slug`, search carries only `slugs[]`.
    local slug = item.slug
    if type(slug) ~= "string" or slug == "" then
        slug = nil
        if type(item.slugs) == "table" then
            for _, s in ipairs(item.slugs) do
                if type(s) == "string" and s ~= "" then
                    slug = s
                    break
                end
            end
        end
    end
    if not slug then return nil end
    local book = {
        title = string_clean(item.title),
        url   = baseUrl .. "/watch/" .. slug,
        cover = absUrl(item.image),
    }
    -- Score is a string like "7.37", or "" / null when unknown.
    local score = tonumber(item.Score)
    if score then book.rating = "Rating: " .. tostring(score) .. "/10" end
    return book
end

local function itemsToResult(arr)
    local items = {}
    if type(arr) == "table" then
        for _, item in ipairs(arr) do
            local book = itemToBook(item)
            if book then table.insert(items, book) end
        end
    end
    return { items = items, hasNext = false }
end

function getCatalogList(index)
    local r = http_get(API .. "/latest/anime?page=" .. (index + 1) .. "&limit=20")
    if not r.success then
        log_error("Hianime: catalog request failed (HTTP " .. tostring(r.code) .. ")")
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" then
        log_error("Hianime: json_parse failed for getCatalogList")
        return { items = {}, hasNext = false }
    end
    local items = {}
    if type(data.animes) == "table" then
        for _, item in ipairs(data.animes) do
            local book = itemToBook(item)
            if book then table.insert(items, book) end
        end
    end
    local page = tonumber(data.page) or 0
    local totalPages = tonumber(data.totalPages) or 0
    return { items = items, hasNext = page < totalPages }
end

function getCatalogSearch(index, query)
    -- The API has no search pagination: only page 0 exists.
    if index > 0 then return { items = {}, hasNext = false } end
    if type(query) ~= "string" or query == "" then
        return { items = {}, hasNext = false }
    end
    local r = http_post(API .. "/search", json_stringify({ title = query }))
    if not r.success then
        log_error("Hianime: search request failed (HTTP " .. tostring(r.code) .. ")")
        return { items = {}, hasNext = false }
    end
    -- Response is a bare JSON array.
    local data = json_parse(r.body)
    if type(data) ~= "table" then
        log_error("Hianime: json_parse failed for getCatalogSearch")
        return { items = {}, hasNext = false }
    end
    return itemsToResult(data)
end

function getBookTitle(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a or type(a.title) ~= "string" or a.title == "" then return nil end
    return string_clean(a.title)
end

function getBookCoverImageUrl(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a then return nil end
    local cover = absUrl(a.image)
    return cover ~= "" and cover or nil
end

function getBookDescription(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a or type(a.synopsis) ~= "string" then return nil end
    local text = string_trim(a.synopsis)
    return text ~= "" and text or nil
end

function getBookGenres(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a or type(a.genres) ~= "table" then return {} end
    local genres = {}
    for _, g in ipairs(a.genres) do
        if type(g) == "string" and g ~= "" then table.insert(genres, g) end
    end
    return genres
end

function getBookStatus(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a or type(a.Status) ~= "string" or a.Status == "" then return nil end
    return a.Status
end

function getBookRating(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a then return nil end
    local score = tonumber(a.Score)
    if not score then return nil end
    return "Rating: " .. tostring(score) .. "/10"
end

-- Episodes are chapters, ordered oldest first; seasons are always empty here.
-- The site fetches this list in windows of 100.
local EPISODE_BLOCK = 100

function getChapterList(bookUrl)
    local a = fetchAnime(bookUrl)
    if not a then return {} end

    local raw = {}
    local function take(list)
        if type(list) ~= "table" then return end
        for _, ep in ipairs(list) do
            if type(ep) == "table" then raw[#raw + 1] = ep end
        end
    end

    -- /api/anime/{slug} serves episodes[] truncated to a single item, so the
    -- real list comes from /api/episodes/{anime._id} (the endpoint the site's
    -- own watch page uses). The key is the Mongo id, not the slug.
    local id = a._id
    if type(id) == "string" and id ~= "" then
        local total = tonumber(a.totalEpisodes) or 0
        if total <= 0 then
            -- No total on the detail: the unbounded reply carries it, and it
            -- doubles as window one (it is itself capped at 100 episodes).
            local r = http_get(API .. "/episodes/" .. id)
            if r.success then
                local d = json_parse(r.body)
                if type(d) == "table" then
                    take(d.episodes)
                    total = tonumber(d.total) or #raw
                end
            else
                log_error("Hianime: episodes request failed (HTTP " .. tostring(r.code) .. ")")
            end
        end

        local urls = {}
        for from = #raw + 1, total, EPISODE_BLOCK do
            urls[#urls + 1] = API .. "/episodes/" .. id ..
                "?start=" .. from ..
                "&end=" .. tostring(math.min(from + EPISODE_BLOCK - 1, total))
        end
        if #urls > 0 then
            for i, r in ipairs(http_get_batch(urls)) do
                if r.success then
                    local d = json_parse(r.body)
                    if type(d) == "table" then
                        take(d.episodes)
                    else
                        log_error("Hianime: bad episodes response for " .. urls[i])
                    end
                else
                    log_error("Hianime: episodes request failed (HTTP " .. tostring(r.code) .. ")")
                end
            end
        end
        if #raw == 0 then
            log_error("Hianime: no episodes for " .. tostring(a.title or bookUrl))
            return {}
        end
    else
        -- Detail without a Mongo id: the truncated list is all we have.
        take(a.episodes)
    end

    table.sort(raw, function(x, y)
        return (tonumber(x.episodeNumber) or 0) < (tonumber(y.episodeNumber) or 0)
    end)
    local chapters, seen = {}, {}
    for _, ep in ipairs(raw) do
        local slug = ep.slug
        if type(slug) == "string" and slug ~= "" and not seen[slug] then
            seen[slug] = true
            local title = ep.title
            if type(title) ~= "string" or title == "" then
                title = "Episode " .. tostring(tonumber(ep.episodeNumber) or (#chapters + 1))
            end
            chapters[#chapters + 1] = {
                title = string_clean(title),
                url   = baseUrl .. "/watch/" .. slug,
            }
        end
    end
    return chapters
end

------------------------------------------------------------------------------
-- Stream resolution
------------------------------------------------------------------------------

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64_CHARS do
    B64_INDEX[B64_CHARS:sub(i, i)] = i - 1
end

-- Base64 → bytes. Arithmetic only: works on Lua 5.1/LuaJ without bit operators.
local function base64Decode(data)
    data = data:gsub("%s", ""):gsub("%-", "+"):gsub("%_", "/")
    local out = {}
    for i = 1, #data, 4 do
        local c1 = data:sub(i, i)
        local c2 = data:sub(i + 1, i + 1)
        local c3 = data:sub(i + 2, i + 2)
        local c4 = data:sub(i + 3, i + 3)
        local v1 = B64_INDEX[c1] or 0
        local v2 = B64_INDEX[c2] or 0
        local v3 = B64_INDEX[c3]
        local v4 = B64_INDEX[c4]
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if v3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if v4 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

-- Byte-wise XOR with OBF_KEY (the JS deobfuscate() roundtrip over UTF-8 bytes;
-- Lua strings are byte arrays, so no transcoding is needed).
local function xorDecode(data)
    local out = {}
    for i = 1, #data do
        local a = data:byte(i)
        local b = OBF_KEY:byte((i - 1) % #OBF_KEY + 1)
        local r, p = 0, 1
        for _ = 1, 8 do
            if a % 2 ~= b % 2 then r = r + p end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            p = p * 2
        end
        out[i] = string.char(r)
    end
    return table.concat(out)
end

-- Origin of the provider page — the HLS server checks exactly this Referer
-- (the m3u8 itself lives on another host).
local function pageOrigin(url)
    local scheme, host = url:match("^(https?)://([^/?#]+)")
    if not scheme or not host then return nil end
    return scheme .. "://" .. host .. "/"
end

-- Provider page → master m3u8 URL + subtitle list (nil when absent).
local function resolveStream(html)
    -- Pattern A: a direct HLS URL embedded in the page.
    local direct = html:match('(https?://[^"\'%s]+%.m3u8[^"\'%s]*)')
    if direct then return direct, nil end

    -- Pattern B: obfuscated player config.
    local blob = html:match('window%.__P%s*=%s*"([^"]+)"')
        or html:match("window%.__P%s*=%s*'([^']+)'")
    if not blob then return nil, nil end
    local cfg = json_parse(xorDecode(base64Decode(blob)))
    if type(cfg) ~= "table" or type(cfg.src) ~= "string" or cfg.src == "" then
        return nil, nil
    end

    local subtitles = nil
    if type(cfg.subtitles) == "table" then
        subtitles = {}
        for _, s in ipairs(cfg.subtitles) do
            if type(s) == "table" and type(s.src) == "string" and s.src ~= "" then
                local track = { url = s.src }
                if type(s.label) == "string" and s.label ~= "" then track.label = s.label end
                if type(s.lang) == "string" and s.lang ~= "" then track.lang = s.lang end
                table.insert(subtitles, track)
            end
        end
        if #subtitles == 0 then subtitles = nil end
    end
    return cfg.src, subtitles
end

-- Episode → playable variants (sub providers first, then dub).
function getVideoList(episodeUrl)
    local slug = episodeUrl:match("/watch/(.+)$")
    if type(slug) ~= "string" or slug == "" then
        log_error("Hianime: cannot parse episode URL " .. tostring(episodeUrl))
        return {}
    end
    local r = http_get(API .. "/episode/" .. slug)
    if not r.success then
        log_error("Hianime: episode request failed (HTTP " .. tostring(r.code) .. ")")
        return {}
    end
    local data = json_parse(r.body)
    local episode = type(data) == "table" and data.episode or nil
    if type(episode) ~= "table" or type(episode.link) ~= "table" then
        log_error("Hianime: unexpected episode response for " .. slug)
        return {}
    end

    -- Provider page URLs, deduplicated, sub before dub. The track name is
    -- kept per URL so each variant can be labelled SUB/DUB in the UI.
    local providers, seen, trackOf = {}, {}, {}
    for _, key in ipairs({ "sub", "dub" }) do
        local list = episode.link[key]
        if type(list) == "table" then
            for _, u in ipairs(list) do
                if type(u) == "string" and u ~= "" and not seen[u] then
                    seen[u] = true
                    trackOf[u] = key == "sub" and "SUB" or "DUB"
                    table.insert(providers, u)
                end
            end
        end
    end

    local pages = http_get_batch(providers)
    if type(pages) ~= "table" then pages = {} end

    local sources = {}
    for i, pageUrl in ipairs(providers) do
        local res = pages[i]
        if type(res) == "table" and res.success and type(res.body) == "string" then
            local stream, subtitles = resolveStream(res.body)
            if stream then
                local source = { url = stream, mime = "hls" }
                -- Label the variant with its track so the picker shows
                -- SUB/DUB instead of an anonymous option.
                local host = pageUrl:match("^https?://([^/?#]+)") or ""
                source.quality = trackOf[pageUrl] .. " · " .. host
                local referer = pageOrigin(pageUrl)
                if referer then source.headers = { ["Referer"] = referer } end
                if subtitles then source.subtitles = subtitles end
                table.insert(sources, source)
            else
                log_error("Hianime: no playable source on " .. pageUrl)
            end
        else
            log_error("Hianime: provider page failed " .. pageUrl)
        end
    end
    return sources
end

-- Option values mirror the site's own filter config: "All"/"Default" are its
-- no-filter defaults, so they are never sent to the API.
local FILTER_TYPE = {
    { value = "All", label = "All" },
    { value = "TV", label = "TV" },
    { value = "Movie", label = "Movie" },
    { value = "OVA", label = "OVA" },
    { value = "Special", label = "Special" },
    { value = "ONA", label = "ONA" },
    { value = "Music", label = "Music" },
}

local FILTER_STATUS = {
    { value = "All", label = "All" },
    { value = "Airing", label = "Airing" },
    { value = "Completed", label = "Completed" },
    { value = "Upcoming", label = "Upcoming" },
}

local FILTER_GENRE = {
    { value = "Action", label = "Action" },
    { value = "Adventure", label = "Adventure" },
    { value = "Cars", label = "Cars" },
    { value = "Comedy", label = "Comedy" },
    { value = "Dementia", label = "Dementia" },
    { value = "Demons", label = "Demons" },
    { value = "Drama", label = "Drama" },
    { value = "Ecchi", label = "Ecchi" },
    { value = "Fantasy", label = "Fantasy" },
    { value = "Game", label = "Game" },
    { value = "Harem", label = "Harem" },
    { value = "Historical", label = "Historical" },
    { value = "Horror", label = "Horror" },
    { value = "Isekai", label = "Isekai" },
    { value = "Josei", label = "Josei" },
    { value = "Kids", label = "Kids" },
    { value = "Magic", label = "Magic" },
    { value = "Martial Arts", label = "Martial Arts" },
    { value = "Mecha", label = "Mecha" },
    { value = "Military", label = "Military" },
    { value = "Music", label = "Music" },
    { value = "Mystery", label = "Mystery" },
    { value = "Parody", label = "Parody" },
    { value = "Police", label = "Police" },
    { value = "Psychological", label = "Psychological" },
    { value = "Romance", label = "Romance" },
    { value = "Samurai", label = "Samurai" },
    { value = "School", label = "School" },
    { value = "Sci-Fi", label = "Sci-Fi" },
    { value = "Seinen", label = "Seinen" },
    { value = "Shoujo", label = "Shoujo" },
    { value = "Shoujo Ai", label = "Shoujo Ai" },
    { value = "Shounen", label = "Shounen" },
    { value = "Shounen Ai", label = "Shounen Ai" },
    { value = "Slice of Life", label = "Slice of Life" },
    { value = "Space", label = "Space" },
    { value = "Sports", label = "Sports" },
    { value = "Super Power", label = "Super Power" },
    { value = "Supernatural", label = "Supernatural" },
    { value = "Thriller", label = "Thriller" },
    { value = "Vampire", label = "Vampire" },
}

local FILTER_RATED = {
    { value = "All", label = "All" },
    { value = "G - All Ages", label = "G - All Ages" },
    { value = "PG - Children", label = "PG - Children" },
    { value = "PG-13 - Teens 13 or older", label = "PG-13 - Teens 13 or older" },
    { value = "R - 17+ (violence & profanity)", label = "R - 17+ (violence & profanity)" },
    { value = "R+ - Mild Nudity", label = "R+ - Mild Nudity" },
    { value = "Rx - Hentai", label = "Rx - Hentai" },
}

local FILTER_SCORE = {
    { value = "All", label = "All" },
    { value = "1", label = "1" },
    { value = "2", label = "2" },
    { value = "3", label = "3" },
    { value = "4", label = "4" },
    { value = "5", label = "5" },
    { value = "6", label = "6" },
    { value = "7", label = "7" },
    { value = "8", label = "8" },
    { value = "9", label = "9" },
    { value = "10", label = "10" },
}

local FILTER_LANGUAGE = {
    { value = "All", label = "All" },
    { value = "English", label = "English" },
    { value = "Japanese", label = "Japanese" },
}

local FILTER_SORT = {
    { value = "Default", label = "Default" },
    { value = "Popularity", label = "Popularity" },
    { value = "Score", label = "Score" },
    { value = "Alphabetical", label = "Alphabetical" },
}

-- Select filters are sent under these keys; anything else is ignored.
local FILTER_SELECT_KEYS = { "type", "status", "rated", "score", "language", "sort" }

function getFilterList()
    return {
        { type = "select", key = "type", label = "Type", defaultValue = "All", options = FILTER_TYPE },
        { type = "select", key = "status", label = "Status", defaultValue = "All", options = FILTER_STATUS },
        { type = "checkbox", key = "genre", label = "Genres", options = FILTER_GENRE },
        { type = "select", key = "rated", label = "Content Rating", defaultValue = "All", options = FILTER_RATED },
        { type = "select", key = "score", label = "Score", defaultValue = "All", options = FILTER_SCORE },
        { type = "select", key = "language", label = "Language", defaultValue = "All", options = FILTER_LANGUAGE },
        { type = "select", key = "sort", label = "Sort", defaultValue = "Default", options = FILTER_SORT },
    }
end

function getCatalogFiltered(index, filters)
    if type(filters) ~= "table" then filters = {} end
    local body = { page = index + 1, limit = 20 }
    for _, key in ipairs(FILTER_SELECT_KEYS) do
        local value = filters[key]
        if type(value) == "string" and value ~= "" and value ~= "All" and value ~= "Default" then
            body[key] = value
        end
    end
    -- Checkbox values arrive as genre_included, but the API wants a JSON
    -- array under the singular key and matches all of them.
    local genres = filters["genre_included"]
    if type(genres) == "table" and #genres > 0 then
        body["genre"] = genres
    end

    local r = http_post(API .. "/filter", json_stringify(body))
    if not r.success then
        log_error("Hianime: filter request failed (HTTP " .. tostring(r.code) .. ")")
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if type(data) ~= "table" or type(data.results) ~= "table" then
        log_error("Hianime: json_parse failed for getCatalogFiltered")
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, item in ipairs(data.results) do
        local book = itemToBook(item)
        if book then table.insert(items, book) end
    end
    local page = tonumber(data.page) or 0
    local totalPages = tonumber(data.totalPages) or 0
    return { items = items, hasNext = page < totalPages }
end
