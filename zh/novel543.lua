-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "novel543"
name     = "Novel543"
version  = "1.0.1"
baseUrl  = "https://www.novel543.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novel543.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = "https://www.novel543.com/bookstack/?page=" .. tostring(index + 1)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, "ul.list li.media")) do
    local titleEl = html_select_first(li.html, "div.media-content h3 a")
    local bookUrl = absUrl(html_attr(li.html, "div.media-left a", "href"))
    local cover   = absUrl(html_attr(li.html, "div.media-left img", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск (только первая страница) ───────────────────────────────────────────

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local url = "https://www.novel543.com/search/" .. url_encode(query)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, "ul.list li.media")) do
    local titleEl = html_select_first(li.html, "div.media-content h3 a")
    local bookUrl = absUrl(html_attr(li.html, "div.media-left a", "href"))
    local cover   = absUrl(html_attr(li.html, "div.media-left img", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = false }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1.title")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".cover img")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.intro")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Список глав (AJAX GET на /dir) ────────────────────────────────────────────

function getChapterList(bookUrl)
  local dirUrl = bookUrl:gsub("/$", "") .. "/dir"
  local r = http_get(dirUrl)
  if not r.success then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "ul.all li a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      table.insert(chapters, {
        title = string_clean(a.text),
        url   = chUrl
      })
    end
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "p.meta span.iconf:last-child")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы (многостраничный) ────────────────────────────────────────────

function getChapterText(html, url)
  local chapterFile = string.match(url, "/([^/]+)%.html$") or ""

  local function extractPage(pageHtml)
    local cleaned = html_remove(pageHtml, "div.gadBlock", "div.adBlock", "script", "ins", ".ads", ".ad", "p:contains(溫馨提示)")
    local el = html_select_first(cleaned, "div.content")
    if not el then return "" end
    return html_text("<div>" .. el.html .. "</div>")
  end

  local parts = {}
  local first = extractPage(html)
  if first ~= "" then table.insert(parts, first) end

  local currentHtml = html
  for _ = 1, 20 do
    local subUrl = nil
    for _, a in ipairs(html_select(currentHtml, "a[href]")) do
      local href = a.href
      local fname = string.match(href, "/([^/]+)$") or ""
      if string.match(fname, "^" .. chapterFile:gsub("%-", "%%-") .. "_%d+%.html$") then
        subUrl = absUrl(href)
        break
      end
    end

    if not subUrl then break end

    local pr = http_get(subUrl)
    if not pr.success then break end

    local sub = extractPage(pr.body)
    if sub ~= "" then table.insert(parts, sub) end

    currentHtml = pr.body
  end

  return string_trim(table.concat(parts, "\n\n"))
end
