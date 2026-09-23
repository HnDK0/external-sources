id       = "freewebnovel"
name     = "FreeWebNovel"
version  = "1.1.0"
baseUrl  = "https://freewebnovel.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/freewebnovel.png"

local _pageCache = {}

local function fetchPage(url)
  if _pageCache[url] then return _pageCache[url] end
  local r = http_get(url)
  if r.success then
    _pageCache[url] = r.body
    return r.body
  end
  return nil
end

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
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

local function catalogUrl(basePath, page)
  if page <= 1 then
    return baseUrl .. "/" .. basePath
  end
  return baseUrl .. "/" .. basePath .. "/" .. tostring(page)
end

local function parseItems(html)
  local items = {}
  for _, row in ipairs(html_select(html, ".ul-list1 .li-row, .serach-result .li-row")) do
    local titleEl = html_select_first(row.html, ".tit a")
    if titleEl then
      local cover = absUrl(html_attr(row.html, ".pic img", "src"))
      -- Рейтинг из карточки (каталог, поиск, фильтры):
      -- <div class="core"><span>3.8</span></div>
      local ratingEl = html_select_first(row.html, ".core span")
      local rating = ratingEl and string_clean(ratingEl.text) or ""
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = cover,
        rating = rating
      })
    end
  end
  return items
end

function getCatalogList(index)
  local page = index + 1
  -- Latest Release — единственная сортировка без серверного лимита в 100
  -- результатов (most-popular и search-adv отдают максимум 100).
  local r = http_get(catalogUrl("sort/latest-release", page))
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "/search?keyword=" .. url_encode(query) .. "&page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.tit")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".pic img", "src")
  if not src or src == "" then
    src = html_attr(body, ".pic img", "data-src")
  end
  if not src or src == "" then
    src = html_attr(body, ".books img, .m-imgtxt img", "src")
  end
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".m-desc .txt")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, item in ipairs(html_select(body, ".m-imgtxt .txt .item")) do
    local span = html_select_first(item.html, "span[title='Genre']")
    if span then
      for _, a in ipairs(html_select(item.html, ".right a")) do
        local g = string_trim(a.text)
        if g ~= "" then table.insert(genres, g) end
      end
      break
    end
  end
  return genres
end

-- ── Статус / Дата обновления ──────────────────────────────────────────────

-- Статус книги из блока метаданных .m-imgtxt:
-- <div class="item"><span ... title="Status"></span>
--   <div class="right"><span class="s1 s2"><a ...>OnGoing</a></span></div></div>
function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  for _, item in ipairs(html_select(body, ".m-imgtxt .txt .item")) do
    local span = html_select_first(item.html, "span[title='Status']")
    if span then
      local a = html_select_first(item.html, ".right a")
      if a then return string_trim(a.text) end
      local s = html_select_first(item.html, ".right span")
      if s then return string_trim(s.text) end
      return nil
    end
  end
  return nil
end

-- Дата последнего обновления в блоке "6 Latest Chapters":
-- <span class="lastupdate">[ Updated 3 days ago ]</span>
-- Сайт отдаёт только относительную строку — приводим к YYYY-MM-DD.
local function normalizeUpdateDate(raw)
  if not raw or raw == "" then return nil end
  local n, unit = string.match(raw, "Updated%s+(%d+)%s+(%w+)%s+ago")
  if not n then return nil end
  local mult = {
    minute = 60, minutes = 60,
    hour = 3600, hours = 3600,
    day = 86400, days = 86400,
    week = 7 * 86400, weeks = 7 * 86400,
    month = 30 * 86400, months = 30 * 86400,
    year = 365 * 86400, years = 365 * 86400,
  }
  local secs = mult[unit]
  if not secs then return nil end
  return os.date("%Y-%m-%d", os.time() - n * secs)
end

function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".lastupdate")
  if not el then return nil end
  return normalizeUpdateDate(string_trim(el.text))
end

-- ── Rating ──────────────────────────────────────────────────────────────

-- Рейтинг книги со страницы книги: <p class="vote">3.8 / 5 ( 653 votes )</p>
-- внутри .score. Извлекаем голое число (шкала 0-5).
function getBookRating(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".score .vote")
  if not el then return nil end
  local n = string.match(string_clean(el.text), "%d+%.?%d*")
  return n or nil
