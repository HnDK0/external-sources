id       = "asurascans"
name     = "Asura Scans"
version  = "1.7.0"
baseUrl  = "https://asurascans.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/asurascans.webp"
content_type = "manga"

-- Manga/manhwa source: chapters are image pages. getPageList returns the
-- ORDERED ORIGINAL CDN URLs (raw, un-rewritten) — the app renders them
-- natively (SSIV tiled decode, custom page-image LRU cache) and applies the
-- image-quality tiers itself at load time (HIGH = raw URL; BALANCED/SAVER/
-- LOW = weserv.nl re-encode). getChapterText stays as the legacy fallback
-- for app builds without page-list support; it reuses the Astro props JSON
-- so the rows get the real aspect ratio (yrel = height / width).
--
-- Verified against NoveLA feat/image-chapters (2026-08-09):
-- getPageList/getChapterText are called with doc.outerHtml() (jsoup
-- round-trip) + doc.location(); the escaped props attribute (&quot;…&quot;)
-- survives the round-trip, so the primary path works in-app as-is.

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Cloudflare-protected: requests without browser-like headers get a JS
-- challenge shell (200, no cards) instead of the real page. Verified live:
-- http_get with these headers returns the real page, without them it returns
-- a card-less shell.
local CHROME_HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
}

local function fetch(url)
    local r = http_get(url, { headers = CHROME_HEADERS })
    if not r.success then return nil end
    return r.body
end

local function cleanChapterTitle(text)
    local t = string_clean(text)
    -- Strip relative-time suffixes: "Chapter 206 16 hours ago" -> "Chapter 206"
    t = regex_replace(t, "\\s+\\d+\\s+(hour|day|week|month|year)s?\\s+ago\\s*$", "")
    t = regex_replace(t, "\\s+last\\s+(week|month|year)\\s*$", "")
    -- Strip absolute-date suffixes: "Chapter 201 S2-END Mar 7, 2026" -> "Chapter 201 S2-END"
    t = regex_replace(t, "\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d+,\\s*\\d{4}\\s*$", "")
    t = regex_replace(t, "\\s+(yesterday|today)\\s*$", "")
    return string_trim(t)
end

-- Дата публикации главы из текста строки списка: "16 hours ago",
-- "Mar 7, 2026", "yesterday" → unix epoch; nil если даты нет.
local MONTHS = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
                 Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }

local function parseChapterDate(text)
    local now = os.time()
    local t = string_clean(text)
    local n, unit = string.match(t, "(%d+)%s+(hour|day|week|month|year)s?%s+ago")
    if n then
        local mult = { hour = 3600, day = 86400, week = 7 * 86400,
                       month = 30 * 86400, year = 365 * 86400 }
        return now - tonumber(n) * (mult[unit] or 86400)
    end
    if string.match(t, "today") then return now end
    if string.match(t, "yesterday") then return now - 86400 end
    if string.match(t, "last%s+week") then return now - 7 * 86400 end
    if string.match(t, "last%s+month") then return now - 30 * 86400 end
    if string.match(t, "last%s+year") then return now - 365 * 86400 end
    local mon, day, year = string.match(t, "(%a+)%s+(%d+),%s*(%d+)")
    if mon and MONTHS[mon] then
        local ok, ts = pcall(os.time, { year = tonumber(year), month = MONTHS[mon],
                                        day = tonumber(day), hour = 0, min = 0, sec = 0 })
        if ok then return ts end
    end
    return nil
end

local function parseCards(body)
    local items = {}
    local seen = {}
    for _, card in ipairs(html_select(body, "div.series-card")) do
        local a = html_select_first(card.html, "a[href*='/comics/']")
        if a then
            local url = absUrl(a.href)
            if url ~= "" and not seen[url] then
                seen[url] = true
                local img = html_select_first(card.html, "img")
                local cover = ""
                if img then
                    local src = img.src
                    if src == "" then src = img:attr("data-src") end
                    cover = absUrl(src)
                end
                -- Clean title lives in the h3 below the cover link (verified live)
                local h3 = html_select_first(card.html, "h3")
                local title = h3 and string_clean(h3.text) or ""
                -- Fallback: link text with chapter/rating suffix stripped
                -- (home-page carousels have no h3)
                if title == "" then
                    title = string_clean(a.text)
                    title = regex_replace(title, "\\s*Chapter\\s*\\d+.*$", "")
                    title = regex_replace(title, "\\s*\\d+\\.\\d+\\s*$", "")
                    title = string_trim(title)
                end
                -- Card rating chip: the only div.absolute in a card holds the
                -- star + "9.2" span (scale 10, same as the JSON-LD bestRating).
                -- App rating parser ("x/10" → normalized 5-scale) rejects bare
                -- numbers > 5, so always emit the explicit scale.
                local rating = ""
                local rspan = html_select_first(card.html, "div.absolute span")
                if rspan then
                    local r = string_trim(rspan.text)
                    if tonumber(r) then rating = r .. "/10" end
                end
                if title ~= "" then
                    local item = { title = title, url = url, cover = cover }
                    if rating ~= "" then item.rating = rating end
                    table.insert(items, item)
                end
            end
        end
    end
    return items
