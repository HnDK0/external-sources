-- -- Метаданные ----------------------------------------------------------------
id       = "novelbuddy"
name     = "NovelBuddy"
version  = "2.3.0"
baseUrl  = "https://novelbuddy.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbuddy.png"

-- Отключаем ложное срабатывание CloudflareInterceptor
disable_cloudflare_detection = true

-- Добавляем обязательный заголовок Referer ко всем запросам
function onBeforeRequest(url)
  return {
    headers = {
      ["Referer"] = baseUrl
    }
  }
end

-- -- Хелперы -------------------------------------------------------------------

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Нормализует поле cover: может прийти как строка или как таблица { url = "..." }
local function resolveCover(raw, slug)
  local cover = ""
  if type(raw) == "table" then
    cover = raw.url or raw.src or ""
  elseif type(raw) == "string" then
    cover = raw
  end
  if cover == "" and slug and slug ~= "" then
    cover = "https://static.novelbuddy.com/thumb/" .. slug .. ".png"
  end
  return cover
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

-- Декодирует HTML entities в plain text
local function decodeHtmlEntities(text)
  if not text or text == "" then return "" end
  text = text:gsub("&amp;",  "&")
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&lt;",   "<")
  text = text:gsub("&gt;",   ">")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#(%d+);",  function(n) return string.char(tonumber(n)) end)
  text = text:gsub("&#x(%x+);", function(h) return string.char(tonumber(h, 16)) end)
  return text
end

-- Извлекает JSON из тега <script id="__NEXT_DATA__"> (string-based)
local function extractNextData(body)
  if not body then return nil end
  local startPos = body:find('<script id="__NEXT_DATA__" type="application/json">', 1, true)
  if not startPos then return nil end
  local contentStart = startPos + string.len('<script id="__NEXT_DATA__" type="application/json">')
  local endPos = body:find('</script>', contentStart, true)
  if not endPos then return nil end
  local jsonStr = body:sub(contentStart, endPos - 1)
  return json_parse(jsonStr)
end

-- Извлекает slug из URL книги
local function slugFromUrl(bookUrl)
  return bookUrl:match("/([^/]+)$") or ""
end

-- Ищет книгу через API поиска по slug
local function searchBySlug(slug)
  if slug == "" then return nil end
  local searchUrl = "https://api.novelbuddy.com/titles/search?q=" .. url_encode(slug) .. "&limit=1"
  local sr = http_get(searchUrl)
  if not sr.success then return nil end
  local sdata = json_parse(sr.body)
  if not sdata then return nil end
  local items = (sdata.data and sdata.data.items) or sdata.items or {}
  if #items == 0 or not items[1].id then return nil end
  return items[1]
end

-- Загружает полные данные книги по id через API
local function fetchDetailById(mangaId, fallback)
  local detailUrl = "https://api.novelbuddy.com/titles/" .. url_encode(mangaId)
  local dr = http_get(detailUrl)
  if dr.success then
    local ddata = json_parse(dr.body)
    if ddata and ddata.data then
      local full = ddata.data
      full.id      = full.id      or mangaId
      full.slug    = full.slug    or (fallback and fallback.slug) or ""
      full.name    = full.name    or (fallback and fallback.name)
      full.cover   = full.cover   or (fallback and fallback.cover)
      full.summary = full.summary or full.description or ""
      full.genres  = full.genres  or {}
      full.stats   = full.stats   or (fallback and fallback.stats) or {}
      full.updated_at = full.updated_at or (fallback and fallback.updated_at)
      full.updatedAt  = full.updatedAt  or full.updated_at
      return full
    end
  end
  if fallback then
    return {
      id         = mangaId,
      slug       = fallback.slug or "",
      name       = fallback.name,
      cover      = fallback.cover,
      summary    = fallback.description or "",
      genres     = {},
      stats      = fallback.stats or {},
      updated_at = fallback.updated_at,
      updatedAt  = fallback.updated_at,
    }
  end
  return nil
end

-- Возвращает mangaId и mangaSlug — только через API, без запросов к novelbuddy.com
local function resolveMangaId(bookUrl)
  local slug = slugFromUrl(bookUrl)
  local item = searchBySlug(slug)
  if item then
    return item.id, item.slug or slug
  end
  return nil, slug
