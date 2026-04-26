-- -- Метаданные ----------------------------------------------------------------
id       = "novelbuddy"
name     = "NovelBuddy"
version  = "2.6.8"
baseUrl  = "https://novelbuddy.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbuddy.png"

-- Весь контент грузим через API, сайт не трогаем вообще

-- -- Константы -----------------------------------------------------------------

local API_BASE = "https://api.novelbuddy.com/"

-- -- Хелперы -------------------------------------------------------------------

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

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
  text = regex_replace(text, "(?i)Find authorized novels in Webnovel.*?Please click www\\.webnovel\\.com for visiting\\.", "")
  text = regex_replace(text, "(?i)free.{0,10}novel\\.com", "")
  text = string_trim(text)
  return text
end

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

local function removeChapterTitleDuplicate(text, chapterName)
  if not text or text == "" or not chapterName or chapterName == "" then return text end

  local nameClean = chapterName:match("^%s*(.-)%s*$"):lower()

  local changed = true
  while changed do
    changed = false
    local before, firstLine, after = text:match("^(%s*)([^\n]+)(\n?.*)$")
    if not firstLine then break end
    local lineClean = firstLine:match("^%s*(.-)%s*$"):lower()
    if lineClean == nameClean
      or nameClean:find(lineClean, 1, true)
      or lineClean:find(nameClean, 1, true) then
      text = after or ""
      changed = true
    end
  end

  return string_trim(text)
end

local function slugFromUrl(bookUrl)
  local path = bookUrl:match("^[^?#]+") or bookUrl
  return path:match("/([^/]+)$") or ""
end

local function resolveGenreStr(genres)
  if not genres then return "" end
  if type(genres) == "string" then return genres end
  if type(genres) == "table" then return table.concat(genres, ",") end
  return ""
end

-- -- API запросы ---------------------------------------------------------------

local function apiGet(path)
  local fullUrl = API_BASE .. path
  local r = http_get(fullUrl)
  if not r or not r.success then
    log_error("NovelBuddy: API GET failed: " .. fullUrl)
    return nil
  end
  local data = json_parse(r.body)
  if not data then
    log_error("NovelBuddy: JSON parse failed for: " .. fullUrl)
    return nil
  end
  return data
end

-- Поиск по slug, возвращает первый элемент или nil
-- Обрезаем slug до первых 4 сегментов чтобы не получить 400 от API
local function searchBySlug(slug)
  if not slug or slug == "" then return nil end
  local parts = {}
  for part in slug:gmatch("[^-]+") do
    table.insert(parts, part)
    if #parts >= 4 then break end
  end
  local shortSlug = table.concat(parts, "-")
  log_info("NovelBuddy: searchBySlug slug=" .. slug .. " shortSlug=" .. shortSlug)
  local data = apiGet("titles/search?q=" .. url_encode(shortSlug) .. "&limit=1")
  if not data then return nil end
  local items = (data.data and data.data.items) or data.items or {}
  if #items == 0 then return nil end
  return items[1]
end

-- Детальная инфо по ID книги
local function fetchDetailById(mangaId, fallback)
  local data = apiGet("titles/" .. url_encode(mangaId))
  if data and data.data then
    local full = data.data
    full.id         = full.id         or mangaId
    full.slug       = full.slug       or (fallback and fallback.slug) or ""
    full.name       = full.name       or (fallback and fallback.name)
    full.cover      = full.cover      or (fallback and fallback.cover)
    full.summary    = full.summary    or full.description or ""
    full.genres     = full.genres     or {}
    full.stats      = full.stats      or (fallback and fallback.stats) or {}
    full.updated_at = full.updated_at or (fallback and fallback.updated_at)
    return full
  end
  if fallback then
    return {
      id         = mangaId,
      slug       = fallback.slug or "",
      name       = fallback.name,
      cover      = fallback.cover,
      summary    = fallback.description or fallback.summary or "",
      genres     = fallback.genres or {},
      stats      = fallback.stats or {},
      updated_at = fallback.updated_at,
    }
  end
  return nil
end

-- Получить ID и slug книги по её URL
local function resolveMangaId(bookUrl)
  local slug = slugFromUrl(bookUrl)
  local item = searchBySlug(slug)
  if item and item.id then
    return item.id, item.slug or slug
  end
  return nil, slug
