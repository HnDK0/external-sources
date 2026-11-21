-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "wcshuba"
name     = "Wucuo Shuba"
version  = "1.0.0"
baseUrl  = "https://www.wcshuba.com/"
language = "zh"
charset  = "UTF-8"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/wcshuba.png"

-- The slider WAF answers 403 with `server: cloudflare`, which the core's
-- challenge detector reads as a CF challenge by headers alone — the plugin
-- would never see that page. The site's gate is a plain verify GET (below),
-- so opt out of the CF flow for this host and handle it in Lua.
cf_options = { whitelist = true }

-- ── Site notes ──────────────────────────────────────────────────────────────
-- wcshuba (無錯書吧) serves every path behind a "huadong" slider WAF: the
-- first request from a fresh session answers 403 with a drag-slider page.
-- The slider is decoration — the JS only calls
--   /a20be899_…_yanzheng_huadong.php?type={t}&key={k}&value={md5}
-- and that plain GET sets an httponly cookie (1 h) that unlocks the site.
-- type/key/value are constants baked into the challenge template, so the
-- whole handshake is one fixed URL (verified: the same URL unlocks a cold
-- cookie jar).
--
-- URL patterns:
--   Book:      /book/{id}.html
--   Chapters:  /chapterlist/{id}.html, then /chapterlist/{id}/{n}.html
--              (100 chapters per page)
--   Read:      /read/{id}/{chapterId}.html
--   Catalog:   /sort/ and /sort/{n}.html (all novels), 30 per page
--   Search:    /search/?searchkey={q}, /search/{n}?searchkey={q}
--
-- Both a PC and a WAP copy of each book list are in the markup, so items
-- are de-duplicated by URL.

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead. Shared libs load lazily and are cached per session.
local _libs
local function LIB(id)
    if type(require_lib) ~= "function" then
        show_error("Requires NoveLA update", "This plugin needs the shared libraries")
        error("Requires NoveLA update (require_lib)", 0)
    end
    if not _libs then _libs = {} end
    if not _libs[id] then _libs[id] = require_lib(id) end
    return _libs[id]
end

local function absUrl(href)
    return LIB("urls").absUrl(baseUrl, href)
end

-- WAF handshake: one GET on the verify endpoint sets the unlock cookie.
local WAF_SOLVE = baseUrl ..
    "a20be899_96a6_40b2_88ba_32f1f75f1552_yanzheng_huadong.php" ..
    "?type=ad82060c2e67cc7e2cc47552a4fc1242" ..
    "&key=9e7ca253cf3c2f72bca84249a5da9301" ..
    "&value=d1c130c7c810ce6a031e0cdc48795072"

local function isCaptcha(body)
    return type(body) == "string" and string.find(body, "人机身份验证", 1, true) ~= nil
end

-- The client stores response cookies itself; the explicit set_cookies is a
-- fallback for clients that strip Set-Cookie from r.headers.
local function solveWaf()
    sleep(300)
    local r = http_get(WAF_SOLVE)
    if not r.success then
        log_error("wcshuba: WAF solve failed (HTTP " .. tostring(r.code) .. ")")
        return false
    end
    local sc = r.headers and (r.headers["set-cookie"] or r.headers["Set-Cookie"])
    if type(sc) == "table" then sc = sc[1] end
    local name, value = string.match(sc or "", "^%s*([^=;%s]+)=([^;]*)")
    if name and value and value ~= "" then
        set_cookies(baseUrl, { [name] = value })
    end
    return true
end

-- The site IP-bans bursts with a long 520 stretch (measured: one run of a few
-- simultaneous requests ended in >15 min of 520 for every path). Keep the pace
-- of a human reader and solve at most once per minute — an expired cookie is
-- the only legit reason to knock on the verify endpoint again.
local _cache = {}
local _lastSolve = -60000

local function nowMs()
    if type(os_time) == "function" then return os_time() end
    return os.time() * 1000
end

-- "too many requests, wait 30 seconds" after ~15 chapter pages; the core
-- retries 429 itself but caps Retry-After at 5 s, so wait it out here.
local RATE_LIMIT_WAIT_MS = 30000

