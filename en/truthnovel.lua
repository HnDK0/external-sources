id       = "truthnovel"
name     = "Truth Novel"
version  = "1.0.9"
baseUrl  = "https://truthnovel.top"
language = "en"
icon     = "https://truthnovel.top/wp-content/uploads/2024/12/%D9%86%D8%B3%D8%AE%D8%A9-%D8%A7%D9%84%D9%81%D8%B5%D9%84-%D8%A7%D9%84%D9%81-%D8%A7%D9%84%D8%B5%D8%BA%D9%8A%D8%B1%D8%A9-%D9%84%D9%84%D9%85%D9%88%D9%82%D8%B9-%D8%A7%D9%84%D8%B9%D8%B1%D8%A8%D9%8A.jpg"

local function absUrl(href)
    if not href or href == "" then
        return ""
    end

    if href:sub(1,4) == "http" then
        return href
    end

    if href:sub(1,2) == "//" then
        return "https:" .. href
    end

    return url_resolve(baseUrl, href)
end

function getCatalogList(index)

    if index > 0 then
        return {
            items = {},
            hasNext = false
        }
    end

    return {
        items = {
            {
                title = "Lord of Truth",
                url = baseUrl .. "/list/257/",
                cover = icon
            }
        },
        hasNext = false
    }
end

function getCatalogSearch(index, query)
    return getCatalogList(index)
end

function getBookTitle(bookUrl)
    return "Lord of Truth"
end

function getBookCoverImageUrl(bookUrl)
    return icon
end

function getBookDescription(bookUrl)
    return "Lord of Truth / Master of Truth"
end

function getBookGenres(bookUrl)
    return {
        "Fantasy"
    }
end

function getChapterList(bookUrl)

    local r = http_get(bookUrl)

    if not r.success then
        return {}
    end

    local chapters = {}

    for _, a in ipairs(html_select(r.body, "a.w4pl_post_title")) do

        local title = a.text or ""
        local url = absUrl(a.href)

        if title ~= "" and url ~= "" then
            table.insert(chapters, {
                title = title,
                url = url
            })
        end
    end

    if #chapters == 0 then

        for _, a in ipairs(html_select(r.body, "a.post_title")) do

            local title = a.text or ""
            local url = absUrl(a.href)

            if title ~= "" and url ~= "" then
                table.insert(chapters, {
                    title = title,
                    url = url
                })
            end
        end
    end

    table.sort(chapters, function(a, b)

        local na =
            tonumber(
                (a.title or ""):match("^(%d+)")
            ) or 0

        local nb =
            tonumber(
                (b.title or ""):match("^(%d+)")
            ) or 0

        return na < nb
    end)

    return chapters
end

function getChapterListHash(bookUrl)
    return "truthnovel-v9"
end

function getChapterText(html, url)

    if not html or html == "" then
        return ""
    end

    local content =
        html:match(
            '<div class="entry%-content.-wpdiscuz'
        )

    if not content then
        content =
            html:match(
                '<article.-wpdiscuz'
            )
    end

    if not content then
        content =
            html:match(
                '<body.-</body>'
            )
    end

    if not content then
        return html
    end

    content =
        content:gsub(
            '<script.-</script>',
            ''
        )

    content =
        content:gsub(
            '<style.-</style>',
            ''
        )

    content =
        content:gsub(
            '<!%-%-.-%-%->',
            ''
        )

    content =
        content:gsub(
            '<br%s*/?>',
            '\n'
        )

    content =
        content:gsub(
            '</p>',
            '\n\n'
        )

    content =
        content:gsub(
            '<[^>]->',
            ''
        )

    content =
        content:gsub('&nbsp;', ' ')
        :gsub('&quot;', '"')
        :gsub('&#8220;', '"')
        :gsub('&#8221;', '"')
        :gsub('&#8217;', "'")
        :gsub('&hellip;', '...')
        :gsub('&amp;', '&')

    content =
        content:gsub(
            'Ø§Ù„Ù…ÙˆØ¶ÙˆØ¹ Ø§Ù„Ø³Ø§Ø¨Ù‚',
            ''
        )

    content =
        content:gsub(
            'Ø§Ù„Ù…ÙˆØ¶ÙˆØ¹ Ø§Ù„ØªØ§Ù„ÙŠ',
            ''
        )

    content =
        content:gsub(
            'Disclaimer',
            ''
        )

    content =
        content:gsub(
            'Novel Stories',
            ''
        )

    content =
        content:gsub(
            'wpDiscuz',
            ''
        )

    content =
        content:gsub(
            '\n%s*\n%s*\n+',
            '\n\n'
        )

    return content
end
