id       = "meionovels"
name     = "MeioNovels"
version  = "1.0.0"
baseUrl  = "https://meionovels.com"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/meionovels.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

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
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

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

-- ── Утилиты для парсинга ──────────────────────────────────────────────────────

local function parseCoverSrc(body)
    local cover = html_attr(body, ".summary_image img", "src")
    if cover == "" then
        cover = html_attr(body, ".tab-thumb img", "src")
    end
    if cover == "" then
        cover = html_attr(body, ".c-image-hover img", "src")
    end
    return cover ~= "" and absUrl(cover) or nil
end

local function parseCatalogItems(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".c-tabs-item__content")) do
        local titleEl = html_select_first(card.html, ".post-title h3.h4 a")
        local cover   = html_attr(card.html, ".tab-thumb img", "src")
        if cover == "" then
            cover = html_attr(card.html, ".c-image-hover img", "src")
        end
        if titleEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = cover ~= "" and absUrl(cover) or nil
            })
        end
    end
    return items
end

local function hasNextPage(body)
    local nextLink = html_select_first(body, ".nav-previous a")
    return nextLink ~= nil
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/page/" .. page .. "/?s&post_type=wp-manga&m_orderby=rating"

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "/page/" .. page .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".post-title h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    return parseCoverSrc(body)
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".description-summary .summary__content")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local genres = {}
    for _, a in ipairs(html_select(body, ".genres-content a")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Хэш списка глав (прямой запрос, не кэш!) ────────────────────────────────

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end

    -- Берём количество глав из .post-content_item с h5="Chapters"
    local chapterCount = ""
    for _, item in ipairs(html_select(r.body, ".post-content_item")) do
        local heading = html_select_first(item.html, ".summary-heading h5")
        if heading and string_trim(heading.text) == "Chapters" then
            local content = html_select_first(item.html, ".summary-content")
            if content then
                chapterCount = string_trim(content.text)
            end
            break
        end
    end

    return chapterCount ~= "" and "chapters_" .. chapterCount or nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local chapters = {}

    -- Парсим все главы (с учётом вложенности Volume > Chapter)
    for _, li in ipairs(html_select(body, ".listing-chapters_wrap .wp-manga-chapter")) do
        local a = html_select_first(li.html, "a")
        if a and a.href and a.href ~= "" then
            table.insert(chapters, {
                title = string_clean(a.text),
                url   = absUrl(a.href)
            })
        end
    end

    -- Если глав не нашлось через плоский список, пробуем вложенную структуру
    if #chapters == 0 then
        for _, vol in ipairs(html_select(body, ".listing-chapters_wrap .has-child")) do
            for _, li in ipairs(html_select(vol.html, ".wp-manga-chapter")) do
                local a = html_select_first(li.html, "a")
                if a and a.href and a.href ~= "" then
                    table.insert(chapters, {
                        title = string_clean(a.text),
                        url   = absUrl(a.href)
                    })
                end
            end
        end
    end

    -- Сортируем по номеру главы (ascending)
    table.sort(chapters, function(a, b)
        local na = tonumber(a.url:match("chapter%-(%d+)") or a.url:match("chapter-(%d+)") or "0") or 0
        local nb = tonumber(b.url:match("chapter%-(%d+)") or b.url:match("chapter-(%d+)") or "0") or 0
        return na < nb
    end)

    return chapters
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html,
        "script", "style",
        ".ads", ".advertisement",
        ".chapter-nav", ".nav-links",
        "#comments", ".disqus"
    )

    -- Основной селектор для Madara theme
    local el = html_select_first(cleaned, ".reading-content .text-left")
    if not el then
        el = html_select_first(cleaned, ".entry-content")
    end
    if not el then
        el = html_select_first(cleaned, ".chapter-content")
    end
    if not el then
        el = html_select_first(cleaned, "#content")
    end
    if not el then return "" end

    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Фильтры ───────────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "m_orderby",
            label        = "Order By",
            defaultValue = "rating",
            options = {
                { value = "rating",     label = "Rating"         },
                { value = "latest",     label = "Latest"         },
                { value = "alphabet",   label = "A-Z"            },
                { value = "trending",   label = "Trending"       },
                { value = "views",      label = "Most Views"     },
                { value = "new-manga",  label = "New"            },
                { value = "",           label = "Relevance"      },
            }
        },
        {
            type  = "checkbox",
            key   = "genre",
            label = "Genres",
            options = {
                { value = "action",           label = "Action"           },
                { value = "adventure",        label = "Adventure"        },
                { value = "comedy",           label = "Comedy"           },
                { value = "cooking",          label = "Cooking"          },
                { value = "drama",            label = "Drama"            },
                { value = "ecchi",            label = "Ecchi"            },
                { value = "fanfiction",       label = "Fanfiction"       },
                { value = "fantasy",          label = "Fantasy"          },
                { value = "gender-bender",    label = "Gender Bender"    },
                { value = "harem",            label = "Harem"            },
                { value = "historical",       label = "Historical"       },
                { value = "horror",           label = "Horror"           },
                { value = "isekai",           label = "Isekai"           },
                { value = "josei",            label = "Josei"            },
                { value = "magic",            label = "Magic"            },
                { value = "martial-arts",     label = "Martial Arts"     },
                { value = "mature",           label = "Mature"           },
                { value = "mecha",            label = "Mecha"            },
                { value = "musik",            label = "Musik"            },
                { value = "mystery",          label = "Mystery"          },
                { value = "one-shot",         label = "One Shot"         },
                { value = "psychological",    label = "Psychological"    },
                { value = "reverse-harem",    label = "Reverse Harem"    },
                { value = "romance",          label = "Romance"          },
                { value = "school-life",      label = "School Life"      },
                { value = "sci-fi",           label = "Sci-fi"           },
                { value = "seinen",           label = "Seinen"           },
                { value = "shoujo",           label = "Shoujo"           },
                { value = "shoujo-ai",        label = "Shoujo Ai"        },
                { value = "shounen",          label = "Shounen"          },
                { value = "shounen-ai",       label = "Shounen Ai"       },
                { value = "slice-of-life",    label = "Slice of Life"    },
                { value = "smut",             label = "Smut"             },
                { value = "sports",           label = "Sports"           },
                { value = "supernatural",     label = "Supernatural"     },
                { value = "tragedy",          label = "Tragedy"          },
                { value = "virtual-reality",  label = "Virtual Reality"  },
                { value = "wuxia",            label = "Wuxia"            },
                { value = "xianxia",          label = "Xianxia"          },
                { value = "xuanhuan",         label = "Xuanhuan"         },
                { value = "yuri",             label = "Yuri"             },
            }
        },
        {
            type         = "select",
            key          = "op",
            label        = "Genres Condition",
            defaultValue = "",
            options = {
                { value = "",  label = "OR (having one of selected genres)" },
                { value = "1", label = "AND (having all selected genres)"   },
            }
        },
        {
            type         = "select",
            key          = "adult",
            label        = "Adult Content",
            defaultValue = "",
            options = {
                { value = "",  label = "All"              },
                { value = "0", label = "None adult content" },
                { value = "1", label = "Only adult content" },
            }
        },
        {
            type  = "checkbox",
            key   = "status",
            label = "Status",
            options = {
                { value = "on-going",  label = "OnGoing"   },
                { value = "end",       label = "Completed"  },
                { value = "canceled",  label = "Canceled"   },
                { value = "on-hold",   label = "On Hold"    },
                { value = "upcoming",  label = "Upcoming"   },
            }
        },
        {
            type         = "text",
            key          = "author",
            label        = "Author",
            defaultValue = ""
        },
        {
            type         = "text",
            key          = "release",
            label        = "Year of Released",
            defaultValue = ""
        },
    }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page    = index + 1
    local orderby = filters["m_orderby"] or "rating"
    local op      = filters["op"] or ""
    local adult   = filters["adult"] or ""
    local author  = filters["author"] or ""
    local release = filters["release"] or ""
    local genres  = filters["genre_included"] or {}
    local statuses = filters["status_included"] or {}

    local url = baseUrl .. "/page/" .. page .. "/?s&post_type=wp-manga"
                .. "&m_orderby=" .. url_encode(orderby)
                .. "&op=" .. url_encode(op)
                .. "&adult=" .. url_encode(adult)

    if author ~= "" then
        url = url .. "&author=" .. url_encode(author)
    end
    if release ~= "" then
        url = url .. "&release=" .. url_encode(release)
    end

    for _, v in ipairs(genres) do
        url = url .. "&genre[]=" .. url_encode(v)
    end
    for _, v in ipairs(statuses) do
        url = url .. "&status[]=" .. url_encode(v)
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end