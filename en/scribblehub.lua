-- ScribbleHub Lua Plugin
-- Migrated from Kotlin native source

return {
    id = "scribblehub",
    name = "ScribbleHub",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://www.scribblehub.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://www.scribblehub.com/series-ranking/?sort=1&order=2&pg=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".search_main_box")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".search_title a")[1]
            local coverElem = html_select(item, ".search_img img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = titleElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://www.scribblehub.com/?s=" .. url_encode(input) .. "&post_type=fictionposts&paged=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".search_main_box")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".search_title a")[1]
            local coverElem = html_select(item, ".search_img img")[1]
            
            if titleElem then
                table.insert(books, {
                    title = titleElem:get_text(),
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
        local title = html_select(doc, "div.fic_title")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".fic_image img[src]")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".wi_fic_desc")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters
    getChapterList = function(url)
        local seriesId = string.match(url, "series/(%d+)/")
        if not seriesId then return {} end
        
        local ajaxUrl = "https://www.scribblehub.com/wp-admin/admin-ajax.php"
        local res = http_post(ajaxUrl, "action=wi_getreleases_pagination&pagenum=-1&mypostid=" .. seriesId, {
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Content-Type"] = "application/x-www-form-urlencoded"
        })
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, ".toc_w a[href]")
        local chapters = {}
        
        -- ScribbleHub returns chapters in newest-first order via AJAX, need to reverse
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
        local content = html_select(doc, "#chp_raw")[1]
        if content then
            content:remove("script")
            content:remove(".modern_chapter_ad")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local hashElem = html_select(doc, ".fic_stats span.st_item:has(.fa-list-alt)")[1]
        return hashElem and hashElem:get_text() or nil
    end
}
