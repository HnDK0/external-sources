id       = "truthnovel"
name     = "Truth Novel"
version  = "1.1.3"
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

-- Site moved to Next.js routes: /novels/<arabic-slug>, /read/<slug>/<num>.
local BOOK_URL = baseUrl .. "/novels/لورد-الحقيقة"

local function fetchPage(url) return lib("fetch").page(url) end

local function absUrl(href) return lib("urls").absUrl(baseUrl, href) end

local function slugFromBookUrl(bookUrl)
    local clean = (bookUrl or ""):gsub("/+$", "")
    local slug = clean:match("/novels/([^/]+)$")
    if slug then return slug end
    return clean:match("/([^/]+)$") or ""
end

-- Next.js RSC payload is escaped JSON. Extract the chapters array first
-- instead of matching "number"..."title" across the whole page: the schema
-- may reorder fields or change unrelated objects without breaking us.
local function payloadChapters(body)
    local plain = body:gsub('\\"', '"')
    local start = plain:find('"chapters"%s*:%s*%[')
    if not start then return {} end
    local open = plain:find("%[", start)
    if not open then return {} end

    -- Bracket-match the array (titles are plain Arabic/English text; a stray
    -- bracket inside a title is not expected on this site).
    local depth, pos, close = 0, open, nil
    while pos <= #plain do
        local ch = plain:sub(pos, pos)
        if ch == "[" then depth = depth + 1
        elseif ch == "]" then
            depth = depth - 1
            if depth == 0 then close = pos break end
        end
        pos = pos + 1
    end
    if not close then return {} end

    local out = {}
    for obj in plain:sub(open + 1, close - 1):gmatch("{([^{}]*)}") do
        local num = obj:match('"number"%s*:%s*"?([%d%.]+)')
        local title = obj:match('"title"%s*:%s*"([^"]*)"')
        if num then out[#out + 1] = { num = num, title = title or "" } end
    end
    return out
end

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
    if index > 0 then return { items = {}, hasNext = false } end
    local body = fetchPage(BOOK_URL)
    local cover = body and html_attr(body, "meta[property='og:image']", "content") or ""
    return {
        items = {
            { title = "Lord of Truth", url = BOOK_URL, cover = cover }
        },
        hasNext = false
    }
end

function getCatalogSearch(index, query)
    return getCatalogList(index)
end

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local title = html_attr(body, "meta[property='og:title']", "content")
    if title ~= "" then return string_clean(title) end
    local h1 = html_select_first(body, "h1")
    return h1 and string_clean(h1.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "meta[property='og:image']", "content")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local desc = html_attr(body, "meta[property='og:description']", "content")
    return desc ~= "" and string_clean(desc) or nil
end

function getBookGenres(bookUrl)
    return { "Fantasy" }
end

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        log_error("truthnovel: getChapterList failed for " .. bookUrl)
        return {}
    end

    local slug = slugFromBookUrl(bookUrl)
    local chapters, seen = {}, {}

    local function add(num, title)
        if not num or num == "" or seen[num] then return end
        local n = tonumber(num)
        if not n then return end
        local name = string_trim(string_clean(title or ""))
        if name == "" or name:match("^%d+$") or name:match("ابدأ القراءة") then name = nil end
        chapters[#chapters + 1] = {
            title = name and (num .. " - " .. name) or num,
            url   = baseUrl .. "/read/" .. slug .. "/" .. num,
        }
        seen[num] = true
    end

    -- Full list from the Next.js RSC payload.
    for _, ch in ipairs(payloadChapters(body)) do add(ch.num, ch.title) end

    -- Newest chapters rendered as links.
    for _, a in ipairs(html_select(body, 'a[href^="/read/"]')) do
        local num = (a.href or ""):match("/([%d%.]+)$")
        if num and not seen[num] then
            local name = ""
            local el = html_select_first(a.html or "", "span.line-clamp-1")
            if el and el.text then name = el.text end
            if name == "" and a.text then
                name = string_clean(a.text):gsub("^%s*[%d%,%.]+", "")
                name = string_trim(name)
            end
            add(num, name)
        end
    end

    -- Legacy fallback for the old WordPress markup.
    if #chapters == 0 then
        for _, a in ipairs(html_select(body, "a.w4pl_post_title, a.post_title")) do
            local title = string_clean(a.text)
            local url = absUrl(a.href)
            if title ~= "" and url ~= "" then
                chapters[#chapters + 1] = { title = title, url = url }
            end
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber((a.url or ""):match("/([%d%.]+)$")) or 0
        local nb = tonumber((b.url or ""):match("/([%d%.]+)$")) or 0
        return na < nb
    end)
    return chapters
end

function getChapterListHash(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local last, lastNum = nil, -1
    for _, ch in ipairs(payloadChapters(body)) do
        local n = tonumber(ch.num)
        if n and n > lastNum then lastNum, last = n, ch.num end
    end
    for _, a in ipairs(html_select(body, 'a[href^="/read/"]')) do
        local n = tonumber(((a.href or ""):match("/([%d%.]+)$")) or "")
        if n and n > lastNum then lastNum, last = n, a.href end
    end
    return last
end

function getChapterText(html, url)
    if not html or html == "" then return "" end

    local cleaned = html_remove(html, "script", "style", "nav", "header", "footer")
    local parts = {}

    for _, p in ipairs(html_select(cleaned, 'p[style*="text-align:right"]')) do
        local t = html_text(p.html)
        if t and t ~= "" then parts[#parts + 1] = t end
    end

    if #parts == 0 then
        for _, p in ipairs(html_select(cleaned, "p")) do
            local t = html_text(p.html)
            if t and t ~= "" and not t:match("^%s*$")
                and not t:match("تعليق") and not t:match("رد")
                and not t:match("إعجاب") and not t:match("يحتوي على حرق") then
                parts[#parts + 1] = t
            end
        end
    end

    if #parts == 0 then
        local el = html_select_first(cleaned, ".bs-blog-post.single > article")
        if el then
            for _, p in ipairs(html_select(el.html, "p")) do
                parts[#parts + 1] = html_text(p.html)
            end
        end
    end

    return applyStandardContentTransforms(table.concat(parts, "\n\n"))
end
