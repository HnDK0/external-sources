-- -- Метаданные ----------------------------------------------------------------
id       = "novelbuddy"
name     = "NovelBuddy"
version  = "2.4.0"
baseUrl  = "https://novelbuddy.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbuddy.png"

-- CF/Turnstile всегда на сайте — НЕ включаем обход CF (disable_cloudflare_detection = true уже убрано)
-- Весь контент грузим через API, сайт не трогаем вообще

-- -- Хелперы -------------------------------------------------------------------

local API_BASE = "https://api.novelbuddy.com/"

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
  -- Убираем вотермарки Webnovel / freewebnovel
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

local function stripHtml(content)
  if not content or content == "" then return "" end
  content = regex_replace(content, "<p[^>]*>", "\n")
  content = regex_replace(content, "</p>", "")
  content = regex_replace(content, "<br[^>]*>", "\n")
  content = regex_replace(content, "<[^>]+>", "")
  content = decodeHtmlEntities(content)
  content = regex_replace(content, "\n\n\n+", "\n\n")
  content = regex_replace(content, "(?m)^[ \t]+", "")
  return string_trim(content)
end

local function slugFromUrl(bookUrl)
  return bookUrl:match("/([^/]+)$") or ""
end

local function resolveGenreStr(genres)
  if not genres then return "" end
  if type(genres) == "string" then return genres end
  if type(genres) == "table" then return table.concat(genres, ",") end
  return ""
end

-- -- API запросы ---------------------------------------------------------------

local function apiGet(path)
  local url = API_BASE .. path
  local r = http_get(url)
  if not r.success then
    log_error("NovelBuddy: API GET failed: " .. url)
    return nil
  end
  local data = json_parse(r.body)
  if not data then
    log_error("NovelBuddy: JSON parse failed for: " .. url)
    return nil
  end
  return data
end

local function searchBySlug(slug)
  if slug == "" then return nil end
  local data = apiGet("titles/search?q=" .. url_encode(slug) .. "&limit=1")
  if not data then return nil end
  local items = (data.data and data.data.items) or data.items or {}
  if #items == 0 or not items[1].id then return nil end
  return items[1]
end

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
    full.updatedAt  = full.updatedAt  or full.updated_at
    return full
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

local function resolveMangaId(bookUrl)
  local slug = slugFromUrl(bookUrl)
  local item = searchBySlug(slug)
  if item then
    return item.id, item.slug or slug
  end
  return nil, slug
end

local function fetchBookData(bookUrl)
  local slug = slugFromUrl(bookUrl)
  local item = searchBySlug(slug)
  if not item then return nil end
  return fetchDetailById(item.id, item)
end

-- -- Каталог -------------------------------------------------------------------

function getCatalogList(index, filters)
  local page   = index + 1
  local sort   = "popular"
  local status = "all"
  local genres = ""
  local exclude = ""
  local min_ch = ""
  local max_ch = ""

  if type(filters) == "table" then
    sort    = filters["sort"]    or sort
    status  = filters["status"]  or status
    genres  = resolveGenreStr(filters["genre"])
    exclude = resolveGenreStr(filters["exclude"])
    min_ch  = filters["min_ch"]  or ""
    max_ch  = filters["max_ch"]  or ""
  end

  local apiUrl = "titles/search?sort=" .. url_encode(sort)
                 .. "&page=" .. tostring(page) .. "&limit=24"

  if status ~= "all" and status ~= "" then
    apiUrl = apiUrl .. "&status=" .. url_encode(status)
  end
  if genres ~= "" then
    apiUrl = apiUrl .. "&genres=" .. genres
  end
  if exclude ~= "" then
    apiUrl = apiUrl .. "&exclude=" .. exclude
  end
  if min_ch ~= "" then
    apiUrl = apiUrl .. "&min_ch=" .. url_encode(min_ch)
  end
  if max_ch ~= "" then
    apiUrl = apiUrl .. "&max_ch=" .. url_encode(max_ch)
  end

  local data = apiGet(apiUrl)
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
  local page = index + 1
  local data = apiGet("titles/search?q=" .. url_encode(query)
                      .. "&page=" .. tostring(page) .. "&limit=24")
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
  if manga then return resolveCover(manga.cover, manga.slug) end
  return nil
