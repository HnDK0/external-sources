-- Bookhamster Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "bookhamster",
    name = "Bookhamster",
    version = "1.0.0",
    language = "ru",
    baseUrl = "https://bookhamster.ru",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://bookhamster.ru/vse-knigi/?sort=По+рейтингу&bpage=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "div.one-book-home")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.title-home a")[1]
            local coverElem = html_select(item, "div.img-home > a > img")[1]
            local urlElem = html_select(item, "div.img-home > a")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and coverElem.src or ""
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
        if index > 0 then return { items = {}, hasNext = false } end
        local url = "https://bookhamster.ru/vse-knigi/?searchname=" .. url_encode(input) .. "&bpage=1"
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "div.one-book-home")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.title-home a")[1]
            local coverElem = html_select(item, "div.img-home > a > img")[1]
            local urlElem = html_select(item, "div.img-home > a")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = false }
    end,

    -- Book Details
    getBookTitle = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local title = html_select(doc, "h1.entry-title")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, "div.img-ranobe > img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "meta[name=description]")[1]
        return desc and desc:attr("content") or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        local items = html_select(doc, ".li-ranobe")
        local chapters = {}
        
        for i = 1, #items do
            local item = items[i]
            local link = html_select(item, ".li-col1-ranobe a")[1]
            if link then
                table.insert(chapters, {
                    title = link:get_text(),
                    url = link.href
                })
            end
        end
        -- Reverse to get oldest first
        local reversed = {}
        for i = #chapters, 1, -1 do
            table.insert(reversed, chapters[i])
        end
        return reversed
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, ".entry-content")[1]
        if content then
            content:remove("script")
            content:remove(".ads")
            content:remove(".pc-adv")
            content:remove(".mob-adv")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local last = html_select(doc, ".data-value")[1]
        return last and last:get_text() or nil
    end
}
