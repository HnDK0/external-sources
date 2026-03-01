-- Novel543 Lua Plugin
-- Migrated from Kotlin native source (Sub-page recursive text joining)

return {
    id = "novel543",
    name = "Novel543",
    version = "1.0.0",
    language = "zh",
    baseUrl = "https://www.novel543.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://www.novel543.com/bookstack/?page=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "ul.list li.media")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "div.media-content h3 a")[1]
            local coverImg = html_select(item, "div.media-left img")[1]
            local urlLink = html_select(item, "div.media-left a")[1]
            
            if titleLink and urlLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = urlLink.href,
                    cover = coverImg and coverImg.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        if index > 0 then return { items = {}, hasNext = false } end
        local url = "https://www.novel543.com/search/" .. url_encode(input)
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "ul.list li.media")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "div.media-content h3 a")[1]
            local coverImg = html_select(item, "div.media-left img")[1]
            local urlLink = html_select(item, "div.media-left a")[1]
            
            if titleLink and urlLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = urlLink.href,
                    cover = coverImg and coverImg.src or ""
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
        local title = html_select(doc, "h1.title")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".cover img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "div.intro")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters (AJAX /dir)
    getChapterList = function(url)
        local dirUrl = url:gsub("/+$", "") .. "/dir"
        local res = http_get(dirUrl)
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "ul.all li a")
        local chapters = {}
        
        for i = 1, #links do
            table.insert(chapters, {
                title = links[i]:get_text(),
                url = url_resolve("https://www.novel543.com/", links[i].href)
            })
        end
        return chapters
    end,

    getChapterText = function(html)
        -- In Lua we can't easily do recursive network requests inside getChapterText 
        -- because it's usually called on already downloaded HTML.
        -- However, we can try to join pages if we were to handle download in getChapterText.
        -- For now, we implement basic text extraction as in other sources.
        local doc = html_parse(html)
        local content = html_select(doc, "div.content")[1]
        if content then
            content:remove("div.gadBlock")
            content:remove("script")
            content:remove("ins")
            content:remove(".ads")
            content:remove(".ad")
            content:remove("p:contains(溫馨提示)")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local meta = html_select(doc, "p.meta span.iconf:last-child")[1]
        return meta and meta:get_text() or nil
    end
}
