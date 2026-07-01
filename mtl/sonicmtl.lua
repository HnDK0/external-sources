-- SonicMTL plugin for NovaLa
-- Source: https://www.sonicmtl.com/
-- Version: 1.6.2

id       = "sonicmtl"
name     = "Sonic MTL"
version  = "1.6.2"
baseUrl  = "https://www.sonicmtl.com"
language = "Mtl"
icon     = "https://www.sonicmtl.com/wp-content/uploads/2021/09/sonicmtl-icon-1.png"


local _pageCache = {}

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function cleanText(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("\n%s*\n%s*\n+", "\n\n")
    return string_trim(text)
end

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)









    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- ── Catalog parsing ─────────────────────────────────────────────────────

local function parseCard(cardHtml)
    local titleEl =
        html_select_first(cardHtml, ".item-summary .post-title a") or
        html_select_first(cardHtml, ".post-title a") or
        html_select_first(cardHtml, "h3 a") or
        html_select_first(cardHtml, "a[title]")

    local linkEl =
        html_select_first(cardHtml, ".item-thumb a") or
        html_select_first(cardHtml, ".item-summary .post-title a") or
        html_select_first(cardHtml, ".post-title a") or
        html_select_first(cardHtml, "a[title]")

    if not titleEl or not linkEl then return nil end

    local title = string_clean(titleEl.text or "")
    local url = absUrl(linkEl.href or "")
    if title == "" or url == "" then return nil end

    local cover = html_attr(cardHtml, "img", "src")
    if cover == "" then cover = html_attr(cardHtml, "img", "data-src") end
    if cover == "" then cover = html_attr(cardHtml, "img", "data-lazy-src") end

    return {
        title = title,
        url = url,
        cover = absUrl(cover)
    }
end

local function parseCatalogItems(body)
    local items = {}
    local seen = {}

    local selectors = {
        ".page-item-detail",
        ".page-listing-item .page-item-detail",
        ".c-tabs-item__content",
        ".item-summary",
        ".popular-item-wrap",
        ".slider__item",
    }

    for _, sel in ipairs(selectors) do
        for _, card in ipairs(html_select(body, sel)) do
            local item = parseCard(card.html or card)
            if item and not seen[item.url] then
                seen[item.url] = true
                table.insert(items, item)
            end
        end
    end

    if #items == 0 then
        for _, a in ipairs(html_select(body, "a[href*='/novel/']")) do
            local href = absUrl(a.href or "")
            local title = string_clean(a.text or "")
            if href ~= "" and title ~= "" and not seen[href] then
                seen[href] = true
                table.insert(items, {
                    title = title,
                    url = href,
                    cover = ""
                })
            end
        end
    end

    return items


end

-- ── Chapter parsing ─────────────────────────────────────────────────────

local function parseChapterLinks(body, novelSlug)
    local chapters = {}
    local seen = {}

    local function addChapter(title, href)
        href = absUrl(href or "")
        title = string_clean(title or "")

        if href == "" or title == "" or seen[href] then
            return
        end

        if novelSlug and not href:find("/novel/" .. novelSlug .. "/") then
            return
        end

        if not href:find("/chapter") and not href:find("chapter%-") then
            return
        end

        seen[href] = true
        table.insert(chapters, {
            title = title,
            url = href
        })
    end




    for _, sel in ipairs({
        ".wp-manga-chapter a",
        ".listing-chapters_wrap a",
        ".listing-chapters_wrap .wp-manga-chapter a",
        ".chapters_selectbox_holder a",
        ".chapter-item a",
        ".chapter a",
        "a.btn-link",
        "a[href*='/chapter']",
    }) do
        for _, a in ipairs(html_select(body, sel)) do
            addChapter(a.text or "", a.href or "")
        end
    end

    local numbered = {}
    for _, ch in ipairs(chapters) do
        local n = tonumber((ch.title or ""):match("^(%d+)")) or
                  tonumber((ch.url or ""):match("chapter%-(%d+)")) or
                  tonumber((ch.url or ""):match("/(%d+)%-[^/]+/?$")) or 0
        table.insert(numbered, { n = n, title = ch.title, url = ch.url })
    end

    table.sort(numbered, function(a, b)
        if a.n == b.n then
            return a.url < b.url
        end
        return a.n < b.n
    end)

    local sorted = {}
    for _, ch in ipairs(numbered) do
        table.insert(sorted, {
            title = ch.title,
            url = ch.url
        })
    end

    return sorted
end

-- ── AJAX chapter fetching (enhanced for JSON arrays) ──────────────────

