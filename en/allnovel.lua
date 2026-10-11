-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "allnovel"
name     = "AllNovel"
version  = "1.0.7"
baseUrl  = "https://allnovel.org/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/allnovel.png"
-- status = "dead"  -- домен allnovel.org мёртв: редиректит на novelfull.com,
--                    который покрыт отдельным плагином en/novelfull.lua
status   = "dead"

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

-- novelBinCoverUrl: строим URL обложки из слага книги (src из каталога игнорируем)
local function transformCover(bookUrl)
  if not bookUrl or bookUrl == "" then return "" end
  local slug = string.match(bookUrl, "/([^/?#]+)%.html$") or string.match(bookUrl, "/([^/?#]+)/?$") or ""
  if slug == "" then return "" end
  return "https://images.novelbin.me/novel/" .. slug .. ".jpg"
end

-- Standard chapter-text cleanup (domain lines, leading "Chapter N" heading,
-- translator/editor credit lines) from the shared content lib.
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "latest-release-novel"
  if page > 1 then url = url .. "?page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".col-truyen-main .row")) do
    local titleEl = html_select_first(row.html, "div.col-xs-7 > div > h3 > a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = transformCover(bookUrl)
      })
    end
  end

  local hasNext = html_select_first(r.body, ".pagination .next, li.next a") ~= nil
  return { items = items, hasNext = hasNext }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "search?keyword=" .. url_encode(query)
  if page > 1 then url = url .. "&page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".col-truyen-main .row")) do
    local titleEl = html_select_first(row.html, "div.col-xs-7 > div > h3 > a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = transformCover(bookUrl)
      })
    end
  end

  local hasNext = html_select_first(r.body, ".pagination .next, li.next a") ~= nil
  return { items = items, hasNext = hasNext }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = LIB("fetch").page(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h3.title")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local cover = transformCover(bookUrl)
  if cover ~= "" then return cover end
  local body = LIB("fetch").page(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".book img[src]")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  local body = LIB("fetch").page(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".desc-text")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Статус / Дата обновления ─────────────────────────────────────────────────

function getBookStatus(bookUrl)
  local body = LIB("fetch").page(bookUrl)
  if not body then return nil end
  for _, div in ipairs(html_select(body, ".info div")) do
    local h3 = html_select_first(div.html, "h3")
    if h3 and string_trim(h3.text) == "Status:" then
      local a = html_select_first(div.html, "a")
      if a then return LIB("meta").status(a.text) end
    end
  end
  return nil
end

-- Сайт не показывает дату обновления на странице книги (нет <time>, meta dates,
-- JSON-LD dateModified и т.п.) — getBookLastUpdate не реализуется.

-- ── Список глав (PAGE_BASED) ──────────────────────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local maxPage = 1
  local lastPageEl = html_select_first(r.body, "#list-chapter > ul:nth-child(3) > li.last > a")
  if lastPageEl then
    local href = lastPageEl.href or ""
    local p = string.match(href, "[?&]page=(%d+)")
    if p then maxPage = tonumber(p) or 1 end
  end

  -- Собираем URL всех страниц (кроме первой — она уже загружена)
  local pageUrls = {}
  for page = 2, maxPage do
    table.insert(pageUrls, bookUrl .. "?page=" .. tostring(page))
  end

  -- Параллельная загрузка остальных страниц
  local pageResults = {}
  if #pageUrls > 0 then
    pageResults = http_get_batch(pageUrls)
  end

  local chapters = {}

  -- Страница 1 уже есть
  for _, a in ipairs(html_select(r.body, "ul.list-chapter li a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      table.insert(chapters, { title = string_clean(a.text), url = chUrl })
    end
  end

  -- Остальные страницы из batch (порядок сохранён)
  for _, pr in ipairs(pageResults) do
    if pr.success then
      for _, a in ipairs(html_select(pr.body, "ul.list-chapter li a")) do
        local chUrl = absUrl(a.href)
        if chUrl ~= "" then
          table.insert(chapters, { title = string_clean(a.text), url = chUrl })
        end
      end
    end
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".l-chapters li:first-child a")
  if el then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", "h3")
  local el = html_select_first(cleaned, "#chapter-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local body = LIB("fetch").page(bookUrl)
  if not body then return {} end
  for _, div in ipairs(html_select(body, ".info div")) do
    local h3 = html_select_first(div.html, "h3")
    if h3 and string_trim(h3.text) == "Genre:" then
      return LIB("meta").collectGenres(html_select(div.html, "a"))
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
      defaultValue = "most-popular",
      options = {
        { value = "most-popular",    label = "Most Popular"    },
        { value = "hot-novel",       label = "Hot Novel"       },
        { value = "completed-novel", label = "Completed Novel" },
      }
    },
    {
      type        = "checkbox",
      key         = "genre",
      label       = "Genre",
      multiselect = false,
      options = {
        { value = "Action",        label = "Action"        },
        { value = "Adult",         label = "Adult"         },
        { value = "Adventure",     label = "Adventure"     },
        { value = "Comedy",        label = "Comedy"        },
        { value = "Drama",         label = "Drama"         },
        { value = "Ecchi",         label = "Ecchi"         },
        { value = "Fantasy",       label = "Fantasy"       },
        { value = "Gender+Bender", label = "Gender Bender" },
        { value = "Harem",         label = "Harem"         },
        { value = "Historical",    label = "Historical"    },
        { value = "Horror",        label = "Horror"        },
        { value = "Josei",         label = "Josei"         },
        { value = "Martial+Arts",  label = "Martial Arts"  },
        { value = "Mature",        label = "Mature"        },
        { value = "Mecha",         label = "Mecha"         },
        { value = "Mystery",       label = "Mystery"       },
        { value = "Psychological", label = "Psychological" },
        { value = "Reincarnation", label = "Reincarnation" },
        { value = "Romance",       label = "Romance"       },
        { value = "School+Life",   label = "School Life"   },
        { value = "Sci-fi",        label = "Sci-fi"        },
        { value = "Seinen",        label = "Seinen"        },
        { value = "Shoujo",        label = "Shoujo"        },
        { value = "Shounen",       label = "Shounen"       },
        { value = "Shounen+Ai",    label = "Shounen Ai"    },
        { value = "Slice+of+Life", label = "Slice of Life" },
        { value = "Smut",          label = "Smut"          },
        { value = "Sports",        label = "Sports"        },
        { value = "Supernatural",  label = "Supernatural"  },
        { value = "Tragedy",       label = "Tragedy"       },
        { value = "Wuxia",         label = "Wuxia"         },
        { value = "Xianxia",       label = "Xianxia"       },
        { value = "Xuanhuan",      label = "Xuanhuan"      },
        { value = "Yaoi",          label = "Yaoi"          },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = LIB("catalog").nextIndex(index)
  local ftype  = filters["type"] or "most-popular"
  local genres = filters["genre_included"] or {}
  local genre  = genres[1] or ""

  local basePath = genre ~= "" and ("genre/" .. genre) or ftype
  local url = baseUrl .. basePath
  if page > 1 then url = url .. "?page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".col-truyen-main .row")) do
    local titleEl = html_select_first(row.html, "div.col-xs-7 > div > h3 > a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = transformCover(bookUrl)
      })
    end
  end
  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end
