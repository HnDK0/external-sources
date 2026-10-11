-- =====================================================================
-- Lib: novelfire family — shared engine for the novelfire.net /
--      novelphoenix.com clones (en/novelfire, en/novelphoenix). The two
--      copies shared 13 of their 17 functions; the site-specific parts
--      (book path, status and "last update" selectors) are config.
-- Loaded via require_lib("novelfire"); uses require_lib("urls") and
-- require_lib("meta").
--
-- config (first argument of every M.* function):
--   baseUrl            string  site origin, no trailing slash (required)
--   name               string  label for log lines (default "novelfire")
--   chapterPath        string  book path segment used to build chapter
--                              URLs, "/book" (novelfire) / "/novel"
--                              (novelphoenix)
--   statusSelector     string  strong elements scanned for the status
--                              word (default ".header-stats strong")
--   lastUpdateSelector string  elements scanned for "Updated N units ago"
--                              (default ".chapter-latest-container .update")
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")
local meta = require_lib("meta")

local M = {}

local function origin(config)
    return config.baseUrl
end

local function absUrl(config, href)
    return urls.absUrl(origin(config), href)
end

local function chapterPath(config)
    return config.chapterPath or "/book"
end

local function statusSelector(config)
    return config.statusSelector or ".header-stats strong"
end

local function lastUpdateSelector(config)
    return config.lastUpdateSelector or ".chapter-latest-container .update"
end

-- ── Helpers ─────────────────────────────────────────────────────────

-- The engine calls the detail functions in parallel, the cache drops the
-- duplicate http_get calls for one and the same bookUrl.
local _pageCache = {}

