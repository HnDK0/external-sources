-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "indowebnovel"
name     = "Indowebnovel"
version  = "1.1.1"
baseUrl  = "https://indowebnovel.id/"
language = "id"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/indowebnovel.png"

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
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Bab\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Penerjemah|Editor|Proofreader|Baca\\s+(di|di+sini|novel|lanjutan)|Sumber|Donasi|Trakteer|Dukung\\s+kami)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?im)^\\s*(Sponsored|Advertisement|Ads)\\s*by[^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Кэш страницы книги (fetchPage) ────────────────────────────────────────────

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

-- ── Парсинг элементов каталога ────────────────────────────────────────────────

local function parseCatalogItems(body)
  local items = {}
  for _, el in ipairs(html_select(body, ".flexbox2-content")) do
    local a = html_select_first(el.html, "a[title]")
    if a then
      local bookUrl = absUrl(a.href)
      local title   = a.title
      if title == "" then
        local titleEl = html_select_first(a.html, ".flexbox2-title span:first-child")
        if titleEl then title = titleEl.text end
      end
      local cover   = html_attr(el.html, ".flexbox2-thumb img", "src")
      -- рейтинг в карточке каталога: <div class="score">4.4</div>
      local rEl = html_select_first(el.html, ".score")
      if bookUrl ~= "" and title ~= "" then
        table.insert(items, {
          title  = string_clean(title),
          url    = bookUrl,
          cover  = absUrl(cover),
          rating = rEl and string_clean(rEl.text) or nil
        })
      end
    end
  end
  return items
end

-- ── Формирование базового URL advanced-search ─────────────────────────────────

local function buildSearchUrl(params)
  local url = baseUrl .. "advanced-search/"
  local page = params.page or 1
  if page > 1 then
    url = url .. "page/" .. tostring(page) .. "/"
  end
  url = url .. "?title="
  url = url .. "&author="
  url = url .. "&yearx="
  url = url .. "&status=" .. url_encode(params.status or "")
  url = url .. "&type=" .. url_encode(params.typ or "")
  url = url .. "&order=" .. url_encode(params.order or "popular")
  -- страны (все 4 по умолчанию)
  local countries = params.countries or { "china", "jepang", "korea", "unknown" }
  for i, c in ipairs(countries) do
    url = url .. "&country%5B" .. tostring(i - 1) .. "%5D=" .. url_encode(c)
  end
  -- жанры
  for _, g in ipairs(params.genres or {}) do
    url = url .. "&genre%5B%5D=" .. url_encode(g)
  end
  return url
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = buildSearchUrl({ page = page })

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local url = buildSearchUrl({
    page  = page,
    title = query
  })
  -- переопределяем title в URL
  url = url:gsub("title=", "title=" .. url_encode(query))

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".series-titlex h2")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".series-thumb img")
  if el then
    local src = el.src
    if src == "" then src = el:attr("data-src") end
    return absUrl(src)
  end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".series-synops")
  if el then return string_trim(el.text) end
  return nil
end

