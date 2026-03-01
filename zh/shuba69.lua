-- Shuba69 Lua Plugin
-- Migrated from Kotlin native source (GBK encoding, POST search)

return {
    id = "shuba69",
    name = "69Shuba",
    version = "1.0.0",
    language = "zh",
    baseUrl = "https://www.69shuba.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://www.69shuba.com/novels/monthvisit_0_0_" .. (index + 1) .. ".htm"
        local res = http_get(url, {}, "GBK")
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "ul[id=\"article_list_content\"] li")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.newnav h3 a")[1]
            local urlElem = html_select(item, "a.imgbox")[1]
            local coverElem = html_select(item, "img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search (POST with GBK)
    getCatalogSearch = function(index, input)
        if index > 0 then return { items = {}, hasNext = false } end
        
        local searchUrl = "https://www.69shuba.com/modules/article/search.php"
        local body = "searchkey=" .. url_encode(input, "GBK") .. "&searchtype=all"
        
        local res = http_post(searchUrl, body, {
            charset = "GBK",
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded"
            }
        })
        
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "div.newbox ul li")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "h3 a:last-child")[1]
            local urlElem = html_select(item, "a.imgbox")[1]
            local coverElem = html_select(item, "img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
                })
            end
        end
        
        return { items = books, hasNext = false }
    end,

    -- Book Details
    getBookTitle = function(url)
        local res = http_get(url, {}, "GBK")
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local title = html_select(doc, "div.booknav2 h1 a")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url, {}, "GBK")
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, "div.bookimg2 img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url, {}, "GBK")
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "div.navtxt")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local chapterListUrl = url:gsub("/txt/", "/"):gsub(".htm", "/")
        local res = http_get(chapterListUrl, {}, "GBK")
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "div#catalog ul li a")
        local chapters = {}
        
        for i = 1, #links do
            table.insert(chapters, {
                title = links[i]:get_text(),
                url = url_resolve(baseUrl, links[i].href)
            })
        end
        
        -- Reverse to get oldest first (site is newest-first)
        local reversed = {}
        for i = #chapters, 1, -1 do
            table.insert(reversed, chapters[i])
        end
        return reversed
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, "div.txtnav")[1]
        if content then
            content:remove("h1")
            content:remove("div.txtinfo")
            content:remove("div.bottom-ad")
            content:remove("div.bottem2")
            content:remove(".visible-xs")
            content:remove("script")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url, {}, "GBK")
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local last = html_select(doc, ".infolist li:nth-child(2)")[1]
        return last and last:get_text() or nil
    end
}
