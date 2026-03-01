-- WuxiaWorld.site Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "wuxia_world_site",
    name = "WuxiaWorld.site",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://wuxiaworld.site",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://wuxiaworld.site/novel/?m_orderby=trending"
        if page > 1 then url = url .. "&page=" .. page end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".page-item-detail")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".post-title h3 a")[1]
            local coverElem = html_select(item, ".c-image-hover img")[1]
            
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
        local url = "https://wuxiaworld.site/?s=" .. url_encode(input) .. "&post_type=wp-manga"
        if page > 1 then url = "https://wuxiaworld.site/page/" .. page .. "/?s=" .. url_encode(input) .. "&post_type=wp-manga" end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".c-tabs-item__content")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".post-title h3 a")[1]
            local coverElem = html_select(item, ".c-image-hover img")[1]
            
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
        local img = html_select(doc, ".summary_image img")[1]
        return img and (img:attr("data-src") or img.src) or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".summary__content")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters: AJAX
    getChapterList = function(url)
        local ajaxUrl = url:gsub("/+$", "") .. "/ajax/chapters/"
        local res = http_post(ajaxUrl, "", {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        })
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "li.wp-manga-chapter a[href]")
        local chapters = {}
        
        -- WuxiaWorld returns newest-first, need to reverse
        for i = #links, 1, -1 do
            table.insert(chapters, {
                title = links[i]:get_text(),
                url = links[i].href
            })
        end
        return chapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, ".reading-content")[1]
        if content then
            content:remove("script")
            content:remove(".ads")
            content:remove(".advertisement")
            content:remove(".social-share")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local btn = html_select(doc, "#btn-read-first")[1]
        return btn and btn.href or nil
    end
}
