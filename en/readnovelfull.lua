-- ReadNovelFull Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "read_novel_full",
    name = "ReadNovelFull",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://readnovelfull.com",
    -- icon will be loaded from yaml config

    -- Catalog: Most Popular
    getCatalogList = function(index)
        local url = "https://readnovelfull.com/novel-list/most-popular-novel"
        if index > 0 then
            url = url .. "?page=" .. (index + 1)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-novel-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "div.col-xs-3 > div > img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
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
        local url = "https://readnovelfull.com/novel-list/search?keyword=" .. url_encode(input)
        if index > 0 then
            url = url .. "&page=" .. (index + 1)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-novel-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "div.col-xs-3 > div > img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
                    cover = coverElem and coverElem.src or ""
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
        local desc = html_select(doc, "#tab-description")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        
        local novelIdElem = html_select(doc, "#rating[data-novel-id]")[1]
        if not novelIdElem then return {} end
        local novelId = novelIdElem:attr("data-novel-id")
        
        local ajaxUrl = "https://readnovelfull.com/ajax/chapter-archive?novelId=" .. novelId
        local ajaxRes = http_get(ajaxUrl)
        if not ajaxRes.success then return {} end
        
        local ajaxDoc = html_parse(ajaxRes.body)
        local links = html_select(ajaxDoc, "a[href]")
        local chapters = {}
        
        for i = 1, #links do
            table.insert(chapters, {
                title = links[i]:attr("title") or links[i]:get_text(),
                url = links[i].href
            })
        end
        return chapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, "#chr-content")[1]
        if content then
            content:remove("script")
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
        local last = html_select(doc, ".l-chapter a.chapter-title")[1]
        return last and last.href or nil
    end
}
