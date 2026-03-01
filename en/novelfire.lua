-- NovelFire Lua Plugin
-- Migrated from Kotlin native source (PAGE_BASED chapter pagination)

return {
    id = "novelfire",
    name = "NovelFire",
    version = "1.0.0",
    language = "en",
    baseUrl = "https://novelfire.net",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local url = "https://novelfire.net/search-adv?ctgcon=and&totalchapter=0&ratcon=min&rating=0&status=-1&sort=rank-top&page=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".novel-list > .novel-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title")[1]
            local urlElem = html_select(item, ".novel-title a")[1]
            local coverElem = html_select(item, "img")[1]
            
            if titleElem and urlElem then
                table.insert(books, {
                    title = titleElem:get_text(),
                    url = urlElem.href,
                    cover = coverElem and (coverElem:attr("data-src") or coverElem.src) or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search
    getCatalogSearch = function(index, input)
        local url = "https://novelfire.net/search?keyword=" .. url_encode(input) .. "&page=" .. (index + 1)
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".novel-list.chapters .novel-item")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleElem = html_select(item, ".novel-title")[1]
            local urlElem = html_select(item, "a")[1]
            local coverElem = html_select(item, "img")[1]
            
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
        local title = html_select(doc, "h1.novel-title")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, "img[src*='server-1'], .cover img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".summary .content, .summary")[1]
        if desc then
            desc:remove("h4.lined")
            return desc:get_text()
        end
        return nil
    end,

    -- Chapters (PAGE_BASED)
    getChapterList = function(url)
        local res = http_get(url)
        if not res.success then return {} end
        local doc = html_parse(res.body)
        
        -- Get max page from pagination
        local lastPage = 1
        local pageLinks = html_select(doc, ".pagination a[href*='?page=']")
        for i = 1, #pageLinks do
            local p = tonumber(string.match(pageLinks[i].href, "page=(%d+)"))
            if p and p > lastPage then lastPage = p end
        end
        
        local bookSlug = string.match(url, "([^/]+)/*$")
        local allChapters = {}
        
        for p = 1, lastPage do
            local pageUrl = "https://novelfire.net/book/" .. bookSlug .. "/chapters?page=" .. p
            local pRes = http_get(pageUrl)
            if pRes.success then
                local pDoc = html_parse(pRes.body)
                local links = html_select(pDoc, "a[href*='/chapter-']")
                for j = 1, #links do
                    table.insert(allChapters, {
                        title = links[j]:get_text(),
                        url = links[j].href
                    })
                end
            end
        end
        return allChapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, "#content, .chapter-content, div.entry-content")[1]
        if content then
            content:remove("script")
            content:remove("nav")
            content:remove(".ads")
            content:remove(".advertisement")
            content:remove(".disqus")
            content:remove(".comments")
            content:remove(".c-message")
            content:remove(".nav-next")
            content:remove(".nav-previous")
            return html_text(content)
        end
        return ""
    end

    getChapterListHash = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local hash = html_select(doc, ".body p.latest")[1]
        return hash and hash:get_text() or nil
    end
}