end

local CHAPTERS_PAGE_SIZE = 200

local function fetchChapterPage(bookUrl, page)
  if page > 1 then
    sleep(math.random(150, 350))
  end
  local sep = bookUrl:find("?") and "&" or "?"
  local url = bookUrl .. sep .. "ajax=chapters&page=" .. tostring(page) .. "&pageSize=" .. tostring(CHAPTERS_PAGE_SIZE)
  local r = http_get(url, {
    headers = {
      ["X-Requested-With"] = "XMLHttpRequest",
      ["Accept"]           = "application/json, text/javascript, */*; q=0.01",
    }
  })
  if not r.success then
    log_error("freewebnovel: chapters ajax failed code=" .. tostring(r.code) .. " page=" .. tostring(page))
    return nil
  end
  local data = json_parse(r.body)
  if not data or not data.html then
    log_error("freewebnovel: json_parse failed or missing html, page=" .. tostring(page))
    return nil
  end
  return data
end

function parsePage(bookUrl, page)
  local data = fetchChapterPage(bookUrl, page)
  if not data then return { chapters = {}, totalPages = 1 } end
  local totalPages = tonumber(data.totalPage) or 1
  local chapters = {}
  for _, a in ipairs(html_select(data.html, "a[href]")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local title = a:attr("title")
      if not title or title == "" then title = string_clean(a.text) end
      table.insert(chapters, {
        title = string_clean(title),
        url   = chUrl
      })
    end
  end
  return { chapters = chapters, totalPages = totalPages }
end

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".advertisement", ".chapter-nav", ".nav-links", "h4", "sub")
  local el = html_select_first(cleaned, "div.txt")
  if not el then
    el = html_select_first(cleaned, "#chapter-content, #chr-content")
  end
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort",
      defaultValue = "popular",
      options = {
        { value = "popular",   label = "Most Popular"   },
        { value = "updated",   label = "Last Updated"   },
        { value = "rating",    label = "Highest Rated"  },
        { value = "collected", label = "Most Collected" },
        { value = "chapters",  label = "Most Chapters"  },
        { value = "title",     label = "Title A - Z"    },
      }
    },
    {
      type         = "select",
      key          = "genre_match",
      label        = "Genre Match",
      defaultValue = "all",
      options = {
        { value = "all",     label = "All selected"     },
        { value = "any",     label = "Any selected"     },
        { value = "exclude", label = "Exclude selected" },
      }
    },
    {
      type        = "checkbox",
      key         = "genre",
      label       = "Genre",
      multiselect = true,
      options = {
        { value = "Action",        label = "Action"        },
        { value = "Adult",         label = "Adult"         },
        { value = "Adventure",     label = "Adventure"     },
        { value = "Comedy",        label = "Comedy"        },
        { value = "Drama",         label = "Drama"         },
        { value = "Eastern",       label = "Eastern"       },
        { value = "Ecchi",         label = "Ecchi"         },
        { value = "Fan-fic",       label = "Fan-fic"       },
        { value = "Fantasy",       label = "Fantasy"       },
        { value = "Game",          label = "Game"          },
        { value = "Gender Bender", label = "Gender Bender" },
        { value = "Harem",         label = "Harem"         },
        { value = "Historical",    label = "Historical"    },
        { value = "Horror",        label = "Horror"        },
        { value = "Josei",         label = "Josei"         },
        { value = "Martial Arts",  label = "Martial Arts"  },
        { value = "Mature",        label = "Mature"        },
        { value = "Mecha",         label = "Mecha"         },
        { value = "Mystery",       label = "Mystery"       },
        { value = "Psychological", label = "Psychological" },
        { value = "Reincarnation", label = "Reincarnation" },
        { value = "Romance",       label = "Romance"       },
        { value = "School Life",   label = "School Life"   },
        { value = "Sci-fi",        label = "Sci-fi"        },
        { value = "Seinen",        label = "Seinen"        },
        { value = "Shoujo",        label = "Shoujo"        },
        { value = "Shounen Ai",    label = "Shounen Ai"    },
        { value = "Shounen",       label = "Shounen"       },
        { value = "Slice of Life", label = "Slice of Life" },
        { value = "Smut",          label = "Smut"          },
        { value = "Sports",        label = "Sports"        },
        { value = "Supernatural",  label = "Supernatural"  },
        { value = "System",        label = "System"        },
        { value = "Tragedy",       label = "Tragedy"       },
        { value = "Wuxia",         label = "Wuxia"         },
        { value = "Xianxia",       label = "Xianxia"       },
        { value = "Xuanhuan",      label = "Xuanhuan"      },
        { value = "Yaoi",          label = "Yaoi"          },
      }
    },
    {
      type         = "select",
      key          = "content_rating",
      label        = "Content Rating",
      defaultValue = "",
      options = {
        { value = "",            label = "All"                    },
        { value = "general",     label = "General Audiences"      },
        { value = "guidance",    label = "Parental Guidance"      },
        { value = "suggestive",  label = "Suggestive Content"     },
        { value = "adults-only", label = "Explicit Content (18+)" },
      }
    },
    {
      type         = "select",
      key          = "last_updated",
      label        = "Last Updated",
      defaultValue = "",
      options = {
        { value = "",         label = "Any time"        },
        { value = "24-hours", label = "Within 24 hours" },
        { value = "7-days",   label = "Within 7 days"   },
        { value = "30-days",  label = "Within 30 days"  },
        { value = "3-months", label = "Within 3 months" },
      }
    },
    {
      type         = "select",
      key          = "chapters",
      label        = "Chapters",
      defaultValue = "",
      options = {
        { value = "",          label = "All"       },
        { value = "under-50",  label = "< 50"      },
        { value = "50-100",    label = "50 - 100"  },
        { value = "100-200",   label = "100 - 200" },
        { value = "200-500",   label = "200 - 500" },
        { value = "500-1000",  label = "500 - 1000"},
        { value = "over-1000", label = "> 1000"    },
      }
    },
    {
      type         = "select",
      key          = "rating",
      label        = "Rating",
      defaultValue = "",
      options = {
        { value = "",    label = "Any Rating" },
        { value = "3",   label = "3+ Stars"   },
        { value = "4",   label = "4+ Stars"   },
        { value = "4.5", label = "4.5+ Stars" },
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
      }
    },
    {
      type        = "checkbox",
      key         = "language",
      label       = "Original Language",
      multiselect = true,
      options = {
        { value = "1", label = "Chinese Novel" },
        { value = "2", label = "Korean Novel"  },
        { value = "3", label = "Japanese Novel"},
        { value = "4", label = "English Novel" },
      }
    },
  }