function getBookRating(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  -- голое число (шкала 0-5); ratingCount не трогаем — он отдаёт PHP-варнинг
  local el = html_select_first(body, ".series-infoz span[itemprop=\"ratingValue\"]")
  if el then return string_clean(el.text) end
  return nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, a in ipairs(html_select(body, ".series-genres a")) do
    local g = string_trim(a.text)
    if g ~= "" then table.insert(genres, g) end
  end
  return genres
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end

  local chapters = {}
  -- реальный класс списка — .series-chapterlists (с «s»), не .series-chapterlist
  for _, a in ipairs(html_select(body, ".series-chapterlists li a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      -- заголовок в первом <span>; второй span.date — дата публикации
      local titleEl = html_select_first(a.html, "span")
      table.insert(chapters, {
        title = titleEl and string_clean(titleEl.text) or string_clean(a.text),
        url   = chUrl
      })
    end
  end

  -- Реверсим: от первой к последней
  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  -- ВАЖНО: прямой http_get, НЕ fetchPage!
  local r = http_get(bookUrl)
  if not r.success then return nil end
  -- Берём href первой (самой новой) главы — уникален для каждого обновления
  local el = html_select_first(r.body, ".series-chapterlists li:first-child a")
  if el and el.href ~= "" then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  if not html or html == "" then return "" end

  local cleaned = html_remove(html,
    "script", "style",
    ".ads", ".advertisement", ".ad",
    ".chapter-nav", ".nav-links",
    "#comments", ".comment",
    ".sharedaddy", ".jp-relatedposts",
    ".code-block", ".code-block-*"
  )

  -- Ищем контент в чистом контейнере .adsads > #content или fallback
  local el = html_select_first(cleaned, ".adsads > #content.clearfix.font_default")
  if not el then
    el = html_select_first(cleaned, ".adsads > #content")
  end
  if not el then
    el = html_select_first(cleaned, "main")
  end
  if not el then return "" end

  local text = html_text(el.html)
  return applyStandardContentTransforms(text)
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "order",
      label        = "Order by",
      defaultValue = "popular",
      options = {
        { value = "popular",       label = "Popular"        },
        { value = "title",         label = "A-Z"            },
        { value = "titlereverse",  label = "Z-A"            },
        { value = "update",        label = "Latest Update"  },
        { value = "latest",        label = "Latest Added"   },
        { value = "rating",        label = "Rating"         },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",           label = "All"       },
        { value = "ongoing",    label = "Ongoing"   },
        { value = "completed",  label = "Completed" },
      }
    },
    {
      type         = "select",
      key          = "type",
      label        = "Type",
      defaultValue = "",
      options = {
        { value = "",               label = "All"         },
        { value = "Web Novel",      label = "Web Novel"   },
        { value = "Light Novel",    label = "Light Novel" },
      }
    },
    {
      type    = "checkbox",
      key     = "genre",
      label   = "Genres",
      options = {
        { value = "action",             label = "Action"             },
        { value = "adult",              label = "Adult"              },
        { value = "adventure",          label = "Adventure"          },
        { value = "comedy",             label = "Comedy"             },
        { value = "drama",              label = "Drama"              },
        { value = "ecchi",              label = "Ecchi"              },
        { value = "fantasy",            label = "Fantasy"            },
        { value = "game",               label = "Game"               },
        { value = "gender-bender",      label = "Gender Bender"      },
        { value = "harem",              label = "Harem"              },
        { value = "historical",         label = "Historical"         },
        { value = "horror",             label = "Horror"             },
        { value = "josei",              label = "Josei"              },
        { value = "martial-arts",       label = "Martial Arts"       },
        { value = "mature",             label = "Mature"             },
        { value = "mecha",              label = "Mecha"              },
        { value = "mystery",            label = "Mystery"            },
        { value = "original-inggris",   label = "Original (Inggris)" },
        { value = "psychological",      label = "Psychological"      },
        { value = "romance",            label = "Romance"            },
        { value = "school-life",        label = "School Life"        },
        { value = "sci-fi",             label = "Sci-fi"             },
        { value = "seinen",             label = "Seinen"             },
        { value = "seinen-xuanhuan",    label = "Seinen Xuanhuan"    },
        { value = "shounen",            label = "Shounen"            },
        { value = "slice-of-life",      label = "Slice of Life"      },
        { value = "smut",               label = "Smut"               },
        { value = "sports",             label = "Sports"             },
        { value = "supernatural",       label = "Supernatural"       },
        { value = "tragedy",            label = "Tragedy"            },
        { value = "wuxia",              label = "Wuxia"              },
        { value = "xianxia",            label = "Xianxia"            },
        { value = "xuanhuan",           label = "Xuanhuan"           },
        { value = "xuanhuan-events",    label = "Xuanhuan Events"    },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page    = index + 1
  local order   = filters["order"]  or "popular"
  local status  = filters["status"] or ""
  local typ     = filters["type"]   or ""
  local genres  = filters["genre_included"] or {}

  local countries = { "china", "jepang", "korea", "unknown" }

  local url = buildSearchUrl({
    page      = page,
    order     = order,
    status    = status,
    typ       = typ,
    genres    = genres,
    countries = countries,
  })

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end