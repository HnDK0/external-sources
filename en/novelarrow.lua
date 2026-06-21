-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "NovelArrow"
name     = "Novel Arrow"
version  = "1.0.1"
baseUrl  = "https://novelarrow.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbin.png"

-- ── Константы ─────────────────────────────────────────────────────────────────

local apiBase = "https://novelarrow.com/api-web/"

-- ── Кэш деталей книги ─────────────────────────────────────────────────────────
-- Движок вызывает getBookTitle/Cover/Description/Genres параллельно.
-- fetchBookData кэширует JSON-ответ, чтобы сделать только 1 запрос вместо 4.

local _bookCache = {}

local function fetchBookData(novelId)
    if _bookCache[novelId] then
        return _bookCache[novelId]
    end
    local r = http_get(apiBase .. "novels/" .. novelId)
    if not r.success then
        log_error("novelarrow: fetchBookData failed novelId=" .. novelId .. " code=" .. tostring(r.code))
        return nil
    end
    local parsed = json_parse(r.body)
    if not parsed then
        log_error("novelarrow: fetchBookData json_parse failed for novelId=" .. novelId)
        return nil
    end
    local data = parsed.item and parsed.item.novelInfo or nil
    if data then
        _bookCache[novelId] = data
    end
    return data
end

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Извлекает novel_id (slug) из URL книги:
-- https://novelarrow.com/novel/weapons-of-mass-destruction → "weapons-of-mass-destruction"
local function extractNovelId(bookUrl)
    return bookUrl:match("/novel/([^/?#]+)")
end

-- Извлекает novel_id и chapter_id из URL главы:
-- https://novelarrow.com/chapter/weapons-of-mass-destruction/chapter-1
local function extractChapterParts(chapterUrl)
    local novelId, chapterId = chapterUrl:match("/chapter/([^/?#]+)/([^/?#]+)")
    return novelId, chapterId
end

-- Строит URL обложки для каталога (240x360)
local function coverUrl(novelId)
    return "https://images.novelarrow.com/novel_240_360/" .. novelId .. ".jpg"
end

-- Очищает HTML описания — убирает теги, оставляет текст
local function stripHtml(html)
    if not html or html == "" then return "" end
    local text = regex_replace(html, "<[^>]*>", "")
    text = string_normalize(text)
    return string_trim(text)
end

-- Стандартная очистка текста главы
local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?i)novelarrow\\.com.*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

