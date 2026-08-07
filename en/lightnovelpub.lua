id       = "lightnovelpub"
name     = "LightNovelPub"
version  = "1.0.1"
baseUrl  = "https://lightnovelpub.org"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/lightnovelpub.png"

-- ── Helpers ──────────────────────────────────────────────────────────────────

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

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
    text = string_trim(text)
    return text
end

local function parseCatalogCards(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".recommendation-card")) do
        local linkEl  = html_select_first(card.html, "a.card-cover-link")
        local titleEl = html_select_first(card.html, "h3.card-title")
        local cover   = html_attr(card.html, ".card-cover img", "src")
        if cover == "" then cover = html_attr(card.html, "img", "src") end
        if linkEl and titleEl then
            local item = {
                title = string_clean(titleEl.text),
                url   = absUrl(linkEl.href),
                cover = absUrl(cover)
            }
            -- Рейтинг из карточки каталога: <div class="card-rating">★ 4.72</div>.
            -- На genre-all карточки показывают рейтинг, на advanced-search — нет,
            -- поэтому ключ rating добавляем только если значение реально нашлось.
            local ratingEl = html_select_first(card.html, ".card-rating")
            if ratingEl then
                local n = string.match(string_clean(ratingEl.text), "%d+%.?%d*")
                if n then item.rating = n end
            end
            table.insert(items, item)
        end
    end
    return items
end

-- ── Catalog ──────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local r = http_get(baseUrl .. "/genre-all/?order=popular&page=" .. page)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogCards(r.body)
    return { items = items, hasNext = #items > 0 }
end

-- ── Search ───────────────────────────────────────────────────────────────────

-- Поиск идёт через JSON API /api/search/ — в объектах novels рейтинга нет
-- (только rank), поэтому ключ rating здесь не заполняется.
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end

    local r = http_get(baseUrl .. "/api/search/?q=" .. url_encode(query))
    if not r.success then return { items = {}, hasNext = false } end

    local data = json_parse(r.body)
    if not data or not data.novels then return { items = {}, hasNext = false } end

    local items = {}
    for _, novel in ipairs(data.novels) do
        if novel.title and novel.slug then
            table.insert(items, {
                title = string_clean(novel.title),
                url   = baseUrl .. "/novel/" .. novel.slug .. "/",
                cover = novel.cover_path ~= "" and absUrl(novel.cover_path) or ""
            })
        end
    end
    return { items = items, hasNext = false }
end

-- ── Book details ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1.novel-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "meta[property='og:image']", "content")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".summary-content")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, el in ipairs(html_select(body, ".genre-tag")) do
        local label = string_trim(el.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Rating ───────────────────────────────────────────────────────────────────

-- Рейтинг книги со страницы книги: <span class="rating-number">4.72</span>
-- внутри <div class="star-rating">. Прямой http_get (без fetchPage — кэш
-- не нужен, движок вызывает функцию отдельным запросом), список глав не парсит.
function getBookRating(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".star-rating .rating-number")
    return el and string_clean(el.text) or nil
end

-- ── Chapter list (parsePage) ─────────────────────────────────────────────────

local function getTotalPages(body)
    local maxPage = 1
    for _, opt in ipairs(html_select(body, "select#pageSelect option")) do
        local p = tonumber(opt.text)
        if p and p > maxPage then maxPage = p end
    end
    return maxPage
end

function parsePage(bookUrl, page)
    local slug = bookUrl:match("/novel/([^/]+)")
    if not slug then return { chapters = {}, totalPages = 1 } end

    local url = baseUrl .. "/novel/" .. slug .. "/chapters/?page=" .. page
    local r = http_get(url)
    if not r.success then return { chapters = {}, totalPages = 1 } end

    local totalPages = getTotalPages(r.body)

    local chapters = {}
    for _, card in ipairs(html_select(r.body, ".chapter-card")) do
        local num = html_select_first(card.html, ".chapter-number")
        local titleEl = html_select_first(card.html, ".chapter-title")
        if num then
            local n = string_clean(num.text)
            if n ~= "" then
                table.insert(chapters, {
                    title = titleEl and string_clean(titleEl.text) or "",
                    url   = baseUrl .. "/novel/" .. slug .. "/chapter/" .. n .. "/"
                })
            end
        end
    end

    sleep(math.random(150, 300))
    return { chapters = chapters, totalPages = totalPages }
end

-- ── Chapter text ─────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "style",
                                ".chapter-ad-container", ".ad-unit",
                                ".chapter-nav", "#comments", ".disqus")
    local el = html_select_first(cleaned, "#chapterText, .chapter-text")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Filters ──────────────────────────────────────────────────────────────────

