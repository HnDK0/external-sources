-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "twkan"
name     = "TWKan"
version  = "1.0.2"
baseUrl  = "https://twkan.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/twkan.png"

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

-- Session-cached book page (shared fetch lib): the book details are read by
-- several functions in one adapter run. getChapterListHash stays on a direct
-- http_get — the hash must see a fresh page.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- Standard chapter-text cleanup (domain lines, leading "第N章" heading,
-- translator/editor credit lines) from the shared content lib.
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url
  if page == 1 then
    url = "https://twkan.com/novels/newhot_2_0_1.html"
  else
    url = "https://twkan.com/novels/newhot_2_0_" .. tostring(page) .. ".html"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, "#article_list_content li")) do
    local titleEl = html_select_first(li.html, "h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(li.html, "img", "data-src")
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
  local encoded = url_encode(query)
  local url = "https://twkan.com/search/" .. encoded .. "/" .. tostring(page) .. ".html"

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, "#article_list_content li, .search-result li, li")) do
    local titleEl = html_select_first(li.html, "h3 a, h3")
    local aEl     = html_select_first(li.html, "a[href*='/book/']")
    if titleEl and aEl then
      local bookUrl = absUrl(aEl.href)
      local cover   = html_attr(li.html, "img", "data-src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1 a")
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
    log_error("twkan: cannot extract bookId from " .. bookUrl)
    return {}
  end

  local ajaxUrl = "https://twkan.com/ajax_novels/chapterlist/" .. bookId .. ".html"
  local r = http_get(ajaxUrl)
  if not r.success then
    log_error("twkan: AJAX failed " .. tostring(r.code))
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
  if not r.success then return nil end
  local el = html_select_first(r.body, ".infolist li:nth-child(2)")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", ".txtad")
  local el = html_select_first(cleaned, "#txtcontent0")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end