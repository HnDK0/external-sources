-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "xbiquge"
name     = "XBiquge"
version  = "1.0.4"
baseUrl  = "https://www.xbiquge.info/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/xbiquge.png"

-- ── Changelog (1.0.0 → 1.0.1) ───────────────────────────────────────────────
-- FIX: Multi-page chapter support. Biquge family chapters can be split
--      across multiple pages (e.g. 148374.html, 148374_2.html, 148374_3.html).
--      The previous version only extracted page 1, missing up to 2/3 of the
--      chapter content. Now walks {chapterFile}_{N}.html links and concatenates.
-- ADD: Strip biquge page markers ("第(1/3)页", "Page (1/3)") from content.
-- FIX (1.0.2 → 1.0.3): Book pages on xbiquge.info return HTTP 404 without a
--      trailing slash (/135/135267 → 404, /135/135267/ → 200). The engine may
--      strip the trailing slash from catalog URLs, so add normalizeBookUrl()
--      and apply it to every bookUrl input (getChapterList, getBookTitle,
--      getBookCoverImageUrl, getBookDescription, getChapterListHash,
--      getBookStatus, getBookLastUpdate) to re-append the slash.
-- ────────────────────────────────────────────────────────────────────────────

-- ── Site notes ──────────────────────────────────────────────────────────────
-- xbiquge.info (新笔趣阁) is a Simplified-Chinese biquge-family novel site.
--
-- URL patterns:
--   Book page:       /{folderId}/{bookId}/                e.g. /10/10202/
--   Chapter:         /{folderId}/{bookId}/{chId}.html     e.g. /10/10202/1144623.html
--   Chapter list pg: /{folderId}/{bookId}/index_{N}.html  e.g. /10/10202/index_2.html
--   Catalog:         /list{catId}/{page}.html             e.g. /list1/1.html
--   Search:          /search.php?q={query}&p={page}       (GET, URL-encoded UTF-8)
--
-- Chapter content:
--   The chapter body lives in <article class="font_max"> inside
--   section > .container > .box.single. Content uses <br> separators
--   (biquge family convention), not <p> tags. The chapter title is in <h1>.
--   Noise elements to strip:
--     .row.resetfontsize  (font-size controls: 字体 大 中 小 换手 关灯)
--     .row.nav-bottom     (prev/next chapter links)
--     script              (inline ad / analytics scripts)
--
-- Catalog / search structure:
--   Books are in <dl> elements inside .hot. Each <dl> has:
--     <dt><a href="/.../bookurl/"><img src=".../cover.jpg"/></a></dt>
--     <dd><h3><a href="/.../bookurl/">Book Title</a></h3></dd>
--     <dd class="book_other">作者：<span><a>Author</a></span></dd>
--     <dd class="book_other">状态：连载</dd>
--     <dd class="book_other">更新时间：YYYY-MM-DD HH:MM:SS</dd>
--     <dd class="book_other">最新章节：<a href="...">Chapter</a></dd>
--   Pagination: links at the bottom of .hot — "»" points to the last page.
--
-- Chapter list:
--   The book page shows the first 100 chapters in <div class="book_list2">.
--   Subsequent pages are at /{folder}/{book}/index_{N}.html (N=2,3,...).
--   Total page count is discoverable from the pagination links (the "»"
--   link points to index_{last}.html). We fetch all pages in parallel
--   via http_get_batch and concatenate. Chapters are listed oldest-first,
--   so no reversal is needed.
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
-- title/cover/description/status/chapter-list functions in one adapter run.
-- getChapterListHash stays on a direct http_get — the hash must see a fresh
-- page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Книжная страница на xbiquge.info отдаёт 404 БЕЗ завершающего слэша
-- (/135/135267 → 404, /135/135267/ → 200). Движок при сохранении URL из
-- каталога может отрезать trailing slash, поэтому здесь всегда добавляем
-- его обратно для любого bookUrl, который не указывает на файл (.html/.php).
local function normalizeBookUrl(url)
  if not url or url == "" then return url end
  if string.find(url, "%.html$") or string.find(url, "%.php") then return url end
  if string.find(url, "/$") then return url end
  return url .. "/"
