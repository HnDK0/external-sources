-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "ixdzs8"
name     = "iXdzs8"
version  = "1.0.3"
baseUrl  = "https://www.ixdzs8.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ixdzs8.png"

-- ── Changelog (1.0.0 → 1.0.1) ───────────────────────────────────────────────
-- FIX: Chapter list now uses the POST /novel/clist/ API instead of
--      synthesizing URLs from .catalog count. The API returns correct
--      ordernums (which map to p{N}.html URLs), avoiding the bug where
--      some novels use p1.html as the novel info page (not chapter 1).
-- ────────────────────────────────────────────────────────────────────────────

-- ── Site notes ──────────────────────────────────────────────────────────────
-- ixdzs8 (爱下电子书) is a Simplified-Chinese novel site.
--
-- URL patterns:
--   Book page:  /read/{bookId}/                 e.g. /read/620438/
--   Chapter:    /read/{bookId}/p{N}.html        e.g. /read/620438/p1.html
--   Catalog:    /sort/{catId}/                  e.g. /sort/1/ (玄幻)
--   Catalog pg: /sort/{catId}/index-0-0-0-{N}.html
--   Search:     /bsearch?q={query}              (GET, URL-encoded UTF-8)
--   Search pg:  /bsearch?q={query}&page={N}
--
-- Anti-bot:
--   First request to ANY chapter URL returns a 384-byte page:
--     <script>let token = "BASE64..."; window.location.href =
--       location.pathname + "?challenge=" + encodeURIComponent(token);</script>
--   Following up with `?challenge={token}` returns the real chapter HTML.
--   The token is fresh per request, so we must do the two-step dance every
--   time we fetch a chapter. We implement this in `fetchChapter`.
--
-- Chapter content:
--   The chapter body lives in a single <section> element inside
--   <article class="page-content">. Each paragraph is a <p>. There is no
--   inline noise — the section is clean prose. The chapter title is in
--   <h1>, and the book title is in <h2>.
--
-- Chapter list:
--   The book page only shows the latest 10 chapters inline. The total
--   count is in `.catalog` as text "共{N}章". To build the full list we
--   parse the count and synthesize URLs /read/{bookId}/p1.html ..
--   /read/{bookId}/p{N}.html. (chapter_id == page number; verified
--   sequential across multiple novels.)
-- ────────────────────────────────────────────────────────────────────────────

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

-- Session-cached book page (shared fetch lib): the book page is read by the
-- title/cover/description/status functions in one adapter run.
-- getChapterListHash stays on a direct http_get — the hash must see a fresh
-- page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Extract bookId from a book URL like /read/620438/ or /read/620438
local function extractBookId(bookUrl)
  return string.match(bookUrl, "/read/(%d+)")
end

-- Apply standard content transforms from the shared content lib: strip site
-- domain references, the leading chapter title (a duplicated
-- "第N章 第N章 rest" prefix collapses into the same strip) and the
-- translator/editor attribution lines.
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
end

-- ixdzs8 anti-bot: every chapter request first returns a 384-byte
-- challenge page with `let token = "..."; window.location.href = ...?challenge=...`.
-- We extract the token and re-request with ?challenge={token}.
-- Returns the body of the real chapter page, or "" on failure.
local function fetchChapter(chapterUrl)
  local r = http_get(chapterUrl)
  if not r.success then return "" end

  -- If the response doesn't look like the challenge page, return it directly.
  if not string.find(r.body, "正在验证浏览器", 1, true) then
    return r.body
  end

  -- Extract the token: let token = "....";
  local token = string.match(r.body, 'let%s+token%s*=%s*"([^"]+)"')
  if not token or token == "" then return r.body end

  -- Re-request with ?challenge={token}. If the URL already has a query
  -- string, append with & instead of ?.
  local sep = string.find(chapterUrl, "?", 1, true) and "&" or "?"
  local challengeUrl = chapterUrl .. sep .. "challenge=" .. url_encode(token)
  local r2 = http_get(challengeUrl)
  if not r2.success then return "" end
  return r2.body
end

-- ── Catalog ─────────────────────────────────────────────────────────────────
-- /sort/{catId}/ returns ~20 books per page; pagination via
-- /sort/{catId}/index-0-0-0-{N}.html (N starts at 1).

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url
  if page == 1 then
    url = baseUrl .. "sort/1/"
  else
    url = baseUrl .. "sort/1/index-0-0-0-" .. tostring(page) .. ".html"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  -- Each book is a <li class="burl"> containing .l-img (with cover) and
  -- .l-info (with h3.bname a). Iterating .l-info alone loses the cover,
  -- so iterate the <li> wrapper.
  for _, li in ipairs(html_select(r.body, "main li.burl")) do
    local titleEl = html_select_first(li.html, "h3.bname a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(li.html, "img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = absUrl(cover)
        })
      end
    end
  end

  -- hasNext: look for a next-page link.
  local hasNext = false
  for _, a in ipairs(html_select(r.body, ".page a")) do
    local txt = string_clean(a.text)
    if txt == "»" or string.find(txt, "下一页") or string.find(txt, "下頁") then
      hasNext = true
      break
    end
  end
  -- Fallback heuristic: if we got a full page, assume there might be more.
  if #items >= 10 then hasNext = true end

  return { items = items, hasNext = hasNext }
end

