-- WtrLab Lua Plugin
-- Full implementation including API, Decryption, and Google Translate AI

return {
    id = "wtr_lab",
    name = "WtrLab",
    version = "1.1.0",
    language = "multi",
    baseUrl = "https://wtr-lab.com",
    -- icon will be loaded from yaml config

    -- Configuration for UI
    getScreenConfig = function()
        return {
            fields = {
                {
                    key = "mode",
                    label = "Translation Mode",
                    type = "select",
                    options = {
                        { value = "ai", label = "AI Translation" },
                        { value = "raw", label = "Original (Web)" }
                    }
                },
                {
                    key = "lang",
                    label = "Target Language",
                    type = "select",
                    options = {
                        { value = "none", label = "None (Original)" },
                        { value = "ru", label = "Русский" },
                        { value = "en", label = "English" },
                        { value = "es", label = "Español" },
                        { value = "de", label = "Deutsch" },
                        { value = "fr", label = "Français" },
                        { value = "it", label = "Italiano" },
                        { value = "tr", label = "Türkçe" },
                        { value = "id", label = "Bahasa Indonesia" }
                    }
                }
            }
        }
    end,

    -- Helper to get preference with default
    getPref = function(key, default)
        local val = get_preference(key)
        if val == "" or val == nil then return default end
        return val
    end,

    -- Catalog
    getCatalogList = function(index)
        local url = "https://wtr-lab.com/en/novel-list?sort=hot&page=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".serie-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "a.title")[1]
            local coverElem = html_select(item, ".image-wrap img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text():trim(),
                    url = titleElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://wtr-lab.com/en/novel-finder?text=" .. url_encode(input) .. "&page=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".serie-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "a.title")[1]
            local coverElem = html_select(item, ".image-wrap img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text():trim(),
                    url = titleElem.href,
                    cover = coverElem and coverElem.src or ""
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
        local title = html_select(doc, "h1.long-title")[1]
        return title and title:get_text():trim() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".image-section .image-wrap img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".desc-wrap .description")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters via API
    getChapterList = function(url)
        local novelId = string.match(url, "/novel/(%d+)/")
        local slug = string.match(url, "/novel/%d+/([^/]+)")
        if not novelId then return {} end
        
        local apiUrl = "https://wtr-lab.com/api/chapters/" .. novelId
        local res = http_get(apiUrl, { headers = { ["Referer"] = url } })
        if not res.success then return {} end
        
        local data = json_parse(res.body)
        local chaptersJson = data.chapters or {}
        local chapters = {}
        
        for i = 1, #chaptersJson do
            local ch = chaptersJson[i]
            local order = ch.order or i
            table.insert(chapters, {
                title = order .. ": " .. (ch.title or ("Chapter " .. order)),
                url = "https://wtr-lab.com/novel/" .. novelId .. "/" .. (slug or "") .. "/chapter-" .. order
            })
        end
        return chapters
    end,

    -- Chapter Content with AI Translation and Decryption
    getChapterText = function(html)
        -- In LuaSourceAdapter, html is the raw body of the chapter page
        -- But WtrLab requires API call to get real content
        local doc = html_parse(html)
        local chapterUrl = doc:location()
        
        local novelId = string.match(chapterUrl, "/novel/(%d+)/")
        local chapterNo = string.match(chapterUrl, "chapter%-(%d+)") or "1"
        
        local mode = get_preference("mode") or "ai"
        local lang = get_preference("lang") or "none"
        
        local apiParams = {
            translate = (mode == "raw") and "web" or "ai",
            language = lang,
            raw_id = novelId,
            chapter_no = tonumber(chapterNo),
            retry = false,
            force_retry = false
        }
        
        local res = http_post("https://wtr-lab.com/api/reader/get", json_stringify(apiParams), {
            headers = {
                ["Content-Type"] = "application/json",
                ["Referer"] = chapterUrl,
                ["Origin"] = "https://wtr-lab.com"
            }
        })
        
        if not res.success then return "Failed to fetch content from API" end
        
        local json = json_parse(res.body)
        if not json.success then 
            return "API Error: " .. (json.error or "unknown")
        end
        
        local data = json.data.data or json.data
        local rawBody = json_stringify(data.body)
        
        -- Decryption via proxy (same as native)
        local finalBody = rawBody
        if rawBody:find("^\"arr:") then
            local proxyRes = http_post("https://wtr-lab-proxy.fly.dev/chapter", json_stringify({payload = data.body}), {
                headers = { ["Content-Type"] = "application/json" }
            })
            if proxyRes.success then
                local pData = json_parse(proxyRes.body)
                if pData.body then
                    finalBody = json_stringify(pData.body)
                end
            end
        end
        
        local paragraphs = json_parse(finalBody)
        if type(paragraphs) ~= "table" then return "Failed to parse paragraphs" end
        
        -- Glossary & Patch
        local glossary = {}
        if data.glossary_data and data.glossary_data.terms then
            for i, termArr in ipairs(data.glossary_data.terms) do
                glossary[i-1] = termArr[1]
            end
        end
        
        local patches = {}
        if data.patch then
            for _, p in ipairs(data.patch) do
                if p.zh and p.en then patches[p.zh] = p.en end
            end
        end
        
        local result = {}
        for _, p in ipairs(paragraphs) do
            if type(p) == "string" and p ~= "[image]" then
                local text = p
                -- Apply glossary
                for idx, term in pairs(glossary) do
                    text = text:gsub("※" .. idx .. "⛬", term):gsub("※" .. idx .. "〓", term)
                end
                -- Apply patches
                for zh, en in pairs(patches) do
                    text = text:gsub(zh, en)
                end
                
                table.insert(result, text)
            end
        end
        
        -- AI Translation if requested
        if lang ~= "none" then
            local sourceLang = (mode == "raw") and "zh-CN" or "en"
            local fullText = table.concat(result, "\n\n")
            -- We translate in one go or chunks. Lua API google_translate handles one string.
            local translated = google_translate(fullText, sourceLang, lang)
            return translated:gsub("\n", "<p></p>"):gsub("<p></p>", "</p><p>")
        end
        
        return "<p>" .. table.concat(result, "</p><p>") .. "</p>"
    end
}
