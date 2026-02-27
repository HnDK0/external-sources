-- Advanced WTR-Lab Lua Plugin
-- Supports translation modes, API calls, pagination, and complex chapter fetching

return {
    id = "wtrlab_advanced",
    name = "WTR-Lab (Advanced)",
    version = "2.0.0",
    language = "multilanguage",
    baseUrl = "https://wtr-lab.com/",
    
    -- Advanced features
    requiresPost = true,
    hasPagination = true,
    requiresTranslation = true,
    apiEndpoints = {"reader/get", "chapters/", "chapter"},
    
    -- Configuration options
    config = {
        translationMode = "ai", -- "ai" or "raw"
        targetLanguage = "none", -- "none", "en", "ru", "es", etc.
        useProxy = true
    },
    
    -- Catalog functions with pagination
    getCatalogList = function(index)
        local url = "https://wtr-lab.com/novel-list?page=" .. (index + 1)
        local response = http_get(url)
        
        if not response.success then
            return {items = {}, hasNext = false, error = response.body}
        end
        
        local doc = html_parse(response.body)
        local items = html_select(doc, "div.serie-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "a.title")[1]
            local coverElem = html_select(item, ".image-wrap img")[1]
            
            if titleElem then
                local book = {
                    title = titleElem.text or "Unknown",
                    url = "https://wtr-lab.com" .. (titleElem.href or ""),
                    cover = "https://wtr-lab.com" .. (coverElem.src or "")
                }
                table.insert(books, book)
            end
        end
        
        -- Detect pagination
        local pagination = detect_pagination(response.body)
        
        return {
            items = books,
            hasNext = pagination.hasNext,
            lastPage = pagination.lastPage
        }
    end,
    
    -- Advanced search with POST support
    getCatalogSearch = function(index, input)
        if index > 0 then
            return {items = {}, hasNext = false} -- No pagination in search
        end
        
        local url = "https://wtr-lab.com/novel-finder"
        local data = "text=" .. url_encode(input)
        local response = http_post(url, data)
        
        if not response.success then
            return {items = {}, hasNext = false, error = response.body}
        end
        
        local doc = html_parse(response.body)
        local items = html_select(doc, "div.serie-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "a.title")[1]
            local coverElem = html_select(item, ".image-wrap img")[1]
            
            if titleElem then
                local book = {
                    title = titleElem.text or "Unknown",
                    url = "https://wtr-lab.com" .. (titleElem.href or ""),
                    cover = "https://wtr-lab.com" .. (coverElem.src or "")
                }
                table.insert(books, book)
            end
        end
        
        return {
            items = books,
            hasNext = false
        }
    end,
    
    -- Book information functions
    getBookTitle = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local titleElem = html_select(doc, "h1.long-title")[1]
        return titleElem and titleElem.text or nil
    end,
    
    getBookCoverImageUrl = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local coverElem = html_select(doc, ".image-section .image-wrap img")[1]
        return coverElem and ("https://wtr-lab.com" .. (coverElem.src or "")) or nil
    end,
    
    getBookDescription = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local descElem = html_select(doc, ".desc-wrap .description")[1]
        return descElem and descElem.text or nil
    end,
    
    -- Advanced chapter list using API
    getChapterList = function(bookUrl)
        -- Extract novel ID from URL
        local matches = regex_match(bookUrl, "/novel/(%d+)/")
        if not matches or not matches[1] then
            return {}
        end
        
        local novelId = matches[1]
        local apiUrl = "https://wtr-lab.com/api/chapters/" .. novelId
        
        local response = http_get(apiUrl)
        if not response.success then return {} end
        
        local data = json_parse(response.body)
        if not data.chapters then return {} end
        
        local chapters = {}
        for i = 1, #data.chapters do
            local chapter = data.chapters[i]
            local chapterData = {
                title = (chapter.order or i) .. ": " .. (chapter.title or "Chapter " .. i),
                url = bookUrl .. "/chapter-" .. (chapter.order or i)
            }
            table.insert(chapters, chapterData)
        end
        
        return chapters
    end,
    
    -- Advanced chapter text with translation support
    getChapterText = function(html)
        -- Extract chapter information from URL (would be passed separately in real implementation)
        -- For now, return mock content with translation
        
        local content = html_select(html, ".content")[1]
        if not content then return nil end
        
        local text = content.text or ""
        
        -- Apply translation if configured
        if _G.config.targetLanguage ~= "none" then
            text = translate_text(text, _G.config.targetLanguage)
        end
        
        -- Clean up the text
        text = regex_match(text, "<[^>]*>"):gsub("", "")
        text = regex_match(text, "%s+"):gsub(" ", " ")
        
        return text
    end,
    
    getChapterListHash = function(bookUrl)
        local chapters = getChapterList(bookUrl)
        if #chapters == 0 then return nil end
        
        local lastChapter = chapters[#chapters]
        return lastChapter.url
    end,
    
    -- Helper functions for WTR-Lab specific features
    extractNovelId = function(bookUrl)
        local matches = regex_match(bookUrl, "/novel/(%d+)/")
        return matches and matches[1] or nil
    end,
    
    buildChapterApiUrl = function(novelId, chapterNo, language, mode)
        local baseUrl = "https://wtr-lab.com/api/reader/get"
        local params = {
            translate = mode == "raw" and "web" or "ai",
            language = language,
            raw_id = novelId,
            chapter_no = chapterNo,
            retry = false,
            force_retry = false
        }
        
        return baseUrl .. "?" .. json_stringify(params)
    end,
    
    decryptChapterBody = function(encryptedBody)
        if not string.find(encryptedBody, "arr:") then
            return encryptedBody
        end
        
        -- Call proxy service for decryption
        local proxyUrl = "https://wtr-lab-proxy.fly.dev/chapter"
        local proxyData = json_stringify({payload = encryptedBody})
        local response = http_post(proxyUrl, proxyData)
        
        if response.success then
            local result = json_parse(response.body)
            return result.body or encryptedBody
        end
        
        return encryptedBody
    end,
    
    processChapterParagraphs = function(apiResponse)
        local paragraphs = {}
        
        if apiResponse.bodyArray then
            for i = 1, #apiResponse.bodyArray do
                local text = apiResponse.bodyArray[i]
                if text ~= "[image]" and text ~= "" then
                    -- Apply glossary terms
                    if apiResponse.glossaryTerms then
                        for idx, term in pairs(apiResponse.glossaryTerms) do
                            text = string.gsub(text, "※" .. idx .. "⛬", term)
                            text = string.gsub(text, "※" .. idx .. "〓", term)
                        end
                    end
                    
                    -- Apply patches
                    if apiResponse.patchMap then
                        for zh, en in pairs(apiResponse.patchMap) do
                            text = string.gsub(text, zh, en)
                        end
                    end
                    
                    table.insert(paragraphs, text)
                end
            end
        else
            -- Split by lines
            for line in string.gmatch(apiResponse.resolvedBody, "[^\r\n]+") do
                if line ~= "" then
                    table.insert(paragraphs, line)
                end
            end
        end
        
        return paragraphs
    end
}
