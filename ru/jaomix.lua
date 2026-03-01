-- Jaomix Lua Plugin
-- Migrated from Kotlin native source (AJAX pagination, reverse order)

return {
    id = "jaomix",
    name = "Jaomix",
    version = "1.0.0",
    language = "ru",
    baseUrl = "https://jaomix.ru",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://jaomix.ru/"
        if index > 0 then
            url = url .. "?gpage=" .. (index + 1)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "div.block-home > div.one")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.title-home")[1]
            local urlElem = html_select(item, "div.img-home > a")[1]
            local coverElem = html_select(item, "div.img-home > a > img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and coverElem.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://jaomix.ru/?searchrn=" .. url_encode(input)
        if index > 0 then
            url = url .. "&gpage=" .. (index + 1)
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, "div.block-home > div.one")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, "div.title-home")[1]
            local urlElem = html_select(item, "div.img-home > a")[1]
            local coverElem = html_select(item, "div.img-home > a > img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
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
        local title = html_select(doc, "h1")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, "div.img-book > img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, "#desc-tab")[1]
        return desc and desc:get_text() or nil
    end,

    -- Chapters (AJAX based pagination)
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        
        -- Get max page from select
        local maxPage = 1
        local options = html_select(doc, "select.sel-toc option")
        if #options > 0 then
            maxPage = #options
        else
            options = html_select(doc, "select[onchange*='loadChaptList'] option")
            if #options > 0 then maxPage = #options end
        end
        
        local allChapters = {}
        local ajaxUrl = "https://jaomix.ru/wp-admin/admin-ajax.php"
        
        -- Load chapters from last page to first for correct order
        for p = maxPage, 1, -1 do
            local body = "action=loadpagenavchapstt&page=" .. p
            local ajaxRes = http_post(ajaxUrl, body, {
                headers = {
                    ["Content-Type"] = "application/x-www-form-urlencoded",
                    ["X-Requested-With"] = "XMLHttpRequest",
                    ["Origin"] = "https://jaomix.ru",
                    ["Referer"] = url
                }
            })
            
            if ajaxRes.success then
                local ajaxDoc = html_parse(ajaxRes.body)
                local links = html_select(ajaxDoc, "div.title a[href]")
                -- Chapters within page are newest-first, need to reverse
                for i = #links, 1, -1 do
                    local titleElem = html_select(links[i], "h2")[1]
                    table.insert(allChapters, {
                        title = titleElem and titleElem:get_text() or links[i]:get_text(),
                        url = links[i].href
                    })
                end
            end
        end
        return allChapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, ".entry-content")[1]
        if content then
            content:remove("script")
            content:remove(".ads")
            content:remove(".adblock-service")
            content:remove(".lazyblock")
            content:remove(".clear")
            content:remove("style")
            return html_text(content)
        end
        return ""
    end,

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local last = html_select(doc, ".block-toc-out .columns-toc:first-child .flex-dow-txt:first-child a")[1]
        return last and last.href or nil
    end
}
