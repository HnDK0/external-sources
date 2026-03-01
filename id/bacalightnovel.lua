-- BacaLightnovel Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "baca_lightnovel",
    name = "BacaLightnovel",
    version = "1.0.0",
    language = "id",
    baseUrl = "https://bacalightnovel.co",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://bacalightnovel.co/series/"
        if index > 0 then
            url = url .. "?page=" .. (index + 1) .. "&order=populer"
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".listupd > .maindet .mdthumb a")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            table.insert(books, {
                title = item:attr("title"),
                url = item.href,
                cover = item.src
            })
        end
        
        return {
            items = books,
            hasNext = #books > 0
        }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://bacalightnovel.co/"
        if index == 0 then
            url = url .. "?s=" .. url_encode(input)
        else
            url = url .. "page/" .. (index + 1) .. "/?s=" .. url_encode(input)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".listupd > .maindet .mdthumb a")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            table.insert(books, {
                title = item:attr("title"),
                url = item.href,
                cover = item.src
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
        local title = html_select(doc, "h1.entry-title")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".sertothumb img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".entry-content")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        local links = html_select(doc, ".eplister li > a:not(.dlpdf)")
        local chapters = {}
        
        for i = 1, #links do
            local titleElem = html_select(links[i], ".epl-title")[1]
            table.insert(chapters, {
                title = titleElem and titleElem:get_text() or links[i]:get_text(),
                url = links[i].href
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
        local content = html_select(doc, ".epcontent[itemprop=text] .text-left")[1]
        if content then
            content:remove("script")
            content:remove(".ads")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local last = html_select(doc, ".epcurlast")[1]
        return last and last:get_text() or nil
    end
}
