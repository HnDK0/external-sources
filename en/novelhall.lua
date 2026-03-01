-- NovelHall Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "novelhall",
    name = "NovelHall",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://www.novelhall.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://www.novelhall.com/completed.html"
        if page > 1 then
            url = "https://www.novelhall.com/completed-" .. page .. ".html"
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "table tbody tr")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "td.w70 a[href]")[1]
            if titleLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = titleLink.href,
                    cover = "" -- No cover in catalog
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
        local page = index + 1
        local url = "https://www.novelhall.com/index.php?s=so&module=book&keyword=" .. url_encode(input)
        if page > 1 then
            url = url .. "&page=" .. page
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "td:nth-child(2) a[href]")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            table.insert(books, {
                title = item:get_text(),
                url = item.href,
                cover = ""
            })
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
        local img = html_select(doc, ".book-img.hidden-xs img[src]")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "span.js-close-wrap")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        local links = html_select(doc, "#morelist a[href]")
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
        local content = html_select(doc, "div#htmlContent")[1]
        if content then
            content:remove("script")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local first = html_select(doc, ".book-catalog li:first-child a")[1]
        return first and first.href or nil
    end
}
