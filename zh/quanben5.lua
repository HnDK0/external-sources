-- Quanben5 Lua Plugin
-- Migrated from Kotlin native source (JSONP search, custom base64)

local staticChars = "PXhw7UT1B0a9kQDKZsjIASmOezxYG4CHo5Jyfg2b8FLpEvRr3WtVnlqMidu6cN"

local function customBase64Encode(str)
    local result = ""
    for i = 1, #str do
        local char = str:sub(i, i)
        local num0 = string.find(staticChars, char, 1, true)
        local code = char
        if num0 then
            local newIdx = ((num0 - 1) + 3) % 62
            code = staticChars:sub(newIdx + 1, newIdx + 1)
        end
        -- Simulating SecureRandom with math.random for simplicity in Lua
        local num1 = math.random(0, 61)
        local num2 = math.random(0, 61)
        result = result .. staticChars:sub(num1 + 1, num1 + 1) .. code .. staticChars:sub(num2 + 1, num2 + 1)
    end
    return result
end

return {
    id = "quanben5",
    name = "Quanben5",
    version = "1.0.0",
    language = "zh",
    baseUrl = "https://big5.quanben5.com",
    -- icon will be loaded from yaml config

    -- Catalog
    getCatalogList = function(index)
        local page = index + 1
        local url = "https://big5.quanben5.com/category/1.html"
        if page > 1 then
            url = "https://big5.quanben5.com/category/1_" .. page .. ".html"
        end
        
        local res = http_get(url)
        if not res.success then return { items = {}, hasNext = false } end
        
        local doc = html_parse(res.body)
        local items = html_select(doc, ".pic_txt_list")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "h3 a")[1]
            local coverImg = html_select(item, ".pic img")[1]
            if titleLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = url_resolve("https://big5.quanben5.com/", titleLink.href),
                    cover = coverImg and coverImg.src or ""
                })
            end
        end
        
        return { items = books, hasNext = #books > 0 }
    end,

    -- Search (Custom JSONP logic)
    getCatalogSearch = function(index, input)
        if index > 0 or input == "" then return { items = {}, hasNext = false } end
        
        local encodedKeywords = url_encode(input)
        local bParam = url_encode(customBase64Encode(encodedKeywords))
        local timestamp = os.time() * 1000
        
        local searchUrl = "https://big5.quanben5.com/?c=book&a=search.json&callback=search&t=" .. timestamp .. "&keywords=" .. encodedKeywords .. "&b=" .. bParam
        
        local res = http_get(searchUrl, {
            ["Referer"] = "https://big5.quanben5.com/search.html"
        })
        
        if not res.success then return { items = {}, hasNext = false } end
        
        -- Parse JSONP content
        local content = string.match(res.body, '\"content\":\"(.-)\"')
        if not content then return { items = {}, hasNext = false } end
        
        -- Clean escaped quotes and slashes, and unescape unicode
        content = content:gsub('\\"', '"'):gsub('\\/', '/')
        content = unescape_unicode(content)
        
        local doc = html_parse(content)
        local items = html_select(doc, ".pic_txt_list")
        local books = {}
        
        for i = 1, #items do
            local item = items[i]
            local titleLink = html_select(item, "h3 a")[1]
            local coverImg = html_select(item, ".pic img")[1]
            if titleLink then
                table.insert(books, {
                    title = titleLink:get_text(),
                    url = url_resolve("https://big5.quanben5.com/", titleLink.href),
                    cover = coverImg and coverImg.src or ""
                })
            end
        end
        
        return { items = books, hasNext = false }
    end,

    -- Book Details
    getBookTitle = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local title = html_select(doc, "span.name")[1]
        return title and title:get_text() or nil
    end,

    getBookCoverImageUrl = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local img = html_select(doc, ".box .pic img")[1]
        return img and img.src or nil
    end,

    getBookDescription = function(url)
        local res = http_get(url)
        if not res.success then return nil end
        local doc = html_parse(res.body)
        local desc = html_select(doc, ".box .description")[1]
        if desc then
            desc:remove("h2")
            return desc:get_text()
        end
        return nil
    end,

    -- Chapters
    getChapterList = function(url)
        local chaptersUrl = url:gsub("/+$", "") .. "/xiaoshuo.html"
        local res = http_get(chaptersUrl)
        if not res.success then return {} end
        
        local doc = html_parse(res.body)
        local links = html_select(doc, "ul.list li a")
        local chapters = {}
        
        for i = 1, #links do
            table.insert(chapters, {
                title = links[i]:get_text(),
                url = url_resolve("https://big5.quanben5.com/", links[i].href)
            })
        end
        return chapters
    end,

    getChapterText = function(html)
        local doc = html_parse(html)
        local content = html_select(doc, "#content")[1]
        if content then
            content:remove("#ad")
            content:remove("script")
            content:remove("style")
            return html_text(content)
        end
        return ""
    end
}