end

-- Загружает данные книги — только через API, без запросов к novelbuddy.com
local function fetchBookData(bookUrl)
  local slug = slugFromUrl(bookUrl)
  local item = searchBySlug(slug)
  if not item then return nil end
  return fetchDetailById(item.id, item)
end

-- -- Каталог -------------------------------------------------------------------

function getCatalogList(index)
  local page   = index + 1
  local apiUrl = "https://api.novelbuddy.com/titles/search?sort=popular&page=" .. tostring(page) .. "&limit=24"

  local r = http_get(apiUrl)
  if not r.success then return { items = {}, hasNext = false } end

  local data = json_parse(r.body)
  if not data then return { items = {}, hasNext = false } end

  local inner    = data.data or {}
  local rawItems = inner.items or {}
  local items    = {}
  for _, novel in ipairs(rawItems) do
    local slug    = novel.slug or ""
    local bookUrl = absUrl("/" .. slug)
    local cover   = resolveCover(novel.cover, slug)
    local title   = novel.name or ""
    if slug ~= "" and title ~= "" then
      table.insert(items, { title = title, url = bookUrl, cover = cover })
    end
  end

  local pagination = inner.pagination or {}
  local hasNext = pagination.has_next
  if hasNext == nil then hasNext = #items >= 24 end

  return { items = items, hasNext = hasNext }
end

-- -- Поиск ---------------------------------------------------------------------

function getCatalogSearch(index, query)
  local page   = index + 1
  local apiUrl = "https://api.novelbuddy.com/titles/search?q=" .. url_encode(query)
                 .. "&page=" .. tostring(page) .. "&limit=24"

  local r = http_get(apiUrl)
  if not r.success then return { items = {}, hasNext = false } end

  local data = json_parse(r.body)
  if not data then return { items = {}, hasNext = false } end

  local inner    = data.data or {}
  local rawItems = inner.items or data.items or data.results or {}
  local items    = {}
  for _, novel in ipairs(rawItems) do
    local slug    = novel.slug or ""
    local bookUrl = absUrl("/" .. slug)
    local cover   = resolveCover(novel.cover, slug)
    local title   = novel.name or novel.title or ""
    if slug ~= "" and title ~= "" then
      table.insert(items, { title = title, url = bookUrl, cover = cover })
    end
  end

  local pagination = inner.pagination or data.pagination or data.meta or {}
  local hasNext = pagination.has_next
  if hasNext == nil then hasNext = #items >= 24 end

  return { items = items, hasNext = hasNext }
end

-- -- Детали книги --------------------------------------------------------------

function getBookTitle(bookUrl)
  local manga = fetchBookData(bookUrl)
  if manga then return manga.name end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local manga = fetchBookData(bookUrl)
  if manga then
    return resolveCover(manga.cover, manga.slug)
  end
  return nil
end

