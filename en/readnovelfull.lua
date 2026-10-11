-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "read_novel_full"
name     = "ReadNovelFull"
version  = "1.1.2"
baseUrl  = "https://readnovelfull.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/readnovelfull.png"

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

local function transformCover(coverUrl)
  if not coverUrl or coverUrl == "" then return "" end
  coverUrl = regex_replace(coverUrl, "t-200x89", "t-300x439")
  coverUrl = regex_replace(coverUrl, "t-80x113", "t-300x439")
  return coverUrl
end

-- Standard chapter-text cleanup from the shared content lib.
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- Session-cached book page (shared fetch lib, same contract as before).
local function fetchBookPage(url)
  return LIB("fetch").page(url)
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local catalogBase = baseUrl .. "novel-list/most-popular-novel"
  local url = index == 0 and catalogBase or (catalogBase .. "?page=" .. tostring(LIB("catalog").nextIndex(index)))

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".col-novel-main .row")) do
    local titleEl = html_select_first(row.html, ".novel-title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(row.html, "div.col-xs-3 > div > img", "src")
      if cover == "" then cover = html_attr(row.html, "div.col-xs-3 > div > img", "data-src") end
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = transformCover(absUrl(cover))
      })
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local searchBase = baseUrl:gsub("/$", "") .. "/novel-list/search?keyword=" .. url_encode(query)
  local url = index == 0 and searchBase or (searchBase .. "&page=" .. tostring(LIB("catalog").nextIndex(index)))

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".col-novel-main .row")) do
    local titleEl = html_select_first(row.html, ".novel-title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(row.html, "div.col-xs-3 > div > img", "src")
      if cover == "" then cover = html_attr(row.html, "div.col-xs-3 > div > img", "data-src") end
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = transformCover(absUrl(cover))
      })
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h3.title")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local cover = html_attr(r.body, ".book img[src]", "src")
  if cover == "" then return nil end
  return transformCover(absUrl(cover))
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "#tab-description")
  return el and string_trim(el.text) or nil
end

-- ── Рейтинг книги ─────────────────────────────────────────────────────────────

-- Рейтинг со страницы книги: <span itemprop="ratingValue">8.7</span> (шкала 10,
-- bestRating=10). Формат "Rating: 8.7/10" — приложение само пересчитает к 0-5
-- (голое число вне 0-5 без явной шкалы движок не показывает).
function getBookRating(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, 'span[itemprop="ratingValue"]')
  if not el then return nil end
  local n = string.match(string_clean(el.text), "%d+%.?%d*")
  if not n then return nil end
  return "Rating: " .. n .. "/10"
end

-- ── Статус / Дата обновления ──────────────────────────────────────────────────

