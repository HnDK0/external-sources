-- NovelBin source plugin
-- Compatible with LuaJ (Lua 5.1) — no goto, no colon methods on table fields

id       = "NovelBin"
name     = "Novel Bin"
version  = "1.0.8"
baseUrl  = "https://novelbin.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbin.png"

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function transformCoverUrl(coverUrl)
  -- Принудительно приводим к строке, чтобы gsub точно отработал
  local url = tostring(coverUrl or "")
  if url:find("novel_200_89") then
    -- Используем plain-поиск (true), чтобы исключить проблемы с экранированием
    local newUrl = url:gsub("novel_200_89", "novel")
    return newUrl
  end
  
  return url
end

local function buildCatalogUrl(index)
  local page = index + 1
  if page == 1 then
    return baseUrl .. "sort/top-view-novel"
  else
    return baseUrl .. "sort/top-view-novel?page=" .. page
  end
end

local function buildSearchUrl(index, query)
  local page = index + 1
  if page == 1 then
    return baseUrl .. "search?keyword=" .. url_encode(query)
  else
    return baseUrl .. "search?keyword=" .. url_encode(query) .. "&page=" .. page
  end
end

local function parseCatalogItems(body)
  local items = {}
  local rows = html_select(body, ".col-novel-main .row")
  for _, row in ipairs(rows) do
    local titleEls = html_select(row.html, ".novel-title a")
    if titleEls[1] then
      local cover = html_attr(row.html, "img[data-src]", "data-src")
      if cover == "" then
        cover = html_attr(row.html, "img[src]", "src")
      end
      table.insert(items, {
        title = string_trim(titleEls[1].text),
        url   = titleEls[1].href,
        cover = transformCoverUrl(cover)
      })
    end
  end
  return items
end

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = buildCatalogUrl(index)
  local r = http_get(url)
  if not r.success then
    log_error("getCatalogList failed: " .. url .. " code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
  end
  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
  local url = buildSearchUrl(index, query)
  local r = http_get(url)
  if not r.success then
    log_error("getCatalogSearch failed: " .. url)
    return { items = {}, hasNext = false }
  end
  local items = {}
  local rows = html_select(r.body, ".col-novel-main .row")
  for _, row in ipairs(rows) do
    local titleEls = html_select(row.html, ".novel-title a")
    if titleEls[1] then
      local cover = html_attr(row.html, "img[src]", "src")
      table.insert(items, {
        title = string_trim(titleEls[1].text),
        url   = titleEls[1].href,
        cover = transformCoverUrl(cover)
      })
    end
  end
  return { items = items, hasNext = #items > 0 }
end

-- ── Book metadata ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h3.title")
  if el then return string_trim(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local url = html_attr(r.body, "meta[property='og:image']", "content")
  if url ~= "" then return url end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.desc-text")
  if el then return string_trim(el.text) end
  return nil
end

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".l-chapter a.chapter-title")
  if el then return el.href end
  return nil
end

-- ── Chapter list (AJAX) ───────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then
    log_error("getChapterList: failed to load " .. bookUrl)
    return {}
  end

  local ogUrl = html_attr(r.body, "meta[property='og:url']", "content")
  if ogUrl == "" then
    log_error("getChapterList: no og:url meta")
    return {}
  end

  local m = regex_match(ogUrl, "([^/?#]+)/*$")
  if not m[1] then
    log_error("getChapterList: cannot extract novelId from " .. ogUrl)
    return {}
  end

  local ajaxUrl = "https://novelbin.com/ajax/chapter-archive?novelId=" .. m[1]
  log_info("getChapterList AJAX: " .. ajaxUrl)

  local ar = http_get(ajaxUrl)
  if not ar.success then
    log_error("getChapterList: AJAX failed code=" .. tostring(ar.code))
    return {}
  end

  local chapters = {}
  local links = html_select(ar.body, "ul.list-chapter li a")
  for _, a in ipairs(links) do
    local title = string_trim(a.text)
    if title == "" then title = a.href end
    table.insert(chapters, { title = title, url = a.href })
  end

  log_info("getChapterList: loaded " .. #chapters .. " chapters")
  return chapters
end

-- ── Chapter text ──────────────────────────────────────────────────────────────

function getChapterText(html)
  local cleaned = html_remove(html, "script", ".ads", "h3", ".chapter-warning", ".ad-insert")
  local el = html_select_first(cleaned, "#chr-content")
  if el then return html_text(el.html) end
  el = html_select_first(cleaned, ".chr-c")
  if el then return html_text(el.html) end
  el = html_select_first(cleaned, "#chapter-content")
  if el then return html_text(el.html) end
  el = html_select_first(cleaned, ".chapter-content")
  if el then return html_text(el.html) end
  return ""
end