end

-- Apply standard content transforms from the shared content lib: strip site
-- domain references, the leading chapter title (a duplicated
-- "第N章：第N章 …" prefix collapses into the same strip; biquge titles often
-- look like "第1189章 学的过于好了-《大明第一国舅》" and the whole line goes)
-- and the translator/editor attribution lines. The biquge page markers
-- ("第(1/3)页", "Page (1/3)", "页次(1/3)") at the start and end of each
-- multi-page chapter page are site-specific and stay here.
local function applyStandardContentTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
  if text == "" then return "" end

  text = regex_replace(text, "(?im)^\\s*第?\\s*[\\(（]\\s*\\d+\\s*/\\s*\\d+\\s*[\\)）]\\s*页\\s*$", "")
  text = regex_replace(text, "(?im)^\\s*Page\\s*\\(\\s*\\d+\\s*/\\s*\\d+\\s*\\)\\s*$", "")
  text = regex_replace(text, "(?im)^\\s*页次\\s*[\\(（]\\s*\\d+\\s*/\\s*\\d+\\s*[\\)）]\\s*$", "")

  return string_trim(text)
end

-- Parse a list of <dl> book cards from an HTML body.
-- Used by both getCatalogList and getCatalogSearch.
local function parseBookCards(body)
  local items = {}
  for _, dl in ipairs(html_select(body, ".hot dl")) do
    local titleEl = html_select_first(dl.html, "dd h3 a, h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(dl.html, "dt a img, img", "src")
      local t = string_clean(titleEl.text)
      -- Only accept book-like URLs (/{folder}/{book}/).
      if bookUrl ~= "" and t ~= "" and string.find(bookUrl, "/%d+/%d+/") then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = absUrl(cover)
        })
      end
    end
  end
  return items
end

-- Discover the highest page number from the pagination links.
local function findLastPage(body)
  local lastPage = 1
  for _, a in ipairs(html_select(body, ".page a, a[href*='list'], a[href*='search.php']")) do
    local href = a.href or ""
    local txt = string_clean(a.text)
    -- Direct page number link
    local p = tonumber(txt)
    if p and p > lastPage then lastPage = p end
    -- "»" link points to the last page URL like /list1/12.html or ?p=12
    if txt == "»" or string.find(txt, "末页") or string.find(txt, "最后") then
      local m = string.match(href, "[?&]p=(%d+)")
      if not m then m = string.match(href, "/(%d+)%.html") end
      if m then
        local p2 = tonumber(m)
        if p2 and p2 > lastPage then lastPage = p2 end
      end
    end
  end
  return lastPage
end

-- ── Catalog ─────────────────────────────────────────────────────────────────
-- /list{catId}/{page}.html — categories 1-8 (玄幻 武侠 都市 历史 网游 科幻 言情 其他)
-- Default catalog uses list1 (玄幻).

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "list1/" .. tostring(page) .. ".html"
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseBookCards(r.body)

  -- hasNext: look for "»" or "下一页" link, OR if we got a full page.
  local hasNext = false
  for _, a in ipairs(html_select(r.body, ".page a, a[href*='list']")) do
    local txt = string_clean(a.text)
    if txt == "»" or txt == "下一页" or txt == "下页" then
      hasNext = true
      break
    end
  end
  if #items >= 10 then hasNext = true end

  return { items = items, hasNext = hasNext }
end

