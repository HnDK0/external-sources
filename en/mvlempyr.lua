id       = "mvlempyr.com"
name     = "MVLEMPYR"
version  = "1.0.4"
baseUrl  = "https://www.mvlempyr.io"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/mvlempyr.webp"

local chapSite = "https://chap.heliosarchive.online/"

local _pageCache = {}
local _allNovels = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
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

local function checkCaptcha(body)
    local titleEl = html_select_first(body, "title")
    if titleEl then
        local title = string_trim(titleEl.text)
        if title == "Attention Required! | Cloudflare" or title == "Just a moment..." then
            return true
        end
    end
    return false
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

local function mulmod(a, b, m)
    local result = 0
    a = a % m
    b = b % m
    while b > 0 do
        if b % 2 == 1 then
            result = (result + a) % m
        end
        a = (a * 2) % m
        b = math.floor(b / 2)
    end
    return result
end

local function convertNovelId(e)
    local MOD = 1999999997
    local result = 1
    local base = 7 % MOD
    local exp = math.floor(e)
    while exp > 0 do
        if exp % 2 == 1 then
            result = mulmod(result, base, MOD)
        end
        base = mulmod(base, base, MOD)
        exp = math.floor(exp / 2)
    end
    return result
end

local function paginate(data, index)
    local startIdx = index * 20
    local result = {}
    for i = startIdx + 1, math.min(startIdx + 20, #data) do
        table.insert(result, data[i])
    end
    return result
end

local function parseDateTime(dateStr)
    if not dateStr or dateStr == "" then return 0 end
    local y, m, d, h, min, s = dateStr:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return 0 end
    local t = os.time({
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s)
    })
    return (t or 0) * 1000
end

