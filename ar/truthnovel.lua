id       = "truthnovel"
name     = "Truth Novel"
version  = "1.1.2"
baseUrl  = "https://truthnovel.top"
language = "ar"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/truthnovel.png"

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead. require_lib caches loaded libs.
local function lib(id)
    if type(require_lib) ~= "function" then
        show_error("Requires NoveLA update", "This plugin needs the shared libraries")
        error("Requires NoveLA update (require_lib)", 0)
    end
    return require_lib(id)
end

local _cover = baseUrl .. "/wp-content/uploads/2024/12/نسخة-الفصل-الف-الصغيرة-للموقع-العربي.jpg"

local function absUrl(href) return lib("urls").absUrl(baseUrl, href) end

-- Standard cleanup (domain lines, leading "Chapter N" heading, translator
-- credits) from the shared content lib, then the site's own passes.
local function applyStandardContentTransforms(text)
    text = lib("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
    -- Remove standalone separator lines (=, ~, -, —) wherever they appear
    -- (old regex "(?s)\\n={3,}.*" cut everything after the FIRST separator line,
    -- which swallowed the whole chapter when a "=======" line appears near the top)
    text = regex_replace(text, "(?m)^\\s*[=~\\-—_]{3,}\\s*(\\r?\\n|$)", "")
    -- Drop empty &nbsp; paragraphs
    text = regex_replace(text, "(?m)^[\\s\\p{Z}\\uFEFF]*&nbsp;[\\s\\p{Z}\\uFEFF]*(\\r?\\n|$)", "")
    -- Cut the site footer ("لدعم هذا العمل مادياً/معنوياً ..." with payment links)
    text = regex_replace(text, "(?s)\\n\\s*لدعم هذا العمل.*", "")
    -- Collapse leftover blank runs
    text = regex_replace(text, "\\n{3,}", "\n\n")
    text = string_trim(text)
    return text
end

function getCatalogList(index)
    if index > 0 then
        return { items = {}, hasNext = false }
    end
    return {
        items = {
            {
                title = "Lord of Truth",
                url   = baseUrl .. "/list/257/",
                cover = _cover
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
    return _cover
end

function getBookDescription(bookUrl)
    return "Lord of Truth / Master of Truth"
end

function getBookGenres(bookUrl)
    return { "Fantasy" }
end

function getChapterList(bookUrl)
    bookUrl = bookUrl:gsub("/?$", "/")
    local r = http_get(bookUrl)
    if not r.success then
        log_error("truthnovel: getChapterList failed for " .. bookUrl)
        return {}
    end

    local chapters = {}
    for _, a in ipairs(html_select(r.body, "a.w4pl_post_title")) do
        local title = string_clean(a.text)
        local url = absUrl(a.href)
        if title ~= "" and url ~= "" then
            table.insert(chapters, { title = title, url = url })
        end
    end

    if #chapters == 0 then
        for _, a in ipairs(html_select(r.body, "a.post_title")) do
            local title = string_clean(a.text)
            local url = absUrl(a.href)
            if title ~= "" and url ~= "" then
                table.insert(chapters, { title = title, url = url })
            end
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber((a.title or ""):match("^(%d+)")) or 0
        local nb = tonumber((b.title or ""):match("^(%d+)")) or 0
        return na < nb
    end)

    return chapters
end

function getChapterListHash(bookUrl)
    bookUrl = bookUrl:gsub("/?$", "/")
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local links = html_select(r.body, "a.w4pl_post_title")
    if #links == 0 then
        links = html_select(r.body, "a.post_title")
    end
    return #links > 0 and links[1].href or nil
end

function getChapterText(html, url)
    if not html or html == "" then return "" end

    local cleaned = html_remove(html, "script", "style")
    local el = html_select_first(cleaned, ".bs-blog-post.single > article")
    if not el then return "" end

    local parts = {}
    for _, p in ipairs(html_select(el.html, "p")) do
        table.insert(parts, html_text(p.html))
    end
    return applyStandardContentTransforms(table.concat(parts, "\n\n"))
end