end

function getBookDescription(bookUrl)
  local manga = fetchBookData(bookUrl)
  if not manga then return nil end
  local summary = manga.summary or manga.description or ""
  if summary ~= "" then
    summary = regex_replace(summary, "<[^>]+>", "")
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
-- URL главы = API endpoint напрямую, без хаков через #api=
-- Формат: https://api.novelbuddy.com/titles/{mangaId}/chapters/{chapterId}
-- В поле url мы сохраняем этот API URL, в поле title — название главы

function getChapterList(bookUrl)
  local mangaId, mangaSlug = resolveMangaId(bookUrl)

  if not mangaId then
    log_error("NovelBuddy: manga id not found for " .. bookUrl)
    return {}
  end

  local chaptersData = apiGet("titles/" .. url_encode(mangaId) .. "/chapters")
  local rawChapters = {}

  if chaptersData then
    if chaptersData.success ~= false then
      rawChapters = (chaptersData.data and chaptersData.data.chapters) or chaptersData.chapters or {}
    else
      log_error("NovelBuddy: chapters API success=false for id=" .. tostring(mangaId))
    end
  end

  -- Фолбэк: detail endpoint
  if #rawChapters == 0 then
    log_error("NovelBuddy: chapters empty, trying detail for id=" .. tostring(mangaId))
    local detail = apiGet("titles/" .. url_encode(mangaId))
    if detail and detail.data then
      rawChapters = detail.data.chapters or {}
    end
  end

  local chapters = {}
  for _, ch in ipairs(rawChapters) do
    local chId   = tostring(ch.id or "")
    local chSlug = ch.slug or chId
    local title  = ch.name or ch.title or chSlug

    -- URL = прямой API endpoint для загрузки контента главы
    -- НЕ используем URL сайта — там CF/Turnstile блокирует
    local chApiUrl = ""
    if chId ~= "" then
      chApiUrl = API_BASE .. "titles/" .. url_encode(mangaId) .. "/chapters/" .. url_encode(chId)
    elseif chSlug ~= "" then
      chApiUrl = API_BASE .. "titles/" .. url_encode(mangaId) .. "/chapters/" .. url_encode(chSlug)
    end

    if chApiUrl ~= "" then
      table.insert(chapters, {
        title = string_clean(title),
        url   = chApiUrl,
      })
    end
  end

  -- API возвращает главы от новых к старым — переворачиваем
  local reversed = {}
  for i = #chapters, 1, -1 do
    table.insert(reversed, chapters[i])
  end
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
-- url — это API URL вида https://api.novelbuddy.com/titles/{id}/chapters/{id}
-- html — приложение может передать тело ответа или пустую строку
-- Мы всегда грузим через API URL напрямую

