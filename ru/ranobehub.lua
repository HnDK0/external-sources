-- RanobeHub Lua Plugin
-- Migrated from Kotlin hardcoded RanobeHub.kt

return {
    id = "ranobehub",
    name = "RanobeHub (Lua)",
    version = "1.0.0",
    language = "ru",
    baseUrl = "https://ranobehub.org",
    -- icon will be loaded from yaml config

    -- Catalog: Search by rating
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://ranobehub.org/api/search?page=" .. page .. "&sort=computed_rating&status=0&take=40"
        
        local response = http_get(url)
        if not response.success then
            return { items = {}, hasNext = false }
        end
        
        local data = json_parse(response.body)
        local resource = data.resource or {}
        local books = {}
        
        for i = 1, #resource do
            local item = resource[i]
            local names = item.names or {}
            local title = names.rus or names.eng or names.original or item.name
            
            if title and item.id then
                table.insert(books, {
                    title = title,
                    url = "https://ranobehub.org/ranobe/" .. item.id,
                    cover = item.poster and item.poster.medium or ""
                })
            end
        end
        
        return {
            items = books,
            hasNext = #books > 0
        }
    end,

    -- Search: Fulltext
    getCatalogSearch = function(index, input)
        if index > 0 or input == "" then return { items = {}, hasNext = false } end
        
        local query = url_encode(input)
        local url = "https://ranobehub.org/api/fulltext/global?query=" .. query .. "&take=10"
        
        local response = http_get(url)
        if not response.success then return { items = {}, hasNext = false } end
        
        local results = json_parse(response.body) or {}
        local books = {}
        
        for i = 1, #results do
            local res = results[i]
            if res.meta and res.meta.key == "ranobe" then
                local data = res.data or {}
                for j = 1, #data do
                    local item = data[j]
                    local names = item.names or {}
                    local title = names.rus or names.eng or names.original or item.name
                    
                    if title and item.id then
                        table.insert(books, {
                            title = title,
                            url = "https://ranobehub.org/ranobe/" .. item.id,
                            cover = item.image and string.gsub(item.image, "/small", "/medium") or ""
                        })
                    end
                end
            end
        end
        
        return { items = books, hasNext = false }
    end,

    -- Book Details
    getBookTitle = function(bookUrl)
        local id = string.match(bookUrl, "/ranobe/(%d+)")
        if not id then return nil end
        
        local res = http_get("https://ranobehub.org/api/ranobe/" .. id)
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        local names = data.names or {}
        return names.rus or names.eng or names.original or data.name
    end,

    getBookCoverImageUrl = function(bookUrl)
        local id = string.match(bookUrl, "/ranobe/(%d+)")
        if not id then return nil end
        
        local res = http_get("https://ranobehub.org/api/ranobe/" .. id)
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        local posters = data.posters or {}
        return posters.medium
    end,

    getBookDescription = function(bookUrl)
        local id = string.match(bookUrl, "/ranobe/(%d+)")
        if not id then return nil end
        
        local res = http_get("https://ranobehub.org/api/ranobe/" .. id)
        if not res.success then return nil end
        
        local data = json_parse(res.body).data or {}
        local desc = data.description or ""
        return string.gsub(desc, "<[^>]*>", "")
    end,

    -- Chapters
    getChapterList = function(bookUrl)
        local id = string.match(bookUrl, "/ranobe/(%d+)")
        if not id then return {} end
        
        local res = http_get("https://ranobehub.org/api/ranobe/" .. id .. "/contents")
        if not res.success then return {} end
        
        local data = json_parse(res.body)
        local volumes = data.volumes or {}
        local chapters = {}
        
        for i = 1, #volumes do
            local vol = volumes[i]
            local volNum = vol.num or 0
            local volChapters = vol.chapters or {}
            
            for j = 1, #volChapters do
                local chap = volChapters[j]
                local chapNum = chap.num or 0
                table.insert(chapters, {
                    title = chap.name or ("Глава " .. chapNum),
                    url = "https://ranobehub.org/ranobe/" .. id .. "/" .. volNum .. "/" .. chapNum
                })
            end
        end
        return chapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, ".ui.text.container")[1] 
                     or html_select(doc, ".text")[1]
                     or html_select(doc, ".content")[1]
        
        if content then
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(bookUrl)
        local id = string.match(bookUrl, "/ranobe/(%d+)")
        if not id then return nil end
        
        local res = http_get("https://ranobehub.org/api/ranobe/" .. id .. "/contents")
        if not res.success then return nil end
        
        local data = json_parse(res.body)
        local volumes = data.volumes or {}
        local lastVol = volumes[#volumes]
        if lastVol and lastVol.chapters then
            local lastChap = lastVol.chapters[#lastVol.chapters]
            return lastChap and tostring(lastChap.num)
        end
        return nil
    end
}
