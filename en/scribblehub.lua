-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "scribblehub"
name     = "ScribbleHub"
version  = "1.0.7"
baseUrl  = "https://www.scribblehub.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/scribblehub.png"

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

-- Book page is read by 5+ getters in parallel; the shared fetch cache keeps
-- it to one request. getChapterListHash stays direct: it needs a fresh page.
local function fetchPage(url) return LIB("fetch").page(url) end

-- The page has several span.rnd_stats (Content Warning, Report Story, the
-- real status line). html_select_first picks the wrong one: walk all matches
-- and keep the one that actually says "Updated".
local function findStatusLine(body)
  for _, el in ipairs(html_select(body, "span.rnd_stats + span")) do
    local txt = string_clean(el.text)
    if string.find(txt, "Updated", 1, true) then return txt end
  end
  return nil
end

-- Standard chapter-text cleanup from the shared content lib; the local copy
-- also stripped leading "Глава N" headers — kept as a site-specific extra.
local function applyStandardContentTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
  if text == "" then return "" end
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  return string_trim(text)
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

-- Card rating is precomputed as plain text "(4.6)" in .search_ratings.
local function parseCatalogCards(body)
  local items = {}
  for _, card in ipairs(html_select(body, ".search_main_box")) do
    local titleEl = html_select_first(card.html, ".search_title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".search_img img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        local item = { title = t, url = bookUrl, cover = absUrl(cover) }
        local ratingEl = html_select_first(card.html, ".search_ratings")
        if ratingEl then
          local rating = string.match(string_clean(ratingEl.text), "[%d%.]+")
          if rating then item.rating = rating end
        end
        table.insert(items, item)
      end
    end
  end
  return items
end

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "series-ranking/?sort=1&order=2&pg=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseCatalogCards(r.body)
  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────
--
-- Обычный WP-поиск ?s=<q>&post_type=fictionposts на сайте сломан (страница
-- «Search Results» пустая даже в живом браузере). Рабочий поиск — series-finder
-- с параметром sh=<query> (проверено на живом сайте: sh=god → 25 релевантных
-- серий на страницу, пагинация через pg=).

function getCatalogSearch(index, query)
  local page = LIB("catalog").nextIndex(index)
  local url = baseUrl .. "series-finder/?sf=1&sh=" .. url_encode(query) ..
              "&sort=ratings&order=desc&pg=" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseCatalogCards(r.body)
  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "div.fic_title")
  if el then return string_clean(el.text) end
  local og = html_attr(body, "meta[property='og:title']", "content")
  return og ~= "" and string_clean(og) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".fic_image img", "src")
  if src == "" then src = html_attr(body, ".novel-cover img", "src") end
  if src == "" then src = html_attr(body, "meta[property='og:image']", "content") end
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".wi_fic_desc")
  if el then return string_trim(el.text) end
  local og = html_attr(body, "meta[property='og:description']", "content")
  return og ~= "" and string_trim(og) or nil
end

-- ── Список глав (POST AJAX) ───────────────────────────────────────────────────

function getChapterList(bookUrl)
  -- Извлекаем series ID из URL: /series/12345/title/
  local seriesId = string.match(bookUrl, "/series/(%d+)/")
  if not seriesId then
    log_error("scribblehub: cannot extract seriesId from " .. bookUrl)
    return {}
  end

  local ajaxUrl = baseUrl .. "wp-admin/admin-ajax.php"
  local body = "action=wi_getreleases_pagination&pagenum=-1&mypostid=" .. seriesId

  local r = http_post(ajaxUrl, body, {
    headers = {
      ["Content-Type"]    = "application/x-www-form-urlencoded",
      ["X-Requested-With"] = "XMLHttpRequest",
      ["Origin"]          = baseUrl:gsub("/$", ""),
      ["Referer"]         = bookUrl,
      ["Accept"]          = "*/*",
      ["Accept-Language"] = "en-US,en;q=0.9"
    }
  })
  if not r.success then
    log_error("scribblehub: AJAX failed " .. tostring(r.code))
    return {}
  end

  -- Every .toc_w row may also contain the author profile link (the home
  -- "Latest Releases" widget reuses the class). Prefer the row's own
  -- a.toc_a, then fall back to any href containing "/chapter/".
  local chapters = {}
  for _, row in ipairs(html_select(r.body, ".toc_w")) do
    local chLink = html_select_first(row.html, "a.toc_a[href]")
    if not chLink then
      for _, a in ipairs(html_select(row.html, "a[href]")) do
        if string.find(a.href or "", "/chapter/", 1, true) then chLink = a break end
      end
    end
    if chLink then
      local chUrl = absUrl(chLink.href)
      local t = string_trim(chLink.text)
      if chUrl ~= "" and t ~= "" then
        table.insert(chapters, { title = t, url = chUrl })
      end
    end
  end

  -- API отдаёт newest-first → разворачиваем
  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  -- Direct GET (fresh), but jitter the start: a library-wide refresh calls
  -- this for every book at once and used to trigger Cloudflare 429s.
  sleep(math.random(400, 2500))
  local r = http_get(bookUrl)
  if not r.success then return nil end
  return findStatusLine(r.body)
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", ".modern_chapter_ad", "div.modern_chapter_ad")
  local el = html_select_first(cleaned, "#chp_raw")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end
