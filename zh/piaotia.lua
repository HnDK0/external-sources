-- PiaoTia Lua Plugin
-- Migrated from Kotlin native source (GBK encoding, document.write fix)

return {
    id = "piaotia",
    name = "PiaoTia",
    version = "1.0.0",
    language = "zh",
    baseUrl = "https://www.piaotia.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://www.piaotia.com/modules/article/index.php?fullflag=1&page=" .. (index + 1)
        local res = http_get(url, {}, "GBK")
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "table.grid tr:not(:first-child)")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "td.odd a")[1]
            if titleLink then
                local bookUrl = titleLink.href
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = bookUrl,
                    cover = "" -- covers are dynamic
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search (Handling redirect to book info)
    getCatalogSearch = function(index, input)
        local url = "https://www.piaotia.com/modules/article/search.php?searchtype=articlename&searchkey=" .. url_encode(input, "GBK") .. "&page=" .. (index + 1)
        local res = http_get(url, {}, "GBK")
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        -- If redirected to book info page
        if string.find(res.body, "/bookinfo/") then
            local title = html_select(doc, "div#content h1")[1]
            local books = {{
                title = title and title:get_text() or input,
                url = url, -- The current URL after redirect
                cover = ""
            }}
            return { items = books, hasNext = false }
        end
        
        local items = html_select(doc, "table.grid tr:not(:first-child)")
        local books = {}
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "td.odd a")[1]
            if titleLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = titleLink.href,
                    cover = ""
                })
            end
        end
        return { items = books, hasNext = #books > 0 }
    end,

    -- Book Details
    getBookTitle = function(url)
        local res = http_get(url, {}, "GBK")
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local title = html_select(doc, "div#content h1")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        -- Dynamic cover URL building
        local folderId, bookId = string.match(url, "/(%d+)/(%d+)")
        if folderId and bookId then
            return "https://www.piaotia.com/files/article/image/" .. folderId .. "/" .. bookId .. "/" .. bookId .. "s.jpg"
        end
        return nil
    end,

    getBookDescription = function(url)
        local res = http_get(url, {}, "GBK")
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "div[style*='float:left']")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters (AJAX based)
    getChapterList = function(url)
        local chapterListUrl = url
        if string.find(url, "/bookinfo/") then
            chapterListUrl = url:gsub("/bookinfo/", "/html/"):gsub(".html", "/")
        end
        
        local res = http_get(chapterListUrl, {}, "GBK")
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "div.centent ul li a, div#content ul li a")
        local chapters = {}
        
        for i = 1, #links do
            table.insert(chapters, {
                title = links[i]:get_text(),
                url = url_resolve(chapterListUrl, links[i].href)
            })
        end
        return chapters
    end,

    getChapterText = function(html)
        -- Handle document.write() replacement as in native
        local fixedHtml = html:gsub("<script language=\"javascript\">GetFont%(%);</script>", "<div id=\"content\">")
        fixedHtml = fixedHtml:gsub("<script language=javascript>GetFont%(%);</script>", "<div id=\"content\">")
        
        local doc = html_parse(fixedHtml)
        local content = html_select(doc, "div#content")[1]
        if content then
            content:remove("h1")
            content:remove("script")
            content:remove("div")
            content:remove("table")
            return html_text(content)
        end
        return ""
    end
}
