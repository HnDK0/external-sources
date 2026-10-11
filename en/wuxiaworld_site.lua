-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "wuxia_world_site"
name     = "WuxiaWorld.site"
-- Version: 1.1.2
version  = "1.1.2"
baseUrl  = "https://wuxiaworld.site/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/wuxiaworld.site.png"

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

local function absUrl(href)
  return LIB("urls").absUrl(baseUrl, href)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Рейтинг из карточки каталога/поиска или со страницы книги:
-- <div class="post-total-rating allow_vote"><span class="score font-meta total_votes">4.1</span></div>
-- На странице книги селектор .score.font-meta.total_votes встречается дважды
-- (рейтинг и виджет «Your Rating»), поэтому берём именно вложенный в .post-total-rating.
local function extractRating(html)
  local el = html_select_first(html, ".post-total-rating .score")
  if el then
    local r = string_clean(el.text)
    if r ~= "" then return r end
  end
  return nil
end

-- Общая загрузка страницы книги с кэшем в рамках одного вызова движка
-- (детальные функции вызываются параллельно — кэш убирает лишние запросы).
-- Session-cached book page (shared fetch lib, same contract as before).
local function fetchBookPage(url)
  return LIB("fetch").page(url)
end

-- Standard chapter-text cleanup from the shared content lib.
local function applyStandardContentTransforms(text)
  return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "novel/?m_orderby=trending"
  if page > 1 then url = url .. "&page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".page-item-detail")) do
    local titleEl = html_select_first(card.html, ".post-title h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".c-image-hover img", "data-src")
      if cover == "" then cover = html_attr(card.html, ".c-image-hover img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        local item = { title = t, url = bookUrl, cover = absUrl(cover) }
        local rating = extractRating(card.html)
        if rating then item.rating = rating end
        table.insert(items, item)
      end
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local url
  if page == 1 then
    url = baseUrl .. "?s=" .. url_encode(query) .. "&post_type=wp-manga"
  else
    url = baseUrl .. "page/" .. tostring(page) .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".c-tabs-item__content")) do
    local titleEl = html_select_first(card.html, ".post-title h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".c-image-hover img", "data-src")
      if cover == "" then cover = html_attr(card.html, ".c-image-hover img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        local item = { title = t, url = bookUrl, cover = absUrl(cover) }
        local rating = extractRating(card.html)
        if rating then item.rating = rating end
        table.insert(items, item)
      end
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local src = html_attr(r.body, ".summary_image img", "data-src")
  if src == "" then src = html_attr(r.body, ".summary_image img", "src") end
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".summary__content")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Рейтинг книги ─────────────────────────────────────────────────────────────

-- Рейтинг со страницы книги: <span class="score font-meta total_votes">4.1</span>
-- внутри .post-total-rating. Только рейтинг, список глав не трогаем; nil при ошибке.
function getBookRating(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  return extractRating(r.body)
end

-- ── Список глав (POST AJAX) ───────────────────────────────────────────────────

function getChapterList(bookUrl)
  local ajaxUrl = bookUrl:gsub("/?$", "") .. "/ajax/chapters/"

  local r = http_post(ajaxUrl, "", {
    headers = {
      ["Referer"] = bookUrl,
      ["X-Requested-With"] = "XMLHttpRequest"
    }
  })
  if not r.success then
    log_error("wuxiaworld.site: AJAX failed " .. tostring(r.code))
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "li.wp-manga-chapter a[href]")) do
    local chUrl = absUrl(a.href)
    local t = string_trim(a.text)
    if chUrl ~= "" then
      table.insert(chapters, { title = t, url = chUrl })
    end
  end

  -- API отдаёт newest-first → разворачиваем
  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "#btn-read-first")
  if el then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", ".ads", ".advertisement", ".social-share")
  local el = html_select_first(cleaned, ".reading-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  -- trim + drop empties — shared meta lib (site order kept).
  return LIB("meta").collectGenres(html_select(r.body, ".genres-content a"))
end

-- ── Status / Last update ───────────────────────────────────────────────────

-- Статус книги: <div class="post-status"><div class="summary-content">OnGoing</div></div>
-- Текст оставляем как на сайте (без маппинга) — shared meta lib.
function getBookStatus(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return nil end
  local el = html_select_first(html, ".post-status .summary-content")
  if not el then return nil end
  return LIB("meta").status(el.text)
end

-- Дата обновления: <meta property="article:modified_time"
-- content="2022-06-29T07:45:21+00:00"/> — ISO-дата, shared meta lib оставит только YYYY-MM-DD.
function getBookLastUpdate(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return nil end
  local v = html_attr(html, "meta[property='article:modified_time']", "content")
  if v == "" then return nil end
  return LIB("meta").normalizeDate(v)
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "m_orderby",
      label        = "Order by",
      defaultValue = "trending",
      options = {
        { value = "trending",   label = "Trending"    },
        { value = "latest",     label = "Latest"      },
        { value = "alphabet",   label = "A-Z"         },
        { value = "rating",     label = "Rating"      },
        { value = "views",      label = "Most Views"  },
        { value = "new-manga",  label = "New"         },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",         label = "All"       },
        { value = "on-going", label = "Ongoing"   },
        { value = "end",      label = "Completed" },
        { value = "canceled", label = "Canceled"  },
        { value = "on-hold",  label = "On Hold"   },
      }
    },
    {
      type         = "select",
      key          = "adult",
      label        = "Adult Content",
      defaultValue = "",
      options = {
        { value = "",  label = "All"        },
        { value = "0", label = "No Adult"   },
        { value = "1", label = "Only Adult" },
      }
    },
    {
      type    = "checkbox",
      key     = "genre",
      label   = "Genres",
      options = {
        { value = "action",             label = "Action"          },
        { value = "adult",              label = "Adult"           },
        { value = "adventure",          label = "Adventure"       },
        { value = "comedy",             label = "Comedy"          },
        { value = "drama-genre",        label = "Drama"           },
        { value = "ecchi",              label = "Ecchi"           },
        { value = "fantasy",            label = "Fantasy"         },
        { value = "gender-bender",      label = "Gender Bender"   },
        { value = "harems-novel",       label = "Harem"           },
        { value = "historical",         label = "Historical"      },
        { value = "horror",             label = "Horror"          },
        { value = "isekai",             label = "Isekai"          },
        { value = "josei",              label = "Josei"           },
        { value = "lgbt",               label = "LGBT+"           },
        { value = "magical-realism",    label = "Magical Realism" },
        { value = "manhwa",             label = "Manhwa"          },
        { value = "martial-arts-genre", label = "Martial Arts"    },
        { value = "mature",             label = "Mature"          },
        { value = "mecha",              label = "Mecha"           },
        { value = "mystery",            label = "Mystery"         },
        { value = "psychological",      label = "Psychological"   },
        { value = "reincarnation",      label = "Reincarnation"   },
        { value = "romance",            label = "Romance"         },
        { value = "school-life",        label = "School Life"     },
        { value = "sci-fi",             label = "Sci-fi"          },
        { value = "seinen",             label = "Seinen"          },
        { value = "shoujo-genre",       label = "Shoujo"          },
        { value = "shoujo-ai",          label = "Shoujo Ai"       },
        { value = "shounen",            label = "Shounen"         },
        { value = "shounen-ai",         label = "Shounen Ai"      },
        { value = "slice-of-life",      label = "Slice of Life"   },
        { value = "smut",               label = "Smut"            },
        { value = "sports",             label = "Sports"          },
        { value = "supernatural",       label = "Supernatural"    },
        { value = "teen",               label = "Teen"            },
        { value = "thriller",           label = "Thriller"        },
        { value = "tragedy",            label = "Tragedy"         },
        { value = "video-games",        label = "Video Games"     },
        { value = "wuxia",              label = "Wuxia"           },
        { value = "xianxia",            label = "Xianxia"         },
        { value = "xuanhuan",           label = "Xuanhuan"        },
        { value = "yaoi",               label = "Yaoi"            },
        { value = "yuri",               label = "Yuri"            },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page    = LIB("catalog").nextIndex(index)
  local orderby = filters["m_orderby"] or "trending"
  local status  = filters["status"]    or ""
  local adult   = filters["adult"]     or ""
  local genres  = filters["genre_included"] or {}

  local url = baseUrl .. "?s=&post_type=wp-manga"
  url = url .. "&m_orderby=" .. url_encode(orderby)
  for _, g in ipairs(genres) do
    url = url .. "&genre%5B%5D=" .. url_encode(g)
  end
  if #genres > 0 then url = url .. "&op=1" end
  if adult ~= "" then url = url .. "&adult=" .. url_encode(adult) end
  if status ~= "" then url = url .. "&status%5B%5D=" .. url_encode(status) end
  if page > 1 then url = url .. "&paged=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".c-tabs-item__content")) do
    local titleEl = html_select_first(card.html, ".post-title h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".tab-thumb img", "data-src")
      if cover == "" then cover = html_attr(card.html, ".tab-thumb img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        local item = { title = t, url = bookUrl, cover = absUrl(cover) }
        local rating = extractRating(card.html)
        if rating then item.rating = rating end
        table.insert(items, item)
      end
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end
