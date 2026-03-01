-- NovelBin Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "NovelBin",
    name = "NovelBin",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://novelbin.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://novelbin.com/sort/top-view-novel"
        if page > 1 then url = url .. "?page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-novel-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "img[data-src]")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
                    cover = coverElem and coverElem:attr("data-src") or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local page = index + 1
        local url = "https://novelbin.com/search?keyword=" .. url_encode(input)
        if page > 1 then url = url .. "&page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-novel-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "img[src]")[1]
            
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
        local img = html_select(doc, "meta[property='og:image']")[1]
        return img and img:attr("content") or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "div.desc-text")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        
        local novelUrl = html_select(doc, "meta[property=og:url]")[1]
        if not novelUrl then return {} end
        
        local novelId = string.match(novelUrl:attr("content"), "([^/]+)/*$")
        if not novelId then return {} end
        
        local ajaxUrl = "https://novelbin.com/ajax/chapter-archive?novelId=" .. novelId
        local ajaxRes = http_get(ajaxUrl)
        if not ajaxRes.success then return {} end
        
        local ajaxDoc = html_parse(ajaxRes.body)
        local links = html_select(ajaxDoc, "ul.list-chapter li a")
        local chapters = {}
        
        for i = 1, #links do
            table.insert(chapters, {
                title = links[i]:get_text(),
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
            content:remove("h3")
            return html_text(content)
        end
        return ""
    end
}
