-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "uukan"
name     = "UUkan"
version  = "1.0.0"
baseUrl  = "https://www.uukan.org/"
language = "zh"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/uukan.png"

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

-- Ranking/search/library pages share one card markup:
--   <div class="bookbox"><h2 class="bookname"><a href="/book/ID.html">T</a>
-- The card carries no cover and the site has no cover images in any listing
-- (ranking, search, library), so none is returned. The app then backfills one
-- cover per card through its own details call — that is why the listing stays
-- request-free here (see the catalogue cover switch in Settings → Network).
local function parseBookCards(body)
  local items = {}
  for _, a in ipairs(html_select(body, ".bookbox h2.bookname a")) do
    table.insert(items, {
      title = string_clean(a.text),
      url   = absUrl(a.href)
    })
  end
  return items
end

-- ".pages a.next" is absent on the last page (verified: /ranking/hits/100.html,
-- last chapter-list page), so its presence is a reliable end marker.
local function hasNextPage(body)
  return html_select_first(body, ".pages a.next") ~= nil
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = page == 1
    and (baseUrl .. "ranking.html")
    or (baseUrl .. "ranking/hits/" .. page .. ".html")

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  return { items = parseBookCards(r.body), hasNext = hasNextPage(r.body) }
end

-- ── Search ──────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "search/" .. url_encode(query)
  url = page == 1 and (url .. ".html") or (url .. "/" .. page .. ".html")

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  return { items = parseBookCards(r.body), hasNext = hasNextPage(r.body) }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.booktitle")
  return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local cover = html_attr(body, ".bookcover img.thumbnail", "src")
  return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".bookinfo p.bookintro")
  if not el then return nil end
  local text = html_text(el.html)
  -- Trailing promo paragraph the site appends after a <br>:
  -- 《书名》是作家「作者」倾力打造的一部…佳作。本书由思兔小说为您呈现…
  text = regex_replace(text, "(?m)^《[^\\n]*是作家[^\\n]*$", "")
  return string_trim(text)
end

function getBookAuthor(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "p.booktag a.red")
  return el and string_trim(el.text) or nil
end

function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "p.booktag span.red")
  return LIB("meta").status(el and el.text)
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  return LIB("meta").collectGenres(html_select(body, "p.booktag a.blue"))
end

-- "更新时间：2026-11-21 14:30:27"
function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "p.booktime")
  return el and LIB("meta").normalizeDate(el.text) or nil
end

-- ── Chapter list ────────────────────────────────────────────────────────────

-- Full list lives on /chapter/<id>.html, 500 chapters per page, then
-- /chapter/<id>/2.html, /3.html… The pages are already oldest → newest.
function getChapterList(bookUrl)
  local id = bookUrl:match("/book/([^/?#]+)%.html")
  if not id then
    log_error("uukan: cannot extract book id from " .. bookUrl)
    return {}
  end

  local chapters = {}
  local url = baseUrl .. "chapter/" .. id .. ".html"
  -- Guard against a broken "next" marker turning the walk into a hang.
  for _ = 1, 100 do
    local r = http_get(url)
    if not r.success then break end

    for _, a in ipairs(html_select(r.body, "div#allchapter dd a")) do
      table.insert(chapters, {
        title = string_clean(a.text),
        url   = absUrl(a.href)
      })
    end

    local nextHref = html_attr(r.body, "a#linkNext", "href")
    if nextHref == "" or not nextHref:find("/%d+%.html$") then break end
    url = absUrl(nextHref)
  end

  return chapters
end

-- The book page carries the newest chapter and its update time.
function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "p.booktime")
  return el and el.text or nil
end

-- ── Chapter text ────────────────────────────────────────────────────────────

function getChapterText(html, url)
  if not html or html == "" then
    local r = http_get(url)
    if not r.success then return "" end
    html = r.body
  end

  -- #content holds only <p> paragraphs (ads/notes sit outside it).
  local paragraphs = html_select(html, "div#content p")
  if #paragraphs == 0 then return "" end

  local parts = {}
  for _, p in ipairs(paragraphs) do
    table.insert(parts, string_trim(html_text(p.html)))
  end

  return LIB("content").standardTransforms(table.concat(parts, "\n"), {
    domain = baseUrl,
    lang   = "zh"
  })
end
