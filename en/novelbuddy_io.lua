-- Метаданные
id       = "novelbuddy"
name     = "NovelBuddy"
version  = "3.0.0"
baseUrl  = "https://novelbuddy.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbuddy.png"

-- Отключаем детект turnstile — сайт его использует в обычном контенте
cf_options = {
    whitelist      = false,
    ignore_markers = { "turnstile", "Ray ID" }
}

local API_BASE = "https://api.novelbuddy.com/"

-- ── Хелперы ──────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function resolveCover(raw, slug)
    local cover = ""
    if type(raw) == "table" then
        cover = raw.url or raw.src or ""
    elseif type(raw) == "string" then
        cover = raw
    end
    if cover == "" and slug and slug ~= "" then
        cover = "https://static.novelbuddy.com/thumb/" .. slug .. ".png"
    end
    return cover
end

local function slugFromUrl(bookUrl)
    local path = bookUrl:match("^[^?#]+") or bookUrl
    return path:match("/([^/]+)$") or ""
end

local function decodeHtmlEntities(text)
    if not text or text == "" then return "" end
    text = text:gsub("&amp;",  "&")
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&lt;",   "<")
    text = text:gsub("&gt;",   ">")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&#(%d+);",  function(n) return string.char(tonumber(n)) end)
    text = text:gsub("&#x(%x+);", function(h) return string.char(tonumber(h, 16)) end)
    return text
end

