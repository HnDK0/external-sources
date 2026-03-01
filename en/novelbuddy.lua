-- NovelBuddy Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "novelbuddy",
    name = "NovelBuddy",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://novelbuddy.io",
    -- icon will be loaded from yaml config

    -- Catalog: Most Views
    getCatalogList = function(index)
        local url = "https://novelbuddy.io/search?sort=views"
        if index > 0 then
            url = url .. "&page=" .. (index + 1)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".book-detailed-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".title")[1]
            local urlElem = html_select(item, "h3 a")[1]
            local coverElem = html_select(item, ".thumb img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
                })
            end
        end
        
        return {
            items = books,
            hasNext = #books > 0
        }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://novelbuddy.io/search?q=" .. url_encode(input)
        if index > 0 then
            url = url .. "&page=" .. (index + 1)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".book-detailed-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".title")[1]
            local urlElem = html_select(item, "h3 a")[1]
            local coverElem = html_select(item, ".thumb img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
                })
            end
        end
        
        return {
            items = books,
            hasNext = #books > 0
        }
    end,

    -- Book Details
    getBookTitle = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local title = html_select(doc, "h1")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".img-cover img")[1]
        return img and (img:attr("data-src") or img.src) or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".section-body.summary .content")[1]
        if desc then
            desc:remove("h3")
            return desc:get_text()
        end
        return nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        
        -- Extract bookId from scripts
        local bookId = string.match(res.body, "bookId%s*=%s*(%d+)")
        if not bookId then return {} end
        
        local ajaxUrl = "https://novelbuddy.io/api/manga/" .. bookId .. "/chapters?source=detail"
        local ajaxRes = http_get(ajaxUrl)
        if not ajaxRes.success then return {} end
        
        local ajaxDoc = html_parse(ajaxRes.body)
        local items = html_select(ajaxDoc, "li")
        local chapters = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "strong.chapter-title")[1]
            local linkElem = html_select(item, "a")[1]
            if linkElem then
                table.insert(chapters, {
                    title = titleElem and titleElem:get_text() or linkElem:get_text(),
                    url = linkElem.href
                })
            end
        end
        
        -- Reverse to get oldest first (API usually returns newest first)
        local reversed = {}
        for i = #chapters, 1, -1 do
            table.insert(reversed, chapters[i])
        end
        return reversed
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, ".content-inner")[1]
        if content then
            content:remove("script")
            content:remove("#listen-chapter")
            content:remove("#google_translate_element")
            content:remove(".ads")
            content:remove(".advertisement")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local hashElem = html_select(doc, ".meta p:has(strong:contains(Chapters)) span")[1]
        return hashElem and hashElem:get_text() or nil
    end
}