-- Статус книги: <li><h3>Status:</h3><a class="text-primary">Ongoing</a></li>
-- (нормализация — shared meta-библиотека).
function getBookStatus(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return nil end
  for _, li in ipairs(html_select(html, "ul.info li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Status:" then
      local a = html_select_first(li.html, "a")
      if a then return LIB("meta").status(a.text) end
    end
  end
  return nil
end

-- Дата обновления: <div class="item-time"> 5 years ago</div> → YYYY-MM-DD.
-- Относительный формат сайта парсится shared meta-библиотекой.
function getBookLastUpdate(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return nil end
  local el = html_select_first(html, ".item-time")
  if not el then return nil end
  return LIB("meta").normalizeDate(el.text)
end

-- ── Список глав (AJAX) ────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then
    log_error("readnovelfull: getChapterList failed for " .. bookUrl)
    return {}
  end

  -- novelId хранится в атрибуте data-novel-id элемента #rating
  local novelId = html_attr(r.body, "#rating[data-novel-id]", "data-novel-id")
  if novelId == "" then
    log_error("readnovelfull: novelId not found at " .. bookUrl)
    return {}
  end

  local ajaxUrl = baseUrl:gsub("/$", "") .. "/ajax/chapter-archive?novelId=" .. novelId
  local ar = http_get(ajaxUrl)
  if not ar.success then
    log_error("readnovelfull: AJAX failed code=" .. tostring(ar.code))
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(ar.body, "a[href]")) do
    local title = a.title
    if not title or title == "" then title = string_trim(a.text) end
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      table.insert(chapters, { title = string_clean(title), url = chUrl })
    end
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".l-chapter a.chapter-title")
  return el and el.href or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", ".ads", ".advertisement", "h3", ".chapter-warning", ".ad-insert")
  local el = html_select_first(cleaned, "#chr-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  for _, li in ipairs(html_select(r.body, "ul.info.info-meta li, ul.info-meta li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Genre:" then
      -- trim + drop empties — shared meta lib (site order kept).
      return LIB("meta").collectGenres(html_select(li.html, "a"))
    end
  end
  return {}
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "type",
      label        = "Novel Listing",
      defaultValue = "novel-list/most-popular-novel",
      options = {
        { value = "novel-list/most-popular-novel", label = "Most Popular"    },
        { value = "novel-list/hot-novel",          label = "Hot Novel"       },
        { value = "novel-list/completed-novel",    label = "Completed Novel" },
      }
    },
    {
      type        = "checkbox",
      key         = "genre",
      label       = "Genre",
      multiselect = false,
      options = {
        { value = "action",         label = "Action"         },
        { value = "adult",          label = "Adult"          },
        { value = "adventure",      label = "Adventure"      },
        { value = "comedy",         label = "Comedy"         },
        { value = "drama",          label = "Drama"          },
        { value = "eastern",        label = "Eastern"        },
        { value = "ecchi",          label = "Ecchi"          },
        { value = "fantasy",        label = "Fantasy"        },
        { value = "game",           label = "Game"           },
        { value = "gender+bender",  label = "Gender Bender"  },
        { value = "harem",          label = "Harem"          },
        { value = "historical",     label = "Historical"     },
        { value = "horror",         label = "Horror"         },
        { value = "josei",          label = "Josei"          },
        { value = "martial+arts",   label = "Martial Arts"   },
        { value = "mature",         label = "Mature"         },
        { value = "mecha",          label = "Mecha"          },
        { value = "modern+life",    label = "Modern Life"    },
        { value = "mystery",        label = "Mystery"        },
        { value = "psychological",  label = "Psychological"  },
        { value = "reincarnation",  label = "Reincarnation"  },
        { value = "romance",        label = "Romance"        },
        { value = "school+life",    label = "School Life"    },
        { value = "sci-fi",         label = "Sci-fi"         },
        { value = "seinen",         label = "Seinen"         },
        { value = "shoujo",         label = "Shoujo"         },
        { value = "shounen",        label = "Shounen"        },
        { value = "slice+of+life",  label = "Slice of Life"  },
        { value = "smut",           label = "Smut"           },
        { value = "sports",         label = "Sports"         },
        { value = "supernatural",   label = "Supernatural"   },
        { value = "system",         label = "System"         },
        { value = "thriller",       label = "Thriller"       },
        { value = "tragedy",        label = "Tragedy"        },
        { value = "transmigration", label = "Transmigration" },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = LIB("catalog").nextIndex(index)
  local ftype  = filters["type"] or "novel-list/most-popular-novel"
  local genres = filters["genre_included"] or {}
  local genre  = genres[1] or ""

  local basePath = genre ~= "" and ("genres/" .. genre) or ftype
  local url = baseUrl .. basePath
  if page > 1 then url = url .. "?page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".col-novel-main .row")) do
    local titleEl = html_select_first(row.html, ".novel-title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover = html_attr(row.html, "div.col-xs-3 > div > img", "src")
      if cover == "" then cover = html_attr(row.html, "div.col-xs-3 > div > img", "data-src") end
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = transformCover(absUrl(cover))
      })
    end
  end
  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end