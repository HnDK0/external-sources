-- =====================================================================
-- Lib: cdnlibs — shared source layer for the LibGroup CDN family:
--      ru/mangalib (siteId 1), ru/hentailib (siteId 4) — manga pages,
--      ru/ranobelib (siteId 3) — novel text (TipTap / ProseMirror).
--      Backend: https://api.cdnlibs.org/api/manga/ with a "Site-Id"
--      header and a site_id[0] query parameter.
-- Loaded via require_lib("cdnlibs"). No dependencies on other libs.
--
-- A plugin keeps its metadata, its getFilterList and its hooks, then
-- installs every shared entry point with one call:
--
--   local CDN = require_lib("cdnlibs")
--   CDN.setup({ id = "mangalib", baseUrl = "https://mangalib.me/",
--               siteId = "1", mode = "manga", ... })
--
-- Config:
--   baseUrl           string, required — plugin baseUrl ("https://x.me/")
--   siteId            string/number, required — "Site-Id" + site_id[0]
--   mode              "manga" (default) | "novel"
--   id                plugin id, used as the log prefix
--   domain            host for Referer/Origin; derived from baseUrl
--   pageCdnPrefix     manga: host prepended to scheme-less page urls
--   resolveSlugUrl    manga: re-resolve data.slug_url before the chapter
--                     request (hentailib serves another slug than the URL)
--   ageFilterKey      age filter key of getFilterList: "age" (mangalib) or
--                     "ageRestriction" (hentailib/ranobelib, default)
--   descriptionFields query string of getBookDescription
--   authDomains       localStorage domains probed for the Bearer token
--
-- Hooks (all optional):
--   buildHeaders(h)             h = default headers; return a table to
--                               replace them (or mutate and return nil)
--   ageGateFallback(bookUrl, body)
--                               called when the book JSON request failed
--                               and the site page was fetched instead
--   textExtractor(node, opts)   TipTap/ProseMirror node -> string:
--                               opts == nil          plain text (summary)
--                               opts.html            chapter HTML (novel)
--                               opts.attachMap       id -> attachment url
-- =====================================================================

local M = {}

local API_BASE = "https://api.cdnlibs.org/api/manga/"
local USER_AGENT = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.004)"
  .. " AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36"
local FAMILY_DOMAINS = { "mangalib.me", "hentailib.me", "ranobelib.me" }

-- Manga detail fields the MangaLib/HentaiLib SPA requests for the book page.
local DETAIL_FIELDS = "fields[]=eng_name&fields[]=otherNames&fields[]=summary&fields[]=rate"
  .. "&fields[]=genres&fields[]=tags&fields[]=teams&fields[]=authors&fields[]=publisher"
  .. "&fields[]=userRating&fields[]=manga_status_id&fields[]=status_id&fields[]=artists"

-- Entry points installed by setup(); "getPageList" only in manga mode.
local ENTRY_POINTS = {
    "getCatalogList", "getCatalogSearch", "getCatalogFiltered",
    "getBookTitle", "getBookCoverImageUrl", "getBookDescription",
    "getBookGenres", "getBookRating", "getBookStatus", "getBookLastUpdate",
    "getChapterList", "getChapterListHash", "getPageList", "getChapterText",
}

M.entryPoints = ENTRY_POINTS

-- ── JSON helpers ───────────────────────────────────────────────────────

