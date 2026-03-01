-- AllNovel Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "allnovel",
    name = "AllNovel",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://allnovel.org",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://allnovel.org/latest-release-novel"
        if page > 1 then url = url .. "?page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-truyen-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.col-xs-7 > div > h3 > a")[1]
            local coverElem = html_select(item, "div.col-xs-3 > div > img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local page = index + 1
        local url = "https://allnovel.org/search?keyword=" .. url_encode(input)
        if page > 1 then url = url .. "&page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-truyen-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.col-xs-7 > div > h3 > a")[1]
            local coverElem = html_select(item, "div.col-xs-3 > div > img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
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
        local title = html_select(doc, "h3.title")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".book img[src]")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".desc-text")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        
        -- Get max page
        local lastPageElem = html_select(doc, "#list-chapter > ul:nth-child(3) > li.last > a")[1]
        local maxPage = 1
        if lastPageElem then
            maxPage = tonumber(string.match(lastPageElem.href, "page=(%d+)")) or 1
        end
        
        local allChapters = {}
        for p = 1, maxPage do
            local pageUrl = url .. "?page=" .. p
            local pageRes = http_get(pageUrl)
            if pageRes.success then
                local pageDoc = html_parse(pageRes.body)
                local links = html_select(pageDoc, "ul.list-chapter li a")
                for i = 1, #links do
                    table.insert(allChapters, {
                        title = links[i]:get_text(),
                        url = links[i].href
                    })
                end
            end
        end
        return allChapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, "#chapter-content")[1]
        if content then
            content:remove("script")
            content:remove(".ads")
            content:remove("h3")
            return html_text(content)
        end
        return ""
    end
}
