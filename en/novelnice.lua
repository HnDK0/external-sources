id       = "novelnice"
name     = "NovelNice"
version  = "1.3.0"
baseUrl  = "https://novelnice.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelnice.png"

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

-- Рейтинг в карточке/на книге: span.score.font-meta.total_votes внутри
-- .post-total-rating. Возвращаем nil, если голосов нет (значение "0").
local function parseRating(body)
    local el = html_select_first(body, ".post-total-rating .total_votes")
    if not el then return nil end
    local v = string_trim(el.text)
    if v == "" or v == "0" or v == "0.0" then return nil end
    return v
end

-- Карточки каталога: .page-item-detail (обложка .item-thumb img,
-- заголовок .item-summary .post-title h3.h5 a, рейтинг
-- .item-summary .post-total-rating .total_votes).
local function parseCatalogItems(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".page-item-detail")) do
        local titleEl = html_select_first(card.html, ".item-summary .post-title h3.h5 a")
        if titleEl then
            local item = {
                title = string_clean(titleEl.text),
                url   = absUrl(titleEl.href),
            }
            local cover = html_attr(card.html, ".item-thumb img", "src")
            if cover ~= "" then item.cover = absUrl(cover) end
            local rating = parseRating(card.html)
            if rating then item.rating = rating end
            table.insert(items, item)
        end
    end
    return items
end

-- Пагинация Madara: .nav-previous a ведёт на СЛЕДУЮЩУЮ страницу (Older)
local function hasNextPage(body)
    local nextLink = html_select_first(body, ".nav-previous a")
    return nextLink ~= nil
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    -- Каталог живёт на /read/ (запросы с post_type=wp-manga блокирует Cloudflare → 403)
    local url = baseUrl .. "read/?m_orderby=rating"
    if page > 1 then
        url = baseUrl .. "read/page/" .. page .. "/?m_orderby=rating"
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = hasNextPage(r.body) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    -- Поиск на сайте фактически не работает: сайт ищет через
    -- ?s=<q>&post_type=wp-manga, а CF блокирует параметр post_type (403).
    -- Без него WordPress ищет только по обычным постам → всегда пусто.
    -- Оставляем вызов, чтобы движок не падал; результатов не будет.
    local page = index + 1
    local url = baseUrl .. "?s=" .. url_encode(query)
    if page > 1 then
        url = baseUrl .. "page/" .. page .. "/?s=" .. url_encode(query)
    end

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

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    return parseRating(body)
end

-- ── Количество AJAX-страниц глав ──────────────────────────────────────────────

-- Счётчик глав на странице книги (.post-content_item → "Chapters: N"),
-- страниц = ceil(N / 200) — AJAX-эндпоинт отдаёт по 200 глав на страницу.
local function getTotalPages(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return 1 end

    for _, item in ipairs(html_select(r.body, ".post-content_item")) do
        local heading = html_select_first(item.html, ".summary-heading h5")
        if heading and string_trim(heading.text) == "Chapters" then
            local content = html_select_first(item.html, ".summary-content")
            local count = content and tonumber(string_trim(content.text)) or 0
            if count and count > 0 then return math.ceil(count / 200) end
            break
        end
    end
    return 1
end

-- ── Парсинг одной AJAX-страницы глав ──────────────────────────────────────────

local function fetchAjaxPage(bookUrl, sitePage)
    local pr = http_post(
        bookUrl:gsub("/?$", "") .. "/ajax/chapters/?t=" .. tostring(sitePage),
        "",
        {
            headers = {
                ["X-Requested-With"] = "XMLHttpRequest",
                ["Referer"]          = bookUrl
            },
            charset = "UTF-8"
        }
    )
    if not pr.success then return {} end

    local chapters = {}
    for _, li in ipairs(html_select(pr.body, ".wp-manga-chapter")) do
        local a = html_select_first(li.html, "a")
        if a and a.href and a.href ~= "" then
            table.insert(chapters, {
                title = string_clean(a.text),
                url   = absUrl(a.href)
            })
        end
    end
    return chapters
end

-- ── parsePage — пагинированный список глав ────────────────────────────────────
--
-- Вызывается движком вместо getChapterList (см. гайд, «Paginated Chapter List»).
-- Возвращает { chapters = [...], totalPages = N }.
--
-- Сайт отдаёт новые главы на странице 1 AJAX-пагинации (t=1 = самые новые),
-- внутри каждой страницы тоже новые сверху. Инвертируем оба уровня.

function parsePage(bookUrl, page)
    local totalPages = getTotalPages(bookUrl)

    -- Движок запрашивает страницы 1, 2, 3... (1 = самые старые главы).
    -- На сайте страница 1 = самые новые, поэтому маппим:
    --   движок page 1  →  сайт page totalPages  (самые старые)
    --   движок page N  →  сайт page 1           (самые новые)
    local sitePage = totalPages - page + 1

    local raw = fetchAjaxPage(bookUrl, sitePage)

    -- Разворачиваем: сайт отдаёт новые сверху, нам нужны старые сверху
    local chapters = {}
    for i = #raw, 1, -1 do
        table.insert(chapters, raw[i])
    end

    sleep(math.random(150, 300))

    return {
        chapters   = chapters,
        totalPages = totalPages,
    }
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
        -- Запасной: ищем внутри .entry-content
        local entry = html_select_first(cleaned, ".entry-content")
        if entry then
            el = html_select_first(entry.html, ".reading-content")
        end
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
                { value = "drama",            label = "Drama"            },
                { value = "eastern",          label = "Eastern"          },
                { value = "fantasy",          label = "Fantasy"          },
                { value = "game",             label = "Game"             },
                { value = "historical",       label = "Historical"       },
                { value = "horror",           label = "Horror"           },
                { value = "josei",            label = "Josei"            },
                { value = "martial-arts",     label = "Martial Arts"     },
                { value = "mystery",          label = "Mystery"          },
                { value = "psychological",    label = "Psychological"    },
                { value = "romance",          label = "Romance"          },
                { value = "school-life",      label = "School Life"      },
                { value = "sci-fi",           label = "Sci-fi"           },
                { value = "shounen",          label = "Shounen"          },
                { value = "slice-of-life",    label = "Slice of Life"    },
                { value = "supernatural",     label = "Supernatural"     },
                { value = "urban",            label = "Urban"            },
                { value = "wuxia",            label = "Wuxia"            },
                { value = "xianxia",          label = "Xianxia"          },
                { value = "xuanhuan",         label = "Xuanhuan"         },
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

    -- Каталог с фильтрами тоже на /read/ (без post_type — CF блокирует)
    local url = baseUrl .. "read/"
    if page > 1 then
        url = baseUrl .. "read/page/" .. page .. "/"
    end
    url = url .. "?m_orderby=" .. url_encode(orderby)
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