local GENRE_OPTIONS = {
    { value = "Action",          label = "Action"          },
    { value = "Adult",           label = "Adult"           },
    { value = "Adventure",       label = "Adventure"       },
    { value = "Comedy",          label = "Comedy"          },
    { value = "Drama",           label = "Drama"           },
    { value = "Eastern",         label = "Eastern"         },
    { value = "Ecchi",           label = "Ecchi"           },
    { value = "Fan-Fiction",     label = "Fan-Fiction"     },
    { value = "Fantasy",         label = "Fantasy"         },
    { value = "Game",            label = "Game"            },
    { value = "Gender-Bender",   label = "Gender Bender"   },
    { value = "Harem",           label = "Harem"           },
    { value = "Historical",      label = "Historical"      },
    { value = "Horror",          label = "Horror"          },
    { value = "Isekai",          label = "Isekai"          },
    { value = "Josei",           label = "Josei"           },
    { value = "LGBT+",           label = "LGBT+"           },
    { value = "Magic",           label = "Magic"           },
    { value = "Magical-Realism", label = "Magical Realism" },
    { value = "Martial-Arts",    label = "Martial Arts"    },
    { value = "Mature",          label = "Mature"          },
    { value = "Mecha",           label = "Mecha"           },
    { value = "Mystery",         label = "Mystery"         },
    { value = "Psychological",   label = "Psychological"   },
    { value = "Romance",         label = "Romance"         },
    { value = "School-Life",     label = "School Life"     },
    { value = "Sci-Fi",          label = "Sci-Fi"          },
    { value = "Seinen",          label = "Seinen"          },
    { value = "Shoujo",          label = "Shoujo"          },
    { value = "Shounen",         label = "Shounen"         },
    { value = "Slice-of-Life",   label = "Slice of Life"   },
    { value = "Sports",          label = "Sports"          },
    { value = "Supernatural",    label = "Supernatural"    },
    { value = "Thriller",        label = "Thriller"        },
    { value = "Tragedy",         label = "Tragedy"         },
    { value = "Wuxia",           label = "Wuxia"           },
    { value = "Xianxia",         label = "Xianxia"         },
    { value = "Xuanhuan",        label = "Xuanhuan"        },
    { value = "Yaoi",            label = "Yaoi"            },
    { value = "Yuri",            label = "Yuri"            },
}

function getFilterList()
    return {
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = GENRE_OPTIONS,
        },
        {
            type         = "select",
            key          = "genre_logic",
            label        = "Genre Logic",
            defaultValue = "AND",
            options = {
                { value = "AND", label = "ALL selected" },
                { value = "OR",  label = "ANY selected" },
            }
        },
        {
            type  = "checkbox",
            key   = "status",
            label = "Status",
            options = {
                { value = "ongoing",   label = "Ongoing"   },
                { value = "completed", label = "Completed"  },
                { value = "hiatus",    label = "Hiatus"     },
            }
        },
        {
            type         = "select",
            key          = "chapter_range",
            label        = "Chapter Count",
            defaultValue = "all",
            options = {
                { value = "all",     label = "Any"         },
                { value = "<50",     label = "< 50"        },
                { value = "50-100",  label = "50 – 100"    },
                { value = "100-500", label = "100 – 500"   },
                { value = "500-1000",label = "500 – 1000"  },
                { value = ">1000",   label = "> 1000"      },
            }
        },
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "rank",
            options = {
                { value = "rank",      label = "Rank"       },
                { value = "rating",    label = "Rating"     },
                { value = "views",     label = "Views"      },
                { value = "bookmarks", label = "Bookmarks"  },
                { value = "updates",   label = "Updates"    },
                { value = "new",       label = "Newest"     },
            }
        },
        {
            type         = "select",
            key          = "order",
            label        = "Order",
            defaultValue = "desc",
            options = {
                { value = "desc", label = "Descending" },
                { value = "asc",  label = "Ascending"  },
            }
        },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1

    local genresInc = filters["genres_included"] or {}
    local genresExc = filters["genres_excluded"] or {}
    local logic     = filters["genre_logic"]     or "AND"
    local status    = filters["status_included"]  or {}
    local chRange   = filters["chapter_range"]   or "all"
    local sort      = filters["sort"]            or "rank"
    local order     = filters["order"]           or "desc"

    local params = {}
    for _, g in ipairs(genresInc) do
        params[#params + 1] = "genres_include=" .. url_encode(g)
    end
    for _, g in ipairs(genresExc) do
        params[#params + 1] = "genres_exclude=" .. url_encode(g)
    end
    if #genresInc > 1 then
        params[#params + 1] = "genre_logic=" .. logic
    end
    for _, s in ipairs(status) do
        params[#params + 1] = "status=" .. url_encode(s)
    end
    if chRange ~= "all" then
        params[#params + 1] = "chapter_range=" .. url_encode(chRange)
    end
    if sort ~= "rank" then
        params[#params + 1] = "sort=" .. sort
    end
    if order ~= "desc" then
        params[#params + 1] = "order=" .. order
    end
    params[#params + 1] = "page=" .. page

    local url = baseUrl .. "/advanced-search/?" .. table.concat(params, "&")

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogCards(r.body)
    return { items = items, hasNext = #items > 0 }
end