local function fetchAjaxChapters(bookUrl, mangaId)
    local novelSlug = bookUrl:match("/novel/([^/]+)/")

    local attempts = {
        {
            url = bookUrl:gsub("/?$", "") .. "/ajax/chapters/?t=1",
            body = "",
            post = true
        },
        {
            url = bookUrl:gsub("/?$", "") .. "/ajax/chapters/",
            body = "",
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=wp-manga-get-chapters&post_id=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=wp-manga-get-chapters&manga_id=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=wp-manga-get-chapters&manga=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=manga_get_chapters&post_id=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=manga_get_chapters&manga_id=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=manga_get_chapters&manga=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=madara_load_chapters&post_id=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=madara_load_chapters&manga_id=" .. tostring(mangaId),
            post = true
        },
        {
            url = baseUrl .. "/wp-admin/admin-ajax.php",
            body = "action=madara_load_chapters&manga=" .. tostring(mangaId),
            post = true
        },
    }

    for _, req in ipairs(attempts) do
        local r
        if req.post then
            r = http_post(req.url, req.body, {
                headers = {
                    ["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8",
                    ["X-Requested-With"] = "XMLHttpRequest",
                    ["Referer"] = bookUrl,
                    ["Origin"] = baseUrl
                }
            })
        else
            r = http_get(req.url, {
                headers = {
                    ["X-Requested-With"] = "XMLHttpRequest",
                    ["Referer"] = bookUrl
                }
            })
        end

        if r and r.success and r.body and r.body ~= "" then
            local body = r.body
            local chapters = nil

            -- Try to parse as JSON
            if string.sub(body, 1, 1) == "{" or string.sub(body, 1, 1) == "[" then
                local data = json_parse(body)
                if data then
                    -- Case 1: root is an array of chapters
                    if type(data) == "table" and data[1] ~= nil then
                        chapters = {}
                        for _, item in ipairs(data) do
                            local title = item.title or item.name or item.label or ""
                            local url = item.url or item.link or item.href or ""
                            if title ~= "" and url ~= "" then
                                table.insert(chapters, { title = string_clean(title), url = absUrl(url) })
                            end
                        end
                    -- Case 2: data has a field that is an array
                    else
                        local arrayField = data.chapters or data.list or data.items or data.results
                        if type(arrayField) == "table" and arrayField[1] ~= nil then
                            chapters = {}
                            for _, item in ipairs(arrayField) do
                                local title = item.title or item.name or item.label or ""
                                local url = item.url or item.link or item.href or ""
                                if title ~= "" and url ~= "" then
                                    table.insert(chapters, { title = string_clean(title), url = absUrl(url) })
                                end
                            end
                        end
                    end

                    -- If we still don't have chapters, look for HTML inside data
                    if not chapters or #chapters == 0 then
                        local htmlContent = data.data or data.html or data.content or data.chapters_html
                        if htmlContent and htmlContent ~= "" then
                            chapters = parseChapterLinks(htmlContent, novelSlug)
                        end
                    end
                end
            end

            -- If JSON parsing didn't yield chapters, treat body as raw HTML
            if not chapters or #chapters == 0 then
                chapters = parseChapterLinks(body, novelSlug)
            end





            if chapters and #chapters > 0 then
                return chapters
            end







        end
    end

    return {}
end

-- ── Catalog ─────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = (page == 1) and (baseUrl .. "/novel/") or (baseUrl .. "/novel/page/" .. page .. "/")
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = #items > 0 }
end



function getCatalogSearch(index, query)
    local page = index + 1
    local url = (page == 1)
        and (baseUrl .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga")
        or (baseUrl .. "/page/" .. page .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga")
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)














    return { items = items, hasNext = #items > 0 }
end

-- ── Book Details ────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".post-title h1") or html_select_first(body, "h1")
    if el and el.text and el.text ~= "" then
        return string_clean(el.text)
    end
    local og = html_select_first(body, "meta[property='og:title']")
    if og and og.content and og.content ~= "" then
        local t = string_clean(og.content)
        t = t:gsub("%s*MTL and Audiobook$", ""):gsub("%s*MTL$", "")
        return t
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local og = html_select_first(body, "meta[property='og:image']")
    if og and og.content and og.content ~= "" then
        return absUrl(og.content)
    end
    local img = html_select_first(body, ".summary_image img") or html_select_first(body, ".item-thumb img")
    if img then
        local src = img.src or img["data-src"] or img["data-lazy-src"] or ""
        if src ~= "" then return absUrl(src) end
    end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local og = html_select_first(body, "meta[property='og:description']")
    if og and og.content and og.content ~= "" then
        return string_clean(og.content)
    end
    local el = html_select_first(body, ".summary__content") or
               html_select_first(body, ".description-summary .summary__content") or
               html_select_first(body, ".description-summary")
    if el and el.text and el.text ~= "" then
        return cleanText(el.text)
    end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    local seen = {}
    for _, a in ipairs(html_select(body, ".genres-content a, .genres_wrap a.btn-genres, .post-content_item a[href*='/novel-genre/']")) do
        local g = string_clean(a.text or "")
        if g ~= "" and not seen[g] then
            seen[g] = true
            table.insert(genres, g)

        end
    end
    return genres
end

-- ── Chapter List ────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end


















    local novelSlug = bookUrl:match("/novel/([^/]+)/")
    local chapters = parseChapterLinks(body, novelSlug)
    if #chapters > 0 then
        return chapters
    end

    local mangaId = html_attr(body, "#manga-chapters-holder", "data-id")
    if not mangaId or mangaId == "" then
        mangaId = body:match('"manga_id":"(%d+)"') or body:match('data%-id="(%d+)"')
    end

    if mangaId and mangaId ~= "" then
        chapters = fetchAjaxChapters(bookUrl, mangaId)
        if #chapters > 0 then
            return chapters






        end




    end

    return {}

end

function getChapterListHash(bookUrl)
    local chapters = getChapterList(bookUrl)
    if #chapters == 0 then return bookUrl end
    local first = chapters[1] and chapters[1].url or ""
    local last = chapters[#chapters] and chapters[#chapters].url or ""
    return tostring(#chapters) .. ":" .. first .. ":" .. last


end

-- ── Chapter Text ────────────────────────────────────────────────────────
































