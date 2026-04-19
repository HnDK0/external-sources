-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "novelbuddy"
name     = "NovelBuddy"
version  = "1.0.4"
baseUrl  = "https://novelbuddy.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbuddy.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local domains = { "https://novelbuddy.io", "https://novelbuddy.com" }

local function http_get_fb(url)
  for _, domain in ipairs(domains) do
    local r = http_get(url:gsub("https?://novelbuddy%.[a-z]+", domain))
    if r.success then return r end
  end
  return { success = false }
end

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Нормализует URL книги: заменяет любой домен на baseUrl и /novel/ на /book/
local function normalizeBookUrl(bookUrl)
  if not bookUrl or bookUrl == "" then return bookUrl end
  bookUrl = bookUrl:gsub("https?://novelbuddy%.[a-z]+", baseUrl)
  bookUrl = bookUrl:gsub("/novel/", "/book/")
  return bookUrl
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

local function parseCatalogItems(body)
  local items = {}
  for _, card in ipairs(html_select(body, ".book-detailed-item")) do
    local titleEl = html_select_first(card.html, ".title")
    local bookUrl = absUrl(html_attr(card.html, "h3 a", "href"))
    local cover   = html_attr(card.html, ".thumb img", "data-src")
    if cover == "" then cover = html_attr(card.html, ".thumb img", "src") end
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = absUrl(cover)
      })
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = baseUrl .. "/search?sort=views"
  if index > 0 then url = url .. "&page=" .. tostring(index + 1) end

  local r = http_get_fb(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url = baseUrl .. "/search?q=" .. url_encode(query)
  if index > 0 then url = url .. "&page=" .. tostring(index + 1) end

  local r = http_get_fb(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get_fb(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get_fb(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local cover = html_attr(r.body, ".img-cover img", "data-src")
  if cover == "" then cover = html_attr(r.body, ".img-cover img", "src") end
  if cover ~= "" then return absUrl(cover) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get_fb(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local cleaned = html_remove(r.body, "h3")
  local el = html_select_first(cleaned, ".section-body.summary .content")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (AJAX GET /api/manga/{bookId}/chapters) ───────────────────────

function getChapterList(bookUrl)
  bookUrl = normalizeBookUrl(bookUrl)
  local r = http_get_fb(bookUrl)
  if not r.success then return {} end

  local bookId = nil
  for _, script in ipairs(html_select(r.body, "script")) do
    local t = script.html
    local id = string.match(t, "bookId%s*=%s*(%d+)")
    if id then bookId = id; break end
  end

  if not bookId then
    log_error("NovelBuddy: bookId not found for " .. bookUrl)
    return {}
  end

  local ajaxUrl = baseUrl .. "/api/manga/" .. bookId .. "/chapters?source=detail"
  local ar = http_get_fb(ajaxUrl)
  if not ar.success then
    log_error("NovelBuddy: AJAX failed " .. tostring(ar.code))
    return {}
  end

  local chapters = {}
  for _, li in ipairs(html_select(ar.body, "li")) do
    local a = html_select_first(li.html, "a")
    if a then
      local chUrl = absUrl(a.href)
      local titleEl = html_select_first(li.html, "strong.chapter-title")
      local title = titleEl and string_clean(titleEl.text) or string_clean(a.text)
      if chUrl ~= "" then
        table.insert(chapters, { title = title, url = chUrl })
      end
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get_fb(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local el = html_select_first(r.body, ".meta p:has(strong:contains(Chapters)) span")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style",
    "#listen-chapter", "#google_translate_element", ".ads", ".advertisement")
  local el = html_select_first(cleaned, ".content-inner")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get_fb(normalizeBookUrl(bookUrl))
  if not r.success then return {} end

  local genres = {}
  for _, p in ipairs(html_select(r.body, ".meta.box p")) do
    local strong = html_select_first(p.html, "strong")
    if strong and string_trim(strong.text) == "Genres :" then
      for _, a in ipairs(html_select(p.html, "a")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
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
      key          = "sort",
      label        = "Order by",
      defaultValue = "views",
      options = {
        { value = "views",      label = "Views"      },
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

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page    = index + 1
  local sort    = filters["sort"]    or "views"
  local status  = filters["status"]  or "all"
  local genres  = filters["genre_included"] or {}

  local url = baseUrl .. "/search?sort=" .. url_encode(sort)
              .. "&status=" .. url_encode(status)

  for _, v in ipairs(genres) do
    url = url .. "&genre[]=" .. url_encode(v)
  end

  url = url .. "&page=" .. tostring(page)

  local r = http_get_fb(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".book-detailed-item")) do
    local titleEl = html_select_first(card.html, ".title")
    local bookUrl = absUrl(html_attr(card.html, "h3 a", "href"))
    local cover   = html_attr(card.html, ".thumb img", "data-src")
    if cover == "" then cover = html_attr(card.html, ".thumb img", "src") end
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = absUrl(cover)
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end