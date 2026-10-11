-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "shuba69"
name     = "69shuba"
version  = "1.0.4"
baseUrl  = "https://www.69shuba.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/69shuba.png"
charset  = "GBK"

-- ── Вспомогательные функции ─────────────────────────────────────────────────

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

local function absUrl(href)
    return LIB("urls").absUrl(baseUrl, href)
end

-- Session-cached book page in GBK (shared fetch lib): the book details are
-- read by several functions in one adapter run. getChapterListHash stays on a
-- direct http_get — the hash must see a fresh page.
local function fetchPage(url)
    return LIB("fetch").page(url, { charset = "GBK" })
end

-- Standard chapter-text cleanup (domain lines, leading "第N章" heading,
-- translator/editor credit lines) from the shared content lib, plus the
-- site-specific "(本章完)" end marker.
local function applyStandardContentTransforms(text)
    text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
    if text == "" then return "" end
    text = regex_replace(text, "(?im)^\\s*\\(本章完\\)\\s*$", "")
    return string_trim(text)
end

-- ── Каталог ──────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = LIB("catalog").nextIndex(index)
    local url = baseUrl .. "novels/monthvisit_0_0_" .. tostring(page) .. ".htm"
    
    local r = http_get(url, { charset = "GBK" })
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, li in ipairs(html_select(r.body, "ul#article_list_content li")) do
        local titleEl = html_select_first(li.html, "div.newnav h3 a")
        if titleEl then
            local cover = html_attr(li.html, "a.imgbox img", "data-src")
            table.insert(items, {
                title = string_trim(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(cover)
            })
        end
    end

    return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Поиск ───────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end

    local payload = "searchkey=" .. url_encode_charset(query, "GBK") .. "&searchtype=all"
    local r = http_post("https://www.69shuba.com/modules/article/search.php", payload, {
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        charset = "GBK"
    })

    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, li in ipairs(html_select(r.body, "div.newbox ul li")) do
        local titleEl = html_select_first(li.html, "h3 a:last-child")
        if titleEl then
            local cover = html_attr(li.html, "a.imgbox img", "data-src")
            table.insert(items, {
                title = string_trim(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(cover)
            })
        end
    end

    return { items = items, hasNext = false }
end

-- ── Детали книги ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "div.booknav2 h1 a")
    return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "div.bookimg2 img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "div.navtxt")
    return el and string_trim(el.text) or nil
end

-- ── Статус и дата обновления ──────────────────────────────────────────────

-- Статус книги — мета-тег og:novel:status (напр. «連載» / «完結»). Сайт в GBK.
function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local s = html_attr(body, "meta[property='og:novel:status']", "content")
  if s and s ~= "" then return s end
  return nil
end

-- Дата обновления — мета-тег og:novel:update_time (формат «YYYY-MM-DD»).
function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local dt = html_attr(body, "meta[property='og:novel:update_time']", "content")
  if dt and dt ~= "" then
    local d = LIB("meta").normalizeDate(dt)
    if d then return d end
  end
  return nil
end

-- ── Список глав ─────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local id = string.match(bookUrl, "/(%d+)%.htm$")
    if not id then return {} end
    local listUrl = baseUrl .. id .. "/"

    local r = http_get(listUrl, { charset = "GBK" })
    if not r.success then return {} end

    local chapters = {}
    local elements = html_select(r.body, "div#catalog ul li a")
    for i = #elements, 1, -1 do
        local a = elements[i]
        table.insert(chapters, {
            title = string_trim(a.text),
            url   = absUrl(a.href)
        })
    end
    return chapters
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    local el = html_select_first(r.body, ".infolist li:nth-child(2)")
    return el and el.text or nil
end

-- ── Текст главы ─────────────────────────────────────────────────────────────

function getChapterText(html, url)
    -- Движок сам декодирует ответ по charset = "GBK" из метаданных,
    -- html уже в UTF-8 — парсим напрямую

    -- Очистка от мусора
    local cleaned = html_remove(html,
        "h1", "div.txtinfo", "div.bottom-ad", "div.bottem2", ".visible-xs", "script"
    )
    
    local el = html_select_first(cleaned, "div.txtnav")
    if not el then return "" end

    return applyStandardContentTransforms(html_text(el.html))
end