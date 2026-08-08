id       = "novelhall"
name     = "NovelHall"
version  = "1.0.2"
baseUrl  = "https://www.novelhall.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelhall.png"

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

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
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
        hasNext = #items > 0 
    }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
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
    return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, ".book-img.hidden-xs img[src]", "src")
    return (cover ~= "" and absUrl(cover)) or nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "span.js-close-wrap")
    return el and string_trim(el.text) or nil
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
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local genres = {}
  for _, a in ipairs(html_select(r.body, ".total a")) do
    local label = string_trim(a.text)
    if label ~= "" then table.insert(genres, label) end
  end
  return genres
end