-- Re-run the WAF handshake at most once a minute (an expired cookie is the
-- only legit reason); otherwise give the cookie a moment to land.
local function ensureWaf()
    if nowMs() - _lastSolve > 60000 then
        _lastSolve = nowMs()
        solveWaf()
    else
        sleep(600)
    end
end

local function request(url)
    sleep(300)
    local r = http_get(url)
    if r.code == 429 then
        sleep(RATE_LIMIT_WAIT_MS)
        r = http_get(url)
    end
    if not r.success or isCaptcha(r.body) then
        ensureWaf()
        r = http_get(url)
    end
    if not r.success or isCaptcha(r.body) then
        log_error("wcshuba: GET failed (HTTP " .. tostring(r.code) .. ") " .. url)
        return nil
    end
    return r.body
end

-- Chapter-list pages go in bursts (same rhythm as en/novelfull.lua): the site
-- starts answering 429 after ~15 page requests in a row, so 5 per batch with a
-- pause between batches, and one retry of a failed batch after the wait.
local BURST_CHUNK  = 5
local BURST_GAP_MS = 1000

local function fetchChunk(urls)
    sleep(300)
    local rs = http_get_batch(urls)
    local bad = false
    local limited = false
    for _, r in ipairs(rs) do
        if r.code == 429 then limited = true end
        if not r.success or isCaptcha(r.body) then bad = true end
    end
    if bad then
        if limited then sleep(RATE_LIMIT_WAIT_MS) else ensureWaf() end
        rs = http_get_batch(urls)
    end
    local bodies = {}
    for i, r in ipairs(rs) do
        if r.success and not isCaptcha(r.body) then bodies[i] = r.body end
    end
    return bodies
end

local function getPage(url)
    local cached = _cache[url]
    if cached then return cached end
    local body = request(url)
    if body then _cache[url] = body end
    return body
end

-- "下一页" in the pagination markup is absent on the last page.
local function hasNextPage(body)
    return type(body) == "string" and string.find(body, 'title="下一页"', 1, true) ~= nil
end

-- Book cards are <dl> blocks (cover link + title link + description).
local function itemsFrom(body)
    local items, seen = {}, {}
    for _, dl in ipairs(html_select(body, "dl")) do
        local a = html_select_first(dl.html, 'a[href*="/book/"]')
        if a then
            local url = absUrl(a.href)
            if url ~= "" and not seen[url] then
                local title = string_clean(a.text)
                if title == "" then
                    title = string_clean(html_attr(dl.html, 'a[href*="/book/"]', "title"))
                end
                if title ~= "" then
                    seen[url] = true
                    local cover = html_attr(dl.html, "img", "data-original")
                    if cover == "" then cover = html_attr(dl.html, "img", "src") end
                    if string.find(cover, "nocover", 1, true) then cover = "" end
                    table.insert(items, {
                        title = title,
                        url   = url,
                        cover = absUrl(cover),
                    })
                end
            end
        end
    end
    return items
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = LIB("catalog").nextIndex(index)
    local url
    if page == 1 then
        url = baseUrl .. "sort/"
    else
        url = baseUrl .. "sort/" .. tostring(page) .. ".html"
    end

    local body = getPage(url)
    if not body then return { items = {}, hasNext = false } end
    return { items = itemsFrom(body), hasNext = hasNextPage(body) }
end

-- ── Search ──────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = LIB("catalog").nextIndex(index)
    local q = LIB("catalog").urlEncode(query or "")
    local url
    if page == 1 then
        url = baseUrl .. "search/?searchkey=" .. q
    else
        url = baseUrl .. "search/" .. tostring(page) .. "?searchkey=" .. q
    end

    local body = getPage(url)
    if not body then return { items = {}, hasNext = false } end
    return { items = itemsFrom(body), hasNext = hasNextPage(body) }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = getPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".booktitle h1 a")
    if not el then el = html_select_first(body, "h1.book-title") end
    if el then return string_clean(el.text) end
    return nil
end

function getBookAuthor(bookUrl)
    local body = getPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".booktitle h2 a")
    if el then return string_clean(el.text) end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = getPage(bookUrl)
    if not body then return nil end
    local src = html_attr(body, "img.book-cover", "src")
    if src == "" then src = html_attr(body, "div.book a.cover img", "src") end
    if src == "" then return nil end
    return absUrl(src)
