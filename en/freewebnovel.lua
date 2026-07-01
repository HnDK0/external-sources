-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "freewebnovel"
name     = "FreeWebNovel"
version  = "1.0.2"
baseUrl  = "https://freewebnovel.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/freewebnovel.png"

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

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "/completed-novel/" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".ul-list1 .li-row")) do
    local titleEl = html_select_first(row.html, ".tit a")
    local cover   = absUrl(html_attr(row.html, ".pic img", "src"))
    if titleEl then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = cover
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск (POST, одна страница) ───────────────────────────────────────────────

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local r = http_post(
    baseUrl .. "/search",
    "searchkey=" .. url_encode(query),
    {
      headers = {
        ["Content-Type"]           = "application/x-www-form-urlencoded",
        ["Referer"]                = baseUrl .. "/",
        ["Accept"]                 = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        ["Accept-Language"]        = "en-US,en;q=0.5",
        ["Accept-Encoding"]        = "gzip, deflate",
        ["Connection"]             = "keep-alive",
        ["Upgrade-Insecure-Requests"] = "1",
        ["Cache-Control"]          = "max-age=0"
      }
    }
  )
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".serach-result .li-row, .ul-list1 .li-row")) do
    local titleEl = html_select_first(row.html, ".tit a")
    local cover   = absUrl(html_attr(row.html, ".pic img", "src"))
    if titleEl then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = cover
      })
    end
  end

  return { items = items, hasNext = false }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1.tit")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".pic img")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".m-desc .txt")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав через AJAX-пагинацию ──────────────────────────────────────────
-- Сайт отдаёт главы порциями по 200 шт: ?ajax=chapters&page=N&pageSize=200
-- Страница 1 = самые старые главы (прямой порядок, как ожидает движок).

local CHAPTERS_PAGE_SIZE = 200

local function fetchChaptersAjax(bookUrl, page, pageSize)
  -- Небольшая случайная задержка перед каждым ajax-запросом глав:
  -- не даём Cloudflare заметить равномерный "ботовский" поток запросов.
  -- Первую страницу не тормозим — она обычно единственная, что нужна сразу.
  -- Диапазон как в гайде для агрессивно блокирующих сайтов (см. jaomix).
  if page > 1 then
    sleep(math.random(150, 350))
  end

  local sep = bookUrl:find("?") and "&" or "?"
  local url = bookUrl .. sep .. "ajax=chapters&page=" .. tostring(page) .. "&pageSize=" .. tostring(pageSize)

  local r = http_get(url, {
    headers = {
      ["X-Requested-With"] = "XMLHttpRequest",
      ["Accept"]           = "application/json, text/javascript, */*; q=0.01",
    }
  })
  if not r.success then
    -- Если это 429/CF-челлендж — приложение само поднимет вебвью для
    -- ручного/автоматического прохождения на уровне сети, retry здесь не нужен.
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

local function extractChaptersFromHtml(html)
  local chapters = {}
  if not html or html == "" then return chapters end
  for _, a in ipairs(html_select(html, "a[href]")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      -- title берётся из атрибута title, не из текста
      local title = a:attr("title")
      if not title or title == "" then title = string_clean(a.text) end
      table.insert(chapters, {
        title = string_clean(title),
        url   = chUrl
      })
    end
  end
  return chapters
end

-- ── Пагинированный список глав ────────────────────────────────────────────────

function parsePage(bookUrl, page)
  local data = fetchChaptersAjax(bookUrl, page, CHAPTERS_PAGE_SIZE)
  if not data then return { chapters = {}, totalPages = 1 } end

  local totalPages = tonumber(data.totalPage) or 1
  local chapters = extractChaptersFromHtml(data.html)

  return { chapters = chapters, totalPages = totalPages }
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  local genres = {}
  for _, item in ipairs(html_select(r.body, ".m-imgtxt .txt .item")) do
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

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "type",
      label        = "Novel Listing",
      defaultValue = "sort/most-popular",
      options = {
        { value = "sort/most-popular",    label = "Most Popular"    },
        { value = "sort/latest-novel",    label = "Latest Novels"   },
        { value = "sort/latest-release",  label = "Latest Release"  },
        { value = "sort/completed-novel", label = "Completed Novel" },
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
        { value = "Eastern",       label = "Eastern"       },
        { value = "Ecchi",         label = "Ecchi"         },
        { value = "Fantasy",       label = "Fantasy"       },
        { value = "Game",          label = "Game"          },
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
  local page   = index + 1
  local ftype  = filters["type"] or "sort/most-popular"
  local genres = filters["genre_included"] or {}
  local genre  = genres[1] or ""

  local basePath = genre ~= "" and ("genre/" .. genre) or ftype
  local url = baseUrl .. "/" .. basePath .. "/" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, row in ipairs(html_select(r.body, ".ul-list1 .li-row")) do
    local titleEl = html_select_first(row.html, ".tit a")
    local cover   = absUrl(html_attr(row.html, ".pic img", "src"))
    if titleEl then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = cover
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".advertisement", "h4", "sub")
  local el = html_select_first(cleaned, "div.txt")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end