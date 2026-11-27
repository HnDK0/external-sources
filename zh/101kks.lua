-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "101kks"
name     = "101看書"
version  = "1.0.1"
baseUrl  = "https://101kks.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/v2/icons/101kks.png"

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
-- title/cover/description/author/status/genres/date functions in one adapter
-- run. getChapterListHash stays on a direct http_get — the hash must see a
-- fresh page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

local function parseBookCards(body)
  local items = {}
  for _, el in ipairs(html_select(body, "#article_list_content li a.imgbox")) do
    local cover = html_attr(el.html, "img", "data-src")
    local title = html_attr(el.html, "img", "alt")
    table.insert(items, {
      cover = cover and absUrl(cover) or nil,
      title = string_clean(title),
      url = absUrl(el.href),
    })
  end
  return items
end

local function hasNextPage(body)
  return html_select_first(body, "#pagelink a.next") ~= nil
end

local function getMetaContent(body, property)
  local s = html_attr(body, string.format("meta[property='%s']", property), "content")
  return s ~= "" and string_clean(s) or nil
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "novels/newhot_0_0_" .. tostring(page) .. ".html"

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  return { items = parseBookCards(r.body), hasNext = hasNextPage(r.body) }
end

-- ── Search ──────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local encoded = url_encode(query)
  local url = baseUrl .. "search/" .. encoded .. "/" .. tostring(page) .. ".html"

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  -- when the search only finds one book, it will be automatically redirected to the book page
  if html_select_first(r.body, "meta[property='og:book_id']") ~= nil then
    local item = {
      title = getMetaContent(r.body, "og:novel:book_name"),
      url = absUrl(getMetaContent(r.body, "og:url")),
      cover = absUrl(getMetaContent(r.body, "og:image")),
    }
    return { items = {item}, hasNext = false }
  else
    return { items = parseBookCards(r.body), hasNext = hasNextPage(r.body) }
  end
end

-- ── Book details ────────────────────────────────────────────────────────────

local function getMetaContentWithFetch(bookUrl, property)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  return getMetaContent(body, property)
end

function getBookTitle(bookUrl)
  return getMetaContentWithFetch(bookUrl, "og:novel:book_name")
end

function getBookCoverImageUrl(bookUrl)
  local src = getMetaContentWithFetch(bookUrl, "og:image")
  return src and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  return getMetaContentWithFetch(bookUrl, "og:description")
end

function getBookAuthor(bookUrl)
    return getMetaContentWithFetch(bookUrl, "og:novel:author")
end

local statusMap = {
  ["連載"] = "Ongoing",
  ["全本"] = "Complete",
}
function getBookStatus(bookUrl)
  return statusMap[getMetaContentWithFetch(bookUrl, "og:novel:status")]
end

-- the tags is available in the script
-- <script>
--    var bookinfo = {
--    ...
--        tags: '穿越,分身,火影,價值,科技,老師,無敵,系統,修仙,'
--    };
-- if it's not available we use category instead
function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  local s = body:match("tags: ['\"]([^'\"]+)")
  if s then
    for tag in s:gmatch("[^,]+") do
      table.insert(genres, tag)
    end
  else
    local cat = getMetaContent(body, "og:novel:category")
    if cat then
      table.insert(genres, cat)
    end
  end
  return #genres > 0 and genres or nil
end

-- "2026-11-24 07:17:06"
function getBookLastUpdate(bookUrl)
  local update_time = getMetaContentWithFetch(bookUrl, "og:novel:update_time")
  return update_time and LIB("meta").normalizeDate(update_time) or nil
end

-- ── Chapter list ────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local bookId = string.match(bookUrl, "/book/([^/.]+)%.html")
  if not bookId then
    log_error(id .. ": cannot extract bookId from " .. bookUrl)
    return {}
  end

  local ajaxUrl = baseUrl .. "ajax_novels/chapterlist/" .. bookId .. ".html"
  local r = http_get(ajaxUrl)
  if not r.success then
    log_error(id .. ": AJAX failed " .. tostring(r.code))
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "ul li a[href]")) do
    local chUrl = absUrl(a.href)
    local t = string_trim(a.text)
    if chUrl ~= "" then
      table.insert(chapters, { title = t, url = chUrl })
    end
  end

  return chapters
end

-- "2026-11-24 07:17:06"
function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  return getMetaContent(r.body, "og:novel:update_time")
end

-- ── Chapter text ────────────────────────────────────────────────────────────

function getChapterText(html, url)
  if not html or html == "" then
    local r = http_get(url)
    if not r.success then return "" end
    html = r.body
  end

  -- ads/promo either in div or script
  local cleaned = html_remove(html, "#txtcontent :is(div, script)")
  local el = html_select_first(cleaned, "#txtcontent")
  if not el then return "" end
  return LIB("content").standardTransforms(html_text(el.html), {
    domain = baseUrl,
    lang   = "zh"
  })
end