end

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/browse"
    if page > 1 then url = url .. "?page=" .. tostring(page) end
    local body = fetch(url)
    if not body then return { items = {}, hasNext = false } end
    local items = parseCards(body)
    -- Past the last page the site renders an empty grid — stop paginating
    -- instead of letting the app scroll into endless empty pages.
    return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/browse?search=" .. url_encode(query)
    local body = fetch(url)
    if not body then return { items = {}, hasNext = false } end
    return { items = parseCards(body), hasNext = false }
end

function getBookTitle(bookUrl)
    local body = fetch(bookUrl)
    if not body then return nil end
    local h1 = html_select_first(body, "h1")
    return h1 and string_clean(h1.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetch(bookUrl)
    if not body then return nil end
    local src = html_attr(body, "img[src*='asura-images/covers/']", "src")
    if src == "" then src = html_attr(body, "meta[property='og:image']", "content") end
    return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
    local body = fetch(bookUrl)
    if not body then return nil end
    local el = html_select_first(body,
        ".summary__content, .summary, .description, .synopsis, .about, .series-description")
    if el then
        local text = string_trim(html_text(el.html))
        if text ~= "" then return text end
    end
    local meta = html_attr(body, "meta[name='description']", "content")
    if meta ~= "" then return string_trim(meta) end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetch(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, "a[href*='genres=']")) do
        local t = string_clean(a.text)
        if t ~= "" then table.insert(genres, t) end
    end
    return genres
end

-- Rating из JSON-LD ComicSeries: aggregateRating.ratingValue — оценка по
-- шкале bestRating ("9.6"/"10"). Формат "9.6/10" — рейтинговый парсер
-- приложения нормализует её в 5-балльную ("4.8"); голое "9.6" он бы отклонил.
function getBookRating(bookUrl)
    local body = fetch(bookUrl)
    if not body then return nil end
    for _, script in ipairs(html_select(body, "script[type='application/ld+json']")) do
        local raw = script.html
        if raw and string.find(raw, "ComicSeries", 1, true) then
            local ok, data = pcall(json_parse, raw)
            if ok and data and data.aggregateRating then
                local v = data.aggregateRating.ratingValue
                if v ~= nil then
                    local s = tostring(v)
                    local best = data.aggregateRating.bestRating
                    if best ~= nil then s = s .. "/" .. tostring(best) end
                    return s
                end
            end
        end
    end
    return nil
end

function getChapterList(bookUrl)
    local body = fetch(bookUrl)
    if not body then return {} end
    local chapters = {}
    local seen = {}
    for _, a in ipairs(html_select(body, "a[href*='/chapter/']")) do
        local url = absUrl(a.href)
        if url ~= "" and not seen[url] then
            seen[url] = true
            local uploaded = parseChapterDate(a.text)
            local title = cleanChapterTitle(a.text)
            -- The site labels the OLDEST row "First Chapter" (it is chapter 1);
            -- keep it but rename. Other nav texts never appear on comic pages
            -- (verified live: 206 unique chapter links, only "First Chapter"
            -- non-standard), so skip them defensively.
            local lower = string.lower(title)
            if title ~= "" and not (lower == "last chapter" or lower == "next chapter"
                or lower == "previous chapter") then
                if lower == "first chapter" then title = "Chapter 1" end
                local entry = { title = title, url = url }
                if uploaded then entry.uploaded = uploaded end
                table.insert(chapters, entry)
            end
        end
    end
    -- The list is newest-first with a "First Chapter" nav link at the TOP
    -- (before the rows), so DOM order + reversal is unreliable. Sort by the
    -- chapter number in the URL instead (app expects chronological).
    local function chapterNumber(u)
        local n = string.match(u, "/chapter/(%d+)")
        return tonumber(n) or 0
    end
    table.sort(chapters, function(a, b) return chapterNumber(a.url) < chapterNumber(b.url) end)
    return chapters
end