end

-- Получить полные данные книги
local function fetchBookData(bookUrl)
  local slug = slugFromUrl(bookUrl)
  local item = searchBySlug(slug)
  if not item or not item.id then return nil end
  return fetchDetailById(item.id, item)
end

-- -- Каталог -------------------------------------------------------------------

function getCatalogList(index, filters)
  local page    = index + 1
  local sort    = ""
  local status  = ""
  local genres  = ""
  local exclude = ""
  local min_ch  = ""
  local max_ch  = ""

  if type(filters) == "table" then
    sort    = filters["sort"]              or ""
    status  = filters["status"]            or ""
    genres  = resolveGenreStr(filters["genre_included"])
    exclude = resolveGenreStr(filters["exclude_included"])
    min_ch  = filters["min_ch"]            or ""
    max_ch  = filters["max_ch"]            or ""
  end

  local params = "page=" .. tostring(page) .. "&limit=24"

  if sort ~= "" then
    params = params .. "&sort=" .. url_encode(sort)
  end
  if status ~= "" and status ~= "all" then
    params = params .. "&status=" .. url_encode(status)
  end
  if genres ~= "" then
    params = params .. "&genres=" .. genres
  end
  if exclude ~= "" then
    params = params .. "&exclude_genres=" .. exclude
  end
  if min_ch ~= "" then
    params = params .. "&min_ch=" .. url_encode(tostring(min_ch))
  end
  if max_ch ~= "" then
    params = params .. "&max_ch=" .. url_encode(tostring(max_ch))
  end

  local data = apiGet("titles/search?" .. params)
  if not data then return { items = {}, hasNext = false } end

  local inner    = (data.data) or {}
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
  local hasNext    = pagination.has_next
  if hasNext == nil then hasNext = (#items >= 24) end

  return { items = items, hasNext = hasNext }
end

-- -- Поиск ---------------------------------------------------------------------

function getCatalogSearch(index, query)
  local page = index + 1
  local data = apiGet("titles/search?q=" .. url_encode(query)
                      .. "&page=" .. tostring(page) .. "&limit=24")
  if not data then return { items = {}, hasNext = false } end

  local inner    = data.data or {}
  local rawItems = inner.items or {}
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

  local pagination = inner.pagination or {}
  local hasNext    = pagination.has_next
  if hasNext == nil then hasNext = (#items >= 24) end

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
  if manga then return resolveCover(manga.cover, manga.slug) end
  return nil
end

function getBookDescription(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local summary = manga.summary or manga.description or ""
  if summary ~= "" then
    summary = summary:gsub("<[^>]+>", "")
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
    local gname = type(g) == "string" and g or (g.name or "")
    if gname ~= "" and not seen[gname] then
      seen[gname] = true
      table.insert(genres, gname)
    end
  end
  return genres
end

-- -- Список глав ---------------------------------------------------------------

function getChapterList(bookUrl)
  local mangaId, mangaSlug = resolveMangaId(bookUrl)
  if not mangaId then
    log_error("NovelBuddy: manga id not found for " .. tostring(bookUrl))
    return {}
  end

  local data = apiGet("titles/" .. url_encode(mangaId) .. "/chapters")
  if not data then
    log_error("NovelBuddy: chapters API failed for id=" .. tostring(mangaId))
    return {}
  end

  local inner       = data.data or {}
  local rawChapters = inner.items or inner.chapters or {}
  local allChapters = {}

  for _, ch in ipairs(rawChapters) do
    local chId  = tostring(ch.id or "")
    local title = ch.name or ch.title or ch.slug or chId

    if chId ~= "" then
      local chApiUrl = API_BASE .. "titles/" .. url_encode(mangaId)
                       .. "/chapters/" .. url_encode(chId)
      table.insert(allChapters, {
        title = string_clean(title),
        url   = chApiUrl,
      })
    end
  end

  local reversed = {}
  for i = #allChapters, 1, -1 do
    table.insert(reversed, allChapters[i])
  end
  return reversed
end

-- -- Хэш для проверки обновлений -----------------------------------------------

function getChapterListHash(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local stats = manga.stats or {}
  local count = stats.chapters_count or stats.chaptersCount
  if count then return tostring(count) end
  return manga.updated_at or nil
end

-- -- Текст главы ---------------------------------------------------------------

function getChapterText(html, url)
  log_info("NovelBuddy: getChapterText called, url=" .. tostring(url))

  if not url or url == "" then
    log_error("NovelBuddy: empty url")
    return ""
  end

  log_info("NovelBuddy: fetching " .. url)
  local r = http_get(url)
  if not r or not r.success or not r.body or r.body == "" then
    log_error("NovelBuddy: HTTP failed, trying html body")
    -- fallback: парсим html который передало приложение
  else
    local ok, apiData = pcall(json_parse, r.body)
    if ok and apiData and apiData.data and apiData.data.chapter then
      local ch = apiData.data.chapter
      local content = ch.content or ch.text or ""
      log_info("NovelBuddy: content[:200]=" .. content:sub(1, 200))
      if content ~= "" then
        local text = html_text(content)
        text = text:gsub("\\n", "")
        text = text:gsub('\\"', '"')
        text = removeChapterTitleDuplicate(text, ch.name or "")
        text = applyStandardContentTransforms(text)
        return text
      end
    end
  end

  -- fallback: html уже загружен приложением как Jsoup документ
  log_info("NovelBuddy: using html fallback")
  local text = html_text(html)
  text = text:gsub("\\n", "")
  text = text:gsub('\\"', '"')
  text = applyStandardContentTransforms(text)
  return text
end

-- -- Список фильтров -----------------------------------------------------------

function getFilterList()
  local genreOptions = {
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
    { value = "thriller",         label = "Thriller"         },
    { value = "tragedy",          label = "Tragedy"          },
    { value = "urban",            label = "Urban"            },
    { value = "urban-life",       label = "Urban Life"       },
    { value = "wuxia",            label = "Wuxia"            },
    { value = "xianxia",          label = "Xianxia"          },
    { value = "xuanhuan",         label = "Xuanhuan"         },
    { value = "yaoi",             label = "Yaoi"             },
    { value = "yuri",             label = "Yuri"             },
  }

  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Order by",
      defaultValue = "",
      options = {
        { value = "",             label = "Default"        },
        { value = "views",        label = "Most Viewed"    },
        { value = "latest",       label = "Latest Update"  },
        { value = "popular",      label = "Popular"        },
        { value = "alphabetical", label = "A-Z"            },
        { value = "rating",       label = "Rating"         },
        { value = "chapters",     label = "Most Chapters"  },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",          label = "All"       },
        { value = "ongoing",   label = "Ongoing"   },
        { value = "completed", label = "Completed" },
        { value = "hiatus",    label = "Hiatus"    },
        { value = "cancelled", label = "Cancelled" },
      }
    },
    {
      type         = "select",
      key          = "min_ch",
      label        = "Minimum Chapters",
      defaultValue = "",
      options = {
        { value = "",     label = "Any"   },
        { value = "1",    label = "1+"    },
        { value = "50",   label = "50+"   },
        { value = "100",  label = "100+"  },
        { value = "200",  label = "200+"  },
        { value = "500",  label = "500+"  },
        { value = "1000", label = "1000+" },
        { value = "2000", label = "2000+" },
      }
    },
    {
      type         = "select",
      key          = "max_ch",
      label        = "Maximum Chapters",
      defaultValue = "",
      options = {
        { value = "",     label = "Any"    },
        { value = "50",   label = "≤ 50"   },
        { value = "100",  label = "≤ 100"  },
        { value = "200",  label = "≤ 200"  },
        { value = "500",  label = "≤ 500"  },
        { value = "1000", label = "≤ 1000" },
        { value = "2000", label = "≤ 2000" },
      }
    },
    {
      type    = "checkbox",
      key     = "genre",
      label   = "Genres (include)",
      options = genreOptions,
    },
    {
      type    = "checkbox",
      key     = "exclude",
      label   = "Genres (exclude)",
      options = genreOptions,
    },
  }
end

-- -- Каталог с фильтрами (делегируем в getCatalogList) ------------------------

function getCatalogFiltered(index, filters)
  return getCatalogList(index, filters)
end