local function cleanContent(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    -- Убираем watermarks
    text = regex_replace(text, "(?i)Find authorized novels in Webnovel.*?Please click www\\.webnovel\\.com for visiting\\.", "")
    text = regex_replace(text, "(?i)free.{0,10}novel\\.com", "")
    -- Убираем строки с доменом сайта
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = string_trim(text)
    return text
end

-- ── API ───────────────────────────────────────────────────────────────────────

local function apiGet(path)
    local r = http_get(API_BASE .. path)
    if not r or not r.success then
        log_error("NovelBuddy: API GET failed: " .. API_BASE .. path .. " code=" .. tostring(r and r.code))
        return nil
    end
    local data = json_parse(r.body)
    if not data then
        log_error("NovelBuddy: JSON parse failed for: " .. API_BASE .. path)
        return nil
    end
    return data
end

-- Получить __NEXT_DATA__ из HTML страницы
local function fetchNextData(url)
    log_info("NovelBuddy: fetchNextData url=" .. url)
    local r = http_get(url)
    if not r or not r.success then
        log_error("NovelBuddy: page fetch failed: " .. url .. " code=" .. tostring(r and r.code))
        return nil
    end
    -- Извлекаем содержимое <script id="__NEXT_DATA__">
    local json_str = r.body:match('<script[^>]+id="__NEXT_DATA__"[^>]*>([^<]+)</script>')
    if not json_str then
        log_error("NovelBuddy: __NEXT_DATA__ not found in " .. url)
        return nil
    end
    local data = json_parse(json_str)
    if not data then
        log_error("NovelBuddy: __NEXT_DATA__ JSON parse failed")
        return nil
    end
    return data
end

-- Поиск по slug через API
local function searchBySlug(slug)
    if not slug or slug == "" then return nil end
    local parts = {}
    for part in slug:gmatch("[^-]+") do
        table.insert(parts, part)
        if #parts >= 4 then break end
    end
    local shortSlug = table.concat(parts, "-")
    local data = apiGet("titles/search?q=" .. url_encode(shortSlug) .. "&limit=1")
    if not data then return nil end
    local items = (data.data and data.data.items) or data.items or {}
    if #items == 0 then return nil end
    return items[1]
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index, filters)
    local page   = index + 1
    local params = "page=" .. tostring(page) .. "&limit=24"

    if type(filters) == "table" then
        local sort   = filters["sort"]   or ""
        local status = filters["status"] or ""
        local genres = filters["genre_included"] or ""
        local excl   = filters["exclude_included"] or ""
        local min_ch = filters["min_ch"] or ""
        local max_ch = filters["max_ch"] or ""

        if sort   ~= "" then params = params .. "&sort="           .. url_encode(sort)   end
        if status ~= "" and status ~= "all" then
            params = params .. "&status=" .. url_encode(status)
        end
        if type(genres) == "table" then genres = table.concat(genres, ",") end
        if genres ~= "" then params = params .. "&genres=" .. genres end
        if type(excl) == "table" then excl = table.concat(excl, ",") end
        if excl   ~= "" then params = params .. "&exclude_genres=" .. excl end
        if min_ch ~= "" then params = params .. "&min_ch=" .. url_encode(tostring(min_ch)) end
        if max_ch ~= "" then params = params .. "&max_ch=" .. url_encode(tostring(max_ch)) end
    end

    local data = apiGet("titles/search?" .. params)
    if not data then return { items = {}, hasNext = false } end

    local inner    = data.data or {}
    local rawItems = inner.items or {}
    local items    = {}

    for _, novel in ipairs(rawItems) do
        local slug    = novel.slug or ""
        local bookUrl = absUrl("/" .. slug)
        local cover   = resolveCover(novel.cover, slug)
        local title   = novel.name or ""
        if slug ~= "" and title ~= "" then
            table.insert(items, { title = title, url = bookUrl, cover = cover })
        end
    end

    local pagination = inner.pagination or {}
    local hasNext    = pagination.has_next
    if hasNext == nil then hasNext = (#items >= 24) end

    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    local page = index + 1
    local data = apiGet("titles/search?q=" .. url_encode(query)
                        .. "&page=" .. tostring(page) .. "&limit=24")
    if not data then return { items = {}, hasNext = false } end

    local inner    = data.data or {}
    local rawItems = inner.items or {}
    local items    = {}

    for _, novel in ipairs(rawItems) do
        local slug    = novel.slug or ""
        local bookUrl = absUrl("/" .. slug)
        local cover   = resolveCover(novel.cover, slug)
        local title   = novel.name or novel.title or ""
        if slug ~= "" and title ~= "" then
            table.insert(items, { title = title, url = bookUrl, cover = cover })
        end
    end

    local pagination = inner.pagination or {}
    local hasNext    = pagination.has_next
    if hasNext == nil then hasNext = (#items >= 24) end

    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────
-- Читаем из __NEXT_DATA__ как TS плагин

local function fetchMangaNextData(bookUrl)
    local nd = fetchNextData(bookUrl)
    if not nd then return nil end
    local initialManga = nd.props and nd.props.pageProps and nd.props.pageProps.initialManga
    if not initialManga then
        log_error("NovelBuddy: initialManga not found in __NEXT_DATA__ for " .. bookUrl)
        return nil
    end
    return initialManga
end

function getBookTitle(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if manga then return manga.name end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if not manga then return nil end
    local slug = slugFromUrl(bookUrl)
    return resolveCover(manga.cover, slug)
end

function getBookDescription(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if not manga then return nil end
    local summary = manga.summary or ""
    if summary ~= "" then
        summary = summary:gsub("<br%s*/?>", "\n")
        summary = summary:gsub("<p[^>]*>", "\n")
        summary = summary:gsub("</p>", "\n\n")
        summary = summary:gsub("<[^>]+>", "")
        summary = decodeHtmlEntities(summary)
        summary = regex_replace(summary, "\\n{3,}", "\n\n")
        return string_trim(summary)
    end
    return nil
end

function getBookGenres(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if not manga then return {} end
    local genres = {}
    local seen   = {}
    for _, g in ipairs(manga.genres or {}) do
        local gname = type(g) == "string" and g or (g.name or "")
        if gname ~= "" and not seen[gname] then
            seen[gname] = true
            table.insert(genres, gname)
        end
    end
    return genres
end

-- ── Список глав ───────────────────────────────────────────────────────────────
-- Сначала пробуем API, fallback — __NEXT_DATA__

function getChapterList(bookUrl)
    -- Получаем id книги через __NEXT_DATA__
    local manga = fetchMangaNextData(bookUrl)
    if not manga then
        log_error("NovelBuddy: cannot get manga data for " .. bookUrl)
        return {}
    end

    local mangaId = manga.id
    if mangaId and mangaId ~= "" then
        -- Пробуем API
        local data = apiGet("titles/" .. url_encode(mangaId) .. "/chapters")
        if data then
            local inner = data.data or {}
            local rawChapters = inner.items or inner.chapters or {}

            if #rawChapters > 0 then
                local allChapters = {}
                for _, ch in ipairs(rawChapters) do
                    local chUrl = ch.url or ""
                    -- Получаем path как в TS: pathname без первого /
                    if chUrl ~= "" then
                        if not string_starts_with(chUrl, "http") then
                            chUrl = absUrl(chUrl)
                        end
                        local path = chUrl:match("https?://[^/]+(.+)") or chUrl
                        -- Итоговый URL главы — страница сайта (как в TS)
                        local fullUrl = baseUrl .. path
                        local title = ch.name or ch.title or ch.slug or ""
                        table.insert(allChapters, {
                            title = string_clean(title),
                            url   = fullUrl,
                        })
                    end
                end
                -- reverse
                local reversed = {}
                for i = #allChapters, 1, -1 do
                    table.insert(reversed, allChapters[i])
                end
                return reversed
            end
        end
    end

    -- Fallback: главы из __NEXT_DATA__
    log_info("NovelBuddy: falling back to __NEXT_DATA__ chapters")
    local chapters = manga.chapters or {}
    local allChapters = {}
    for _, ch in ipairs(chapters) do
        local chUrl = ch.url or ""
        if chUrl ~= "" then
            if not string_starts_with(chUrl, "http") then
                chUrl = absUrl(chUrl)
            end
            local path = chUrl:match("https?://[^/]+(.+)") or chUrl
            local fullUrl = baseUrl .. path
            local title = ch.name or ch.title or ""
            table.insert(allChapters, {
                title = string_clean(title),
                url   = fullUrl,
            })
        end
    end
    local reversed = {}
    for i = #allChapters, 1, -1 do
        table.insert(reversed, allChapters[i])
    end
    return reversed
end

function getChapterListHash(bookUrl)
    local manga = fetchMangaNextData(bookUrl)
    if not manga then return nil end
    local stats = manga.stats or manga.ratingStats or {}
    local count = stats.chapters_count or stats.chaptersCount
    if count then return tostring(count) end
    return manga.updated_at or manga.updatedAt or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────
-- Читаем __NEXT_DATA__ как TS плагин — никакого api.novelbuddy в URL не нужно

function getChapterText(html, url)
    log_info("NovelBuddy: getChapterText url=" .. tostring(url))

    -- Пробуем взять __NEXT_DATA__ из уже загруженного html
    local json_str = html and html:match('<script[^>]+id="__NEXT_DATA__"[^>]*>([^<]+)</script>')

    if not json_str or json_str == "" then
        log_error("NovelBuddy: __NEXT_DATA__ not found in html, fetching url directly")
        local r = http_get(url)
        if not r or not r.success then
            log_error("NovelBuddy: fetch failed code=" .. tostring(r and r.code))
            return ""
        end
        json_str = r.body:match('<script[^>]+id="__NEXT_DATA__"[^>]*>([^<]+)</script>')
        if not json_str then
            log_error("NovelBuddy: __NEXT_DATA__ not found after direct fetch")
            return ""
        end
    end

    local data = json_parse(json_str)
    if not data then
        log_error("NovelBuddy: __NEXT_DATA__ JSON parse failed")
        return ""
    end

    local initialChapter = data.props and data.props.pageProps and data.props.pageProps.initialChapter
    if not initialChapter then
        log_error("NovelBuddy: initialChapter not found in __NEXT_DATA__")
        return ""
    end

    local content = initialChapter.content or ""
    if content == "" then
        log_error("NovelBuddy: empty content in initialChapter")
        return ""
    end

    log_info("NovelBuddy: content length=" .. tostring(#content))

    -- Убираем watermarks как в TS
    content = regex_replace(content,
        "(?i)Find authorized novels in Webnovel.*?faster updates.*?Please click www\\.webnovel\\.com for visiting\\.",
        "")
    content = regex_replace(content, "(?i)free.*?novel\\.com", "")

    local text = html_text(content)
    text = cleanContent(text)
    return text
end

-- ── Фильтры ───────────────────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    return getCatalogList(index, filters)
end

function getFilterList()
    local genreOptions = {
        { value = "action",           label = "Action"           },
        { value = "action-adventure", label = "Action Adventure" },
        { value = "adult",            label = "Adult"            },
        { value = "adventure",        label = "Adventure"        },
        { value = "comedy",           label = "Comedy"           },
        { value = "cultivation",      label = "Cultivation"      },
        { value = "drama",            label = "Drama"            },
        { value = "eastern",          label = "Eastern"          },
        { value = "ecchi",            label = "Ecchi"            },
        { value = "fan-fiction",      label = "Fan Fiction"      },
        { value = "fantasy",          label = "Fantasy"          },
        { value = "game",             label = "Game"             },
        { value = "gender-bender",    label = "Gender Bender"    },
        { value = "harem",            label = "Harem"            },
        { value = "historical",       label = "Historical"       },
        { value = "horror",           label = "Horror"           },
        { value = "isekai",           label = "Isekai"           },
        { value = "josei",            label = "Josei"            },
        { value = "light-novel",      label = "Light Novel"      },
        { value = "litrpg",           label = "LitRPG"           },
        { value = "lolicon",          label = "Lolicon"          },
        { value = "magic",            label = "Magic"            },
        { value = "martial-arts",     label = "Martial Arts"     },
        { value = "mature",           label = "Mature"           },
        { value = "mecha",            label = "Mecha"            },
        { value = "military",         label = "Military"         },
        { value = "modern-life",      label = "Modern Life"      },
        { value = "mystery",          label = "Mystery"          },
        { value = "psychological",    label = "Psychological"    },
        { value = "reincarnation",    label = "Reincarnation"    },
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
        { value = "system",           label = "System"           },
        { value = "thriller",         label = "Thriller"         },
        { value = "tragedy",          label = "Tragedy"          },
        { value = "urban",            label = "Urban"            },
        { value = "urban-life",       label = "Urban Life"       },
        { value = "wuxia",            label = "Wuxia"            },
        { value = "xianxia",          label = "Xianxia"          },
        { value = "xuanhuan",         label = "Xuanhuan"         },
        { value = "yaoi",             label = "Yaoi"             },
        { value = "yuri",             label = "Yuri"             },
    }

    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Order by",
            defaultValue = "",
            options = {
                { value = "",             label = "Default"       },
                { value = "views",        label = "Most Viewed"   },
                { value = "latest",       label = "Latest Update" },
                { value = "popular",      label = "Popular"       },
                { value = "alphabetical", label = "A-Z"           },
                { value = "rating",       label = "Rating"        },
                { value = "chapters",     label = "Most Chapters" },
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "",
            options = {
                { value = "",          label = "All"       },
                { value = "ongoing",   label = "Ongoing"   },
                { value = "completed", label = "Completed" },
                { value = "hiatus",    label = "Hiatus"    },
                { value = "cancelled", label = "Cancelled" },
            }
        },
        {
            type         = "select",
            key          = "min_ch",
            label        = "Minimum Chapters",
            defaultValue = "",
            options = {
                { value = "",     label = "Any"   },
                { value = "1",    label = "1+"    },
                { value = "50",   label = "50+"   },
                { value = "100",  label = "100+"  },
                { value = "200",  label = "200+"  },
                { value = "500",  label = "500+"  },
                { value = "1000", label = "1000+" },
                { value = "2000", label = "2000+" },
            }
        },
        {
            type         = "select",
            key          = "max_ch",
            label        = "Maximum Chapters",
            defaultValue = "",
            options = {
                { value = "",     label = "Any"    },
                { value = "50",   label = "≤ 50"   },
                { value = "100",  label = "≤ 100"  },
                { value = "200",  label = "≤ 200"  },
                { value = "500",  label = "≤ 500"  },
                { value = "1000", label = "≤ 1000" },
                { value = "2000", label = "≤ 2000" },
            }
        },
        {
            type    = "checkbox",
            key     = "genre",
            label   = "Genres (include)",
            options = genreOptions,
        },
        {
            type    = "checkbox",
            key     = "exclude",
            label   = "Genres (exclude)",
            options = genreOptions,
        },
    }
end