-- Страницы главы из Astro-island props JSON: (entity-escaped, переживает
-- jsoup-раундтрип приложения) "pages" = [1,[ [0,{url,width,height}], … ]].
-- Возвращает { url=, w=, h= } в порядке страниц; nil если не распарсилось.
-- Чисто Lua-сайд проверок минимум: engine-фильтр по "-" в pattern'ах
-- ломается, поэтому ни одна проверка здесь не использует string.find с "-".
local function parsePropsPages(body)
    if not body or body == "" then return nil end
    local pk = string.find(body, "&quot;pages&quot;", 1, true)
    if not pk then return nil end
    local props_start = nil
    local pos = 1
    while true do
        local s = string.find(body, "props=\"", pos, true)
        if not s or s > pk then break end
        props_start = s + 7
        pos = s + 1
    end
    if not props_start then return nil end
    local e = string.find(body, "\"", props_start, true)
    if not e then return nil end
    local raw = string.sub(body, props_start, e - 1)
    local decoded = raw:gsub("&quot;", '"'):gsub("&#x27;", "'")
        :gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    local ok, data = pcall(json_parse, decoded)
    if not ok or not data or not data.pages then return nil end
    local arr = data.pages[2] or data.pages[1]
    if type(arr) ~= "table" then return nil end
    local out = {}
    for _, tup in ipairs(arr) do
        local po = tup[2] or tup[1]
        if type(po) == "table" then
            local u = po.url
            if type(u) == "table" then u = u[2] or u[1] end
            if type(u) == "string" and u ~= "" then
                local wi, he = po.width, po.height
                if type(wi) == "table" then wi = wi[2] or wi[1] end
                if type(he) == "table" then he = he[2] or he[1] end
                out[#out + 1] = { url = u, w = wi, h = he }
            end
        end
    end
    if #out == 0 then return nil end
    return out
end

function getPageList(html, url)
    -- Engine passes the fetched chapter HTML. CLI ergonomics: a bare URL means
    -- the caller wants us to fetch (mirrors the app's getChapterPages(doc) flow).
    local body = html
    if not body or body == "" then
        local r = http_get(url, { headers = CHROME_HEADERS })
        if not r.success then return {} end
        body = r.body
    end

    local pages = {}
    local seen = {}

    -- Primary: Astro island props JSON — ORIGINAL CDN URLs in page order.
    -- The app renders these natively (SSIV tiled decode, aspect ratio from
    -- the decoded file) and filters quality at load time (HIGH = as-is,
    -- BALANCED/SAVER/LOW = weserv.nl re-encode), so raw URLs are what the
    -- app wants here — never pre-rewritten and never wsrv-chunked.
    local props = parsePropsPages(body)
    if props then
        for _, p in ipairs(props) do
            if not seen[p.url] then
                seen[p.url] = true
                table.insert(pages, p.url)
            end
        end
    end

    -- Fallback: reader <img> tags in DOM order (server-rendered by the
    -- ChapterReader component), covers excluded. Filtering lives in the
    -- selector (jsoup substring match) — Lua string.find misparses "-" in
    -- patterns on this engine, so no Lua-side checks here.
    if #pages == 0 then
        for _, img in ipairs(html_select(body,
            "img[src*='asura-images/chapters/'], #readerarea img:not([src*='asura-images/covers/'])")) do
            local src = img.src
            if src == "" then src = img:attr("data-src") end
            src = absUrl(src)
            if src ~= "" and not seen[src] then
                seen[src] = true
                table.insert(pages, src)
            end
        end
    end
    return pages
end

function getChapterText(html, url)
    -- Legacy fallback for app builds without page-list support. Prefers the
    -- Astro props JSON (ordered, yrel = height/width so rows keep the real
    -- aspect ratio — the legacy reader resizes rows via yrel, default 1.45);
    -- plain <img> tags otherwise. No wsrv chunking: the 1024px decode cap
    -- belongs to the old Coil-based reader, not to current builds.
    local body = html
    if not body or body == "" then
        local r = http_get(url, { headers = CHROME_HEADERS })
        if not r.success then return "" end
        body = r.body
    end
    local pages = {}
    local seen = {}
    local props = parsePropsPages(body)
    if props then
        for _, p in ipairs(props) do
            if not seen[p.url] then
                seen[p.url] = true
                -- yrel: ratio height/width, 2 знака. string.format на этом
                -- движке игнорирует спеки — округляем арифметически.
                local yrel = ""
                if type(p.w) == "number" and type(p.h) == "number" and p.w > 0 and p.h > 0 then
                    yrel = ' yrel="' .. tostring(math.floor(p.h / p.w * 100 + 0.5) / 100) .. '"'
                end
                -- & → &amp;: jsoup декодирует атрибуты в extractImgTag.
                table.insert(pages, '<img src="' .. p.url:gsub("&", "&amp;") .. '"' .. yrel .. '>')
            end
        end
    end
    if #pages == 0 then
        for _, img in ipairs(html_select(body,
            "img[src*='asura-images/chapters/'], img.w-full.block:not([src*='asura-images/covers/'])")) do
            local src = img.src
            if src == "" then src = img:attr("data-src") end
            src = absUrl(src)
            if src ~= "" and not seen[src] then
                seen[src] = true
                table.insert(pages, '<img src="' .. src .. '">')
            end
        end
    end
    -- Fallback: any image inside a reader container, excluding covers.
    if #pages == 0 then
        local container = html_select_first(body, "#readerarea, .reading-content, #chapter-content, .chapter-content")
        if container then
            for _, img in ipairs(html_select(container.html, "img:not([src*='asura-images/covers/'])")) do
                local src = img.src
                if src == "" then src = img:attr("data-src") end
                src = absUrl(src)
                if src ~= "" and not seen[src] then
                    seen[src] = true
                    table.insert(pages, '<img src="' .. src .. '">')
                end
            end
        end
    end
    -- No cache-warming here (v1.3.0 regression: the shared OkHttp client's
    -- Cloudflare interceptor treats CDN 403/503/429 challenge bodies passed
    -- through weserv as real challenges -> per-host lock + 35s WebView timeout
    -- + 120s cooldown). Pages load lazily; the app-side page cache serves
    -- repeat reads instantly.
    return table.concat(pages, "\n")
end