function getBookDescription(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local summary = manga.summary or manga.description or ""
  if summary ~= "" then
    -- Убираем HTML-теги
    summary = regex_replace(summary, "<[^>]+>", "")
    -- Декодируем HTML entities
    summary = decodeHtmlEntities(summary)
    return string_trim(summary)
  end
  return nil
end

function getBookGenres(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return {} end
  local genres = {}
  local seen   = {}
  for _, g in ipairs(manga.genres or {}) do
    local name = type(g) == "string" and g or (g.name or "")
    if name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(genres, name)
    end
  end
  return genres
end

-- -- Список глав ---------------------------------------------------------------

function getChapterList(bookUrl)
  local mangaId, mangaSlug = resolveMangaId(bookUrl)

  if not mangaId then
    log_error("NovelBuddy: manga id not found for " .. bookUrl)
    return {}
  end

  local chapters = {}

  local apiUrl = "https://api.novelbuddy.com/titles/" .. url_encode(mangaId) .. "/chapters"
  local ar = http_get(apiUrl)

  if ar.success then
    local apiData = json_parse(ar.body)
    if apiData then
      -- Проверяем флаг success (если явно false — пропускаем)
      if apiData.success ~= false then
        local rawChapters = (apiData.data and apiData.data.chapters) or apiData.chapters or {}
        for _, ch in ipairs(rawChapters) do
          -- ch.id — числовой/строковый id главы, ch.slug — читаемый slug
          -- API эндпоинт /chapters/{id} работает только с id, не slug
          local chId   = ch.id   or ""
          local chSlug = ch.slug or chId
          local chUrl  = ""
          if chId ~= "" then
            chUrl = "https://api.novelbuddy.com/titles/" .. url_encode(mangaId) .. "/chapters/" .. url_encode(chId)
          end
          local title = ch.name or ch.title or chSlug
          if chUrl ~= "" then
            table.insert(chapters, { title = string_clean(title), url = chUrl })
          end
        end
      else
        log_error("NovelBuddy: chapters API returned success=false for id=" .. tostring(mangaId))
      end
    end
  else
    log_error("NovelBuddy: chapters API request failed for id=" .. tostring(mangaId))
  end

  -- Фолбэк: запрашиваем детали книги через API и берём главы оттуда
  if #chapters == 0 then
    log_error("NovelBuddy: chapters API empty, trying detail endpoint for id=" .. tostring(mangaId))
    local detailUrl = "https://api.novelbuddy.com/titles/" .. url_encode(mangaId)
    local dr = http_get(detailUrl)
    if dr.success then
      local ddata = json_parse(dr.body)
      local rawChapters = ddata and ddata.data and ddata.data.chapters or {}
      for _, ch in ipairs(rawChapters) do
        local chId   = ch.id   or ""
        local chSlug = ch.slug or chId
        local chUrl  = ""
        if chId ~= "" then
          chUrl = "https://api.novelbuddy.com/titles/" .. url_encode(mangaId) .. "/chapters/" .. url_encode(chId)
        end
        local title = ch.name or ch.title or chSlug
        if chUrl ~= "" then
          table.insert(chapters, { title = string_clean(title), url = chUrl })
        end
      end
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- -- Хэш для обновлений --------------------------------------------------------

function getChapterListHash(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local stats = manga.stats or {}
  local count = stats.chapters_count or stats.chaptersCount
  if count then return tostring(count) end
  return manga.updated_at or manga.updatedAt or nil
end

-- -- Текст главы ---------------------------------------------------------------

function getChapterText(html, url)
  -- Если URL указывает на API — загружаем контент главы напрямую через API
  if url and string_starts_with(url, "https://api.novelbuddy.com/") then
    local r = http_get(url)
    if r.success then
      local apiData = json_parse(r.body)
      if apiData then
        local ch = (apiData.data and apiData.data.chapter) or apiData.chapter or apiData.data or {}
        local content = ch.content or ch.text or ""
        if content ~= "" then
          return applyStandardContentTransforms(content)
        end
      end
    end
    log_error("NovelBuddy: chapter API failed for " .. url)
    return ""
  end

  -- Стандартный путь: HTML уже загружен приложением
  local data = extractNextData(html)
  if data then
    local pp = data.props and data.props.pageProps
    local chapter = pp and pp.initialChapter
    if chapter and chapter.content and chapter.content ~= "" then
      return applyStandardContentTransforms(chapter.content)
    end
  end

  local cleaned = html_remove(html, "script", "style",
    "#listen-chapter", "#google_translate_element", ".ads", ".advertisement",
    "[class*='ad-']", "[id*='ad-']")

  local el = html_select_first(cleaned, ".chapter-content")
  if not el then el = html_select_first(cleaned, "#chapter-content") end
  if not el then el = html_select_first(cleaned, ".content-inner") end
  if not el then el = html_select_first(cleaned, ".reading-content") end
  if not el then el = html_select_first(cleaned, "article") end
  if not el then return "" end

  return applyStandardContentTransforms(html_text(el.html))
end

-- -- Список фильтров -----------------------------------------------------------

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Order by",
      defaultValue = "popular",
      options = {
        { value = "popular",  label = "Popular"       },
        { value = "latest",   label = "Latest Update" },
        { value = "rating",   label = "Rating"        },
        { value = "views",    label = "Most Viewed"   },
        { value = "chapters", label = "Most Chapters" },
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
        { value = "action",           label = "Action"           },
        { value = "action-adventure", label = "Action Adventure" },
        { value = "adult",            label = "Adult"            },
        { value = "adventure",        label = "Adventure"        },
        { value = "comedy",           label = "Comedy"           },
        { value = "cultivation",      label = "Cultivation"      },
        { value = "drama",            label = "Drama"            },
        { value = "eastern",          label = "Eastern"          },
        { value = "ecchi",            label = "Ecchi"            },
        { value = "fan-fiction",      label = "Fan Fiction"      },
        { value = "fantasy",          label = "Fantasy"          },
        { value = "game",             label = "Game"             },
        { value = "gender-bender",    label = "Gender Bender"    },
        { value = "harem",            label = "Harem"            },
        { value = "historical",       label = "Historical"       },
        { value = "horror",           label = "Horror"           },
        { value = "isekai",           label = "Isekai"           },
        { value = "josei",            label = "Josei"            },
        { value = "light-novel",      label = "Light Novel"      },
        { value = "litrpg",           label = "LitRPG"           },
        { value = "lolicon",          label = "Lolicon"          },
        { value = "magic",            label = "Magic"            },
        { value = "martial-arts",     label = "Martial Arts"     },
        { value = "mature",           label = "Mature"           },
        { value = "mecha",            label = "Mecha"            },
        { value = "military",         label = "Military"         },
        { value = "modern-life",      label = "Modern Life"      },
        { value = "mystery",          label = "Mystery"          },
        { value = "psychological",    label = "Psychological"    },
        { value = "reincarnation",    label = "Reincarnation"    },
        { value = "romance",          label = "Romance"          },
        { value = "school-life",      label = "School Life"      },
        { value = "sci-fi",           label = "Sci-fi"           },
        { value = "seinen",           label = "Seinen"           },
        { value = "shoujo",           label = "Shoujo"           },
        { value = "shoujo-ai",        label = "Shoujo Ai"        },
        { value = "shounen",          label = "Shounen"          },
        { value = "shounen-ai",       label = "Shounen Ai"       },
        { value = "slice-of-life",    label = "Slice of Life"    },
        { value = "smut",             label = "Smut"             },
        { value = "sports",           label = "Sports"           },
        { value = "supernatural",     label = "Supernatural"     },
        { value = "system",           label = "System"           },
        { value = "tragedy",          label = "Tragedy"          },
        { value = "urban",            label = "Urban"            },
        { value = "urban-life",       label = "Urban Life"       },
        { value = "wuxia",            label = "Wuxia"            },
        { value = "xianxia",          label = "Xianxia"          },
        { value = "xuanhuan",         label = "Xuanhuan"         },
        { value = "yaoi",             label = "Yaoi"             },
        { value = "yuri",             label = "Yuri"             },
      }
    },
  }
end

-- -- Каталог с фильтрами -------------------------------------------------------

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local sort   = filters["sort"]   or "popular"
  local status = filters["status"] or "all"
  local genres = filters["genre"]  or {}

  local genreStr = table.concat(genres, ",")

  local apiUrl = "https://api.novelbuddy.com/titles/search?sort=" .. url_encode(sort)
                 .. "&page=" .. tostring(page)
                 .. "&limit=24"

  if status ~= "all" and status ~= "" then
    apiUrl = apiUrl .. "&status=" .. url_encode(status)
  end

  if genreStr ~= "" then
    apiUrl = apiUrl .. "&genres=" .. url_encode(genreStr)
  end

  local r = http_get(apiUrl)
  if not r.success then return { items = {}, hasNext = false } end

  local data = json_parse(r.body)
  if not data then return { items = {}, hasNext = false } end

  local inner    = data.data or {}
  local rawItems = inner.items or data.items or data.results or {}
  local items    = {}
  for _, novel in ipairs(rawItems) do
    local slug    = novel.slug or ""
    local bookUrl = absUrl("/" .. slug)
    local cover   = resolveCover(novel.cover, slug)
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