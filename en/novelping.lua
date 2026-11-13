-- ── Метаданные ───────────────────────────────────────────────────────────────
id        = "NovelPing"
name      = "Novel Ping"
version   = "1.0.3"
baseUrl   = "https://novelping.com/"
language  = "en"
icon      = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelping.png"

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

-- ── Кэш страниц (1 запрос вместо 4–5) ────────────────────────────────────────
-- Session-cached page fetch (shared fetch lib, same contract as before).

local function fetchPage(url)
  return LIB("fetch").page(url)
end

local function absUrl(href)
  return LIB("urls").absUrl(baseUrl, href)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- ── JSON API ──────────────────────────────────────────────────────────────────
-- novelping.com/api-web (тот же бэкенд, что у novelarrow.com) отдаёт каталог,
-- поиск и фильтры одним JSON: rating (avgPoint, 0–5), totalPages и обложки,
-- которые собираются из slug. HTML каталога рейтинга не содержит вовсе.

local apiBase = baseUrl:gsub("/$", "") .. "/api-web/"

local function apiGet(path)
  local r = http_get(apiBase .. path, { headers = { ["Accept"] = "application/json" } })
  if not r.success then
    log_error("apiGet: HTTP " .. tostring(r.code) .. " " .. path)
    return nil
  end
  local ok, data = pcall(json_parse, r.body)
  if not ok or type(data) ~= "table" then
    log_error("apiGet: bad JSON " .. path)
    return nil
  end
  return data
end

-- avgPoint приходит как число или {"$numberDecimal":"4.47"}; 0 = нет голосов.
local function apiRating(item)
  local raw = item.avgPoint
  if type(raw) == "table" then raw = raw["$numberDecimal"] end
  local v = tonumber(raw)
  if not v or v <= 0 then return nil end
  return string.format("%.1f", v)
end

local function coverUrl(id)
  -- Полный размер вместо миниатюры novel_200_89: хост и путь стабильны.
  return "https://images.novelping.com/novel/" .. id .. ".jpg"
end

-- Элементы API → CatalogItem-таблица плагина.
local function apiCatalogPage(data)
  local items = {}
  if type(data) ~= "table" or type(data.items) ~= "table" then
    return { items = {}, hasNext = false }
  end
  for _, it in ipairs(data.items) do
    local id = it.novel_id
    local title = it.novel_name
    if type(id) == "string" and id ~= "" and type(title) == "string" and title ~= "" then
      table.insert(items, {
        title  = string_clean(title),
        url    = baseUrl .. "book/" .. id,
        cover  = coverUrl(id),
        rating = apiRating(it),
      })
    end
  end
  local pagination = data.pagination
  local totalPages = type(pagination) == "table" and tonumber(pagination.totalPages) or nil
  local page = type(pagination) == "table" and tonumber(pagination.page) or nil
  local hasNext
  if totalPages and page then
    hasNext = page < totalPages
  else
    hasNext = #items > 0
  end
  return { items = items, hasNext = hasNext }
end

-- Standard chapter-text cleanup from the shared content lib, plus the site's
-- own "Remove Ads From $N" watermark.
local function applyStandardContentTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
  if text == "" then return "" end
  text = regex_replace(text, "(?i)Remove\\s+Ads\\s+From\\s+\\$\\d+", "")
  return string_trim(text)
end

-- ── Извлечение novelId из URL книги (slug) ──────────────────────────────────

local function extractNovelId(bookUrl)
  return bookUrl:match("/book/([^/?#]+)")
end

-- ── AJAX-запрос архива глав ───────────────────────────────────────────────────

local function fetchChapterArchive(novelId, bookUrl)
  local ajaxUrl = baseUrl:gsub("/$", "") .. "/ajax/chapter-archive?novelId=" .. novelId
  local ar = http_get(ajaxUrl, {
    headers = {
      ["Referer"]          = bookUrl,
      ["X-Requested-With"] = "XMLHttpRequest",
    }
  })
  if not ar.success then
    log_error("fetchChapterArchive: AJAX failed code=" .. tostring(ar.code))
    return nil
  end
  return ar.body
end

