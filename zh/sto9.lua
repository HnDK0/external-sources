-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "sto9"
name     = "Sto9"
version  = "1.0.4"
baseUrl  = "https://sto9.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/sto9.png"

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
  text = regex_replace(text, "(?<!\\n)\\u2003\\u2003[^\\n]*o9\\.com[^\\n]*", "")
  text = regex_replace(text, "(?m)^\\s*（還有更新耶）\\s*$", "")
  text = regex_replace(text, "(?i)\\A[\\s\\uFEFF]*((第[\\d一二三四五六七八九十百千萬]+[章節]|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(翻譯|譯者|編輯|校對|翻譯|译者|编辑|校对|更新|閱讀|最新閱讀)[:\\s：][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Кэш страницы книги (fetchPage) ──────────────────────────────────────────

local _pageCache = {}
local function fetchPage(url)
  if _pageCache[url] then return _pageCache[url] end
  local r = http_get(url)
  if not r.success then
    log_error("sto9: fetchPage failed " .. url .. " code=" .. tostring(r.code))
    return nil
  end
  _pageCache[url] = r.body
  return r.body
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = "https://sto9.com/novels/newhot_0_0_" .. tostring(page) .. ".html"
  local r = http_get(url)
  if not r.success then
    log_error("sto9: catalog failed " .. tostring(r.code))
    return { items = {}, hasNext = false }
  end

  local items = {}
  for _, li in ipairs(html_select(r.body, "#article_list_content li")) do
    local titleEl = html_select_first(li.html, "h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(li.html, "img", "data-src")
      if cover == "" then cover = html_attr(li.html, "img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local encoded = url_encode(query)
  local url = "https://sto9.com/search/" .. encoded .. "/" .. tostring(page) .. ".html"
  local r = http_get(url)
  if not r.success then
    log_error("sto9: search failed " .. tostring(r.code))
    return { items = {}, hasNext = false }
  end

  local items = {}
  for _, li in ipairs(html_select(r.body, "#article_list_content li, .search-result li")) do
    local titleEl = html_select_first(li.html, "h3 a, h3")
    local aEl     = html_select_first(li.html, "a[href*='/book/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local cover   = html_attr(li.html, "img", "data-src")
      if cover == "" then cover = html_attr(li.html, "img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Фильтры ───────────────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "category",
      label        = "分類",
      defaultValue = "0",
      options = {
        { value = "0",  label = "全部分類" },
        { value = "1",  label = "玄幻奇幻" },
        { value = "2",  label = "武俠仙俠" },
        { value = "3",  label = "現代都市" },
        { value = "4",  label = "歷史軍事" },
        { value = "5",  label = "科幻小說" },
        { value = "6",  label = "遊戲競技" },
        { value = "7",  label = "恐怖靈異" },
        { value = "8",  label = "言情小說" },
        { value = "9",  label = "動漫同人" },
        { value = "10", label = "其他類型" },
      }
    }
  }
end

function getCatalogFiltered(index, filters)
  local page = index + 1
  local cat  = filters["category"] or "0"
  local url  = "https://sto9.com/novels/class/" .. cat .. "_" .. tostring(page) .. ".html"
  local r = http_get(url)
  if not r.success then
    log_error("sto9: catalog filtered failed " .. tostring(r.code))
    return { items = {}, hasNext = false }
  end

  local items = {}
  for _, li in ipairs(html_select(r.body, "#article_list_content li")) do
    local titleEl = html_select_first(li.html, "h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(li.html, "img", "data-src")
      if cover == "" then cover = html_attr(li.html, "img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги (fetchPage — кэш) ───────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1 a, h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".bookimg2 img", "src")
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "#tab_info .navtxt p")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (AJAX) ────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local bookId = string.match(bookUrl, "/book/([^/.]+)%.html")
  if not bookId then
    log_error("sto9: cannot extract bookId from " .. bookUrl)
    return {}
  end

  local ajaxUrl = "https://sto9.com/ajax_novels/chapterlist/" .. bookId .. ".html"
  local r = http_get(ajaxUrl)
  if not r.success then
    log_error("sto9: AJAX chapterlist failed " .. tostring(r.code))
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

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then
    log_error("sto9: hash failed " .. tostring(r.code))
    return nil
  end
  local el = html_select_first(r.body, ".infolist li:nth-child(2)")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".txtad", ".txtcenter", "#mobile-ad")
  local el = html_select_first(cleaned, ".txtnav")
  if not el then return "" end
  local raw = html_text(el.html)
  raw = regex_replace(raw, "&emsp;&emsp;", "")
  return applyStandardContentTransforms(raw)
end