local function fetchBookPage(config, url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

local function applyStandardContentTransforms(config, text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = origin(config):gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

-- ── Catalog ─────────────────────────────────────────────────────────

-- Catalog card: .novel-title (title + link), lazy cover, rating from
-- <span class="info-rating" data-rating="4.6">.
local function parseCatalogCards(config, body)
    local items = {}
    for _, card in ipairs(html_select(body, ".novel-list > .novel-item")) do
        local titleEl = html_select_first(card.html, ".novel-title")
        local linkEl  = html_select_first(card.html, ".novel-title a")
        local cover   = html_attr(card.html, "img", "data-src")
        if cover == "" then cover = html_attr(card.html, "img", "src") end
        local rating  = html_attr(card.html, ".info-rating", "data-rating")

        if titleEl and linkEl then
            table.insert(items, {
                title  = string_clean(titleEl.text),
                url    = absUrl(config, linkEl.href),
                cover  = absUrl(config, cover),
                rating = rating,
            })
        end
    end
    return items
end

function M.getCatalogList(config, index)
    local page = index + 1
    local url = origin(config) .. "/search-adv?ctgcon=and&totalchapter=0&ratcon=min"
        .. "&rating=0&status=-1&sort=rank-top&page=" .. page

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogCards(config, r.body)
    return { items = items, hasNext = #items > 0 }
end

-- ── Search ──────────────────────────────────────────────────────────

-- Search goes to /search?keyword= — the cards of that list
-- (.novel-list.chapters) carry no rating (only Rank and Chapters), so
-- the rating key is not filled in here.
function M.getCatalogSearch(config, index, query)
    local page = index + 1
    local url = origin(config) .. "/search?keyword=" .. url_encode(query) .. "&page=" .. page

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-list.chapters .novel-item")) do
        local titleEl = html_select_first(card.html, ".novel-title")
        local linkEl  = html_select_first(card.html, "a")
        local cover   = html_attr(card.html, "img", "src")

        if titleEl and linkEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(config, linkEl.href),
                cover = absUrl(config, cover),
            })
        end
    end
    return { items = items, hasNext = #items > 0 }
end

-- ── Book details ────────────────────────────────────────────────────

function M.getBookTitle(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.novel-title")
    return el and string_clean(el.text) or nil
end

function M.getBookCoverImageUrl(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, "img[src*='server-1']", "src")
    if cover == "" then cover = html_attr(r.body, ".cover img", "src") end
    return cover ~= "" and absUrl(config, cover) or nil
end

function M.getBookDescription(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cleaned = html_remove(r.body, "h4.lined")
    local el = html_select_first(cleaned, ".summary .content, .summary")
    return el and string_trim(el.text) or nil
end

-- ── Chapter list (AJAX) ─────────────────────────────────────────────

function M.getChapterList(config, bookUrl)
    -- Step 1: get post_id from the novel page
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local postId = html_attr(r.body, "#novel-report", "report-post_id")
    if not postId or postId == "" then return {} end

    -- Step 2: one AJAX request — all chapters at once
    local ajaxUrl = origin(config) .. "/ajax/listChapterDataAjax"
    local params = "draw=1"
        .. "&columns%5B0%5D%5Bdata%5D=n_sort"
        .. "&columns%5B0%5D%5Bname%5D=cmm_posts_detail.n_sort"
        .. "&columns%5B0%5D%5Bsearchable%5D=true"
        .. "&columns%5B0%5D%5Borderable%5D=true"
        .. "&columns%5B0%5D%5Bsearch%5D%5Bvalue%5D="
        .. "&columns%5B0%5D%5Bsearch%5D%5Bregex%5D=false"
        .. "&columns%5B1%5D%5Bdata%5D=bookmark_created_at"
        .. "&columns%5B1%5D%5Bname%5D=bookmark_chapters.created_at"
        .. "&columns%5B1%5D%5Bsearchable%5D=false"
        .. "&columns%5B1%5D%5Borderable%5D=true"
        .. "&columns%5B1%5D%5Bsearch%5D%5Bvalue%5D="
        .. "&columns%5B1%5D%5Bsearch%5D%5Bregex%5D=false"
        .. "&order%5B0%5D%5Bcolumn%5D=0"
        .. "&order%5B0%5D%5Bdir%5D=asc"
        .. "&order%5B0%5D%5Bname%5D=cmm_posts_detail.n_sort"
        .. "&start=0"
        .. "&length=-1"
        .. "&search%5Bvalue%5D="
        .. "&search%5Bregex%5D=false"
        .. "&post_id=" .. postId
        .. "&only_bookmark=false"

    local bookSlug = bookUrl:match("/([^/]+)$")
    local ar = http_get(ajaxUrl .. "?" .. params)
    if not ar.success then return {} end

    -- Step 3: parse JSON
    local json = json_parse(ar.body)
    if not json or not json.data then return {} end

    local chapters = {}
    for _, item in ipairs(json.data) do
        local nSort = item.n_sort
        if nSort then
            local title = item.title or ("Chapter " .. tostring(nSort))
            local cleanTitle = string_clean(regex_replace(title, "<[^>]+>", ""))
            local chUrl = origin(config) .. chapterPath(config) .. "/"
                .. bookSlug .. "/chapter-" .. tostring(nSort)
            table.insert(chapters, { title = cleanTitle, url = chUrl })
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber(a.url:match("chapter%-(%d+)$")) or 0
        local nb = tonumber(b.url:match("chapter%-(%d+)$")) or 0
        return na < nb
    end)

    return chapters
end

function M.getChapterListHash(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".body p.latest")
    return el and string_clean(el.text) or nil
end

-- ── Chapter text ────────────────────────────────────────────────────

function M.getChapterText(config, html, url)
    local cleaned = html_remove(html, "script", "nav", ".ads", ".advertisement",
                                ".disqus", ".comments", ".c-message", ".nav-next", ".nav-previous")
    local el = html_select_first(cleaned, "#content, .chapter-content, div.entry-content")
    if not el then return "" end

    -- html_text keeps the line breaks
    return applyStandardContentTransforms(config, html_text(el.html))
end

-- ── Genres on the book page ─────────────────────────────────────────

function M.getBookGenres(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local genres = {}
    for _, a in ipairs(html_select(r.body, ".categories .property-item")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Rating ──────────────────────────────────────────────────────────

-- Book rating from the book page: <strong class="nub">4.6</strong>
function M.getBookRating(config, bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".rating .nub")
    return el and string_clean(el.text) or nil
end

-- ── Status / last update ────────────────────────────────────────────

-- Status: <strong class="completed">Completed</strong> inside the block
-- picked by statusSelector; the class of <strong> repeats the text
-- (ongoing / completed), the set below drops the rest of the stats.
local STATUS_VALUES = {
    ongoing = true, completed = true, hiatus = true, dropped = true,
}

function M.getBookStatus(config, bookUrl)
    local html = fetchBookPage(config, bookUrl)
    if not html then return nil end
    for _, el in ipairs(html_select(html, statusSelector(config))) do
        local v = string_clean(string_lower(el.text))
        if STATUS_VALUES[v] then return string_clean(el.text) end
    end
    return nil
end

-- Last update: <p class="update">Updated N unit(s) ago</p>. The page may
-- hold several .update nodes (novelphoenix has one in the review block
-- too) — walk them all and keep the first one that parses as the site's
-- relative date; the others are dropped by meta.normalizeDate.
function M.getBookLastUpdate(config, bookUrl)
    local html = fetchBookPage(config, bookUrl)
    if not html then return nil end
    for _, el in ipairs(html_select(html, lastUpdateSelector(config))) do
        local d = meta.normalizeDate(string_clean(el.text))
        if d then return d end
    end
    return nil
end

-- ── Filter list ─────────────────────────────────────────────────────

function M.getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort Results By",
            defaultValue = "rank-top",
            options = {
                { value = "rank-top",           label = "Rank (Top)"          },
                { value = "rating-score-top",   label = "Rating Score (Top)"  },
                { value = "review",             label = "Review Count (Most)" },
                { value = "comment",            label = "Comment Count (Most)"},
                { value = "bookmark",           label = "Bookmark Count (Most)"},
                { value = "today-view",         label = "Today Views (Most)"  },
                { value = "monthly-view",       label = "Monthly Views (Most)"},
                { value = "total-view",         label = "Total Views (Most)"  },
                { value = "abc",                label = "Title (A>Z)"         },
                { value = "cba",                label = "Title (Z>A)"         },
                { value = "date",               label = "Last Updated (Newest)"},
                { value = "chapter-count-most", label = "Chapter Count (Most)"},
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "Translation Status",
            defaultValue = "-1",
            options = {
                { value = "-1", label = "All"       },
                { value = "1",  label = "Completed" },
                { value = "0",  label = "Ongoing"   },
            }
        },
        {
            type         = "select",
            key          = "genre_operator",
            label        = "Genres (And/Or/Exclude)",
            defaultValue = "and",
            options = {
                { value = "and",     label = "AND"     },
                { value = "or",      label = "OR"      },
                { value = "exclude", label = "EXCLUDE" },
            }
        },
        {
            type         = "select",
            key          = "rating_operator",
            label        = "Rating (Min/Max)",
            defaultValue = "min",
            options = {
                { value = "min", label = "Min" },
                { value = "max", label = "Max" },
            }
        },
        {
            type         = "select",
            key          = "rating",
            label        = "Rating",
            defaultValue = "0",
            options = {
                { value = "0", label = "All" },
                { value = "1", label = "1"   },
                { value = "2", label = "2"   },
                { value = "3", label = "3"   },
                { value = "4", label = "4"   },
                { value = "5", label = "5"   },
            }
        },
        {
            type         = "select",
            key          = "chapters",
            label        = "Chapters",
            defaultValue = "0",
            options = {
                { value = "0",            label = "All"    },
                { value = "1,49",         label = "<50"    },
                { value = "50,100",       label = "50-100" },
                { value = "100,200",      label = "100-200"},
                { value = "200,500",      label = "200-500"},
                { value = "500,1000",     label = "500-1000"},
                { value = "1001,1000000", label = ">1000"  },
            }
        },
        {
            type  = "checkbox",
            key   = "language",
            label = "Language",
            options = {
                { value = "1", label = "Chinese"  },
                { value = "2", label = "Korean"   },
                { value = "3", label = "Japanese" },
                { value = "4", label = "English"  },
            }
        },
        {
            type  = "checkbox",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "3",  label = "Action"        },
                { value = "28", label = "Adult"         },
                { value = "4",  label = "Adventure"     },
                { value = "46", label = "Anime"         },
                { value = "5",  label = "Comedy"        },
                { value = "24", label = "Drama"         },
                { value = "44", label = "Eastern"       },
                { value = "26", label = "Ecchi"         },
                { value = "48", label = "Fan-fiction"   },
                { value = "6",  label = "Fantasy"       },
                { value = "19", label = "Game"          },
                { value = "25", label = "Gender Bender" },
                { value = "7",  label = "Harem"         },
                { value = "12", label = "Historical"    },
                { value = "37", label = "Horror"        },
                { value = "49", label = "Isekai"        },
                { value = "2",  label = "Josei"         },
                { value = "45", label = "Lgbt+"         },
                { value = "50", label = "Magic"         },
                { value = "15", label = "Martial Arts"  },
                { value = "8",  label = "Mature"        },
                { value = "34", label = "Mecha"         },
                { value = "16", label = "Mystery"       },
                { value = "9",  label = "Psychological" },
                { value = "43", label = "Reincarnation" },
                { value = "1",  label = "Romance"       },
                { value = "21", label = "School Life"   },
                { value = "20", label = "Sci-fi"        },
                { value = "10", label = "Seinen"        },
                { value = "38", label = "Shoujo"        },
                { value = "17", label = "Shounen"       },
                { value = "13", label = "Slice of Life" },
                { value = "29", label = "Smut"          },
                { value = "42", label = "Sports"        },
                { value = "18", label = "Supernatural"  },
                { value = "58", label = "System"        },
                { value = "32", label = "Tragedy"       },
                { value = "31", label = "Wuxia"         },
                { value = "23", label = "Xianxia"       },
                { value = "22", label = "Xuanhuan"      },
                { value = "14", label = "Yaoi"          },
                { value = "62", label = "Yuri"          },
            }
        },
    }
end

-- ── Filtered catalog ────────────────────────────────────────────────

function M.getCatalogFiltered(config, index, filters)
    local page           = index + 1
    local sort           = filters["sort"]           or "rank-top"
    local status         = filters["status"]         or "-1"
    local genre_operator = filters["genre_operator"] or "and"
    local rating_op      = filters["rating_operator"] or "min"
    local rating         = filters["rating"]         or "0"
    local chapters       = filters["chapters"]       or "0"
    local languages      = filters["language_included"] or {}
    local genres         = filters["genres_included"]   or {}

    local url = origin(config) .. "/search-adv?ctgcon=" .. genre_operator
        .. "&ratcon=" .. rating_op
        .. "&rating=" .. rating
        .. "&status=" .. status
        .. "&sort="   .. sort
        .. "&totalchapter=" .. url_encode(chapters)
        .. "&page="   .. tostring(page)

    for _, v in ipairs(languages) do url = url .. "&country_id[]=" .. v end
    for _, v in ipairs(genres)    do url = url .. "&categories[]=" .. v end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogCards(config, r.body)
    return { items = items, hasNext = #items > 0 }
end

return M
