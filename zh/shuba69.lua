-- Shuba69 Lua Plugin
-- Migrated from Kotlin native source (GBK encoding, POST search)

id       = "shuba69"
name     = "69Shuba"
version  = "1.0.1"
language = "zh"
baseUrl  = "https://www.69shuba.com"

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local url = "https://www.69shuba.com/novels/monthvisit_0_0_" .. tostring(index + 1) .. ".htm"
    local res = http_get(url, { charset = "GBK" })
    if not res.success then return { items = {}, hasNext = false } end
    
    local books = {}
    local items = html_select(res.body, "ul#article_list_content li")
    
    for _, item in ipairs(items) do
        local titleElem = html_select_first(item.html, "div.newnav h3 a")
        local urlElem   = html_select_first(item.html, "a.imgbox")
        
        if titleElem and urlElem then
            table.insert(books, {
                title = string_trim(titleElem.text),
                url   = urlElem.href,
                cover = html_attr(item.html, "img", "data-src")
            })
        end
    end
    
    return { items = books, hasNext = #books > 0 }
end

function getCatalogSearch(index, input)
    if index > 0 then return { items = {}, hasNext = false } end
    
    local searchUrl = "https://www.69shuba.com/modules/article/search.php"
    local body = "searchkey=" .. url_encode_charset(input, "GBK") .. "&searchtype=all"
    
    local res = http_post(searchUrl, body, {
        charset = "GBK",
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
    })
    
    if not res.success then return { items = {}, hasNext = false } end
    
    local books = {}
    local items = html_select(res.body, "div.newbox ul li")
    
    for _, item in ipairs(items) do
        local titleElem = html_select_first(item.html, "h3 a:last-child")
        local urlElem   = html_select_first(item.html, "a.imgbox")
        
        if titleElem and urlElem then
            table.insert(books, {
                title = string_trim(titleElem.text),
                url   = urlElem.href,
                cover = html_attr(item.html, "img", "data-src")
            })
        end
    end
    
    return { items = books, hasNext = false }
end

-- ── Book Details ─────────────────────────────────────────────────────────────

function getBookTitle(url)
    local res = http_get(url, { charset = "GBK" })
    if not res.success then return nil end
    local el = html_select_first(res.body, "div.booknav2 h1 a")
    return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(url)
    local res = http_get(url, { charset = "GBK" })
    if not res.success then return nil end
    return html_attr(res.body, "div.bookimg2 img", "src")
end

function getBookDescription(url)
    local res = http_get(url, { charset = "GBK" })
    if not res.success then return nil end
    local el = html_select_first(res.body, "div.navtxt")
    return el and string_trim(el.text) or nil
end

-- ── Chapters ──────────────────────────────────────────────────────────────────

function getChapterList(url)
    -- Трансформация URL через regex_replace (без двоеточий)
    local listUrl = regex_replace(url, "/txt/", "/")
    listUrl = regex_replace(listUrl, "%.htm", "/")

    local res = http_get(listUrl, { charset = "GBK" })
    if not res.success then return {} end
    
    local links = html_select(res.body, "div#catalog ul li a")
    local chapters = {}
    
    -- Инвертируем список (от старых к новым)
    for i = #links, 1, -1 do
        table.insert(chapters, {
            title = string_trim(links[i].text),
            url   = links[i].href
        })
    end
    return chapters
end

function getChapterText(html)
    -- Очистка контента
    local cleaned = html_remove(html, "h1", "div.txtinfo", "div.bottom-ad", "div.bottem2", ".visible-xs", "script")
    local content = html_select_first(cleaned, "div.txtnav")
    
    return content and html_text(content.html) or ""
end

function getChapterListHash(url)
    local res = http_get(url, { charset = "GBK" })
    if not res.success then return nil end
    local el = html_select_first(res.body, ".infolist li:nth-child(2)")
    return el and string_trim(el.text) or nil
end