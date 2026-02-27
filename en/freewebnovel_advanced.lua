-- Advanced FreeWebNovel Lua Plugin
-- Supports POST-based search and pagination

return {
    id = "freewebnovel_advanced",
    name = "FreeWebNovel (Advanced)",
    version = "2.0.0",
    language = "en",
    baseUrl = "https://freewebnovel.com",
    
    -- Advanced features
    requiresPost = true,
    hasPagination = true,
    requiresTranslation = false,
    apiEndpoints = {},
    
    -- Catalog functions with pagination
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://freewebnovel.com/completed-novel/" .. page
        
        local response = http_get(url)
        if not response.success then
            return {items = {}, hasNext = false, error = response.body}
        end
        
        local doc = html_parse(response.body)
        local items = html_select(doc, ".ul-list1 .li-row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".tit a")[1]
            local coverElem = html_select(item, ".pic img")[1]
            
            if titleElem then
                local book = {
                    title = cleanText(titleElem.text or "Unknown"),
                    url = "https://freewebnovel.com" .. (titleElem.href or ""),
                    cover = "https://freewebnovel.com" .. (coverElem.src or "")
                }
                table.insert(books, book)
            end
        end
        
        -- Detect if there are more pages
        local hasNext = #books > 0
        
        return {
            items = books,
            hasNext = hasNext,
            lastPage = page
        }
    end,
    
    -- POST-based search (no pagination)
    getCatalogSearch = function(index, input)
        if index > 0 or input == "" then
            return {items = {}, hasNext = false}
        end
        
        local url = "https://freewebnovel.com/search"
        local data = "searchkey=" .. url_encode(input)
        
        -- Add proper headers for POST request
        local headers = {
            "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language: en-US,en;q=0.5",
            "Accept-Encoding: gzip, deflate",
            "Connection: keep-alive",
            "Upgrade-Insecure-Requests: 1",
            "Cache-Control: max-age=0",
            "Referer: https://freewebnovel.com/"
        }
        
        local response = http_post(url, data)
        if not response.success then
            return {items = {}, hasNext = false, error = response.body}
        end
        
        local doc = html_parse(response.body)
        local items = html_select(doc, ".serach-result .li-row, .ul-list1 .li-row")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".tit a")[1]
            local coverElem = html_select(item, ".pic img")[1]
            
            if titleElem then
                local book = {
                    title = cleanText(titleElem.text or "Unknown"),
                    url = "https://freewebnovel.com" .. (titleElem.href or ""),
                    cover = "https://freewebnovel.com" .. (coverElem.src or "")
                }
                table.insert(books, book)
            end
        end
        
        return {
            items = books,
            hasNext = false -- Search doesn't have pagination
        }
    end,
    
    -- Book information functions
    getBookTitle = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local titleElem = html_select(doc, "h1.tit")[1]
        return titleElem and cleanText(titleElem.text) or nil
    end,
    
    getBookCoverImageUrl = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local coverElem = html_select(doc, ".pic img")[1]
        local coverUrl = coverElem and coverElem.src or nil
        
        -- Handle relative URLs
        if coverUrl and not string.find(coverUrl, "^http") then
            if string.find(coverUrl, "^//") then
                coverUrl = "https:" .. coverUrl
            else
                coverUrl = "https://freewebnovel.com" .. coverUrl
            end
        end
        
        return coverUrl
    end,
    
    getBookDescription = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local descElem = html_select(doc, ".m-desc .txt")[1]
        return descElem and cleanText(descElem.text) or nil
    end,
    
    -- Chapter list
    getChapterList = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return {} end
        
        local doc = html_parse(response.body)
        local chapterLinks = html_select(doc, "#idData li a")
        local chapters = {}
        
        for i = 1, #chapterLinks do
            local link = chapterLinks[i]
            local title = link.title or link.text or ("Chapter " .. i)
            local url = link.href
            
            if url then
                -- Handle relative URLs
                if not string.find(url, "^http") then
                    if string.find(url, "^//") then
                        url = "https:" .. url
                    else
                        url = "https://freewebnovel.com" .. url
                    end
                end
                
                local chapterData = {
                    title = cleanText(title),
                    url = url
                }
                table.insert(chapters, chapterData)
            end
        end
        
        return chapters
    end,
    
    -- Advanced chapter text extraction
    getChapterText = function(html)
        local doc = html_parse(html)
        
        -- Try multiple content selectors
        local contentSelectors = {
            "div.txt",
            ".content",
            ".chapter-content",
            ".reader-text",
            "[class*='text']",
            "[class*='content']",
            "article",
            "main"
        }
        
        for i = 1, #contentSelectors do
            local contentElem = html_select(doc, contentSelectors[i])[1]
            if contentElem then
                -- Remove unwanted elements
                local unwanted = {"script", ".ads", ".advertisement", "h4", "sub"}
                for j = 1, #unwanted do
                    local elements = html_select(contentElem, unwanted[j])
                    for k = 1, #elements do
                        elements[k]:remove()
                    end
                end
                
                local text = contentElem.text
                if text and text ~= "" then
                    return cleanText(text)
                end
            end
        end
        
        -- Fallback to body
        local body = doc.body
        if body then
            return cleanText(body.text or "")
        end
        
        return ""
    end,
    
    getChapterListHash = function(bookUrl)
        local response = http_get(bookUrl)
        if not response.success then return nil end
        
        local doc = html_parse(response.body)
        local latestChapter = html_select(doc, ".m-newest1 ul.ul-list5 li:first-child a")[1]
        return latestChapter and latestChapter.href or nil
    end,
    
    -- Helper functions
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
    
    normalizeUrl = function(url, baseUrl)
        if not url then return "" end
        
        if string.find(url, "^http") then
            return url -- Already absolute
        elseif string.find(url, "^//") then
            return "https:" .. url -- Protocol-relative
        elseif string.find(url, "^/") then
            return baseUrl .. url -- Domain-relative
        else
            return baseUrl .. "/" .. url -- Relative
        end
    end,
    
    -- URL transformation helpers
    transformBookUrl = function(url)
        return normalizeUrl(url, "https://freewebnovel.com")
    end,
    
    transformChapterUrl = function(url)
        return normalizeUrl(url, "https://freewebnovel.com")
    end,
    
    transformCoverUrl = function(url)
        return normalizeUrl(url, "https://freewebnovel.com")
    end
}
