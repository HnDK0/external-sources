-- NoBadNovel Lua Plugin
-- Migrated from Kotlin native source (CSS selector escaping fix)

return {
    id = "nobadnovel",
    name = "NoBadNovel",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://www.nobadnovel.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://www.nobadnovel.com/series"
        if page > 1 then
            url = url .. "/page/" .. page
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".grid > div")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "h4 a")[1]
            local coverImg = html_select(item, "img[src]")[1]
            if titleLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = titleLink.href,
                    cover = coverImg and coverImg.src or ""
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
        local url = "https://www.nobadnovel.com/series?keyword=" .. url_encode(input)
        if page > 1 then
            url = "https://www.nobadnovel.com/series/page/" .. page .. "?keyword=" .. url_encode(input)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".grid > div")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "h4 a")[1]
            local coverImg = html_select(item, "img[src]")[1]
            if titleLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = titleLink.href,
                    cover = coverImg and coverImg.src or ""
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
        local img = html_select(doc, "img[src*=cdn.nobadnovel]")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "#intro .content")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        local links = html_select(doc, ".chapter-list a[href]")
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
        -- Escape backslash for Sm:text-lg -> sm\\:text-lg in Jsoup
        local content = html_select(doc, "div.text-base.sm\\:text-lg, div[class*=text-base]")[1]
        if content then
            content:remove("script")
            content:remove(".ads")
            content:remove(".adblock-service")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local last = html_select(doc, ".chapter-list li:last-child a")[1]
        return last and last.href or nil
    end
}
