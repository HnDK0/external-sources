-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "sto9"
name     = "Sto9"
version = "1.0.7"
baseUrl  = "https://sto9.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/sto9.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

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

-- Standard chapter-text cleanup (domain lines, leading "第N章" heading,
-- translator/editor credit lines) from the shared content lib, plus the
-- site-specific watermarks: the o9.com em-spacer line and the "（還有更新耶）"
-- stub the site injects at the end of a chapter.
local function applyStandardContentTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
  if text == "" then return "" end
  text = regex_replace(text, "(?<!\\n)\\u2003\\u2003[^\\n]*o9\\.com[^\\n]*", "")
  text = regex_replace(text, "(?m)^\\s*（還有更新耶）\\s*$", "")
  return string_trim(text)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- ── Кэш страницы книги (fetchPage) ──────────────────────────────────────────

-- Session-cached book page (shared fetch lib): the book details are read by
-- several functions in one adapter run. getChapterListHash stays on a direct
-- http_get — the hash must see a fresh page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
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

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local sanitized = query:gsub("[:%?%%#&]+", " ")
  local encoded = url_encode(sanitized)
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

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
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
  local page = LIB("catalog").nextIndex(index)
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

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
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

-- ── Статус и дата обновления ──────────────────────────────────────────────

-- Статус книги — мета-тег og:novel:status (напр. «連載»).
function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local s = html_attr(body, "meta[property='og:novel:status']", "content")
  if s and s ~= "" then return s end
  return nil
end

-- Дата обновления — мета-тег og:novel:update_time (формат «YYYY-MM-DD» или
-- «YYYY-MM-DD HH:MM:SS»). Берём только часть YYYY-MM-DD.
function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local dt = html_attr(body, "meta[property='og:novel:update_time']", "content")
  if dt and dt ~= "" then
    local d = LIB("meta").normalizeDate(dt)
    if d then return d end
  end
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
