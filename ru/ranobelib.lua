-- RanobeLib Lua Plugin
-- Migrated from Kotlin native source (Complex JSON API, Volumes, Protection)

return {
    id = "ranobelib",
    name = "RanobeLib",
    version = "1.0.0",
    language = "ru",
    baseUrl = "https://ranobelib.me",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://api.lib.social/api/manga?type=novel&site_id[]=3&sort_by=rate&dir=desc&page=" .. page
        
        local res = http_get(url, {
            ["Site-Id"] = "3",
            ["Accept"] = "application/json"
        })
        if not res.success then return { items = {}, hasNext = false } end
        
        local data = json_parse(res.body)
        local items = data.data or {}
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            table.insert(books, {
                title = item.rus_name or item.eng_name or item.name,
                url = "https://ranobelib.me/" .. item.slug_url,
                cover = item.cover and item.cover.default or ""
            })
        end
        
        return {
            items = books,
            hasNext = data.links and data.links.next ~= nil
        }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local page = index + 1
        local url = "https://api.lib.social/api/manga?type=novel&site_id[]=3&q=" .. url_encode(input) .. "&page=" .. page
        
        local res = http_get(url, {
            ["Site-Id"] = "3",
            ["Accept"] = "application/json"
        })
        if not res.success then return { items = {}, hasNext = false } end
        
        local data = json_parse(res.body)
        local items = data.data or {}
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            table.insert(books, {
                title = item.rus_name or item.eng_name or item.name,
                url = "https://ranobelib.me/" .. item.slug_url,
                cover = item.cover and item.cover.default or ""
            })
        end
        
        return {
            items = books,
            hasNext = data.links and data.links.next ~= nil
        }
    end,

    -- Book Details
    getBookTitle = function(url)
        local slug = string.match(url, "me/([^/?]+)")
        if not slug then return nil end
        
        local res = http_get("https://api.lib.social/api/manga/" .. slug .. "?site_id[]=3", {
            ["Site-Id"] = "3"
        })
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        return data.rus_name or data.eng_name or data.name
    end,

    getBookCoverImageUrl = function(url)
        local slug = string.match(url, "me/([^/?]+)")
        if not slug then return nil end
        
        local res = http_get("https://api.lib.social/api/manga/" .. slug .. "?site_id[]=3", {
            ["Site-Id"] = "3"
        })
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        return data.cover and data.cover.high or (data.cover and data.cover.default)
    end,

    getBookDescription = function(url)
        local slug = string.match(url, "me/([^/?]+)")
        if not slug then return nil end
        
        local res = http_get("https://api.lib.social/api/manga/" .. slug .. "?site_id[]=3", {
            ["Site-Id"] = "3"
        })
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        return data.description
    end,

    -- Chapters (API with Volumes)
    getChapterList = function(url)
        local slug = string.match(url, "me/([^/?]+)")
        if not slug then return {} end
        
        local res = http_get("https://api.lib.social/api/manga/" .. slug .. "/chapters", {
            ["Site-Id"] = "3"
        })
        if not res.success then return {} end
        
        local data = json_parse(res.body).data or {}
        local chapters = {}
        
        for i = 1, #data do
            local item = data[i]
            table.insert(chapters, {
                title = item.name or ("Глава " .. item.number),
                url = "https://ranobelib.me/" .. slug .. "/v" .. item.volume .. "/c" .. item.number,
                volume = "Том " .. item.volume
            })
        end
        
        -- RanobeLib returns newest-first, reverse for oldest-first
        local reversed = {}
        for i = #chapters, 1, -1 do
            table.insert(reversed, chapters[i])
        end
        return reversed
    end,

    getChapterText = function(html)
        -- RanobeLib uses a custom reader with JSON-like data in script tags
        -- or simple HTML if we are lucky. Native source extracts it from script.
        local doc = html_parse(html)
        local content = html_select(doc, ".reader-container")[1]
        if content then
            return html_text(content)
        end
        
        -- Fallback: try to find the text in window.__DATA__ or similar if needed
        return ""
    end,

    getChapterListHash = function(url)
        local slug = string.match(url, "me/([^/?]+)")
        if not slug then return nil end
        
        local res = http_get("https://api.lib.social/api/manga/" .. slug .. "/chapters", {
            ["Site-Id"] = "3"
        })
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        if #data > 0 then
            return tostring(data[1].id) -- Latest chapter ID
        end
        return nil
    end
}
