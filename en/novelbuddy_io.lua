-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "novelbuddy_io"
name     = "NovelBuddy (IO)"
version  = "2.1.0"
baseUrl  = "https://novelbuddy.io"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbuddy.png"

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
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- Извлекает JSON из тега <script id="__NEXT_DATA__">
local function extractNextData(body)
  local el = html_select_first(body, "script#__NEXT_DATA__")
  if not el then return nil end
  return json_decode(el.text)
end

-- ── Каталог (популярные) ──────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url  = baseUrl .. "/popular?page=" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local data = extractNextData(r.body)
  if not data then return { items = {}, hasNext = false } end

  local pageProps = data.props and data.props.pageProps
  if not pageProps then return { items = {}, hasNext = false } end

  local rawItems = pageProps.items or {}
  local items = {}
  for _, novel in ipairs(rawItems) do
    local bookUrl = absUrl(novel.url or ("/" .. (novel.slug or "")))
    local cover   = novel.cover or ""
    local title   = novel.name  or ""
    if bookUrl ~= "" and title ~= "" then
      table.insert(items, {
        title = title,
        url   = bookUrl,
        cover = cover
      })
    end
  end

  local pagination = pageProps.pagination or {}
  local hasNext = pagination.has_next
  if hasNext == nil then hasNext = #items > 0 end

  return { items = items, hasNext = hasNext }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────
-- Сайт рендерит результаты поиска на клиенте, поэтому используем API напрямую.

function getCatalogSearch(index, query)
  local page   = index + 1
  local apiUrl = "https://api.novelbuddy.io/titles/search?q=" .. url_encode(query)
                 .. "&page=" .. tostring(page) .. "&limit=24"

  local r = http_get(apiUrl)
  if not r.success then return { items = {}, hasNext = false } end

  local data = json_decode(r.body)
  if not data then return { items = {}, hasNext = false } end

  -- API возвращает {"success":true,"data":{"items":[...]}}
  local inner    = data.data or {}
  local rawItems = inner.items or data.items or data.results or {}
  local items = {}
  for _, novel in ipairs(rawItems) do
    local slug    = novel.slug or ""
    local bookUrl = absUrl("/" .. slug)
    local cover   = novel.cover or
                    ("https://static.novelbuddy.com/thumb/" .. slug .. ".png")
    local title   = novel.name or novel.title or ""
    if slug ~= "" and title ~= "" then
      table.insert(items, {
        title = title,
        url   = bookUrl,
        cover = cover
      })
    end
  end

  local pagination = inner.pagination or data.pagination or data.meta or {}
  local hasNext = pagination.has_next
  if hasNext == nil then hasNext = #items >= 24 end

  return { items = items, hasNext = hasNext }
end

-- ── Внутренний хелпер: загрузить и разобрать страницу книги ──────────────────