-- Парсит items[] из ответа /api-web/novels в таблицу плагина
local function parseNovelItems(items)
    local result = {}
    for _, novel in ipairs(items) do
        local nid   = novel.novel_id or ""
        local title = novel.novel_name or ""
        if nid ~= "" and title ~= "" then
            table.insert(result, {
                title = string_clean(title),
                url   = baseUrl .. "novel/" .. nid,
                cover = coverUrl(nid)
            })
        end
    end
    return result
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = apiBase .. "novels?sort=LASTEST&page=" .. tostring(page) .. "&limit=20&status=all&genre=ALL"
    local r = http_get(url)
    if not r.success then
        log_error("novelarrow: getCatalogList failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if not data or not data.items then return { items = {}, hasNext = false } end
    local items = parseNovelItems(data.items)
    local hasNext = data.pagination and (data.pagination.page < data.pagination.totalPages) or (#items >= 20)
    return { items = items, hasNext = hasNext }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = apiBase .. "novels?keyword=" .. url_encode(query) .. "&page=" .. tostring(page) .. "&limit=20"
    local r = http_get(url)
    if not r.success then
        log_error("novelarrow: getCatalogSearch failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    local data = json_parse(r.body)
    if not data or not data.items then return { items = {}, hasNext = false } end
    local items = parseNovelItems(data.items)
    local hasNext = data.pagination and (data.pagination.page < data.pagination.totalPages) or false
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local nid = extractNovelId(bookUrl)
    if not nid then return nil end
    local data = fetchBookData(nid)
    if not data then return nil end
    local title = data.novel_name or ""
    return title ~= "" and string_clean(title) or nil
end

function getBookCoverImageUrl(bookUrl)
    local nid = extractNovelId(bookUrl)
    if not nid then return nil end
    -- Обложка предсказуема по slug, не нужен API-запрос
    return "https://images.novelarrow.com/novel_480_720/" .. nid .. ".jpg"
end

function getBookDescription(bookUrl)
    local nid = extractNovelId(bookUrl)
    if not nid then return nil end
    local data = fetchBookData(nid)
    if not data then return nil end
    local desc = data.novel_desc or ""
    desc = stripHtml(desc)
    return desc ~= "" and desc or nil
end

function getBookGenres(bookUrl)
    local nid = extractNovelId(bookUrl)
    if not nid then return {} end
    local data = fetchBookData(nid)
    if not data then return {} end
    local genres = {}
    if type(data.novel_genres) == "table" then
        for _, g in ipairs(data.novel_genres) do
            local label = string_trim(tostring(g))
            -- Жанры в API в верхнем регистре: "FANTASY" → "Fantasy"
            label = label:sub(1,1):upper() .. label:sub(2):lower()
            if label ~= "" then table.insert(genres, label) end
        end
    end
    return genres
end

-- ── Список глав (parsePage) ───────────────────────────────────────────────────
-- API отдаёт все главы за один запрос (totalPages всегда = 1).
-- parsePage достаточно — getChapterList и getChapterListHash не нужны.

local function fetchChapters(nid)
    local url = apiBase .. "novels/" .. nid .. "/chapters?sort=asc"
    local r = http_get(url)
    if not r.success then
        log_error("novelarrow: chapters API failed novelId=" .. nid .. " code=" .. tostring(r.code))
        return nil
    end
    local data = json_parse(r.body)
    if not data then
        log_error("novelarrow: chapters json_parse failed for novelId=" .. nid)
        return nil
    end
    return data.items or data.chapters or data.data or data
end

function parsePage(bookUrl, page)
    if page > 1 then
        return { chapters = {}, totalPages = 1 }
    end

    local nid = extractNovelId(bookUrl)
    if not nid then
        log_error("novelarrow: parsePage cannot extract novel_id from " .. bookUrl)
        return { chapters = {}, totalPages = 1 }
    end

    local rawChapters = fetchChapters(nid)
    if not rawChapters or type(rawChapters) ~= "table" then
        return { chapters = {}, totalPages = 1 }
    end

    local chapters = {}
    for _, ch in ipairs(rawChapters) do
        local chId    = ch.chapter_id or ""
        local chTitle = ch.chapter_name or ""
        if chId ~= "" then
            if chTitle == "" then chTitle = chId end
            table.insert(chapters, {
                title = string_clean(chTitle),
                url   = baseUrl .. "chapter/" .. nid .. "/" .. chId
            })
        end
    end

    log_info("novelarrow: parsePage loaded " .. tostring(#chapters) .. " chapters for " .. nid)
    return { chapters = chapters, totalPages = 1 }
end

-- ── Текст главы ───────────────────────────────────────────────────────────────
-- Страница главы рендерится JS и пустая.
-- Получаем контент через JSON API по novel_id + chapter_id из URL.

function getChapterText(html, url)
    local nid, chId = extractChapterParts(url)
    if not nid or not chId then
        log_error("novelarrow: getChapterText cannot parse URL: " .. tostring(url))
        return ""
    end

    local apiUrl = apiBase .. "novels/" .. nid .. "/chapters/" .. chId
    local r = http_get(apiUrl)
    if not r.success then
        log_error("novelarrow: chapter content failed " .. nid .. "/" .. chId .. " code=" .. tostring(r.code))
        return ""
    end

    local data = json_parse(r.body)
    if not data then
        log_error("novelarrow: chapter content json_parse failed")
        return ""
    end

    local chapterInfo = data.item and data.item.chapterInfo
    if not chapterInfo then
        log_error("novelarrow: no chapterInfo in response")
        return ""
    end

    local content = chapterInfo.chapter_content or ""
    if content == "" then return "" end

    -- chapter_content — это HTML с <h3>, <p>, <br> и т.д.
    -- Убираем заголовок главы (<h3>) и мусор, потом извлекаем текст
    local cleaned = html_remove(content, "h3", "script", "style", ".ads")
    local text = html_text(cleaned)
    return applyStandardContentTransforms(text)
end

-- ── Фильтры каталога ──────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "LASTEST",
            options = {
                { value = "LASTEST",  label = "Latest Update" },
                { value = "HOT",      label = "Hot"           },
                { value = "POPULAR",  label = "Popular"       },
                { value = "WEEKLY",   label = "Weekly"        },
                { value = "MONTHLY",  label = "Monthly"       },
                { value = "ALL_TIME", label = "All Time"      },
                { value = "NEW",      label = "New"           },
                { value = "RATING",   label = "Rating"        },
                { value = "CHAPTERS", label = "Most Chapters" },
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "All"       },
                { value = "ongoing",   label = "Ongoing"   },
                { value = "completed", label = "Completed" },
            }
        },
        {
            type         = "select",
            key          = "genre_mode",
            label        = "Genre Mode",
            defaultValue = "AND",
            options = {
                { value = "AND", label = "AND (all selected)" },
                { value = "OR",  label = "OR (any selected)"  },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "ACTION",        label = "Action"        },
                { value = "ADULT",         label = "Adult"         },
                { value = "ADVENTURE",     label = "Adventure"     },
                { value = "COMEDY",        label = "Comedy"        },
                { value = "DRAMA",         label = "Drama"         },
                { value = "EASTERN",       label = "Eastern"       },
                { value = "FAN-FICTION",   label = "Fan-fiction"   },
                { value = "FANTASY",       label = "Fantasy"       },
                { value = "GAME",          label = "Game"          },
                { value = "GENDER-BENDER", label = "Gender Bender" },
                { value = "HAREM",         label = "Harem"         },
                { value = "HISTORICAL",    label = "Historical"    },
                { value = "HORROR",        label = "Horror"        },
                { value = "ISEKAI",        label = "Isekai"        },
                { value = "JOSEI",         label = "Josei"         },
                { value = "LITRPG",        label = "LitRPG"        },
                { value = "MAGIC",         label = "Magic"         },
                { value = "MARTIAL-ARTS",  label = "Martial Arts"  },
                { value = "MATURE",        label = "Mature"        },
                { value = "MECHA",         label = "Mecha"         },
                { value = "MILITARY",      label = "Military"      },
                { value = "MODERN-LIFE",   label = "Modern Life"   },
                { value = "MYSTERY",       label = "Mystery"       },
                { value = "PSYCHOLOGICAL", label = "Psychological" },
                { value = "REINCARNATION", label = "Reincarnation" },
                { value = "ROMANCE",       label = "Romance"       },
                { value = "SCHOOL-LIFE",   label = "School Life"   },
                { value = "SCI-FI",        label = "Sci-fi"        },
                { value = "SEINEN",        label = "Seinen"        },
                { value = "SHOUJO",        label = "Shoujo"        },
                { value = "SHOUNEN",       label = "Shounen"       },
                { value = "SLICE-OF-LIFE", label = "Slice of Life" },
                { value = "SMUT",          label = "Smut"          },
                { value = "SPORTS",        label = "Sports"        },
                { value = "SUPERNATURAL",  label = "Supernatural"  },
                { value = "SYSTEM",        label = "System"        },
                { value = "THRILLER",      label = "Thriller"      },
                { value = "TRAGEDY",       label = "Tragedy"       },
                { value = "URBAN-LIFE",    label = "Urban Life"    },
                { value = "WAR",           label = "War"           },
                { value = "WUXIA",         label = "Wuxia"         },
                { value = "XIANXIA",       label = "Xianxia"       },
                { value = "XUANHUAN",      label = "Xuanhuan"      },
                { value = "YAOI",          label = "Yaoi"          },
                { value = "YURI",          label = "Yuri"          },
            }
        },
    }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page       = index + 1
    local sort       = filters["sort"]       or "LASTEST"
    local status     = filters["status"]     or "all"
    local genre_mode = filters["genre_mode"] or "AND"
    local genres_inc = filters["genres_included"] or {}
    local genres_exc = filters["genres_excluded"] or {}

    local url = apiBase .. "novels?page=" .. tostring(page) .. "&limit=20"
               .. "&sort="       .. url_encode(sort)
               .. "&status="     .. url_encode(status)
               .. "&genre_mode=" .. url_encode(genre_mode)

    for _, g in ipairs(genres_inc) do
        url = url .. "&genres=" .. url_encode(g)
    end
    for _, g in ipairs(genres_exc) do
        url = url .. "&genres_exclude=" .. url_encode(g)
    end

    local r = http_get(url)
    if not r.success then
        log_error("novelarrow: getCatalogFiltered failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    local data = json_parse(r.body)
    if not data or not data.items then return { items = {}, hasNext = false } end

    local items = parseNovelItems(data.items)
    local hasNext = data.pagination and (data.pagination.page < data.pagination.totalPages) or (#items >= 20)
    return { items = items, hasNext = hasNext }
end