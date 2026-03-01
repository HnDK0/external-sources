-- Ifreedom Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "ifreedom",
    name = "Ifreedom",
    version = "1.0.0",
    language = "ru",
    baseUrl = "https://ifreedom.su",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://ifreedom.su/vse-knigi/?sort=По+рейтингу&bpage=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".booksearch .item-book-slide")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".block-book-slide-title")[1]
            local urlElem = html_select(item, "a")[1]
            local coverElem = html_select(item, "img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://ifreedom.su/vse-knigi/?searchname=" .. url_encode(input) .. "&bpage=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".booksearch .item-book-slide")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".block-book-slide-title")[1]
            local urlElem = html_select(item, "a")[1]
            local coverElem = html_select(item, "img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
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
        local img = html_select(doc, "div.book-img.block-book-slide-img > img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "[data-name=\"Описание\"]")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        local items = html_select(doc, "div.chapterinfo a")
        local chapters = {}
        
        for i = 1, #items do
            table.insert(chapters, {
                title = items[i]:get_text(),
                url = items[i].href
            })
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
        local content = html_select(doc, ".chapter-content")[1]
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
        local hashElem = html_select(doc, "div.book-info-list:has(svg.icon-tabler-list-check) div")[1]
        return hashElem and hashElem:get_text() or nil
    end
}
