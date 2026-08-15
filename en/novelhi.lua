-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "novelhi"
name     = "NovelHi"
version  = "1.0.2"
baseUrl  = "https://novelhi.com"
language = "en"
icon     = "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://novelhi.com&size=256"

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = regex_replace(text, "(?im)^\\s*\\[[^\\]\\n]*[Ee]nd[^\\]\\n]*\\]\\s*(\\r?\\n|$)", "")
    text = regex_replace(text, "\\n{3,}", "\n\n")
    text = string_trim(text)
    return text
end

-- NovelHi obfuscates chapter text with ROT13 + a custom font (the raw JSON
-- contains ROT13-encoded English; the font visually decodes it in a browser).
local function rot13Decode(s)
    if not s or s == "" then return "" end
    return (s:gsub("[%a]", function(c)
        local b = c:byte()
        local base = (b < 97) and 65 or 97
        return string.char(base + ((b - base + 13) % 26))
    end))
end

-- Book page cache: the engine calls the detail functions in parallel.
local _pageCache = {}

local function fetchPage(url)
    if not url or url == "" then return nil end
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- Genre id -> slug mapping (from the site's genreIdToSlugMapping).
local GENRES = {
    { id = "1",  slug = "action",        name = "Action"        },
    { id = "3",  slug = "adventure",     name = "Adventure"     },
    { id = "4",  slug = "comedy",        name = "Comedy"        },
    { id = "7",  slug = "light-novel",   name = "Light Novel"   },
    { id = "9",  slug = "fantasy",       name = "Fantasy"       },
    { id = "41", slug = "fanfiction",    name = "Fanfiction"    },
    { id = "10", slug = "game",          name = "Game"          },
    { id = "11", slug = "gender-bender", name = "Gender Bender" },
    { id = "12", slug = "harem",         name = "Harem"         },
    { id = "13", slug = "historical",    name = "Historical"    },
    { id = "14", slug = "horror",        name = "Horror"        },
    { id = "16", slug = "martial-arts",  name = "Martial Arts"  },
    { id = "17", slug = "mature",        name = "Mature"        },
    { id = "18", slug = "mecha",         name = "Mecha"         },
    { id = "19", slug = "military",      name = "Military"      },
    { id = "20", slug = "mystery",       name = "Mystery"       },
    { id = "22", slug = "romance",       name = "Romance"       },
    { id = "23", slug = "school-life",   name = "School Life"   },
    { id = "24", slug = "sci-fi",        name = "Sci-fi"        },
    { id = "30", slug = "slice-of-life", name = "Slice of Life" },
    { id = "32", slug = "sports",        name = "Sports"        },
    { id = "33", slug = "supernatural",  name = "Supernatural"  },
    { id = "34", slug = "tragedy",       name = "Tragedy"       },
    { id = "35", slug = "urban-life",    name = "Urban Life"    },
    { id = "36", slug = "wuxia",         name = "Wuxia"         },
    { id = "37", slug = "xianxia",       name = "Xianxia"       },
    { id = "38", slug = "xuanhuan",      name = "Xuanhuan"      },
    { id = "39", slug = "yaoi",          name = "Yaoi"          },
    { id = "40", slug = "yuri",          name = "Yuri"          },
}

local function genreSlugById(id)
    local idStr = tostring(id or "")
    for _, g in ipairs(GENRES) do
        if g.id == idStr then return g.slug end
    end
    return "other"
end

-- Build the book detail URL the same way the site's JS does.
local function buildBookUrl(b)
    local slug = tostring(b.novelSlug or "")
    if slug ~= "" then
        return baseUrl .. "/novel/" .. genreSlugById(b.primaryGenreId) .. "/" .. slug
    end
    local id = tostring(b.id or "")
    if id ~= "" then return baseUrl .. "/book/" .. id .. ".html" end
    return ""
end

-- Shared parser for the catalog/search JSON API.
local function fetchCatalog(apiUrl)
    local r = http_get(apiUrl, {
        headers = { ["X-Requested-With"] = "XMLHttpRequest" }
    })
    if not r.success then return { items = {}, hasNext = false } end

    local data = json_parse(r.body)
    if not data or not data.data or type(data.data.list) ~= "table" then
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, b in ipairs(data.data.list) do
        local title = string_clean(tostring(b.bookName or ""))
        local url   = buildBookUrl(b)
        if title ~= "" and url ~= "" then
            table.insert(items, {
                title  = title,
                url    = url,
                cover  = absUrl(tostring(b.picUrl or "")),
                rating = tostring(b.rate or ""),
            })
        end
    end

    local page       = tonumber(data.data.pageNum)   or 1
    local total      = tonumber(data.data.total)     or 0
    local pageSize   = tonumber(data.data.pageSize)  or 20
    local totalPages = math.ceil(total / math.max(pageSize, 1))
    return { items = items, hasNext = page < totalPages and #items > 0 }
end

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = (index or 0) + 1
    local url  = baseUrl .. "/book/searchBookListWithShelfState?curr=" .. page .. "&limit=20"
    return fetchCatalog(url)
end

-- ── Search ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = (index or 0) + 1
    local url  = baseUrl .. "/book/searchBookListWithShelfState?curr=" .. page ..
                 "&limit=20&keyword=" .. url_encode(query or "")
    return fetchCatalog(url)
end

-- ── Filters (status + genre, matching the site's own filter UI) ──────────────

function getFilterList()
    local genreOptions = {}
    for _, g in ipairs(GENRES) do
        table.insert(genreOptions, { value = tostring(g.id), label = g.name })
    end
    return {
        {
            key          = "status",
            label        = "Status",
            type         = "select",
            defaultValue = "",
            options = {
                { value = "", label = "All"       },
                { value = "0", label = "Ongoing"  },
                { value = "1", label = "Completed" },
            },
        },
        {
            key          = "genre",
            label        = "Genre",
            type         = "select",
            defaultValue = "",
            options = genreOptions,
        },
    }
end

function getCatalogFiltered(index, filters)
    local page   = (index or 0) + 1
    local status = tostring(filters and filters["status"] or "")
    local genre  = tostring(filters and filters["genre"] or "")

    local params = { "curr=" .. page, "limit=20" }
    if status ~= "" then table.insert(params, "bookStatus=" .. status) end
    -- The genre param is bookGenres[]=id; Tomcat rejects raw [] so the
    -- brackets themselves must be percent-encoded (%5B%5D).
    if genre  ~= "" then table.insert(params, "bookGenres%5B%5D=" .. url_encode(genre)) end

    return fetchCatalog(baseUrl .. "/book/searchBookListWithShelfState?" .. table.concat(params, "&"))
end

-- ── Book details ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1")
    if el then return string_clean(el.text) end
    local name = html_attr(body, "#bookNamedHidden", "value")
    return (name ~= "") and string_clean(name) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img.cover", "src")
    if cover == "" then cover = html_attr(body, "img.decorate-img", "src") end
    return (cover ~= "") and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "p.detail-desc")
    if not el then el = html_select_first(body, "p.mobile-detail-desc") end
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local bookId = html_attr(body, "#bookId", "value")
    if bookId == "" then return {} end

    local r = http_get(baseUrl .. "/book/queryBookGenre?bookId=" .. url_encode(bookId), {
        headers = { ["X-Requested-With"] = "XMLHttpRequest" }
    })
    if not r.success then return {} end

    local data = json_parse(r.body)
    if not data or type(data.data) ~= "table" then return {} end

    local genres = {}
    for _, g in ipairs(data.data) do
        local name = string_clean(tostring(g.genreName or ""))
        if name ~= "" then table.insert(genres, name) end
    end
    return genres
end

-- ── Chapter list ──────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    if not bookUrl or bookUrl == "" then return {} end
    local tocUrl = bookUrl:gsub("/+$", "") .. "/chapters"
    local r = http_get(tocUrl)
    if not r.success then return {} end

    -- PC template: div.dirList ul li a[href] > span
    -- Mobile template: a.mobile-chapter-item[href] > span.mobile-chapter-item__name
    local chapters = {}
    for _, a in ipairs(html_select(r.body, "div.dirList ul li a[href], a.mobile-chapter-item[href]")) do
        -- Drop the layui icon glyph (<i>) so it doesn't leak into the title
        local inner = html_remove(a.html, "i")
        local spanEl = html_select_first(inner, "span")
        local title = spanEl and spanEl.text or a.text
        title = string_clean(title)
        if title ~= "" and a.href and a.href ~= "" then
            table.insert(chapters, {
                title = title,
                url   = absUrl(a.href),
            })
        end
    end
    return chapters
end

-- Hash = id of the last chapter. Must use a direct http_get (not fetchPage)
-- so that new chapters are always detected.
function getChapterListHash(bookUrl)
    if not bookUrl or bookUrl == "" then return nil end
    local r = http_get(bookUrl)
    if not r.success then return nil end

    local lastId = html_attr(r.body, "#lastBookIndexId", "value")
    if lastId ~= "" then return lastId end

    -- Mobile template has no #lastBookIndexId — fall back to the recent-index API.
    local bookId = html_attr(r.body, "#bookId", "value")
    if bookId == "" then return nil end
    local ar = http_get(baseUrl .. "/book/queryUserRecentIndexList?bookId=" .. url_encode(bookId), {
        headers = { ["X-Requested-With"] = "XMLHttpRequest" }
    })
    if not ar.success then return nil end
    local data = json_parse(ar.body)
    if not data or type(data.data) ~= "table" or #data.data == 0 then return nil end
    return tostring(data.data[1].id or "") .. "|" .. tostring(data.data[1].indexNum or "")
end

-- ── Chapter text ──────────────────────────────────────────────────────────────

-- The chapter page loads its text via AJAX: GET {chapterContentPath}?token=...
-- (X-Requested-With: XMLHttpRequest), returning JSON with data.content.
-- The content is ROT13-obfuscated and contains inline ad blocks.
function getChapterText(html, url)
    if not html or html == "" then return "" end
    local path  = html_attr(html, "#chapterContentPath", "value")
    local token = html_attr(html, "#chapterContentToken", "value")
    if path == "" or token == "" then return "" end

    local r = http_get(absUrl(path) .. "?token=" .. url_encode(token), {
        headers = {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Referer"]          = url or baseUrl,
        }
    })
    if not r.success then return "" end

    local data = json_parse(r.body)
    if not data or not data.data or not data.data.content then return "" end

    -- Work on the RAW (still obfuscated) content first: tag names are
    -- ROT13'd too (<script> -> <fpevcg>), so strip ad/script blocks and
    -- entities BEFORE decoding, or the patterns won't match.
    local content = tostring(data.data.content)
    content = regex_replace(content, "(?s)<script.*?</script>", "")
    content = regex_replace(content, "(?s)<ins.*?</ins>", "")
    content = regex_replace(content, "(?s)<style.*?</style>", "")
    content = regex_replace(content, "(?i)<br\\s*/?>", "\n")
    content = regex_replace(content, "&nbsp;", " ")
    content = regex_replace(content, "&amp;", "&")
    content = regex_replace(content, "&lt;", "<")
    content = regex_replace(content, "&gt;", ">")
    content = regex_replace(content, "&#39;", "'")
    content = regex_replace(content, "&quot;", "\"")

    content = rot13Decode(content)
    -- Any remaining tags (decoded names like <frag>, <oe>) are junk
    content = regex_replace(content, "<[^>]*>", "")

    return applyStandardContentTransforms(content)
end
