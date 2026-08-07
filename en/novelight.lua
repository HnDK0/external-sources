-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "novelight"
name     = "Novelight"
version  = "1.0.7"
baseUrl  = "https://novelight.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelight.png"

-- ── Helpers ─────────────────────────────────────────────────────────────────

local _pageCache = {}

-- Cache of the book page, shared by the book-details functions and parsePage
-- (stable metadata only; chapter data always comes from uncached AJAX calls).
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
  -- Водяной знак сайта вшит внутрь параграфов кириллицей (о/е, U+043E/U+0435),
  -- поэтому regex удаления домена его не ловит: # Nоvеlight #
  text = regex_replace(text, "(?i)#\\s*N[oо]v[eе]light\\s*#", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- The site's AJAX endpoints reject plain requests without this header.
local AJAX_HEADERS = {
  headers = {
    ["X-Requested-With"] = "XMLHttpRequest"
  }
}

-- ── Catalog ─────────────────────────────────────────────────────────────────

local function parseCatalogItems(html)
  local items = {}
  for _, card in ipairs(html_select(html, "div.manga-grid-list a.item")) do
    local titleEl = html_select_first(card.html, "div.title")
    local coverEl = html_select_first(card.html, "img")
    local bookUrl = absUrl(card.href)
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = coverEl and absUrl(coverEl.src) or ""
      })
    end
  end
  return items
end

function getCatalogList(index)
  local r = http_get(baseUrl .. "catalog/?page=" .. tostring(index + 1))
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
  local r = http_get(baseUrl .. "catalog/?search=" .. url_encode(query) .. "&page=" .. tostring(index + 1))
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Catalog filters ───────────────────────────────────────────────────────────
-- Mirrors the site's /catalog/ filter form (genre/type/status/country/sorting);
-- all values verified to filter server-side.

local NOVELIGHT_GENRES = {
  { value = "16", label = "Action"         },
  { value = "1",  label = "Thriller"       },
  { value = "2",  label = "Supernatural"   },
  { value = "3",  label = "Sports"         },
  { value = "4",  label = "Slice of Life"  },
  { value = "5",  label = "Sci-Fi"         },
  { value = "6",  label = "Romance"        },
  { value = "7",  label = "Psychological"  },
  { value = "8",  label = "Mystery"        },
  { value = "9",  label = "Mecha"          },
  { value = "10", label = "Horror"         },
  { value = "11", label = "Fantasy"        },
  { value = "12", label = "Ecchi"          },
  { value = "13", label = "Drama"          },
  { value = "14", label = "Comedy"         },
  { value = "15", label = "Adventure"      },
  { value = "17", label = "Adult"          },
  { value = "18", label = "Isekai"         },
  { value = "19", label = "Wuxia"          },
  { value = "20", label = "Shounen"        },
  { value = "21", label = "Yuri"           },
  { value = "22", label = "Shoujo"         },
  { value = "23", label = "Shoujo Ai"      },
  { value = "24", label = "Harem"          },
  { value = "25", label = "Seinen"         },
  { value = "26", label = "Tragedy"        },
  { value = "27", label = "Mature"         },
  { value = "28", label = "Martial Arts"   },
  { value = "29", label = "Gender Bender"  },
  { value = "30", label = "School Life"    },
  { value = "31", label = "Xuanhuan"       },
  { value = "32", label = "Yaoi"           },
  { value = "33", label = "Historical"     },
  { value = "34", label = "Game"           },
  { value = "35", label = "Shounen Ai"     },
}

function getFilterList()
  return {
    {
      type    = "checkbox",
      key     = "genres",
      label   = "Genre",
      options = NOVELIGHT_GENRES,
    },
    {
      type    = "checkbox",
      key     = "type",
      label   = "Type",
      options = {
        { value = "1", label = "Light Novel"    },
        { value = "2", label = "Published Novel" },
        { value = "3", label = "Web Novel"       },
        { value = "4", label = "Fan Fiction"     },
      },
    },
    {
      type    = "checkbox",
      key     = "status",
      label   = "Status",
      options = {
        { value = "releasing",        label = "Releasing"      },
        { value = "completed",        label = "Completed"      },
        { value = "cancelled",        label = "Cancelled"      },
        { value = "not yet released", label = "Not Yet Released" },
      },
    },
    {
      type    = "checkbox",
      key     = "country",
      label   = "Country",
      options = {
        { value = "1", label = "China"  },
        { value = "2", label = "Japan"  },
        { value = "3", label = "Korea"  },
        { value = "6", label = "Other"  },
      },
    },
    {
      type    = "select",
      key     = "ordering",
      label   = "Sort By",
      options = {
        { value = "title",            label = "By Title (A-Z)" },
        { value = "-time_created",    label = "By Publication Date" },
        { value = "-time_updated",    label = "By Update Date" },
        { value = "-year_of_realese", label = "By Year Released" },
        { value = "popularity",       label = "By Popularity" },
      },
    },
  }
end