end

function getCatalogFiltered(index, filters)
  local page  = index + 1
  local parts = { "genre_match=all" }

  local function addParam(key, val)
    if val and val ~= "" then
      parts[#parts + 1] = key .. "=" .. url_encode(val)
    end
  end

  -- Чекбоксы движок отдаёт в filters[key .. "_included"] (массив).
  local genres = filters["genre_included"] or filters["genre"] or {}
  if type(genres) == "string" then genres = { genres } end
  local gmatch = filters["genre_match"] or "all"

  -- Исключённые жанры (долгий тап в UI): сайт выражает это через genre_match=exclude.
  if #genres == 0 then
    local excl = filters["genre_excluded"] or {}
    if #excl > 0 then
      genres = excl
      gmatch = "exclude"
    end
  end

  parts[1] = "genre_match=" .. url_encode(gmatch)
  for _, g in ipairs(genres) do
    parts[#parts + 1] = "genre[]=" .. url_encode(g)
  end

  addParam("content_rating", filters["content_rating"])
  addParam("last_updated",   filters["last_updated"])
  addParam("chapters",       filters["chapters"])
  addParam("rating",         filters["rating"])
  addParam("status",         filters["status"])
  addParam("sort",           filters["sort"] or "popular")

  local langs = filters["language_included"] or filters["language"] or {}
  if type(langs) == "string" then langs = { langs } end
  for _, l in ipairs(langs) do
    parts[#parts + 1] = "language[]=" .. url_encode(l)
  end

  parts[#parts + 1] = "apply=1"
  parts[#parts + 1] = "page=" .. tostring(page)

  local r = http_get(baseUrl .. "/search-adv?" .. table.concat(parts, "&"))
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseItems(r.body)
  return { items = items, hasNext = #items > 0 }
end