-- ── Парсинг глав из HTML шаблона ─────────────────────────────────────────────
-- href уже абсолютные (https://novelping.com/book/{slug}/{chapter-id}),
-- chapter-id бывает любым — берём href как есть.

local function parseChaptersFromArchive(archiveHtml)
  local tmpl = html_select_first(archiveHtml, "template[data-chapter-item-template]")
  if not tmpl then
    log_error("parseChaptersFromArchive: template element not found")
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(tmpl.html, "a[href]")) do
    local span  = html_select_first(a.html, "span.nchr-text")
    local title = span and string_trim(span.text) or ""
    if title == "" then title = string_trim(a.title or "") end
    if title == "" then title = string_trim(a.text) end
    if title == "" then title = a.href end
    table.insert(chapters, { title = title, url = a.href })
  end
  return chapters
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local data = apiGet("novels?page=" .. page .. "&limit=20&sort=LASTEST&status=all&genre=ALL")
  if not data then return { items = {}, hasNext = false } end
  return apiCatalogPage(data)
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local data = apiGet(
    "search?keyword=" .. url_encode(query) .. "&page=" .. page .. "&limit=20"
  )
  if not data then return { items = {}, hasNext = false } end
  return apiCatalogPage(data)
end

-- ── Детали книги (все через кэш — 1 запрос) ──────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h3.title")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local url = html_attr(body, "meta[property='og:image']", "content")
  return url ~= "" and absUrl(url) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "#novel-description-content")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  for _, li in ipairs(html_select(body, "ul.info.info-meta li, ul.info-meta li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Genre:" then
      -- trim + drop empties — shared meta lib (site order kept).
      return LIB("meta").collectGenres(html_select(li.html, "a"))
    end
  end
  return {}
end

function getBookAuthor(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local author = html_attr(body, "meta[property='og:novel:author']", "content")
  author = string_trim(author)
  return author ~= "" and author or nil
end

function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  -- <meta property="og:novel:update_time" content="2026-11-13T06:08:46.343Z">
  local raw = html_attr(body, "meta[property='og:novel:update_time']", "content")
  return raw:match("^(%d%d%d%d%-%d%d%-%d%d)")
end

function getBookRating(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "span[itemprop='ratingValue']")
  if not el then return nil end
  local value = string_trim(el.text)
  if value == "" or tonumber(value) == nil then return nil end
  -- Сайт отдаёт шкалу 0–10 ("8.8"), а приложение без "/10" считает число
  -- оценкой из 5 и молча скрывает рейтинг. bestRating на странице = 10.
  local bestEl = html_select_first(body, "span[itemprop='bestRating']")
  local scale = bestEl and string_trim(bestEl.text) or ""
  if tonumber(scale) == nil then scale = "10" end
  return value .. "/" .. scale
end

function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  for _, li in ipairs(html_select(body, "ul.info.info-meta li, ul.info-meta li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Status:" then
      local a = html_select_first(li.html, "a")
      if a then return LIB("meta").status(a.text) end
    end
  end
  return nil
end

-- getBookLastUpdate не реализован: надёжного источника даты в HTML нет.

-- ── Список глав ───────────────────────────────────────────────────────────────
-- NovelPing отдаёт все главы одним AJAX-запросом (chapter-archive).
-- totalPages = 1, движок при обновлении перечитывает только эту страницу.

function parsePage(bookUrl, page)
  if page > 1 then
    return { chapters = {}, totalPages = 1 }
  end

  local novelId = extractNovelId(bookUrl)
  if not novelId then
    log_error("parsePage: cannot extract novelId from " .. bookUrl)
    return { chapters = {}, totalPages = 1 }
  end

  local archiveHtml = fetchChapterArchive(novelId, bookUrl)
  if not archiveHtml then
    return { chapters = {}, totalPages = 1 }
  end

  local chapters = parseChaptersFromArchive(archiveHtml)
  log_error("parsePage: found " .. tostring(#chapters) .. " chapters")
  return { chapters = chapters, totalPages = 1 }
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html)
  local el = html_select_first(html, "#chr-content")
  if not el then return "" end
  local cleaned = html_remove(el.html, "script", "style", ".ads", "h3", "h4", ".js-ad-slot", ".ad-insert", "[id^=pf-]", "[class*='app-promo']")
  return applyStandardContentTransforms(html_text(cleaned))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────
-- Жанры и теги — из API (те же списки, что рендерит search?advanced=1):
-- genres ~55, tags ~1466. Держать их в коде бессмысленно: сайт добавляет теги
-- постоянно. API недоступен → эти секции просто скрываются, остальное работает.

local function apiOptions(path, valueKey, labelKey)
  local data = apiGet(path)
  local out = {}
  if type(data) ~= "table" or type(data.items) ~= "table" then
    log_error("getFilterList: no options from " .. path)
    return out
  end
  for _, it in ipairs(data.items) do
    local value, label
    if type(it) == "table" then
      value = it[valueKey]
      label = it[labelKey] or value
    else
      value = it
      label = it
    end
    if type(value) == "string" and value ~= "" then
      table.insert(out, { value = value, label = label })
    end
  end
  return out
end

local _filterList

function getFilterList()
  if _filterList then return _filterList end

  local filters = {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort By",
      defaultValue = "",
      options = {
        { value = "LASTEST",  label = "Newest update"    },
        { value = "NEW",      label = "Recently added"   },
        { value = "ALL_TIME", label = "Top (most viewed)" },
        { value = "",         label = "Popular this week" },
        { value = "RATING",   label = "Top rated"        },
        { value = "CHAPTERS", label = "Most chapters"    },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "all",
      options = {
        { value = "all",       label = "All"       },
        { value = "ongoing",   label = "Ongoing"   },
        { value = "completed", label = "Completed" },
      }
    },
    {
      type         = "select",
      key          = "language",
      label        = "Language",
      defaultValue = "ALL",
      options = {
        { value = "ALL", label = "All"      },
        { value = "EN",  label = "English"  },
        { value = "CN",  label = "Chinese"  },
        { value = "JP",  label = "Japanese" },
        { value = "KR",  label = "Korean"   },
      }
    },
    {
      type         = "select",
      key          = "genre_mode",
      label        = "Genre Mode",
      defaultValue = "AND",
      options = {
        { value = "AND", label = "Match all" },
        { value = "OR",  label = "Match any" },
      }
    },
  }

  local genres = apiOptions("genres", "genre_id", "genre_name")
  if #genres > 0 then
    table.insert(filters, {
      type        = "checkbox",
      key         = "genres",
      label       = "Genres",
      multiselect = true,
      options     = genres,
    })
  end

  local tags = apiOptions("tags")
  if #tags > 0 then
    table.insert(filters, {
      type         = "select",
      key          = "tag_mode",
      label        = "Tag Mode",
      defaultValue = "AND",
      options = {
        { value = "AND", label = "Match all" },
        { value = "OR",  label = "Match any" },
      }
    })
    table.insert(filters, {
      type        = "checkbox",
      key         = "tags",
      label       = "Tags",
      multiselect = true,
      options     = tags,
    })
  end

  table.insert(filters, {
    type         = "text",
    key          = "min_chapters",
    label        = "Min Chapters",
    defaultValue = ""
  })
  table.insert(filters, {
    type         = "text",
    key          = "max_chapters",
    label        = "Max Chapters",
    defaultValue = ""
  })

  _filterList = filters
  return _filterList
end

-- ── Каталог с фильтрами (JSON API) ────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page = LIB("catalog").nextIndex(index)
  local parts = { "page=" .. page, "limit=20" }
  local function add(key, value)
    if value == nil or value == "" then return end
    table.insert(parts, key .. "=" .. url_encode(tostring(value)))
  end

  local sort = filters["sort"]
  if sort and sort ~= "" then add("sort", sort) end

  local status = filters["status"]
  if status and status ~= "all" then add("status", status) end

  local language = filters["language"]
  if language and language ~= "ALL" then add("language", language) end

  local genre_mode = filters["genre_mode"]
  if genre_mode and genre_mode ~= "AND" then add("genre_mode", genre_mode) end

  local tag_mode = filters["tag_mode"]
  if tag_mode and tag_mode ~= "AND" then add("tag_mode", tag_mode) end

  for _, g in ipairs(filters["genres_included"] or {}) do add("genres", g) end
  for _, g in ipairs(filters["genres_excluded"] or {}) do add("genres_exclude", g) end
  for _, t in ipairs(filters["tags_included"] or {}) do add("tags", t) end
  for _, t in ipairs(filters["tags_excluded"] or {}) do add("tags_exclude", t) end

  add("min_chapters", filters["min_chapters"])
  add("max_chapters", filters["max_chapters"])

  -- Пустая форма = обычный каталог: API без параметров отдаёт популярное,
  -- а не пустую страницу (в отличие от HTML advanced search).
  local data = apiGet("novels?" .. table.concat(parts, "&"))
  if not data then return { items = {}, hasNext = false } end
  return apiCatalogPage(data)
end