function getChapterText(html, url)
  -- Пробуем распарсить html как JSON ответ от API
  -- (некоторые приложения передают тело уже загруженного запроса)
  if html and html ~= "" then
    local ok, apiData = pcall(json_parse, html)
    if ok and type(apiData) == "table" then
      -- Структура: { success=true, data={ chapter={ content=... } } }
      local chapter = apiData.data and apiData.data.chapter
      if chapter then
        local content = chapter.content or chapter.text or ""
        if content ~= "" then
          content = stripHtml(content)
          return applyStandardContentTransforms(content)
        end
      end
      -- Альтернативная структура: { data={ content=... } }
      if apiData.data and type(apiData.data.content) == "string" and apiData.data.content ~= "" then
        local content = stripHtml(apiData.data.content)
        return applyStandardContentTransforms(content)
      end
    end
  end

  -- Грузим через API URL напрямую
  -- url уже является API endpoint — https://api.novelbuddy.com/titles/.../chapters/...
  if url and url ~= "" then
    -- Убираем якорь если вдруг попал
    local cleanUrl = url:match("^([^#]+)") or url

    local r = http_get(cleanUrl)
    if r.success then
      local apiData = json_parse(r.body)
      if apiData then
        -- Структура: { success=true, data={ chapter={ content=... } } }
        local chapter = apiData.data and apiData.data.chapter
        if chapter then
          local content = chapter.content or chapter.text or ""
          if content ~= "" then
            content = stripHtml(content)
            return applyStandardContentTransforms(content)
          end
        end
        -- Альтернативная структура: { data={ content=... } }
        if apiData.data and type(apiData.data.content) == "string" and apiData.data.content ~= "" then
          local content = stripHtml(apiData.data.content)
          return applyStandardContentTransforms(content)
        end
        -- Структура без обёртки: { content=... }
        if type(apiData.content) == "string" and apiData.content ~= "" then
          local content = stripHtml(apiData.content)
          return applyStandardContentTransforms(content)
        end
      end
      log_error("NovelBuddy: unexpected API response structure for " .. cleanUrl
                .. " | body[:200]=" .. (r.body or ""):sub(1, 200))
    else
      log_error("NovelBuddy: chapter API HTTP failed for " .. cleanUrl)
    end
  end

  log_error("NovelBuddy: getChapterText failed, url=" .. tostring(url))
  return ""
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
        { value = "",            label = "Default"       },
        { value = "views",       label = "Most Viewed"   },
        { value = "latest",      label = "Latest Update" },
        { value = "popular",     label = "Popular"       },
        { value = "alphabetical",label = "A-Z"           },
        { value = "rating",      label = "Rating"        },
        { value = "chapters",    label = "Most Chapters" },
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
        { value = "hiatus",    label = "Hiatus"    },
        { value = "cancelled", label = "Cancelled" },
      }
    },
    {
      type  = "text",
      key   = "min_ch",
      label = "Minimum Chapters",
    },
    {
      type  = "text",
      key   = "max_ch",
      label = "Maximum Chapters",
    },
    -- Жанры Include
    {
      type  = "checkbox",
      key   = "genre",
      label = "Genres (include)",
      options = {
        { value = "action",            label = "Action"            },
        { value = "action-adventure",  label = "Action Adventure"  },
        { value = "adult",             label = "Adult"             },
        { value = "adventure",         label = "Adventure"         },
        { value = "comedy",            label = "Comedy"            },
        { value = "cultivation",       label = "Cultivation"       },
        { value = "drama",             label = "Drama"             },
        { value = "eastern",           label = "Eastern"           },
        { value = "ecchi",             label = "Ecchi"             },
        { value = "fan-fiction",       label = "Fan Fiction"       },
        { value = "fantasy",           label = "Fantasy"           },
        { value = "game",              label = "Game"              },
        { value = "gender-bender",     label = "Gender Bender"     },
        { value = "harem",             label = "Harem"             },
        { value = "historical",        label = "Historical"        },
        { value = "horror",            label = "Horror"            },
        { value = "isekai",            label = "Isekai"            },
        { value = "josei",             label = "Josei"             },
        { value = "light-novel",       label = "Light Novel"       },
        { value = "litrpg",            label = "LitRPG"            },
        { value = "lolicon",           label = "Lolicon"           },
        { value = "magic",             label = "Magic"             },
        { value = "martial-arts",      label = "Martial Arts"      },
        { value = "mature",            label = "Mature"            },
        { value = "mecha",             label = "Mecha"             },
        { value = "military",          label = "Military"          },
        { value = "modern-life",       label = "Modern Life"       },
        { value = "mystery",           label = "Mystery"           },
        { value = "psychological",     label = "Psychological"     },
        { value = "reincarnation",     label = "Reincarnation"     },
        { value = "romance",           label = "Romance"           },
        { value = "school-life",       label = "School Life"       },
        { value = "sci-fi",            label = "Sci-fi"            },
        { value = "seinen",            label = "Seinen"            },
        { value = "shoujo",            label = "Shoujo"            },
        { value = "shoujo-ai",         label = "Shoujo Ai"         },
        { value = "shounen",           label = "Shounen"           },
        { value = "shounen-ai",        label = "Shounen Ai"        },
        { value = "slice-of-life",     label = "Slice of Life"     },
        { value = "smut",              label = "Smut"              },
        { value = "sports",            label = "Sports"            },
        { value = "supernatural",      label = "Supernatural"      },
        { value = "system",            label = "System"            },
        { value = "thriller",          label = "Thriller"          },
        { value = "tragedy",           label = "Tragedy"           },
        { value = "urban",             label = "Urban"             },
        { value = "urban-life",        label = "Urban Life"        },
        { value = "wuxia",             label = "Wuxia"             },
        { value = "xianxia",           label = "Xianxia"           },
        { value = "xuanhuan",          label = "Xuanhuan"          },
        { value = "yaoi",              label = "Yaoi"              },
        { value = "yuri",              label = "Yuri"              },
      }
    },
    -- Жанры Exclude
    {
      type  = "checkbox",
      key   = "exclude",
      label = "Genres (exclude)",
      options = {
        { value = "action",            label = "Action"            },
        { value = "action-adventure",  label = "Action Adventure"  },
        { value = "adult",             label = "Adult"             },
        { value = "adventure",         label = "Adventure"         },
        { value = "comedy",            label = "Comedy"            },
        { value = "cultivation",       label = "Cultivation"       },
        { value = "drama",             label = "Drama"             },
        { value = "eastern",           label = "Eastern"           },
        { value = "ecchi",             label = "Ecchi"             },
        { value = "fan-fiction",       label = "Fan Fiction"       },
        { value = "fantasy",           label = "Fantasy"           },
        { value = "game",              label = "Game"              },
        { value = "gender-bender",     label = "Gender Bender"     },
        { value = "harem",             label = "Harem"             },
        { value = "historical",        label = "Historical"        },
        { value = "horror",            label = "Horror"            },
        { value = "isekai",            label = "Isekai"            },
        { value = "josei",             label = "Josei"             },
        { value = "light-novel",       label = "Light Novel"       },
        { value = "litrpg",            label = "LitRPG"            },
        { value = "lolicon",           label = "Lolicon"           },
        { value = "magic",             label = "Magic"             },
        { value = "martial-arts",      label = "Martial Arts"      },
        { value = "mature",            label = "Mature"            },
        { value = "mecha",             label = "Mecha"             },
        { value = "military",          label = "Military"          },
        { value = "modern-life",       label = "Modern Life"       },
        { value = "mystery",           label = "Mystery"           },
        { value = "psychological",     label = "Psychological"     },
        { value = "reincarnation",     label = "Reincarnation"     },
        { value = "romance",           label = "Romance"           },
        { value = "school-life",       label = "School Life"       },
        { value = "sci-fi",            label = "Sci-fi"            },
        { value = "seinen",            label = "Seinen"            },
        { value = "shoujo",            label = "Shoujo"            },
        { value = "shoujo-ai",         label = "Shoujo Ai"         },
        { value = "shounen",           label = "Shounen"           },
        { value = "shounen-ai",        label = "Shounen Ai"        },
        { value = "slice-of-life",     label = "Slice of Life"     },
        { value = "smut",              label = "Smut"              },
        { value = "sports",            label = "Sports"            },
        { value = "supernatural",      label = "Supernatural"      },
        { value = "system",            label = "System"            },
        { value = "thriller",          label = "Thriller"          },
        { value = "tragedy",           label = "Tragedy"           },
        { value = "urban",             label = "Urban"             },
        { value = "urban-life",        label = "Urban Life"        },
        { value = "wuxia",             label = "Wuxia"             },
        { value = "xianxia",           label = "Xianxia"           },
        { value = "xuanhuan",          label = "Xuanhuan"          },
        { value = "yaoi",              label = "Yaoi"              },
        { value = "yuri",              label = "Yuri"              },
      }
    },
  }
end

-- -- Каталог с фильтрами -------------------------------------------------------

function getCatalogFiltered(index, filters)
  -- Делегируем в getCatalogList — логика там одинаковая
  return getCatalogList(index, filters)
end