-- ── Search ──────────────────────────────────────────────────────────────────
-- /bsearch?q={query} returns 10 results per page; pagination via &page={N}.

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local encoded = url_encode(query)
  local url = baseUrl .. "bsearch?q=" .. encoded .. "&page=" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, "main li.burl")) do
    local titleEl = html_select_first(li.html, "h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(li.html, "img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = absUrl(cover)
        })
      end
    end
  end

  local hasNext = false
  for _, a in ipairs(html_select(r.body, ".page a")) do
    local txt = string_clean(a.text)
    if txt == "»" or string.find(txt, "下一页") or string.find(txt, "下頁") then
      hasNext = true
      break
    end
  end
  if #items >= 10 then hasNext = true end

  return { items = items, hasNext = hasNext }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".panel img", "src")
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  -- The description lives in the 4th .panel (内容简介).
  for _, panel in ipairs(html_select(body, ".panel")) do
    local text = panel.text
    if string.find(text, "内容简介") or string.find(text, "简介") then
      -- Strip the heading line.
      local cleaned = html_remove(panel.html, "h2", "h3")
      local el = html_select_first(cleaned, ".panel")
      if el then return string_trim(el.text) end
      return string_trim(html_text(cleaned))
    end
  end
  return nil
end

-- ── Chapter list (POST API with .catalog fallback) ─────────────────────────
-- ixdzs8 has a dedicated chapter list API: POST /novel/clist/ with body
-- bid={bookId}. Returns JSON: {"rs":200,"data":[{"ordernum":"2","title":"..."}, ...]}
-- The ordernum maps directly to the chapter URL: /read/{bookId}/p{ordernum}.html
-- Note: ordernum starts at 2 (p1.html is the novel info page, not chapter 1).
--
-- FALLBACK: If the API returns empty data (e.g. due to Cloudflare blocking),
-- we parse the book page HTML for .catalog "共{N}章" and synthesize URLs
-- /read/{bookId}/p2.html through /read/{bookId}/p{N+1}.html.
-- (p1.html is the novel info page; chapters start at p2.html.)

function getChapterList(bookUrl)
  local bookId = extractBookId(bookUrl)
  if not bookId then
    log_error("ixdzs8: cannot extract bookId from " .. bookUrl)
    return {}
  end

  -- Try the POST API first.
  local apiUrl = baseUrl .. "novel/clist/"
  local payload = "bid=" .. bookId
  local r = http_post(apiUrl, payload, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
  })

  if r.success then
    local data = json_parse(r.body)
    if data and data.data and #data.data > 0 then
      local chapters = {}
      for _, ch in ipairs(data.data) do
        local ordernum = ch.ordernum or ch["ordernum"]
        local title = ch.title or ch["title"]
        if ordernum and title then
          local chUrl = baseUrl .. "read/" .. bookId .. "/p" .. tostring(ordernum) .. ".html"
          table.insert(chapters, { title = string_clean(title), url = chUrl })
        end
      end
      if #chapters > 0 then return chapters end
    end
  end

  -- FALLBACK: parse the book page HTML for .catalog count.
  log_error("ixdzs8: API returned empty, falling back to .catalog for bid=" .. bookId)
  local pageBody = fetchPage(bookUrl)
  if not pageBody then return {} end

  local catalogEl = html_select_first(pageBody, ".catalog")
  if not catalogEl then return {} end

  local total = string.match(catalogEl.text, "共(%d+)章")
  if not total then return {} end
  total = tonumber(total) or 0
  if total == 0 then return {} end

  -- Chapters start at p2.html (p1.html is the novel info page).
  local chapters = {}
  for i = 2, total + 1 do
    local title = "第" .. tostring(i - 1) .. "章"
    local chUrl = baseUrl .. "read/" .. bookId .. "/p" .. tostring(i) .. ".html"
    table.insert(chapters, { title = title, url = chUrl })
  end

  return chapters
end

-- ── Hash for updates ───────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  -- Direct http_get (NOT cached) so the engine detects new chapters.
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local catalogEl = html_select_first(r.body, ".catalog")
  if catalogEl then return string_clean(catalogEl.text) end
  return nil
end

-- ── Chapter text ────────────────────────────────────────────────────────────
-- Two-step fetch (challenge token), then extract the <section> element.

function getChapterText(html, url)
  -- The `html` argument is what the engine fetched. If it's the challenge
  -- page (the engine doesn't follow the JS redirect), we need to do the
  -- two-step fetch ourselves.
  local body = html
  if string.find(body, "正在验证浏览器", 1, true) then
    body = fetchChapter(url)
  end

  local cleaned = html_remove(body, "script", "style", "ins", "iframe", "nav")
  local el = html_select_first(cleaned, "section")
  if not el then
    -- Fallback: try .page-content section or article.
    el = html_select_first(cleaned, ".page-content section")
    if not el then
      el = html_select_first(cleaned, "article")
      if not el then return "" end
    end
  end

  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Book status / last update ────────────────────────────────────────────────

-- Статус книги: текст из <span class="lz"> (напр. "连载中" / "完结").
function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "span.lz")
  if el then return string_clean(el.text) end
  return nil
end

-- Дата последнего обновления: на странице строка вида
-- "更新:2026-08-23 04:13:00". Извлекаем только дату YYYY-MM-DD.
function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  -- Site-specific wording ("更新:…"), not a bare date anywhere on the page.
  local date = string.match(body, "更新:%s*(%d%d%d%d%-%d%d%-%d%d)")
  if date and date ~= "" then return date end
  return nil
end
