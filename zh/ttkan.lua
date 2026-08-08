-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ttkan"
name     = "TTKan"
version  = "1.0.0"
baseUrl  = "https://www.ttkan.co/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ttkan.png"

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
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((第[\\d一二三四五六七八九十百]+[章节]|Chapter\\s+\\d+|Глава\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(翻译|译者|编辑|校对|更新|阅读|最新阅读)[:\\s：][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- Извлекает novel_id из URL книги вида /novel/chapters/{novel_id}
local function extractNovelId(bookUrl)
  return string.match(bookUrl, "/novel/chapters/([^/?#]+)")
end

-- Строит URL обложки по slug из URL книги
-- bookUrl = ".../novel/chapters/qingshan-huishuohuadezhouzi"
-- → https://static.ttkan.co/cover/qingshan-huishuohuadezhouzi.jpg?w=250&h=300&q=100
local function buildCoverUrl(bookUrl)
  local slug = string.match(bookUrl, "/([^/?#]+)/?$")
  if not slug or slug == "" then return "" end
  return "https://static.ttkan.co/cover/" .. slug .. ".jpg?w=250&h=300&q=100"
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = "https://www.ttkan.co/novel/rank"
  if index > 0 then url = url .. "?page=" .. tostring(index + 1) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".rank_list > div")) do
    local titleEl = html_select_first(card.html, "h2")
    local aEl     = html_select_first(card.html, "a[href*='/novel/chapters/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = buildCoverUrl(bookUrl)
        })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local encoded = url_encode(query)
  local url = "https://www.ttkan.co/novel/search?q=" .. encoded
  if index > 0 then url = url .. "&page=" .. tostring(index + 1) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".novel_cell")) do
    local titleEl = html_select_first(card.html, "h3")
    local aEl     = html_select_first(card.html, "a[href*='/novel/chapters/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, {
          title = t,
          url   = bookUrl,
          cover = buildCoverUrl(bookUrl)
        })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  -- Обложка строится из slug URL книги — без лишнего запроса
  local cover = buildCoverUrl(bookUrl)
  if cover ~= "" then return cover end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".description")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (JSON API) ────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local novelId = extractNovelId(bookUrl)
  if not novelId or novelId == "" then
    log_error("ttkan: cannot extract novelId from " .. bookUrl)
    return {}
  end

  local apiUrl = "https://www.ttkan.co/api/nq/amp_novel_chapters?language=tw&novel_id=" .. novelId

  local r = http_get(apiUrl)
  if not r.success then
    log_error("ttkan: API failed " .. tostring(r.code) .. " " .. apiUrl)
    return {}
  end

  local chapters = {}
  local idx = 1

  local names = regex_match(r.body, '"chapter_name"\\s*:\\s*"([^"]+)"')
  for _, match in ipairs(names) do
    -- regex_match возвращает полное совпадение, извлекаем capture через string.match
    local chapterName = string.match(match, '"chapter_name"%s*:%s*"([^"]+)"')
    if chapterName then
      -- Декодируем unicode escapes если есть
      chapterName = unescape_unicode(chapterName)
      local chUrl = "https://www.ttkan.co/novel/pagea/" .. novelId .. "_" .. tostring(idx) .. ".html"
      table.insert(chapters, { title = chapterName, url = chUrl })
      idx = idx + 1
    end
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "button.btn_show_all_chapters")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html,
    "script", "style",
    ".ads_auto_place", ".mobadsq",
    "amp-img", "img", "svg",
    "center",
    "#div_content_end",
    ".div_adhost",
    ".trc_related_container",
    ".div_feedback",
    ".social_share_frame",
    "amp-social-share",
    "button",
    ".icon", ".decoration",
    ".next_page_links",
    ".more_recommend",
    "a"
  )
  local el = html_select_first(cleaned, ".content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end