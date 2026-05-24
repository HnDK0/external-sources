-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "allnovel"
name     = "AllNovel"
version  = "1.0.3"
baseUrl  = "https://allnovel.org/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/allnovel.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- novelBinCoverUrl: строим URL обложки из слага книги (src из каталога игнорируем)
local function transformCover(bookUrl)
  if not bookUrl or bookUrl == "" then return "" end
  local slug = string.match(bookUrl, "/([^/?#]+)%.html$") or string.match(bookUrl, "/([^/?#]+)/?$") or ""
  if slug == "" then return "" end
  return "https://images.novelbin.me/novel/" .. slug .. ".jpg"
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
  local page = index + 1
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
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h3.title")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local cover = transformCover(bookUrl)
  if cover ~= "" then return cover end
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".book img[src]")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".desc-text")
  if el then return string_trim(el.text) end
  return nil
end

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
  local r = http_get(bookUrl)
  if not r.success then return {} end
  local genres = {}
  for _, div in ipairs(html_select(r.body, ".info div")) do
    local h3 = html_select_first(div.html, "h3")
    if h3 and string_trim(h3.text) == "Genre:" then
      for _, a in ipairs(html_select(div.html, "a")) do
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
  local page   = index + 1
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
  return { items = items, hasNext = #items > 0 }
end