-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  -- trim + drop empties — shared meta lib (site order kept).
  return LIB("meta").collectGenres(html_select(body, ".fic_genre"))
end

-- ── Статус и дата обновления ──────────────────────────────────────────────────

-- Статус и дата живут в ОДНОМ <span>:
--   <span>Ongoing - Updated <span title="Last updated: Aug 20, 2026 01:05 AM">Aug 20, 2026</span></span>
-- Внешний <span> (сосед span.rnd_stats) содержит «Ongoing - Updated Aug 20, 2026» —
-- целиком это мусор. Статус = часть до « - Updated», дата = внутренний <span>.

-- Нормализация абсолютной даты «Mon D, YYYY» / «Mon D, YYYY H:MM AM» → YYYY-MM-DD.
-- Нет/не распозналось → nil.
local monthNames = {
  Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
  Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

local function normalizeDate(raw)
  if not raw or raw == "" then return nil end
  local mon, d, y = string.match(raw, "(%a%a%a)%s+(%d+),%s+(%d%d%d%d)")
  if not mon then return nil end
  local m = monthNames[mon]
  if not m then return nil end
  return string.format("%04d-%02d-%02d", tonumber(y), m, tonumber(d))
end

local function normalizeRelativeDate(raw)
  local n, unit = string.match(raw or "", "(%d+)%s+(%a+)%s+ago")
  if not n then return nil end
  local mult = {
    min = 60, mins = 60, minute = 60, minutes = 60,
    hour = 3600, hours = 3600, day = 86400, days = 86400,
    week = 7 * 86400, weeks = 7 * 86400,
    month = 30 * 86400, months = 30 * 86400,
    year = 365 * 86400, years = 365 * 86400,
  }
  local secs = mult[unit]
  if not secs then return nil end
  return os.date("%Y-%m-%d", os.time() - tonumber(n) * secs)
end

function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local txt = findStatusLine(body)
  if not txt then return nil end
  local status = string.match(txt, "^(.-)%s*%-%s*Updated")
  return status and LIB("meta").status(status) or nil
end

-- Дата обновления живёт в том же внешнем <span>, что и статус (сосед
-- span.rnd_stats): его текст — «Ongoing - Updated Aug 20, 2026» (дата
-- внутреннего <span> конкатенируется в .text). Атрибут title с префиксом
-- «Last updated:» движок через селектор [title^=...] не выбирает, поэтому
-- берём дату из текста внешнего span регуляркой и нормализуем в YYYY-MM-DD.
function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local txt = findStatusLine(body)
  if not txt then return nil end
  local raw = string.match(txt, "Updated%s+(.+)$")
  if not raw then return nil end
  return normalizeDate(raw) or normalizeRelativeDate(raw)
end

-- Confirmed on live HTML: #chk_ficrate .fic_rate_logged carries the computed
-- value in a "rating" attribute ("4.6"); no star parsing needed.
function getBookRating(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local v = html_attr(body, "#chk_ficrate .fic_rate_logged", "rating")
  return v ~= "" and v or nil
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort Results By",
      defaultValue = "ratings",
      options = {
        { value = "chapters",    label = "Chapters"            },
        { value = "frequency",   label = "Chapters per Week"   },
        { value = "dateadded",   label = "Date Added"          },
        { value = "favorites",   label = "Favorites"           },
        { value = "lastchdate",  label = "Last Updated"        },
        { value = "numofrate",   label = "Number of Ratings"   },
        { value = "pages",       label = "Pages"               },
        { value = "pageviews",   label = "Pageviews"           },
        { value = "ratings",     label = "Ratings"             },
        { value = "readers",     label = "Readers"             },
        { value = "reviews",     label = "Reviews"             },
        { value = "totalwords",  label = "Total Words"         },
      }
    },
    {
      type         = "select",
      key          = "order",
      label        = "Order By",
      defaultValue = "desc",
      options = {
        { value = "desc", label = "Descending" },
        { value = "asc",  label = "Ascending"  },
      }
    },
    {
      type         = "select",
      key          = "storyStatus",
      label        = "Story Status",
      defaultValue = "all",
      options = {
        { value = "all",       label = "All"       },
        { value = "completed", label = "Completed" },
        { value = "ongoing",   label = "Ongoing"   },
        { value = "hiatus",    label = "Hiatus"    },
      }
    },
    {
      type         = "select",
      key          = "genre_operator",
      label        = "Genres (And/Or)",
      defaultValue = "and",
      options = {
        { value = "and", label = "And" },
        { value = "or",  label = "Or"  },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Genres",
      options = {
        { value = "9",    label = "Action"        },
        { value = "902",  label = "Adult"         },
        { value = "8",    label = "Adventure"     },
        { value = "891",  label = "Boys Love"     },
        { value = "7",    label = "Comedy"        },
        { value = "903",  label = "Drama"         },
        { value = "904",  label = "Ecchi"         },
        { value = "38",   label = "Fanfiction"    },
        { value = "19",   label = "Fantasy"       },
        { value = "905",  label = "Gender Bender" },
        { value = "892",  label = "Girls Love"    },
        { value = "1015", label = "Harem"         },
        { value = "21",   label = "Historical"    },
        { value = "22",   label = "Horror"        },
        { value = "37",   label = "Isekai"        },
        { value = "906",  label = "Josei"         },
        { value = "1180", label = "LitRPG"        },
        { value = "907",  label = "Martial Arts"  },
        { value = "20",   label = "Mature"        },
        { value = "908",  label = "Mecha"         },
        { value = "909",  label = "Mystery"       },
        { value = "910",  label = "Psychological" },
        { value = "6",    label = "Romance"       },
        { value = "911",  label = "School Life"   },
        { value = "912",  label = "Sci-fi"        },
        { value = "913",  label = "Seinen"        },
        { value = "914",  label = "Slice of Life" },
        { value = "915",  label = "Smut"          },
        { value = "916",  label = "Sports"        },
        { value = "5",    label = "Supernatural"  },
        { value = "901",  label = "Tragedy"       },
      }
    },
    {
      type         = "select",
      key          = "content_warning_operator",
      label        = "Mature Content (And/Or)",
      defaultValue = "and",
      options = {
        { value = "and", label = "And" },
        { value = "or",  label = "Or"  },
      }
    },
    {
      type  = "tristate",
      key   = "content_warning",
      label = "Mature Content",
      options = {
        { value = "48", label = "Gore"             },
        { value = "50", label = "Sexual Content"   },
        { value = "49", label = "Strong Language"  },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page    = LIB("catalog").nextIndex(index)
  local sort    = filters["sort"]          or "ratings"
  local order   = filters["order"]         or "desc"
  local status  = filters["storyStatus"]   or "all"
  local gmgi    = filters["genre_operator"]         or "and"
  local cmct    = filters["content_warning_operator"] or "and"

  local gi = filters["genres_included"]          or {}
  local ge = filters["genres_excluded"]          or {}
  local ci = filters["content_warning_included"] or {}
  local ce = filters["content_warning_excluded"] or {}

  local url = baseUrl .. "series-finder/?sf=1"
              .. "&sort=" .. sort
              .. "&order=" .. order
              .. "&cp=" .. status
              .. "&pg=" .. tostring(page)

  if #gi > 0 then
    url = url .. "&gi=" .. table.concat(gi, ",")
    url = url .. "&mgi=" .. gmgi
  end
  if #ge > 0 then
    url = url .. "&ge=" .. table.concat(ge, ",")
    if #gi == 0 then url = url .. "&mgi=" .. gmgi end
  end
  if #ci > 0 then
    url = url .. "&cti=" .. table.concat(ci, ",")
    url = url .. "&mct=" .. cmct
  end
  if #ce > 0 then
    url = url .. "&cte=" .. table.concat(ce, ",")
    if #ci == 0 then url = url .. "&mct=" .. cmct end
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".search_main_box")) do
    local titleEl = html_select_first(card.html, ".search_title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".search_img img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = LIB("catalog").hasNextPage(items) }
end
