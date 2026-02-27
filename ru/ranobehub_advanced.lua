-- Advanced RanobeHub Lua Plugin
-- Supports API-based catalog, search, and chapter fetching

return {
    id = "ranobehub_advanced",
    name = "RanobeHub (Advanced)",
    version = "2.0.0",
    language = "ru",
    baseUrl = "https://ranobehub.org",
    
    -- Advanced features
    requiresPost = false,
    hasPagination = true,
    requiresTranslation = false,
    apiEndpoints = {"ranobe/", "ranobe/", "ranobe/", "ranobe/contents"},
    
    -- API base URL
    apiBase = "https://ranobehub.org/api/",
    
    -- Catalog functions using API
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://ranobehub.org/api/search?page=" .. page .. "&sort=computed_rating&status=0&take=40"
        
        local response = http_get(url)
        if not response.success then
            return {items = {}, hasNext = false, error = response.body}
        end
        
        local data = json_parse(response.body)
        if not data.resource then
            return {items = {}, hasNext = false}
        end
        
        local books = {}
        for i = 1, #data.resource do
            local novel = data.resource[i]
            
            -- Handle multiple name fields
            local title = nil
            if novel.names then
                title = novel.names.rus or novel.names.eng or novel.names.original
            end
            title = title or novel.name
            
            local id = novel.id
            local poster = nil
            if novel.poster then
                poster = novel.poster.medium
            end
            
            if title and id then
                local book = {
                    title = title,
                    url = "https://ranobehub.org/ranobe/" .. id,
                    cover = poster or ""
                }
                table.insert(books, book)
            end
        end
        
        return {
            items = books,
            hasNext = #books > 0,
            lastPage = page
        }
    end,
    
    -- Search using fulltext API
    getCatalogSearch = function(index, input)
        if index > 0 or input == "" then
            return {items = {}, hasNext = false}
        end
        
        local query = url_encode(input)
        local url = "https://ranobehub.org/api/fulltext/global?query=" .. query .. "&take=10"
        
        local response = http_get(url)
        if not response.success then
            return {items = {}, hasNext = false, error = response.body}
        end
        
        local results = json_parse(response.body)
        local books = {}
        
        for i = 1, #results do
            local result = results[i]
            if result.meta and result.meta.key == "ranobe" and result.data then
                for j = 1, #result.data do
                    local novel = result.data[j]
                    
                    -- Handle multiple name fields
                    local title = nil
                    if novel.names then
                        title = novel.names.rus or novel.names.eng or novel.names.original
                    end
                    title = title or novel.name
                    
                    local id = novel.id
                    local image = novel.image and string.gsub(novel.image, "/small", "/medium") or ""
                    
                    if title and id then
                        local book = {
                            title = title,
                            url = "https://ranobehub.org/ranobe/" .. id,
                            cover = image or ""
                        }
                        table.insert(books, book)
                    end
                end
            end
        end
        
        return {
            items = books,
            hasNext = false
        }
    end,
    
    -- Book information using API
    getBookTitle = function(bookUrl)
        local id = extractId(bookUrl)
        if not id then return nil end
        
        local url = "https://ranobehub.org/api/ranobe/" .. id
        local response = http_get(url)
        if not response.success then return nil end
        
        local data = json_parse(response.body)
        if not data.data then return nil end
        
        local names = data.data.names
        return names.rus or names.eng or names.original or data.data.name
    end,
    
    getBookCoverImageUrl = function(bookUrl)
        local id = extractId(bookUrl)
        if not id then return nil end
        
        local url = "https://ranobehub.org/api/ranobe/" .. id
        local response = http_get(url)
        if not response.success then return nil end
        
        local data = json_parse(response.body)
        if not data.data or not data.data.posters then return nil end
        
        return data.data.posters.medium
    end,
    
    getBookDescription = function(bookUrl)
        local id = extractId(bookUrl)
        if not id then return nil end
        
        local url = "https://ranobehub.org/api/ranobe/" .. id
        local response = http_get(url)
        if not response.success then return nil end
        
        local data = json_parse(response.body)
        if not data.data then return nil end
        
        local description = data.data.description
        if description then
            -- Remove HTML tags
            description = regex_match(description, "<[^>]*>"):gsub("", "")
        end
        return description
    end,
    
    -- Chapter list using API with volume support
    getChapterList = function(bookUrl)
        local id = extractId(bookUrl)
        if not id then return {} end
        
        local url = "https://ranobehub.org/api/ranobe/" .. id .. "/contents"
        local response = http_get(url)
        if not response.success then return {} end
        
        local data = json_parse(response.body)
        if not data.volumes then return {} end
        
        local chapters = {}
        local chapterIndex = 1
        
        -- Process all volumes
        for i = 1, #data.volumes do
            local volume = data.volumes[i]
            local volumeNum = volume.num or 0
            
            if volume.chapters then
                for j = 1, #volume.chapters do
                    local chapter = volume.chapters[j]
                    local chapterNum = chapter.num or 0
                    
                    local chapterData = {
                        title = (chapterNum or j) .. ": " .. (chapter.name or "Chapter " .. (chapterNum or j)),
                        url = "https://ranobehub.org/ranobe/" .. id .. "/" .. volumeNum .. "/" .. chapterNum
                    }
                    table.insert(chapters, chapterData)
                    chapterIndex = chapterIndex + 1
                end
            end
        end
        
        return chapters
    end,
    
    -- Advanced chapter text extraction
    getChapterText = function(html)
        -- Find the content section
        local indexA = string.find(html, "<div class=\"title-wrapper\">", 1, true)
        local indexB = string.find(html, "<div class=\"ui text container\"", indexA or 1, true)
        
        if indexA and indexB then
            local chapterHtml = string.sub(html, indexA, indexB - 1)
            
            -- Replace media IDs with proper URLs
            chapterHtml = regex_match(chapterHtml, "<img data%-media%-id=\"(.*?)\".*?>"):gsub(
                "<img src=\"/api/media/%1\">"
            )
            
            -- Parse the processed HTML
            local doc = html_parse(chapterHtml)
            local body = doc.body
            
            if body then
                -- Remove unwanted elements
                local unwanted = {"script", ".ads", ".advertisement", ".title-wrapper"}
                for i = 1, #unwanted do
                    local elements = html_select(body, unwanted[i])
                    for j = 1, #elements do
                        elements[j]:remove()
                    end
                end
                
                -- Look for actual content with multiple selectors
                local contentSelectors = {
                    ".text",
                    ".content", 
                    ".chapter-content",
                    ".reader-text",
                    "[class*='text']",
                    "[class*='content']",
                    ".ui.text.container p"
                }
                
                for i = 1, #contentSelectors do
                    local contentElement = html_select(body, contentSelectors[i])[1]
                    if contentElement and contentElement.text and contentElement.text ~= "" then
                        return contentElement.text
                    end
                end
                
                -- Fallback to the whole body
                local text = body.text
                if text and text ~= "" then
                    return text
                end
            end
            
            -- Final fallback
            local parsed = html_parse(chapterHtml)
            local fallbackBody = parsed.body
            return fallbackBody and fallbackBody.text or chapterHtml
        else
            return ""
        end
    end,
    
    getChapterListHash = function(bookUrl)
        local id = extractId(bookUrl)
        if not id then return nil end
        
        local url = "https://ranobehub.org/api/ranobe/" .. id .. "/contents"
        local response = http_get(url)
        if not response.success then return nil end
        
        local data = json_parse(response.body)
        if not data.volumes then return nil end
        
        -- Get last volume and last chapter
        local lastVolume = data.volumes[#data.volumes]
        if not lastVolume or not lastVolume.chapters then return nil end
        
        local lastChapter = lastVolume.chapters[#lastVolume.chapters]
        return lastChapter and lastChapter.num or nil
    end,
    
    -- Helper functions
    extractId = function(url)
        local path = string.gsub(url, "https://ranobehub.org", "")
        path = string.gsub(path, "^/", "")
        local parts = {}
        
        for part in string.gmatch(path, "([^/]+)") do
            table.insert(parts, part)
        end
        
        return parts[2] -- Second part after "ranobe"
    end,
    
    -- Additional utility functions for RanobeHub specifics
    cleanText = function(text)
        if not text then return "" end
        
        -- Remove HTML tags
        text = regex_match(text, "<[^>]*>"):gsub("", "")
        
        -- Normalize whitespace
        text = regex_match(text, "%s+"):gsub(" ", " ")
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        
        return text
    end,
    
    formatChapterTitle = function(chapterNum, chapterTitle)
        if not chapterTitle or chapterTitle == "" then
            return "Chapter " .. (chapterNum or "?")
        end
        
        return (chapterNum or "?") .. ": " .. chapterTitle
    end
}