function getCatalogFiltered(index, filters)
  local page = (index or 0) + 1
  filters = filters or {}

  local qs = {}

  local function addRepeated(key, values)
    for _, v in ipairs(values or {}) do
      table.insert(qs, key .. "=" .. url_encode(tostring(v)))
    end
  end

  addRepeated("genres",  filters["genres_included"])
  addRepeated("type",    filters["type_included"])
  addRepeated("status",  filters["status_included"])
  addRepeated("country", filters["country_included"])

  local ordering = filters["ordering"] or ""
  if ordering ~= "" then table.insert(qs, "ordering=" .. url_encode(ordering)) end

  table.insert(qs, "page=" .. tostring(page))

  local r = http_get(baseUrl .. "catalog/?" .. table.concat(qs, "&"))
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Book details ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "header.header-manga h1")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local cover = html_attr(body, ".second-information .poster img", "src")
  return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "#information section.text-info")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end

  local genres = {}
  for _, a in ipairs(html_select(body, "a[href*='?genres=']")) do
    local label = string_clean(a.text)
    if label ~= "" then table.insert(genres, label) end
  end
  return genres
end

-- Рейтинг книги: блок оценки на странице книги, .block.appreciate .text
-- отдаёт "4.7/5" (число + "/5"). Извлекаем только ведущее число.
-- В карточках каталога рейтинга нет, поэтому ключ rating в items не добавляем.
function getBookRating(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".block.appreciate .text")
  if not el then return nil end
  local text = string_clean(el.text)
  return text:match("^(%d+%.?%d*)") or nil
end

-- ── Chapter list (paginated, via parsePage) ─────────────────────────────────
-- The book page only lists the last 10 chapters; the full TOC is paginated and
-- loaded via AJAX: /book/ajax/chapter-pagination?book_id=<id>&page=<v>
-- The <select> holds page values (50 chapters each); the largest value = the
-- oldest chapters, the smallest = the newest.

function parsePage(bookUrl, page)
  -- Сайт банит (300 сек) при быстром последовательном парсинге списка глав,
  -- поэтому разносим запросы страниц во времени.
  sleep(math.random(150, 300))

  local body = fetchPage(bookUrl)
  if not body then return { chapters = {}, totalPages = 1 } end

  local bookId = body:match('BOOK_ID = "(%d+)"')
  if not bookId then return { chapters = {}, totalPages = 1 } end

  -- The TOC <select> holds one option per AJAX page (50 chapters each).
  -- The element API doesn't expose the option's value attribute, so parse
  -- the raw markup: value 1 = the newest chapters, the largest value = oldest.
  local selHtml = body:match('id="select%-pagination%-chapter"(.-)</select>')
  if not selHtml then return { chapters = {}, totalPages = 1 } end

  local minV, maxV = math.huge, 0
  for v in selHtml:gmatch('value="(%d+)"') do
    local n = tonumber(v)
    if n then
      if n < minV then minV = n end
      if n > maxV then maxV = n end
    end
  end
  if maxV == 0 then return { chapters = {}, totalPages = 1 } end

  local totalPages = maxV - minV + 1

  -- The engine requests pages 1, 2, ... where 1 = the oldest chapters;
  -- the site numbers them the other way round, so invert.
  local sitePage = maxV - page + 1

  local r = http_get(baseUrl .. "book/ajax/chapter-pagination?book_id=" .. bookId .. "&page=" .. tostring(sitePage), AJAX_HEADERS)
  if not r.success then return { chapters = {}, totalPages = totalPages } end

  local data = json_parse(r.body)
  if not data or not data.html then return { chapters = {}, totalPages = totalPages } end

  local raw = {}
  for _, a in ipairs(html_select(data.html, "a.chapter")) do
    -- Skip paid/locked chapters: only free ones are readable anonymously.
    if not a.html:find("fa%-lock") and not a.html:find("class=\"cost\"") then
      -- Full title, e.g. "11 vol. 93 chapter - The Spear Balances All Things (Final)"
      local titleEl = html_select_first(a.html, ".title")
      local title = titleEl and titleEl.text or a.text
      raw[#raw + 1] = { title = string_clean(title), url = absUrl(a.href) }
    end
  end

  -- The site lists chapters newest-first within a page; the engine expects
  -- chronological order (oldest at the top).
  local chapters = {}
  for i = #raw, 1, -1 do
    chapters[#chapters + 1] = raw[i]
  end

  return { chapters = chapters, totalPages = totalPages }
end

-- ── Chapter text ─────────────────────────────────────────────────────────────
-- The chapter page only embeds a truncated preview; the full text comes from
-- the AJAX endpoint /book/ajax/read-chapter/<id>. Locked chapters return an
-- empty content for anonymous visitors.

function getChapterText(html, url)
  local chapterId = url:match("/book/chapter/(%d+)")
  if not chapterId then return "" end

  local r = http_get(baseUrl .. "book/ajax/read-chapter/" .. chapterId, AJAX_HEADERS)
  if not r.success then return "" end

  local data = json_parse(r.body)
  if not data or not data.content then return "" end

  local content = html_remove(data.content, "script", "style", ".advertisment")
  local el = html_select_first(content, ".chapter-text")
  if not el then return "" end

  return applyStandardContentTransforms(html_text(el.html))
end
