-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "baca_lightnovel"
name     = "Baca Lightnovel"
version  = "1.0.0"
baseUrl  = "https://bacalightnovel.co/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/bacalightnovel.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Bab\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Penerjemah|Editor|Proofreader|Baca\\s+(di|di+sini))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url
  if index == 0 then
    url = baseUrl .. "series/"
  else
    url = baseUrl .. "series/?page=" .. tostring(index + 1) .. "&order=populer"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, a in ipairs(html_select(r.body, ".listupd > .maindet .mdthumb a")) do
    local bookUrl = absUrl(a.href)
    local title = html_attr(a.html, "img", "title")
    if title == "" then title = html_attr(a.html, "img", "alt") end
    local cover = html_attr(a.html, "img", "src")
    if cover == "" then cover = html_attr(a.html, "img", "data-src") end
    if bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(title),
        url   = bookUrl,
        cover = absUrl(cover)
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url
  if index == 0 then
    url = baseUrl:gsub("/$", "") .. "/?s=" .. url_encode(query)
  else
    url = baseUrl:gsub("/$", "") .. "/page/" .. tostring(index + 1) .. "/?s=" .. url_encode(query)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, a in ipairs(html_select(r.body, ".listupd > .maindet .mdthumb a")) do
    local bookUrl = absUrl(a.href)
    local title = html_attr(a.html, "img", "title")
    if title == "" then title = html_attr(a.html, "img", "alt") end
    local cover = html_attr(a.html, "img", "src")
    if cover == "" then cover = html_attr(a.html, "img", "data-src") end
    if bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(title),
        url   = bookUrl,
        cover = absUrl(cover)
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1.entry-title")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".sertothumb img")
  if el then
    local src = el.src
    if src == "" then src = el:attr("data-src") end
    return absUrl(src)
  end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".entry-content")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (NONE + reverseChapters) ─────────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, ".eplister li > a:not(.dlpdf)")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local titleEl = html_select_first(a.html, ".epl-title")
      table.insert(chapters, {
        title = titleEl and string_clean(titleEl.text) or string_clean(a.text),
        url   = chUrl
      })
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".epcurlast")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads")
  local el = html_select_first(cleaned, ".epcontent[itemprop=text] .text-left")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end