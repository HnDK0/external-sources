-- Twkan Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "twkan",
    name = "Twkan",
    version = "1.0.0",
    language = "zh",
    baseUrl = "https://twkan.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://twkan.com/novels/newhot_2_0_" .. page .. ".html"
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "#article_list_content li")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "h3 a")[1]
            local coverElem = html_select(item, "img")[1]
            
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
        local url = "https://twkan.com/search/" .. url_encode(input) .. "/" .. page .. ".html"
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "#article_list_content li, .search-result li")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "h3 a, h3")[1]
            local urlElem = html_select(item, "a[href*=/book/]")[1]
            local coverElem = html_select(item, "img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
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
        local title = html_select(doc, "h1 a")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".bookimg2 img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "#tab_info .navtxt p")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters: AJAX
    getChapterList = function(url)
        local bookId = string.match(url, "/book/([^.]+).html")
        if not bookId then return {} end
        
        local ajaxUrl = "https://twkan.com/ajax_novels/chapterlist/" .. bookId .. ".html"
        local res = http_get(ajaxUrl)
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "ul li a[href]")
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
        local content = html_select(doc, "#txtcontent0")[1]
        if content then
            content:remove("script")
            content:remove(".txtad")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local last = html_select(doc, ".infolist li:nth-child(2)")[1]
        return last and last:get_text() or nil
    end
}
