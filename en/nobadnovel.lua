-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "nobadnovel"
name     = "NoBadNovel"
version  = "1.0.2"
baseUrl  = "https://www.nobadnovel.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/nobadnovel.png"

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

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Standard chapter-text cleanup (domain lines, leading "Chapter N" heading,
-- translator/editor credit lines) from the shared content lib.
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url
  if index == 0 then
    url = baseUrl .. "series"
  else
    url = baseUrl .. "series/page/" .. tostring(LIB("catalog").nextIndex(index))
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".grid > div")) do
    local titleEl = html_select_first(card.html, "h4 a")
    local bookUrl = absUrl(html_attr(card.html, "a[href*=/series/]", "href"))
    local cover   = absUrl(html_attr(card.html, "img[src]", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url
  if index == 0 then
    url = baseUrl:gsub("/$", "") .. "/series?keyword=" .. url_encode(query)
  else
    url = baseUrl:gsub("/$", "") .. "/series/page/" .. tostring(LIB("catalog").nextIndex(index)) .. "?keyword=" .. url_encode(query)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".grid > div")) do
    local titleEl = html_select_first(card.html, "h4 a")
    local bookUrl = absUrl(html_attr(card.html, "a[href*=/series/]", "href"))
    local cover   = absUrl(html_attr(card.html, "img[src]", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────
-- Session-cached page fetch (shared fetch lib): the engine calls the detail
-- functions in parallel with the same bookUrl. getChapterList /
-- getChapterListHash stay on a direct http_get — they must see fresh HTML.

local function fetchPage(url)
  return LIB("fetch").page(url)
end

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "img[src*=cdn.nobadnovel]")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "#intro .content")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Статус ─────────────────────────────────────────────────────────────────────

function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "div.badge")
  if el then return LIB("meta").status(el.text) end
  return nil
end

-- ── Список глав (NONE, порядок не меняется) ───────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, ".chapter-list a[href]")) do
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
  local el = html_select_first(r.body, ".chapter-list li:last-child a")
  if el then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".adblock-service")
  -- Jsoup: экранирование : в классах через \\
  local el = html_select_first(cleaned, "div.text-base.sm\\:text-lg")
  if not el then
    -- Fallback на более широкий селектор
    el = html_select_first(cleaned, "div[class*=text-base]")
  end
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end