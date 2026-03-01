-- NovLove Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "NovLove",
    name = "NovLove",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://novlove.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://novlove.com/sort/nov-love-daily-update"
        if page > 1 then url = url .. "?page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-novel-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "img.cover")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local page = index + 1
        local url = "https://novlove.com/search?keyword=" .. url_encode(input)
        if page > 1 then url = url .. "&page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".col-novel-main .row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "img.cover")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
                    cover = coverElem and (coverElem.src or coverElem:attr("data-src")) or ""
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
        local img = html_select(doc, "meta[itemprop=image]")[1]
        return img and img:attr("content") or nil
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
        -- Extract novelId from URL (slug)
        local novelId = string.match(url, "([^/]+)/*$")
        if not novelId then return {} end
        
        local ajaxUrl = "https://novlove.com/ajax/chapter-archive?novelId=" .. novelId
        local res = http_get(ajaxUrl)
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "a[href*='/chapter']")
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
            content:remove(".social-share")
            return html_text(content)
        end
        return ""
    end
}