local function getPath(tbl, path)
    if not tbl or not path then return nil end
    local cur = tbl
    for key in path:gmatch("[^.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

local function pickTitle(data)
    return data.rus_name or data.eng_name or data.name or ""
end

-- Site rating is on a 10-point scale ("9.7"); the engine understands
-- "9.7/10". "0"/empty means there is no rating yet.
local function formatRating(avg)
    if not avg or avg == "" or avg == "0" then return nil end
    return avg .. "/10"
end

-- The API answers with an HTML page when the request is rejected.
local function isErrorResponse(body)
    if not body or body == "" then return true end
    if body:sub(1, 15):find("<!DOCTYPE") or body:sub(1, 6):lower():find("<html") then
        return true
    end
    return false
end

-- https://site/ru/my-book -> "my-book"
local function extractSlug(bookUrl)
    local clean = bookUrl:gsub("/?$", "")
    return clean:match("([^/]+)$")
end

local function trim(s)
    if type(s) ~= "string" then return s end
    if type(string_trim) == "function" then return string_trim(s) end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clean(s)
    if type(string_clean) == "function" then return string_clean(s) end
    return trim(s)
end

-- "img/p.jpg" -> "https://img/p.jpg", "//cdn/p.jpg" -> "https://cdn/p.jpg"
local function absImg(url)
    if url:sub(1, 2) == "//" then return "https:" .. url end
    if url:find("://") then return url end
    return "https:" .. url
end

-- ── Module ─────────────────────────────────────────────────────────────

--- Bind the family implementation to `cfg` and install the public entry
--- points as globals. Returns the table of installed functions.
function M.setup(cfg)
    if type(cfg) ~= "table" then
        error("cdnlibs: setup(cfg) requires a config table", 0)
    end
    if type(cfg.baseUrl) ~= "string" or cfg.baseUrl == "" then
        error("cdnlibs: cfg.baseUrl is required", 0)
    end
    if cfg.siteId == nil then
        error("cdnlibs: cfg.siteId is required", 0)
    end

    local baseUrl    = cfg.baseUrl
    local siteId     = tostring(cfg.siteId)
    local mode       = cfg.mode or "manga"
    local tag        = cfg.id or cfg.baseUrl
    local domain     = cfg.domain or (baseUrl:match("^https?://([^/]+)") or "")
    local ageKey     = cfg.ageFilterKey or "ageRestriction"
    local descFields = cfg.descriptionFields or DETAIL_FIELDS
    local isManga    = mode ~= "novel"

    -- The own domain is probed first, then the rest of the family
    -- (all three sites share one auth storage).
    local authDomains = cfg.authDomains
    if not authDomains then
        authDomains = { domain }
        for _, d in ipairs(FAMILY_DOMAINS) do
            if d ~= domain then authDomains[#authDomains + 1] = d end
        end
    end

    local userId = nil

    local function parseAuth()
        if type(get_localStorage) ~= "function" then return nil, nil end
        for _, d in ipairs(authDomains) do
            local raw = get_localStorage(d, "auth")
            if raw and raw ~= "" then
                local ok, data = pcall(json_parse, raw)
                if ok and data then
                    local at = data.token and data.token.access_token
                    local uid = data.auth and data.auth.id
                    if at and uid then
                        userId = tostring(uid)
                        return "Bearer " .. at, userId
                    end
                end
            end
        end
        return nil, nil
    end

    local function defaultHeaders()
        local h = {
            ["Site-Id"]         = siteId,
            ["User-Agent"]      = USER_AGENT,
            ["Accept"]          = "application/json, text/plain, */*",
            ["Accept-Language"] = "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
            ["Referer"]         = "https://" .. domain .. "/",
            ["Origin"]          = "https://" .. domain,
            ["Sec-Fetch-Dest"]  = "empty",
            ["Sec-Fetch-Mode"]  = "cors",
            ["Sec-Fetch-Site"]  = "cross-site",
        }
        local token = parseAuth()
        if token then h["Authorization"] = token end
        return h
    end

    local function headers()
        local h = defaultHeaders()
        if cfg.buildHeaders then
            return cfg.buildHeaders(h) or h
        end
        return h
    end

    local function get(url)
        return http_get(url, { headers = headers() })
    end

    -- ── Book details ───────────────────────────────────────────────────

    local function fetchBookJson(bookUrl)
        local slug = extractSlug(bookUrl)
        if not slug then return nil end
        local r = get(API_BASE .. slug)
        if not r.success then
            if cfg.ageGateFallback then
                local page = get(bookUrl)
                if page.success and page.body then
                    cfg.ageGateFallback(bookUrl, page.body)
                end
            end
            return nil
        end
        if isErrorResponse(r.body) then return nil end
        local parsed = json_parse(r.body)
        return parsed and parsed.data or nil
    end

    local function fetchBook(url)
        local r = get(url)
        if not r.success then return nil end
        if isErrorResponse(r.body) then return nil end
        local parsed = json_parse(r.body)
        return parsed and parsed.data or nil
    end

    local function fetchBookBySlug(bookUrl, query)
        local slug = extractSlug(bookUrl)
        if not slug then return nil end
        return fetchBook(API_BASE .. slug .. query)
    end

    -- ── Chapter payload ────────────────────────────────────────────────

    -- Returns (data, "ok") | (nil, "failed") when the user was notified
    -- | (nil, "empty") for a silent empty result.
    local function fetchChapter(chapterUrl)
        if not chapterUrl or chapterUrl == "" then return nil, "empty" end

        local slug   = chapterUrl:match("/ru/([^/]+)/read/")
        local volume = chapterUrl:match("/v([^/]+)/c")
        local number = chapterUrl:match("/v[^/]+/c([^?]+)")
        local bid    = chapterUrl:match("[?&]bid=([^&]+)")

        if not slug or not volume or not number then
            log_error(tag .. ": cannot parse chapterUrl: " .. chapterUrl)
            return nil, "empty"
        end

        if cfg.resolveSlugUrl then
            local infoR = get(API_BASE .. slug)
            if infoR.success then
                local infoP = json_parse(infoR.body)
                if infoP and infoP.data and infoP.data.slug_url then
                    slug = infoP.data.slug_url
                end
            end
        end

        local apiUrl = API_BASE .. slug .. "/chapter?volume=" .. volume .. "&number=" .. number
        if bid then apiUrl = apiUrl .. "&branch_id=" .. bid end

        log_error(tag .. " DEBUG: apiUrl=" .. apiUrl)
        local r = get(apiUrl)
        log_error(tag .. " DEBUG: success=" .. tostring(r.success) .. " code=" .. tostring(r.code)
            .. " bodyLen=" .. tostring(#(r.body or "")))
        if r.body then
            log_error(tag .. " DEBUG: body(first500)=" .. tostring(r.body:sub(1, 500)))
        end

        if not r.success then
            if show_error then
                show_error("Ошибка загрузки",
                    "Не удалось загрузить страницы главы (HTTP " .. tostring(r.code) .. ").\n"
                    .. "Возможно, глава не существует или требуется авторизация.")
            end
            return nil, "failed"
        end

        if isErrorResponse(r.body) then
            log_error(tag .. " DEBUG: isErrorResponse=true")
            if show_error then
                show_error("Ошибка загрузки",
                    "Не удалось загрузить страницы главы.\nТребуется авторизация.")
            end
            return nil, "failed"
        end

        local parsed = json_parse(r.body)
        if not parsed or not parsed.data then
            log_error(tag .. " DEBUG: parse failed or no data")
            return nil, "empty"
        end

        local data = parsed.data
        log_error(tag .. " DEBUG: data keys=" .. tostring(data.pages and "has_pages" or "no_pages")
            .. " restricted_view=" .. tostring(data.restricted_view and "present" or "nil")
            .. " bundle=" .. tostring(data.bundle and "present" or "nil")
            .. " content=" .. tostring(data.content and "present" or "nil"))

        local rv = data.restricted_view
        if rv then
            log_error(tag .. " DEBUG: restricted_view.is_open=" .. tostring(rv.is_open)
                .. " price=" .. tostring(rv.price))
        end
        if rv and rv.is_open == false then
            local price = rv.price or 0
            local msg = "Эта глава является платной."
            if price > 0 then msg = msg .. "\nЦена: " .. tostring(price) .. " ₽" end
            msg = msg .. "\nКупить можно на " .. domain
            if show_error then show_error("Платная глава", msg) end
            return nil, "failed"
        end

        if data.bundle and data.bundle.is_open == false then
            local price = data.bundle.price or 0
            local name = data.bundle.name or ""
            local msg = "Эта глава является платной."
            if name ~= "" then msg = msg .. "\nБандл: " .. name end
            if price > 0 then msg = msg .. "\nЦена: " .. tostring(price) .. " ₽" end
            msg = msg .. "\nКупить можно на " .. domain
            if show_error then show_error("Платный том", msg) end
            return nil, "failed"
        end

        return data, "ok"
    end

    local function attachmentMap(attachments)
        local map = {}
        if attachments then
            for _, att in ipairs(attachments) do
                local attId = tostring(att.id or att.name or "")
                local attUrl = att.url or ""
                if attId ~= "" and attUrl ~= "" then map[attId] = attUrl end
            end
        end
        return map
    end

    -- Manga: pages[] first, TipTap images from the content node otherwise.
    local function chapterPages(data)
        if data.pages and type(data.pages) == "table" then
            log_error(tag .. " DEBUG: data.pages count=" .. tostring(#data.pages))
            local pages = {}
            for _, page in ipairs(data.pages) do
                local url = page.url
                if url and url ~= "" then
                    if not url:find("://") then url = (cfg.pageCdnPrefix or "") .. url end
                    pages[#pages + 1] = url
                end
            end
            log_error(tag .. " DEBUG: returning pages count=" .. tostring(#pages))
            return pages
        end

        local contentNode = data.content
        local attachments = data.attachments
        log_error(tag .. " DEBUG: contentNode=" .. tostring(contentNode and "present" or "nil")
            .. " attachments=" .. tostring(attachments and "present" or "nil"))

        local attachMap = attachmentMap(attachments)
        local pages = {}

        local function extractImages(node)
            if type(node) ~= "table" then return end
            if node.type == "image" then
                local src = node.attrs and node.attrs.src
                if src and src ~= "" then
                    local imageUrl = attachMap[src] or src
                    imageUrl = absImg(imageUrl)
                    pages[#pages + 1] = imageUrl
                end
            end
            if node.content and type(node.content) == "table" then
                for _, child in ipairs(node.content) do extractImages(child) end
            end
        end

        if type(contentNode) == "table" and contentNode.content then
            extractImages(contentNode)
        end

        log_error(tag .. " DEBUG: final pages count=" .. tostring(#pages))
        return pages
    end

    -- Novel: strips the site watermark and the duplicated chapter heading.
    local function standardTransforms(text)
        if not text or text == "" then return "" end
        if type(string_normalize) == "function" then text = string_normalize(text) end
        if type(regex_replace) ~= "function" then return trim(text) end
        local domainPattern = domain:gsub("%.", "%%.")
        text = regex_replace(text,
            "(?i)(?:^|\\n)[^<\\n]*" .. domainPattern .. ".*?\\n", "\n")
        text = regex_replace(text,
            "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
        return trim(text)
    end

    -- ── Entry points ───────────────────────────────────────────────────

    local function mapItems(parsed, slugFirst)
        local items = {}
        for _, entry in ipairs(parsed.data) do
            local title = pickTitle(entry)
            local slug = slugFirst and (entry.slug or entry.slug_url or "")
                or (entry.slug_url or entry.slug or "")
            local cover = getPath(entry, "cover.default") or ""
            if title ~= "" and slug ~= "" then
                local item = {
                    title = clean(title),
                    url   = baseUrl .. "ru/" .. slug,
                    cover = cover,
                }
                item.rating = formatRating(getPath(entry, "rating.average"))
                items[#items + 1] = item
            end
        end
        return items
    end

    local function catalogRequest(url, slugFirst)
        local r = get(url)
        if not r.success then return { items = {}, hasNext = false } end
        local parsed = json_parse(r.body)
        if not parsed or not parsed.data then return { items = {}, hasNext = false } end
        return { items = mapItems(parsed, slugFirst), parsed = parsed }
    end

    local api = {}

    function api.getCatalogList(index)
        local page = (index or 0) + 1
        local url = API_BASE .. "?site_id[0]=" .. siteId ..
            "&page=" .. tostring(page) ..
            "&sort_by=rating_score&sort_type=desc&chapters[min]=1"
        local res = catalogRequest(url, true)
        local hasNext = getPath(res.parsed, "meta.has_next_page")
        return { items = res.items, hasNext = hasNext == true or #res.items > 0 }
    end

    function api.getCatalogSearch(index, query)
        local page = (index or 0) + 1
        local url = API_BASE .. "?site_id[0]=" .. siteId ..
            "&page=" .. tostring(page) ..
            "&q=" .. url_encode(query)
        local res = catalogRequest(url, false)
        local hasNext = getPath(res.parsed, "meta.has_next_page")
        return { items = res.items, hasNext = hasNext == true }
    end

    function api.getCatalogFiltered(index, filters)
        filters = type(filters) == "table" and filters or {}
        local page = (index or 0) + 1
        local sort_by   = filters["sort_by"]   or "rating_score"
        local sort_type = filters["sort_type"] or "desc"
        local req_ch    = filters["require_chapters"]

        local url = API_BASE .. "?site_id[0]=" .. siteId
            .. "&page="      .. tostring(page)
            .. "&sort_by="   .. sort_by
            .. "&sort_type=" .. sort_type

        if req_ch ~= "false" then url = url .. "&chap_count_min=1" end

        local arrays = {
            { "types_included",          "types[]=" },
            { "format_included",         "format[]=" },
            { "format_excluded",         "format_exclude[]=" },
            { "scanlateStatus_included", "scanlate_status[]=" },
            { "manga_status_included",   "status[]=" },
            { ageKey .. "_included",     "caution[]=" },
            { "genres_included",         "genres[]=" },
            { "genres_excluded",         "genres_exclude[]=" },
        }
        for _, spec in ipairs(arrays) do
            local values = filters[spec[1]]
            if type(values) == "table" then
                for _, v in ipairs(values) do url = url .. "&" .. spec[2] .. v end
            end
        end

        local res = catalogRequest(url, false)
        local hasNext = getPath(res.parsed, "meta.has_next_page")
        return { items = res.items, hasNext = hasNext == true or #res.items > 0 }
    end

    function api.getBookTitle(bookUrl)
        local data = fetchBookJson(bookUrl)
        if not data then return nil end
        local title
        if data.names then
            title = data.names.rus or data.names.eng or data.rus_name or data.name
        else
            title = data.rus_name or data.eng_name or data.name
        end
        return title and clean(title) or nil
    end

    function api.getBookCoverImageUrl(bookUrl)
        local data = fetchBookJson(bookUrl)
        if not data then return nil end
        local cover = getPath(data, "cover.default") or ""
        return cover ~= "" and cover or nil
    end

    function api.getBookDescription(bookUrl)
        local data = fetchBookBySlug(bookUrl, "?" .. descFields)
        if not data then return nil end
        local summary = data.summary or data.description
        if type(summary) == "table" then
            if not cfg.textExtractor then return nil end
            local desc = cfg.textExtractor(summary)
            if desc and trim(desc) ~= "" then return trim(desc) end
            return nil
        end
        if type(summary) == "string" and trim(summary) ~= "" then return trim(summary) end
        return nil
    end

    function api.getBookGenres(bookUrl)
        local data = fetchBookBySlug(bookUrl, "?fields[]=genres&fields[]=tags")
        if not data then return {} end
        local genres = {}
        local function addList(list)
            if not list then return end
            for _, item in ipairs(list) do
                local label = trim(item.name or "")
                if label ~= "" then genres[#genres + 1] = label end
            end
        end
        addList(data.genres)
        addList(data.tags)
        return genres
    end

    function api.getBookRating(bookUrl)
        local data = fetchBookBySlug(bookUrl, "?fields[]=rate_avg&fields[]=rate")
        if not data then return nil end
        return formatRating(getPath(data, "rating.average"))
    end

    function api.getBookStatus(bookUrl)
        local data = fetchBookBySlug(bookUrl, "?fields[]=updated_at")
        if not data then return nil end
        local st = data.status
        if type(st) == "table" and st.label then
            local label = trim(st.label)
            return label ~= "" and clean(label) or nil
        end
        return nil
    end

    function api.getBookLastUpdate(bookUrl)
        local data = fetchBookBySlug(bookUrl, "?fields[]=updated_at")
        if not data then return nil end
        local ua = data.updated_at
        if not ua or ua == "" then return nil end
        local date = string.match(ua, "^(%d%d%d%d%-%d%d%-%d%d)")
        return date ~= "" and date or nil
    end

    function api.getChapterList(bookUrl)
        local slug = extractSlug(bookUrl)
        if not slug then
            log_error(tag .. ": cannot extract slug from " .. bookUrl)
            return {}
        end

        local r = get(API_BASE .. slug .. "/chapters")
        if not r.success then
            log_error(tag .. ": chapters failed code=" .. tostring(r.code))
            return {}
        end

        if isErrorResponse(r.body) then
            if show_error then
                show_error("Ошибка загрузки",
                    "Не удалось загрузить список глав.\nВозможно, требуется авторизация.")
            end
            return nil
        end

        local parsed = json_parse(r.body)
        if not parsed or not parsed.data then return {} end

        local raw = {}
        for _, chapter in ipairs(parsed.data) do
            local volume = tostring(chapter.volume or "")
            local number = tostring(chapter.number or "")
            local name   = chapter.name and chapter.name ~= "" and chapter.name or nil
            local bid    = "0"
            local isPaid = false

            if chapter.branches and chapter.branches[1] then
                local br = chapter.branches[1]
                if br.branch_id ~= nil and br.branch_id ~= "" then
                    bid = tostring(br.branch_id)
                end
                if br.restricted_view and br.restricted_view.is_open == false then
                    isPaid = true
                end
            end
            if chapter.bundle_id then isPaid = true end

            local title = "Том " .. volume .. " Глава " .. number
            if name then title = title .. " " .. name end
            if isPaid then title = title .. " 🔒" end

            local chUrl = baseUrl .. "ru/" .. slug .. "/read/v" .. volume .. "/c" .. number
            local sep = "?"
            if bid ~= "0" then chUrl = chUrl .. sep .. "bid=" .. bid; sep = "&" end
            if userId then chUrl = chUrl .. sep .. "ui=" .. userId end

            raw[#raw + 1] = {
                result = {
                    title  = clean(title),
                    url    = chUrl,
                    volume = "Том " .. volume,
                },
                index = chapter.index or #raw + 1,
            }
        end

        table.sort(raw, function(a, b) return a.index < b.index end)

        local chapters = {}
        for _, item in ipairs(raw) do chapters[#chapters + 1] = item.result end
        return chapters
    end

    function api.getChapterListHash(bookUrl)
        local slug = extractSlug(bookUrl)
        if not slug then return nil end
        local r = get(API_BASE .. slug .. "/chapters")
        if not r.success then return nil end
        if isErrorResponse(r.body) then return nil end
        local parsed = json_parse(r.body)
        if not parsed or not parsed.data then return nil end
        local chapters = parsed.data
        local last = chapters[#chapters]
        return last and tostring(last.item_number or last.number) or nil
    end

    if isManga then
        function api.getPageList(html, chapterUrl)
            local data, status = fetchChapter(chapterUrl)
            if status == "failed" then return nil end
            if status ~= "ok" then return {} end
            return chapterPages(data)
        end

        function api.getChapterText(html, chapterUrl)
            local pages = api.getPageList(html, chapterUrl) or {}
            local out = {}
            for _, p in ipairs(pages) do out[#out + 1] = '<img src="' .. p .. '">' end
            return table.concat(out, "\n")
        end
    else
        function api.getChapterText(html, chapterUrl)
            local data, status = fetchChapter(chapterUrl)
            if status ~= "ok" then return "" end
            if not cfg.textExtractor then return "" end
            local rendered = cfg.textExtractor(data.content, {
                html = true,
                attachMap = attachmentMap(data.attachments),
            })
            if not rendered or rendered == "" then return "" end
            if type(html_text) == "function" then rendered = html_text(rendered) end
            return standardTransforms(rendered)
        end
    end

    local G = _G
    if type(G) ~= "table" then
        error("cdnlibs: _G unavailable, cannot install entry points", 0)
    end
    for _, name in ipairs(ENTRY_POINTS) do
        local fn = api[name]
        if fn ~= nil then G[name] = fn end
    end
    return api
end

return M
