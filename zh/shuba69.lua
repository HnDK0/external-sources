-- 69shuba source plugin
-- Compatible with LuaJ (Lua 5.1) — strict top-level functions

id       = "shuba69"
name     = "69Shuba"
version  = "1.0.3"
baseUrl  = "https://www.69shuba.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/69shuba.png"

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function buildCatalogUrl(index)
  return baseUrl .. "novels/monthvisit_0_0_" .. tostring(index + 1) .. ".htm"
end

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = buildCatalogUrl(index)
  -- В твоем API кодировка передается строкой вторым аргументом в http_get
  local r = http_get(url, "GBK")
  
  if not r.success then
    log_error("getCatalogList failed: " .. url .. " code=" .. tostring(r.code))
    return { items = {}, hasNext = false }
  end

  local items = {}
  local rows = html_select(r.body, "ul#article_list_content li")
  for _, row in ipairs(rows) do
    local titleEls = html_select(row.html, "div.newnav h3 a")
    if titleEls[1] then
      local cover = html_attr(row.html, "a.imgbox img", "data-src")
      table.insert(items, {
        title = string_trim(titleEls[1].text),
        url   = titleEls[1].href,
        cover = cover
      })
    end
  end
  return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local searchUrl = "https://www.69shuba.com/modules/article/search.php"
  -- Используем стандартный url_encode, так как спец. функции для GBK в примере нет
  local payload = "searchkey=" .. url_encode(query) .. "&searchtype=all"
  
  local r = http_post(searchUrl, payload, {
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    charset = "GBK"
  })

  if not r.success then
    log_error("getCatalogSearch failed")
    return { items = {}, hasNext = false }
  end

  local items = {}
  local rows = html_select(r.body, "div.newbox ul li")
  for _, row in ipairs(rows) do
    local titleEls = html_select(row.html, "h3 a:last-child")
    if titleEls[1] then
      local cover = html_attr(row.html, "a.imgbox img", "data-src")
      table.insert(items, {
        title = string_trim(titleEls[1].text),
        url   = titleEls[1].href,
        cover = cover
      })
    end
  end
  return { items = items, hasNext = false }
end

-- ── Book metadata ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl, "GBK")
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.booknav2 h1 a")
  if el then return string_trim(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl, "GBK")
  if not r.success then return nil end
  local url = html_attr(r.body, "div.bookimg2 img", "src")
  if url ~= "" then return url end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl, "GBK")
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.navtxt")
  if el then return string_trim(el.text) end
  return nil
end

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl, "GBK")
  if not r.success then return nil end
  local el = html_select_first(r.body, ".infolist li:nth-child(2)")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Chapter list ──────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  -- Трансформация URL через gsub (как в твоем примере с NovelBin)
  local listUrl = bookUrl:gsub("/txt/", "/"):gsub("%.htm", "/")
  
  local r = http_get(listUrl, "GBK")
  if not r.success then return {} end

  local chapters = {}
  local links = html_select(r.body, "div#catalog ul li a")
  
  -- На сайте новые главы в начале, инвертируем
  for i = #links, 1, -1 do
    local a = links[i]
    table.insert(chapters, {
      title = string_trim(a.text),
      url   = a.href
    })
  end
  return chapters
end

-- ── Chapter text ──────────────────────────────────────────────────────────────

function getChapterText(html)
  local cleaned = html_remove(html, "h1", "div.txtinfo", "div.bottom-ad", "div.bottem2", ".visible-xs", "script")
  local el = html_select_first(cleaned, "div.txtnav")
  if el then return html_text(el.html) end
  return ""
end