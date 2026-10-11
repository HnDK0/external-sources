id       = "novelhall"
name     = "NovelHall"
version  = "1.0.4"
baseUrl  = "https://www.novelhall.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelhall.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead. Shared libs load lazily and are cached per session.
local _libs
local function LIB(id)
    if type(require_lib) ~= "function" then
        show_error("Requires NoveLA update", "This plugin needs the shared libraries")
        error("Requires NoveLA update (require_lib)", 0)
    end
    if not _libs then _libs = {} end
    if not _libs[id] then _libs[id] = require_lib(id) end
    return _libs[id]
end

-- ponytail: кэш страницы книги для переиспользования внутри одного вызова
-- (shared fetch lib кэширует успешные ответы на сессию)
local function fetchBookPage(bookUrl)
    return LIB("fetch").page(bookUrl)
end

local function absUrl(href)
    return LIB("urls").absUrl(baseUrl, href)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Standard chapter-text cleanup (domain lines, leading "Chapter N" heading,
-- translator/editor credit lines) from the shared content lib.
local function applyStandardContentTransforms(text)
    return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = LIB("catalog").nextIndex(index)
    local url = (page == 1) and (baseUrl .. "/completed.html") or (baseUrl .. "/completed-" .. page .. ".html")

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    local links = html_select(r.body, "td.w70 a")
    
    for _, a in ipairs(links) do
        local href = a.href
        if href and href ~= "" and not string.find(href, "javascript") then
            table.insert(items, {
                title = string_clean(a.text),
                url   = absUrl(href),
                cover = ""
            })
        end
    end
    return { 
        items = items, 
        hasNext = LIB("catalog").hasNextPage(items) 
    }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = LIB("catalog").nextIndex(index)
    local url = baseUrl .. "/index.php?s=so&module=book&keyword=" .. url_encode(query)
    if page > 1 then url = url .. "&page=" .. page end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, a in ipairs(html_select(r.body, "td:nth-child(2) a[href]")) do
        table.insert(items, {
            title = string_clean(a.text),
            url   = absUrl(a.href),
            cover = ""
        })
    end
    return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────
-- Session-cached fetch: the engine calls the detail functions in parallel.

function getBookTitle(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, ".book-img.hidden-xs img[src]", "src")
    return (cover ~= "" and absUrl(cover)) or nil
end

function getBookDescription(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "span.js-close-wrap")
    return el and string_trim(el.text) or nil
end

-- ── Статус / Дата обновления ─────────────────────────────────────────────────

function getBookStatus(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    for _, span in ipairs(html_select(body, ".booktag span")) do
        local t = string_trim(span.text)
        local status = t:match("^Status[：:](.+)$")
        if status then return LIB("meta").status(status) end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    local body = fetchBookPage(bookUrl)
    if not body then return nil end
    for _, span in ipairs(html_select(body, ".booktag span")) do
        local t = string_trim(span.text)
        local dateStr = t:match("^UpdateTime[：:](%d%d%d%d%-%d%d%-%d%d)")
        if dateStr then return dateStr end
    end
    return nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, "#morelist a[href]")) do
        table.insert(chapters, {
            title = string_clean(a.text),
            url   = absUrl(a.href)
        })
    end
    return chapters
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".book-catalog li:first-child a")
    return el and el.href or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html, "script")
    local el = html_select_first(cleaned, "div#htmlContent")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return {} end

  -- trim + drop empties — shared meta lib (site order kept).
  return LIB("meta").collectGenres(html_select(body, ".total a"))
end