-- ── Search ──────────────────────────────────────────────────────────────────
-- /search.php?q={query} — pagination via &p={N} (not &page=).

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local encoded = url_encode(query)
  local url = baseUrl .. "search.php?q=" .. encoded .. "&p=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseBookCards(r.body)

  local hasNext = false
  for _, a in ipairs(html_select(r.body, ".page a, a[href*='search.php']")) do
    local txt = string_clean(a.text)
    if txt == "»" or txt == "下一页" or txt == "下页" then
      hasNext = true
      break
    end
  end
  if #items >= 10 then hasNext = true end

  return { items = items, hasNext = hasNext }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, "#fmimg img, .book-cover img, dt a img, img", "src")
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "#intro, .intro, .description, .info p, .info")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Chapter list (multi-page via index_{N}.html) ──────────────────────────
-- The book page shows chapters 1-99 in .book_list2. Subsequent pages are
-- at /{folder}/{book}/index_{N}.html (N=2,3,...,last). We discover the last
-- page from the pagination links and fetch all pages in parallel.

function getChapterList(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  -- Strip trailing slash so we can append /index_N.html cleanly.
  local base = bookUrl:gsub("/$", "")

  -- Fetch page 1 (the book page itself) to discover pagination.
  local body = fetchPage(bookUrl)
  if not body then return {} end

  -- Discover the last page number from pagination links like
  -- /10/10202/index_12.html (the "»" link).
  local lastPage = 1
  for _, a in ipairs(html_select(body, "a[href*='index_']")) do
    local href = a.href or ""
    local m = string.match(href, "index_(%d+)%.html")
    if m then
      local p = tonumber(m)
      if p and p > lastPage then lastPage = p end
    end
  end

  -- Collect chapters from page 1 (already fetched).
  local chapters = {}
  for _, a in ipairs(html_select(body, ".book_list2 a[href]")) do
    local chUrl = absUrl(a.href)
    local t = string_clean(a.text)
    -- Only accept chapter-like URLs, not "倒序" or pagination links.
    if chUrl ~= "" and t ~= "" and string.find(chUrl, "/%d+/%d+/%d+%.html") then
      table.insert(chapters, { title = t, url = chUrl })
    end
  end

  -- Fetch pages 2..lastPage in parallel.
  if lastPage > 1 then
    local urls = {}
    for p = 2, lastPage do
      table.insert(urls, base .. "/index_" .. tostring(p) .. ".html")
    end
    local results = http_get_batch(urls)
    for _, res in ipairs(results) do
      if res.success then
        for _, a in ipairs(html_select(res.body, ".book_list2 a[href]")) do
          local chUrl = absUrl(a.href)
          local t = string_clean(a.text)
          if chUrl ~= "" and t ~= "" and string.find(chUrl, "/%d+/%d+/%d+%.html") then
            table.insert(chapters, { title = t, url = chUrl })
          end
        end
      end
    end
  end

  return chapters
end

-- ── Hash for updates ───────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  -- Direct http_get (NOT cached) — the engine needs a fresh response to
  -- detect new chapters.
  local r = http_get(bookUrl)
  if not r.success then return nil end
  -- The first chapter link in .book_list2 is the oldest; the LAST chapter
  -- link on the LAST index page is the newest. For a cheap hash, use the
  -- first chapter URL on the first page (it changes only when chapters are
  -- inserted at the start, which is rare).
  -- Better: fetch the last index page and use its last chapter URL.
  -- Cheapest: just use the page text length + first chapter URL.
  local firstEl = html_select_first(r.body, ".book_list2 a[href]")
  if not firstEl then return nil end
  return firstEl.href
end

-- ── Chapter text (multi-page) ──────────────────────────────────────────────
-- Biquge family chapters can be split across multiple pages:
--   page 1: /10/10202/148374.html      (the URL the engine fetched)
--   page 2: /10/10202/148374_2.html    (linked as "下一页" / "next page")
--   page 3: /10/10202/148374_3.html    (etc.)
-- The "Next chapter" link in .row.nav-bottom points to the NEXT CHAPTER,
-- but the "下一页" link (if present) points to the NEXT PAGE of the SAME
-- chapter. We detect multi-page by looking for a href matching
-- {chapterFile}_{N}.html and fetch all pages sequentially.
--
-- Content lives in <article class="font_max">. Uses <br> separators.
-- Strip .row.resetfontsize, .row.nav-bottom, scripts, and ad iframes.

local function extractPageText(pageHtml)
  local cleaned = html_remove(pageHtml,
    "script", "style",
    ".row.resetfontsize",   -- font-size controls
    ".row.nav-bottom",      -- prev/next chapter nav
    "ins", "iframe",        -- ad slots
    ".adsbygoogle"
  )
  local el = html_select_first(cleaned, "article.font_max")
  if not el then
    el = html_select_first(cleaned, "#content")
    if not el then
      el = html_select_first(cleaned, "#chaptercontent")
      if not el then
        el = html_select_first(cleaned, ".box.single article")
        if not el then return "" end
      end
    end
  end
  return html_text(el.html)
end

function getChapterText(html, url)
  -- Extract the chapter file name and starting page number from the URL.
  --   url = ".../148374.html"     → chapterFile="148374", currentPage=1
  --   url = ".../148374_3.html"    → chapterFile="148374", currentPage=3
  local chapterFile, startPage = string.match(url, "/([^/]+)_(%d+)%.html$")
  if not chapterFile then
    chapterFile = string.match(url, "/([^/]+)%.html$") or ""
    startPage = "1"
  end
  local currentPage = tonumber(startPage) or 1
  -- Escape chapterFile for Lua pattern matching (% is the escape char).
  local chapterPattern = string.gsub(chapterFile, "%%", "%%%%")
  chapterPattern = "^" .. chapterPattern .. "_(%d+)%.html$"

  local parts = {}
  local first = extractPageText(html)
  if first ~= "" then table.insert(parts, first) end

  -- Walk FORWARD only: look for {chapterFile}_{N}.html where N == currentPage+1.
  -- This avoids re-fetching backward links (page 2 links back to page 1 as
  -- "上一章"/"prev page") and stops at the last page (which links to the
  -- next CHAPTER with a different chapterId, e.g. 148375.html).
  local currentHtml = html

  for _ = 1, 30 do  -- safety limit: 30 pages max per chapter
    local nextPageUrl = nil
    local nextPageNum = nil
    for _, a in ipairs(html_select(currentHtml, "a[href]")) do
      local href = a.href or ""
      -- Extract the file name from the href.
      local fname = string.match(href, "/([^/]+)$") or ""
      -- Check if fname matches {chapterFile}_{N}.html
      local pageNum = string.match(fname, chapterPattern)
      if pageNum then
        local n = tonumber(pageNum)
        -- Only follow FORWARD links (next page, not prev page).
        if n and n == currentPage + 1 then
          nextPageUrl = absUrl(href)
          nextPageNum = n
          break
        end
      end
    end

    if not nextPageUrl then break end

    local pr = http_get(nextPageUrl)
    if not pr.success then break end

    local sub = extractPageText(pr.body)
    if sub ~= "" then table.insert(parts, sub) end

    currentPage = nextPageNum
    currentHtml = pr.body
  end

  local combined = table.concat(parts, "\n\n")
  return applyStandardContentTransforms(combined)
end

-- ── Book status / last update ────────────────────────────────────────────────
-- Статус и дата обновления берутся из мета-тегов Open Graph, которые сайт
-- отдаёт на странице книги:
--   <meta property="og:novel:status" content="连载">
--   <meta property="og:novel:update_time" content="2026-08-18 14:25:23">
-- Если мета-тег отсутствует — возвращаем nil (данных нет).

function getBookStatus(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local s = html_attr(body, "meta[property='og:novel:status']", "content")
  if s ~= "" then return s end
  return nil
end

function getBookLastUpdate(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  -- Дата в формате "YYYY-MM-DD HH:MM:SS"; берём только "YYYY-MM-DD".
  local meta = html_attr(body, "meta[property='og:novel:update_time']", "content")
  local d = LIB("meta").normalizeDate(meta)
  if not d then
    -- Запасной вариант: поиск даты по всему телу страницы.
    d = LIB("meta").normalizeDate(body)
  end
  return d
end
