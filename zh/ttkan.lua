-- Ttkan Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "ttkan",
    name = "Ttkan",
    version = "1.0.0",
    language = "zh",
    baseUrl = "https://www.ttkan.co",
    -- icon will be loaded from yaml config

    -- Catalog: Rank
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://www.ttkan.co/novel/rank"
        if page > 1 then url = url .. "?page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".rank_list > div:has(h2)")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "h2")[1]
            local urlElem = html_select(item, "a[href*='/novel/chapters/']")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = "" -- Handled by transformCoverUrl logic if needed
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local page = index + 1
        local url = "https://www.ttkan.co/novel/search?q=" .. url_encode(input)
        if page > 1 then url = url .. "&page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".novel_cell")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "h3")[1]
            local urlElem = html_select(item, "a[href*='/novel/chapters/']")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = ""
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
        local title = html_select(doc, "h1")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".novel_info amp-img, .novel_info img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".description")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters: AJAX with JSON
    getChapterList = function(url)
        local novelId = string.match(url, "/novel/chapters/([^/?]+)")
        if not novelId then return {} end
        
        local apiUrl = "https://www.ttkan.co/api/nq/amp_novel_chapters?language=tw&novel_id=" .. novelId
        local res = http_get(apiUrl)
        if not res.success then return {} end
        
        local chapters = {}
        local index = 1
        -- ttkan returns JSON with chapter_name and chapter_id. We use regex to parse it simply as in native.
        for name in string.gmatch(res.body, '"chapter_name"%s*:%s*"([^"]+)"') do
            table.insert(chapters, {
                title = name,
                url = "https://www.ttkan.co/novel/pagea/" .. novelId .. "_" .. index .. ".html"
            })
            index = index + 1
        end
        return chapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, ".content")[1]
        if content then
            -- Extensive removal from native source
            content:remove("script")
            content:remove("style")
            content:remove(".ads_auto_place")
            content:remove(".mobadsq")
            content:remove("amp-img")
            content:remove("img")
            content:remove("svg")
            content:remove("center")
            content:remove("#div_content_end")
            content:remove(".div_adhost")
            content:remove(".trc_related_container")
            content:remove(".div_feedback")
            content:remove(".social_share_frame")
            content:remove("amp-social-share")
            content:remove("a[href*=feedback]")
            content:remove("button")
            content:remove(".icon")
            content:remove(".decoration")
            content:remove(".next_page_links")
            content:remove(".more_recommend")
            content:remove("a")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local btn = html_select(doc, "button.btn_show_all_chapters")[1]
        return btn and btn:get_text() or nil
    end
}
