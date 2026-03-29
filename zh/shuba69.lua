-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "shuba69"
name     = "69shuba"
version  = "1.0.1"
baseUrl  = "https://www.69shuba.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/69shuba.png"
charset  = "GBK"

-- ── Вспомогательные функции ─────────────────────────────────────────────────

local function absUrl(href)
    if href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((第[\\d一二三四五六七八九十百]+[章节]|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*\\(本章完\\)\\s*$", "")
    text = string_trim(text)
    return text
end

-- ── Каталог ──────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
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

    return { items = items, hasNext = #items > 0 }
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
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    local el = html_select_first(r.body, "div.booknav2 h1 a")
    return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    local cover = html_attr(r.body, "div.bookimg2 img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl, { charset = "GBK" })
    if not r.success then return nil end
    local el = html_select_first(r.body, "div.navtxt")
    return el and string_trim(el.text) or nil
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

function getChapterText(html)
    -- Пытаемся получить URL текущей страницы из HTML
    local pageUrl = html_attr(html, "link[rel='canonical']", "href")
    if pageUrl == "" then
        pageUrl = html_attr(html, "meta[property='og:url']", "content")
    end

    -- Если нашли URL — перезагружаем страницу с правильной кодировкой
    if pageUrl ~= "" then
        local r = http_get(pageUrl, { charset = "GBK" })
        if r.success then
            html = r.body
        end
    end

    -- Очистка от мусора
    local cleaned = html_remove(html,
        "h1", "div.txtinfo", "div.bottom-ad", "div.bottem2", ".visible-xs", "script"
    )
    
    local el = html_select_first(cleaned, "div.txtnav")
    if not el then return "" end

    return applyStandardContentTransforms(html_text(el.html))
end