local function toSlug(s)
    if not s then return "" end
    s = tostring(s):lower()
    s = s:gsub("[^%w]+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    return s
end

local function normalizeList(list)
    local result = {}
    if type(list) ~= "table" then return result end
    for _, v in ipairs(list) do
        if type(v) == "table" then
            -- на случай если API вернёт объекты { slug = "...", name = "..." }
            v = v.slug or v.name or v.value
        end
        local slug = toSlug(v)
        if slug ~= "" then table.insert(result, slug) end
    end
    return result
end

local function novelToItem(novel)
    local item = {
        title = novel.name,
        url   = baseUrl .. "/" .. novel.path,
        cover = novel.cover
    }
    -- Рейтинг из поля average-review API: карточки каталога/поиска на сайте
    -- рендерятся клиентом из этого же поля (см. шаблон "${e["average-review"].toFixed(1)}"
    -- на странице книги), поэтому ключ заполняется и в каталоге, и в поиске.
    -- Голое число по шкале 0-5; при отсутствии отзывов (0) ключ не указываем.
    if (novel.avgReview or 0) > 0 then
        item.rating = tostring(novel.avgReview)
    end
    return item
end

-- ── Load all novels from WP REST API ────────────────────────────────────────

-- ── Persistent local cache for the full novel list ──────────────────────────
-- Пока не подтверждено, что API поддерживает серверную фильтрацию/поиск,
-- жанры/теги фильтруются на клиенте, а значит без полного списка не обойтись.
-- Кэшируем его локально на срок CACHE_TTL, чтобы не тянуть и не парсить
-- заново весь каталог при каждом холодном старте скрипта.
local CACHE_KEY        = "mvl_novels_cache_v2"
local CACHE_TS_KEY     = "mvl_novels_cache_v2_ts"
local CACHE_TTL        = 6 * 60 * 60          -- 6 часов
local CACHE_MAX_BYTES  = 4000000              -- ~4MB — с запасом под каталоги 10-15k+ новелл;
                                               -- при dict-кодировании и ~6000 новелл выходило ~0.8MB

-- Жанры/теги очень сильно повторяются между новеллами (~35 жанров, ~850 тегов на
-- весь каталог), поэтому вместо того чтобы хранить строку в каждой новелле, храним
-- один общий словарь слагов + индексы в него. cover/path тоже избыточны — cover
-- всегда "https://assets.mvlempyr.app/images/600/" .. novelCode .. ".webp", а path
-- всегда "novel/" .. slug, так что храним только novelCode/slug и восстанавливаем
-- остальное при чтении.

local function loadCachedNovels()
    local tsRaw = get_preference(CACHE_TS_KEY)
    local ts = tonumber(tsRaw)
    if not ts then return nil end
    if os.time() - ts > CACHE_TTL then return nil end

    local raw = get_preference(CACHE_KEY)
    if not raw or raw == "" then return nil end

    local payload = json_parse(raw)
    if type(payload) ~= "table" or type(payload.dict) ~= "table" or type(payload.novels) ~= "table" then
        return nil
    end
    if #payload.novels == 0 then return nil end

    local dict = payload.dict
    local novels = {}
    for _, n in ipairs(payload.novels) do
        local genres = {}
        for _, idx in ipairs(n.g or {}) do
            local s = dict[idx]
            if s then table.insert(genres, s) end
        end
        local tags = {}
        for _, idx in ipairs(n.t or {}) do
            local s = dict[idx]
            if s then table.insert(tags, s) end
        end
        table.insert(novels, {
            name         = n.name or "",
            path         = "novel/" .. (n.slug or ""),
            cover        = "https://assets.mvlempyr.app/images/600/" .. (n.code or "") .. ".webp",
            avgReview    = n.r or 0,
            reviewCount  = n.rc or 0,
            chapterCount = n.cc or 0,
            created      = n.cr or 0,
            genres       = genres,
            tags         = tags,
        })
    end
    return novels
end

local function saveCachedNovels(novels)
    local dict = {}
    local dictIndex = {}
    local function idxFor(slug)
        local idx = dictIndex[slug]
        if not idx then
            table.insert(dict, slug)
            idx = #dict
            dictIndex[slug] = idx
        end
        return idx
    end

    local compact = {}
    for _, n in ipairs(novels) do
        local g = {}
        for _, s in ipairs(n.genres) do table.insert(g, idxFor(s)) end
        local t = {}
        for _, s in ipairs(n.tags) do table.insert(t, idxFor(s)) end
        table.insert(compact, {
            name = n.name,
            slug = (n.path or ""):gsub("^novel/", ""),
            code = (n.cover or ""):match("(%d+)%.webp$") or "",
            r    = n.avgReview,
            rc   = n.reviewCount,
            cc   = n.chapterCount,
            cr   = n.created,
            g    = g,
            t    = t,
        })
    end

    local raw = json_stringify({ dict = dict, novels = compact })
    if not raw then return end
    if #raw > CACHE_MAX_BYTES then
        log_info("mvlempyr: skip caching novel list, too large (" .. #raw .. " bytes)")
        return
    end
    set_preference(CACHE_KEY, raw)
    set_preference(CACHE_TS_KEY, tostring(os.time()))
end

local function loadAll()
    local url = chapSite .. "wp-json/wp/v2/mvl-novels?per_page=15000"
    local r = http_get(url)
    if not r.success then
        log_error("mvlempyr: failed to load novel list code=" .. tostring(r.code))
        return {}
    end
    local data = json_parse(r.body)
    if not data or type(data) ~= "table" then return {} end

    local novels = {}
    for _, novel in ipairs(data) do
        local novelCode = novel["novel-code"] or ""
        local genres = novel.genre
        if type(genres) == "string" then
            local arr = {}
            for g in genres:gmatch("[^,]+") do table.insert(arr, string_trim(g)) end
            genres = arr
        end
        local tags = novel.tags
        if type(tags) == "string" then
            local arr = {}
            for t in tags:gmatch("[^,]+") do table.insert(arr, string_trim(t)) end
            tags = arr
        end
        table.insert(novels, {
            name         = novel.name or "",
            path         = "novel/" .. (novel.slug or ""),
            cover        = "https://assets.mvlempyr.app/images/600/" .. novelCode .. ".webp",
            avgReview    = tonumber(novel["average-review"]) or 0,
            reviewCount  = tonumber(novel["total-reviews"]) or 0,
            chapterCount = tonumber(novel["total-chapters"]) or 0,
            created      = parseDateTime(novel["createdOn"] or ""),
            genres       = normalizeList(genres),
            tags         = normalizeList(tags),
        })
    end
    return novels
end

local function getAllNovels()
    if _allNovels then return _allNovels end

    local cached = loadCachedNovels()
    if cached then
        _allNovels = cached
        return _allNovels
    end

    _allNovels = loadAll()
    if _allNovels and #_allNovels > 0 then
        saveCachedNovels(_allNovels)
    end
    return _allNovels
end

local function getNovelIdFromBody(body)
    local el = html_select_first(body, "#novel-code")
    if not el then return nil end
    local code = string_trim(el.text or "")
    if code == "" then return nil end
    local num = tonumber(code)
    if not num then return nil end
    return convertNovelId(num)
end

-- ── Filter and sort logic ───────────────────────────────────────────────────

local function filterAndSort(novels, filters)
    local filtered = {}
    for _, novel in ipairs(novels) do
        local include = true

        if filters then
            local genresExc = normalizeList(filters["genres_excluded"])
            for _, g in ipairs(genresExc) do
                for _, ng in ipairs(novel.genres) do
                    if ng == g then include = false; break end
                end
                if not include then break end
            end

            if include then
                local genresInc = normalizeList(filters["genres_included"])
                for _, g in ipairs(genresInc) do
                    local found = false
                    for _, ng in ipairs(novel.genres) do
                        if ng == g then found = true; break end
                    end
                    if not found then include = false; break end
                end
            end

            if include then
                local tagsExc = normalizeList(filters["tags_excluded"])
                for _, t in ipairs(tagsExc) do
                    for _, nt in ipairs(novel.tags) do
                        if nt == t then include = false; break end
                    end
                    if not include then break end
                end
            end

            if include then
                local tagsInc = normalizeList(filters["tags_included"])
                for _, t in ipairs(tagsInc) do
                    local found = false
                    for _, nt in ipairs(novel.tags) do
                        if nt == t then found = true; break end
                    end
                    if not found then include = false; break end
                end
            end

            if include then
                local tagsSearch = filters["tags_search"]
                if tagsSearch and tagsSearch ~= "" then
                    local terms = {}
                    for term in tostring(tagsSearch):gmatch("[^,]+") do
                        local slug = toSlug(term)
                        if slug ~= "" then table.insert(terms, slug) end
                    end
                    for _, term in ipairs(terms) do
                        local found = false
                        for _, nt in ipairs(novel.tags) do
                            if nt:find(term, 1, true) then found = true; break end
                        end
                        if not found then include = false; break end
                    end
                end
            end
        end

        if include then
            table.insert(filtered, novel)
        end
    end

    local sortKey = "reviewCount"
    if filters and filters["order"] then
        sortKey = filters["order"]
    end
    table.sort(filtered, function(a, b)
        return (a[sortKey] or 0) > (b[sortKey] or 0)
    end)

    return filtered
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local allNovels = getAllNovels()
    local sorted = filterAndSort(allNovels, nil)
    local items = {}
    for _, n in ipairs(paginate(sorted, index)) do
        table.insert(items, novelToItem(n))
    end
    return { items = items, hasNext = #sorted > (index + 1) * 20 }
end

function getCatalogSearch(index, query)
    local allNovels = getAllNovels()
    local queryLower = query:lower()
    local results = {}
    for _, novel in ipairs(allNovels) do
        if novel.name:lower():find(queryLower, 1, true) then
            table.insert(results, novel)
        end
    end
    local items = {}
    for _, n in ipairs(paginate(results, index)) do
        table.insert(items, novelToItem(n))
    end
    return { items = items, hasNext = #results > (index + 1) * 20 }
end

function getCatalogFiltered(index, filters)
    local allNovels = getAllNovels()
    local sorted = filterAndSort(allNovels, filters)
    local items = {}
    for _, n in ipairs(paginate(sorted, index)) do
        table.insert(items, novelToItem(n))
    end
    return { items = items, hasNext = #sorted > (index + 1) * 20 }
end

-- ── Filters ─────────────────────────────────────────────────────────────────

local _filterListCache = nil

local POPULAR_TAGS_LIMIT = 40

local function slugToLabel(slug)
    local words = {}
    for w in slug:gmatch("[^%-]+") do
        table.insert(words, w:sub(1, 1):upper() .. w:sub(2))
    end
    return table.concat(words, " ")
end

-- Строим список самых часто встречающихся тегов по факту в загруженном каталоге
-- (а не наугад/по алфавиту, как было раньше со статичным списком из 800+ штук).
local function buildPopularTagOptions()
    local novels = getAllNovels()
    if not novels or #novels == 0 then return {} end

    local freq = {}
    for _, n in ipairs(novels) do
        for _, t in ipairs(n.tags) do
            freq[t] = (freq[t] or 0) + 1
        end
    end

    local list = {}
    for slug, count in pairs(freq) do
        table.insert(list, { slug = slug, count = count })
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.slug < b.slug
    end)

    local options = {}
    for i = 1, math.min(POPULAR_TAGS_LIMIT, #list) do
        table.insert(options, { value = list[i].slug, label = slugToLabel(list[i].slug) })
    end
    return options
end

local function buildFilterList()
    return {
        {
            type         = "select",
            key          = "order",
            label        = "Order by",
            defaultValue = "reviewCount",
            options = {
                { value = "created",      label = "Latest Added" },
                { value = "avgReview",    label = "Best Rated" },
                { value = "reviewCount",  label = "Most Reviewed" },
                { value = "chapterCount", label = "Chapter Count" },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",         label = "Action" },
                { value = "adult",          label = "Adult" },
                { value = "adventure",      label = "Adventure" },
                { value = "comedy",         label = "Comedy" },
                { value = "drama",          label = "Drama" },
                { value = "ecchi",          label = "Ecchi" },
                { value = "fan-fiction",    label = "Fan-Fiction" },
                { value = "fantasy",        label = "Fantasy" },
                { value = "gender-bender",  label = "Gender Bender" },
                { value = "harem",          label = "Harem" },
                { value = "historical",     label = "Historical" },
                { value = "horror",         label = "Horror" },
                { value = "josei",          label = "Josei" },
                { value = "martial-arts",   label = "Martial Arts" },
                { value = "mature",         label = "Mature" },
                { value = "mecha",          label = "Mecha" },
                { value = "mystery",        label = "Mystery" },
                { value = "psychological",  label = "Psychological" },
                { value = "romance",        label = "Romance" },
                { value = "school-life",    label = "School Life" },
                { value = "sci-fi",         label = "Sci-fi" },
                { value = "seinen",         label = "Seinen" },
                { value = "shoujo",         label = "Shoujo" },
                { value = "shoujo-ai",      label = "Shoujo Ai" },
                { value = "shounen",        label = "Shounen" },
                { value = "shounen-ai",     label = "Shounen Ai" },
                { value = "slice-of-life",  label = "Slice of Life" },
                { value = "smut",           label = "Smut" },
                { value = "sports",         label = "Sports" },
                { value = "supernatural",   label = "Supernatural" },
                { value = "tragedy",        label = "Tragedy" },
                { value = "wuxia",          label = "Wuxia" },
                { value = "xianxia",        label = "Xianxia" },
                { value = "xuanhuan",       label = "Xuanhuan" },
                { value = "yaoi",           label = "Yaoi" },
                { value = "yuri",           label = "Yuri" },
            }
        },
        {
            type    = "tristate",
            key     = "tags",
            label   = "Popular Tags",
            options = buildPopularTagOptions(),
        },
        {
            type         = "text",
            key          = "tags_search",
            label        = "Other tags (separated by commas: reincarnation, op-mc, harem...)",
            defaultValue = "",
        },
    }
end

function getFilterList()
    if not _filterListCache then
        _filterListCache = buildFilterList()
    end
    return _filterListCache
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    if checkCaptcha(body) then return nil end
    local el = html_select_first(body, "h1.novel-title")
    return el and string_clean(el.text) or "Untitled"
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img.novel-image", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    if checkCaptcha(body) then return nil end
    local el = html_select_first(body, "div.synopsis.w-richtext")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    if checkCaptcha(body) then return {} end
    local genres = {}
    for _, el in ipairs(html_select(body, ".genre-tags")) do
        local label = string_trim(el.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Rating ─────────────────────────────────────────────────────────────────

-- Рейтинг книги со страницы книги: <div id="avg-rating">4</div>
-- (значение совпадает с полем average-review из API каталога, шкала 0-5).
function getBookRating(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    if checkCaptcha(r.body) then return nil end
    local el = html_select_first(r.body, "#avg-rating")
    return el and string_clean(el.text) or nil
end

-- ── Chapter list (paginated via parsePage) ─────────────────────────────────

function parsePage(bookUrl, page)
    local body = fetchPage(bookUrl)
    if not body then
        log_error("mvlempyr: parsePage failed to fetch " .. bookUrl)
        return { chapters = {}, totalPages = 1 }
    end
    if checkCaptcha(body) then return { chapters = {}, totalPages = 1 } end

    local el = html_select_first(body, "#novel-code")
    if not el then return { chapters = {}, totalPages = 1 } end
    local rawCode = string_trim(el.text)
    local num = tonumber(rawCode)
    if not num then return { chapters = {}, totalPages = 1 } end
    local novelId = convertNovelId(num)

    local probeUrl = chapSite .. "wp-json/wp/v2/posts?tags=" .. tostring(novelId) .. "&per_page=500&page=1"
    local pr = http_get(probeUrl)
    local totalPages = 1
    local posts
    if pr.success then
        if pr.headers and pr.headers["x-wp-totalpages"] and #pr.headers["x-wp-totalpages"] > 0 then
            totalPages = tonumber(pr.headers["x-wp-totalpages"][1]) or 1
            if totalPages < 1 then totalPages = 1 end
        end
        posts = json_parse(pr.body)
    end

    local sitePage = totalPages - page + 1
    if sitePage < 1 then
        return { chapters = {}, totalPages = totalPages }
    end

    if sitePage ~= 1 then
        local url = chapSite .. "wp-json/wp/v2/posts?tags=" .. tostring(novelId)
                  .. "&per_page=500&page=" .. tostring(sitePage)
        local r = http_get(url)
        if not r.success then return { chapters = {}, totalPages = totalPages } end
        posts = json_parse(r.body)
    end

    if not posts or type(posts) ~= "table" then
        return { chapters = {}, totalPages = totalPages }
    end

    local chapters = {}
    for _, chap in ipairs(posts) do
        local acf = chap.acf or {}
        local path = "chapter/" .. (acf.novel_code or "") .. "-" .. tostring(acf.chapter_number or 0)
        table.insert(chapters, {
            title         = string_clean(acf.ch_name or ""),
            url           = baseUrl .. "/" .. path,
            releaseTime   = chap.date or "",
            chapterNumber = acf.chapter_number or 0,
        })
    end

    local reversed = {}
    for i = #chapters, 1, -1 do
        table.insert(reversed, chapters[i])
    end

    sleep(math.random(150, 300))
    return { chapters = reversed, totalPages = totalPages }
end

-- ── Chapter text ────────────────────────────────────────────────────────────

function getChapterText(html, url)
    if not html or html == "" then return "" end
    local cleaned = html_remove(html, "script", "style")
    local el = html_select_first(cleaned, "#chapter > span")
    if not el then
        el = html_select_first(cleaned, "#chapter")
    end
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
