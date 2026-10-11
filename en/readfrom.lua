id       = "readfrom"
name     = "Read From Net"
version  = "1.5.2"
baseUrl  = "https://readfrom.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/readfrom.png"

function getUserAgentPreset()
  return "Safari Mobile"
end

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

-- Session-cached page fetch (shared fetch lib, same contract as before).
local function fetchPage(url)
  return LIB("fetch").page(url)
end

local function absUrl(href)
  return LIB("urls").absUrl(baseUrl, href)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

local function getRelPath(url)
  local path = url:gsub("^https?://[^/]+/", "")
  return path:gsub("^/", "")
end

-- Standard chapter-text cleanup from the shared content lib (this site's copy
-- skipped the site-domain lines; nothing on the page matches them anyway).
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { lang = "en" })
end

local function parseCatalogCard(card, isSearch)
  local a = html_select_first(card.html, "h2.title a")
  if not a then return nil end
  local title = string_clean(a.text)
  if title == "" then return nil end
  local coverEl = html_select_first(card.html, "a.highslide img")
  local genres = {}
  local author = ""
  local description = ""
  if isSearch then
    local authorEl = html_select_first(card.html, "h5.title a")
    if authorEl then author = string_clean(authorEl.text) end
    local descEl = html_select_first(card.html, "div.text5")
    if descEl then description = string_trim(html_text(descEl.html)) end
  else
    -- trim + drop empties — shared meta lib (site order kept).
    genres = LIB("meta").collectGenres(html_select(card.html, "h2 a[title*='Genre']") or {})
    local authorEl = html_select_first(card.html, "h4 a")
    if authorEl then author = string_clean(authorEl.text) end
    local descEl = html_select_first(card.html, "div.text3")
    if descEl then description = string_trim(html_text(descEl.html)) end
  end
  return {
    title = title,
    url = absUrl(a.href),
    cover = coverEl and coverEl.src or nil,
    description = description,
    genres = genres,
    author = author,
    path = getRelPath(absUrl(a.href)),
  }
end

local function parseCatalogPage(html, isSearch)
  local items = {}
  local sel = isSearch and "div.text article.box.story.shortstory" or "#dle-content > article.box.story.shortstory"
  for _, card in ipairs(html_select(html, sel) or {}) do
    local item = parseCatalogCard(card, isSearch)
    if item then table.insert(items, item) end
  end
  return items
end

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local r = http_get(baseUrl .. "allbooks/page/" .. page .. "/")
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseCatalogPage(r.body, false)
  local hasNext = #html_select(r.body, "div.navigation span.page_next a") > 0
  return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end
  local r = http_get(baseUrl .. "build_in_search/?q=" .. url_encode(query))
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseCatalogPage(r.body, true)
  return { items = items, hasNext = false }
end

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h2.title")
  if not el then return nil end
  local text = el.text
  local cleaned = regex_replace(text, ",\\s+[Pp]age\\s+\\d+\\s*$", "")
  if cleaned ~= text then
    return string_clean(cleaned)
  end
  return string_clean(text)
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "a.highslide img")
  local src = el and el.src or ""
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return "" end
  local el = html_select_first(body, "meta[name='description']")
  if el then
    local desc = el.content or ""
    if desc ~= "" and not string_starts_with(desc, "Chapter") then
      return string_trim(desc)
    end
  end
  return ""
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  -- trim + drop empties — shared meta lib (site order kept).
  return LIB("meta").collectGenres(html_select(body, "h2 a[title*='Genre']") or {})
end

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  local chapters = {}
  table.insert(chapters, { title = "1", url = bookUrl })
  local navEl = html_select_first(r.body, "div.splitnewsnavigation2 div.pages")
  if navEl then
    for _, a in ipairs(html_select(navEl.html, "a") or {}) do
      if a.href and a.href ~= "" then
        table.insert(chapters, {
          title = string_clean(a.text),
          url = absUrl(a.href)
        })
      end
    end
  end
  return chapters
end

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local navEl = html_select_first(r.body, "div.splitnewsnavigation2 div.pages")
  if not navEl then return nil end
  local pages = html_select(navEl.html, "a")
  local last = pages[#pages]
  return last and last.href or nil
end

function getChapterText(html, url)
  local function extractText(body)
    local cleaned = html_remove(body, "script", "style")
    cleaned = html_remove(cleaned, "a.highslide")
    cleaned = html_remove(cleaned, "div.sharethis-inline-share-buttons")
    local el = html_select_first(cleaned, "#textToRead.text")
    if not el then return nil end
    local inner = regex_replace(el.html, "(?is)<center[^>]*>.*$", "")
    return html_text(inner)
  end
  local text = extractText(html)
  if not text or text == "" then
    local r = http_get(url)
    if r.success then text = extractText(r.body) end
  end
  if not text or text == "" then return "" end
  text = regex_replace(text, "_([^_]+)_", "<i>%1</i>")
  return applyStandardContentTransforms(text)
end