end

function getBookDescription(bookUrl)
    local body = getPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".bookintro")
    if not el then return nil end
    local text = html_text(el.html)
    local desc = string.match(text, "簡介[:：]%s*(.+)$")
    desc = string_trim(desc or text)
    if desc == "" then return nil end
    return desc
end

function getBookGenres(bookUrl)
    local body = getPage(bookUrl)
    if not body then return nil end
    return LIB("meta").collectGenres(html_select(body, ".bookintro a.tag-link"), { clean = true })
end

-- ".bookdes" holds "小說狀態：連載 | 72萬字 / … / 最後更新：2026-11-15 06:58:48".
local function bookDesText(bookUrl)
    local body = getPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".bookdes")
    if not el then return nil end
    return html_text(el.html)
end

function getBookStatus(bookUrl)
    local text = bookDesText(bookUrl)
    if not text then return nil end
    local status = string.match(text, "小說狀態[:：]%s*([^%s]+)")
    if not status then return nil end
    return string_clean(status)
end

function getBookLastUpdate(bookUrl)
    local text = bookDesText(bookUrl)
    if not text then return nil end
    local date = string.match(text, "最後更新[:：]%s*(%d%d%d%d%-%d%d%-%d%d)")
    if not date then date = string.match(text, "更新[:：]%s*(%d%d%d%d%-%d%d%-%d%d)") end
    return date
end

-- ── Chapter list ────────────────────────────────────────────────────────────
-- The index page lists its own chapters plus a <select> with every page URL,
-- 100 chapters per page. Remaining pages are fetched in bursts (fetchChunk):
-- 9448-chapter books have 95 of them, and one request per page in a row is
-- what the site answers with 429.

function getChapterList(bookUrl)
    local id = string.match(bookUrl, "/book/(%d+)")
    if not id then
        log_error("wcshuba: cannot extract book id from " .. bookUrl)
        return {}
    end

    local firstUrl = baseUrl .. "chapterlist/" .. id .. ".html"
    local first = getPage(firstUrl)
    if not first then return {} end

    local pages, seenPage = {}, {}
    for opt in string.gmatch(first, '<option value="(/chapterlist/[^"]+)"') do
        if not seenPage[opt] then
            seenPage[opt] = true
            table.insert(pages, opt)
        end
    end
    if #pages == 0 then pages = { "/chapterlist/" .. id .. ".html" } end

    local bodies = { first }
    local p = 2
    while p <= #pages do
        local last = math.min(p + BURST_CHUNK - 1, #pages)
        local urls = {}
        for i = p, last do urls[#urls + 1] = absUrl(pages[i]) end
        local got = fetchChunk(urls)
        for i = 1, #urls do
            if got[i] then table.insert(bodies, got[i]) end
        end
        if last < #pages then sleep(BURST_GAP_MS) end
        p = last + 1
    end

    local chapters, seen = {}, {}
    for _, body in ipairs(bodies) do
        for _, a in ipairs(html_select(body, 'a[rel="chapter"]')) do
            local url = absUrl(a.href)
            if url ~= "" and not seen[url] then
                seen[url] = true
                table.insert(chapters, { title = string_clean(a.text), url = url })
            end
        end
    end
    return chapters
end

-- ── Hash for updates ───────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
    -- Uncached fetch (see request) so a new chapter always changes the hash.
    local body = request(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".bookdes")
    if not el then return nil end
    return string_clean(el.text)
end

-- ── Chapter text ────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local body = html
    -- The engine's own fetch may land on the WAF page before the cookie exists.
    if body == nil or body == "" or isCaptcha(body) then
        body = getPage(url)
    end
    if not body then return "" end

    local cleaned = html_remove(body, "script", "style", "ins", "iframe", "nav", "#play")
    local el = html_select_first(cleaned, "#booktxt")
    if not el then el = html_select_first(cleaned, "#content") end
    if not el then return "" end

    return LIB("content").standardTransforms(html_text(el.html), { domain = baseUrl, lang = "zh" })
end