local function fetchBookData(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local data = extractNextData(r.body)
  if not data then return nil end
  local pp = data.props and data.props.pageProps
  if not pp then return nil end
  return pp.initialManga or nil
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local manga = fetchBookData(bookUrl)
  if manga then return manga.name end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local manga = fetchBookData(bookUrl)
  if manga then
    local cover = manga.cover or ""
    if cover ~= "" then return cover end
    local slug = manga.slug or ""
    if slug ~= "" then
      return "https://static.novelbuddy.com/thumb/" .. slug .. ".png"
    end
  end
  return nil
end

function getBookDescription(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local summary = manga.summary or ""
  -- summary содержит HTML, конвертируем в текст
  if summary ~= "" then
    -- Убираем теги
    summary = regex_replace(summary, "<[^>]+>", "")
    summary = regex_replace(summary, "&lt;", "<")
    summary = regex_replace(summary, "&gt;", ">")
    summary = regex_replace(summary, "&amp;", "&")
    summary = regex_replace(summary, "&nbsp;", " ")
    return string_trim(summary)
  end
  return nil
end

function getBookGenres(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return {} end
  local genres = {}
  local seen = {}
  -- genres
  for _, g in ipairs(manga.genres or {}) do
    local name = g.name or ""
    if name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(genres, name)
    end
  end
  return genres
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  -- Сначала получаем id книги из __NEXT_DATA__
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local data = extractNextData(r.body)
  if not data then return {} end

  local pp    = data.props and data.props.pageProps
  local manga = pp and pp.initialManga
  if not manga then return {} end

  local mangaId = manga.id or ""
  if mangaId == "" then
    log_error("NovelBuddy IO: manga id not found for " .. bookUrl)
    return {}
  end

  -- Загружаем полный список глав через API
  local apiUrl = "https://api.novelbuddy.io/titles/" .. mangaId .. "/chapters?limit=9999&page=1"
  local ar = http_get(apiUrl)

  local chapters = {}

  if ar.success then
    local apiData = json_decode(ar.body)
    if apiData then
      local rawChapters = apiData.data or apiData.chapters or apiData.items or {}
      for _, ch in ipairs(rawChapters) do
        local slug   = ch.slug or ch.id or ""
        local chUrl  = ch.url or absUrl("/" .. (manga.slug or "") .. "/" .. slug)
        local title  = ch.name or ch.title or slug
        if chUrl ~= "" then
          table.insert(chapters, { title = string_clean(title), url = absUrl(chUrl) })
        end
      end
    end
  end

  -- Если API не дал результатов — берём главы из __NEXT_DATA__ (частичный список)
  if #chapters == 0 then
    local rawChapters = pp.chapters or {}
    local mangaSlug   = manga.slug or ""
    for _, ch in ipairs(rawChapters) do
      local chUrl = ch.url or ("/" .. mangaSlug .. "/" .. (ch.id or ch.slug or ""))
      local title = ch.name or ch.title or ""
      if chUrl ~= "" then
        table.insert(chapters, { title = string_clean(title), url = absUrl(chUrl) })
      end
    end
    -- __NEXT_DATA__ отдаёт newest-first → разворачиваем
    local reversed = {}
    for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
    return reversed
  end

  -- API обычно возвращает newest-first → разворачиваем
  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local stats = manga.stats or {}
  local count = stats.chaptersCount
  if count then return tostring(count) end
  -- Запасной вариант: дата последнего обновления
  return manga.updatedAt or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style",
    "#listen-chapter", "#google_translate_element", ".ads", ".advertisement",
    "[class*='ad-']", "[id*='ad-']")

  -- Новый сайт — пробуем новые селекторы сначала, потом старые
  local el = html_select_first(cleaned, ".chapter-content")
  if not el then el = html_select_first(cleaned, "#chapter-content") end
  if not el then el = html_select_first(cleaned, ".content-inner") end
  if not el then el = html_select_first(cleaned, ".reading-content") end
  if not el then el = html_select_first(cleaned, "article") end
  if not el then return "" end

  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Order by",
      defaultValue = "popular",
      options = {
        { value = "popular",    label = "Popular"    },
        { value = "updated_at", label = "Updated At" },
        { value = "created_at", label = "Created At" },
        { value = "name",       label = "Name"       },
        { value = "rating",     label = "Rating"     },
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
      type  = "checkbox",
      key   = "genre",
      label = "Genres (OR)",
      options = {
        { value = "action",          label = "Action"          },
        { value = "action-adventure",label = "Action Adventure"},
        { value = "adult",           label = "Adult"           },
        { value = "adventure",       label = "Adventure"       },
        { value = "comedy",          label = "Comedy"          },
        { value = "cultivation",     label = "Cultivation"     },
        { value = "drama",           label = "Drama"           },
        { value = "eastern",         label = "Eastern"         },
        { value = "ecchi",           label = "Ecchi"           },
        { value = "fan-fiction",     label = "Fan Fiction"     },
        { value = "fantasy",         label = "Fantasy"         },
        { value = "game",            label = "Game"            },
        { value = "gender-bender",   label = "Gender Bender"   },
        { value = "harem",           label = "Harem"           },
        { value = "historical",      label = "Historical"      },
        { value = "horror",          label = "Horror"          },
        { value = "isekai",          label = "Isekai"          },
        { value = "josei",           label = "Josei"           },
        { value = "light-novel",     label = "Light Novel"     },
        { value = "litrpg",          label = "LitRPG"          },
        { value = "lolicon",         label = "Lolicon"         },
        { value = "magic",           label = "Magic"           },
        { value = "martial-arts",    label = "Martial Arts"    },
        { value = "mature",          label = "Mature"          },
        { value = "mecha",           label = "Mecha"           },
        { value = "military",        label = "Military"        },
        { value = "modern-life",     label = "Modern Life"     },
        { value = "mystery",         label = "Mystery"         },
        { value = "psychological",   label = "Psychological"   },
        { value = "reincarnation",   label = "Reincarnation"   },
        { value = "romance",         label = "Romance"         },
        { value = "school-life",     label = "School Life"     },
        { value = "sci-fi",          label = "Sci-fi"          },
        { value = "seinen",          label = "Seinen"          },
        { value = "shoujo",          label = "Shoujo"          },
        { value = "shoujo-ai",       label = "Shoujo Ai"       },
        { value = "shounen",         label = "Shounen"         },
        { value = "shounen-ai",      label = "Shounen Ai"      },
        { value = "slice-of-life",   label = "Slice of Life"   },
        { value = "smut",            label = "Smut"            },
        { value = "sports",          label = "Sports"          },
        { value = "supernatural",    label = "Supernatural"    },
        { value = "system",          label = "System"          },
        { value = "tragedy",         label = "Tragedy"         },
        { value = "urban",           label = "Urban"           },
        { value = "urban-life",      label = "Urban Life"      },
        { value = "wuxia",           label = "Wuxia"           },
        { value = "xianxia",         label = "Xianxia"         },
        { value = "xuanhuan",        label = "Xuanhuan"        },
        { value = "yaoi",            label = "Yaoi"            },
        { value = "yuri",            label = "Yuri"            },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local sort   = filters["sort"]   or "popular"
  local status = filters["status"] or "all"
  local genres = filters["genre_included"] or {}

  -- Строим жанры через запятую для API
  local genreStr = table.concat(genres, ",")

  -- Используем API /titles/search с фильтрами
  local apiUrl = "https://api.novelbuddy.io/titles/search?sort=" .. url_encode(sort)
                 .. "&page=" .. tostring(page)
                 .. "&limit=24"

  if status ~= "all" and status ~= "" then
    apiUrl = apiUrl .. "&status=" .. url_encode(status)
  end

  if genreStr ~= "" then
    apiUrl = apiUrl .. "&genres=" .. url_encode(genreStr)
  end

  local r = http_get(apiUrl)
  if not r.success then
    -- Запасной вариант: веб-страница /search
    local fallbackUrl = baseUrl .. "/search?sort=" .. url_encode(sort)
                        .. "&page=" .. tostring(page)
    if status ~= "all" and status ~= "" then
      fallbackUrl = fallbackUrl .. "&status=" .. url_encode(status)
    end
    if genreStr ~= "" then
      fallbackUrl = fallbackUrl .. "&genres=" .. url_encode(genreStr)
    end
    r = http_get(fallbackUrl)
    if not r.success then return { items = {}, hasNext = false } end

    local data = extractNextData(r.body)
    if not data then return { items = {}, hasNext = false } end
    local pp       = data.props and data.props.pageProps
    local rawItems = pp and (pp.items or pp.mangas) or {}
    local items    = {}
    for _, novel in ipairs(rawItems) do
      local bookUrl = absUrl(novel.url or ("/" .. (novel.slug or "")))
      if bookUrl ~= "" and (novel.name or "") ~= "" then
        table.insert(items, {
          title = novel.name,
          url   = bookUrl,
          cover = novel.cover or ""
        })
      end
    end
    local pagination = pp and pp.pagination or {}
    return { items = items, hasNext = pagination.has_next or (#items > 0) }
  end

  local data = json_decode(r.body)
  if not data then return { items = {}, hasNext = false } end

  local inner    = data.data or {}
  local rawItems = inner.items or data.items or data.results or {}
  local items    = {}
  for _, novel in ipairs(rawItems) do
    local slug    = novel.slug or ""
    local bookUrl = absUrl("/" .. slug)
    local cover   = novel.cover or
                    ("https://static.novelbuddy.com/thumb/" .. slug .. ".png")
    local title   = novel.name or novel.title or ""
    if slug ~= "" and title ~= "" then
      table.insert(items, { title = title, url = bookUrl, cover = cover })
    end
  end

  local pagination = inner.pagination or data.pagination or data.meta or {}
  local hasNext    = pagination.has_next
  if hasNext == nil then hasNext = #items >= 24 end

  return { items = items, hasNext = hasNext }
end