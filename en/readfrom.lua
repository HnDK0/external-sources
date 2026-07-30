id       = "readfrom"
name     = "Read From Net"
version  = "1.5.1"
baseUrl  = "https://readfrom.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/readfrom.png"

function getUserAgentPreset()
  return "Safari Mobile"
end

local _pageCache = {}

local function fetchPage(url)
  if _pageCache[url] then return _pageCache[url] end
  local r = http_get(url)
  if r.success then
    _pageCache[url] = r.body
    return r.body
  end
  return nil
end

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function getRelPath(url)
  local path = url:gsub("^https?://[^/]+/", "")
  return path:gsub("^/", "")
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
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
    for _, g in ipairs(html_select(card.html, "h2 a[title*='Genre']") or {}) do
      table.insert(genres, string_clean(g.text))
    end
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
  local page = (index or 0) + 1
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
  local genres = {}
  for _, g in ipairs(html_select(body, "h2 a[title*='Genre']") or {}) do
    table.insert(genres, string_clean(g.text))
  end
  return genres
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
