id       = "novelfull"
name     = "NovelFull"
version  = "1.0.7"
baseUrl  = "https://novelfull.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelfull.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- ponytail: кэш страницы книги — движок дёргает 4+ функции деталей параллельно
local _pageCache = {}

local function fetchBookPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then _pageCache[url] = r.body; return r.body end
    return nil
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

-- Реальная вёрстка (novelfull.net, проверено на живой странице):
-- список в .col-truyen-main .ul-list1, карточка = .li-row,
-- заголовок в .txt h3.tit a, обложка (relative) в .pic img.
local function buildCatalogItems(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".col-truyen-main .ul-list1 .li-row")) do
        local a = html_select_first(card.html, ".txt h3.tit a")
        if a and a.href and a.href ~= "" then
            local cover = html_attr(card.html, ".pic img", "src")
            table.insert(items, {
                title = string_clean(a.text),
                url   = absUrl(a.href),
                cover = absUrl(cover),
            })
        end
    end
    return items
end

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "latest-release-novel"
    if page > 1 then url = url .. "?page=" .. tostring(page) .. "&per-page=22" end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = buildCatalogItems(r.body)
    return { items = items, hasNext = #items == 22 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "search?keyword=" .. url_encode(query)
    if page > 1 then url = url .. "&page=" .. tostring(page) end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = buildCatalogItems(r.body)
    return { items = items, hasNext = #items == 22 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, "h1.tit")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local cover = html_attr(html, ".m-book1 img", "src")
    return (cover ~= "" and absUrl(cover)) or nil
end

function getBookDescription(bookUrl)
    local html = fetchBookPage(bookUrl)
    if not html then return nil end
    local el = html_select_first(html, "#novel-summary-inner")
    return el and string_trim(el.text) or nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    -- Число страниц списка глав: <option data-url="...?page=N"> в селекте навигации
    local maxPage = 1
    for page in r.body:gmatch('data%-url="[^"]*%?page=(%d+)"') do
        local n = tonumber(page) or 1
        if n > maxPage then maxPage = n end
    end

    -- ul-list5 — реальный список глав. Кнопка "Read first" (ссылка на главу 1)
    -- находится вне этого блока, поэтому не попадает сюда и не дублирует главу 1.
    local seen = {}
    local res, order = {}, {}
    local function parsePage(html)
        for _, a in ipairs(html_select(html, "ul.ul-list5 a[href*='/chapter-']")) do
            local href = absUrl(a.href)
            if not seen[href] then
                seen[href] = true
                local title = html_attr(a.html, "a", "title")
                if title == "" then title = a.text end
                local num = tonumber((href:match("/chapter%-(%d+)")) or "0") or 0
                table.insert(res, { title = string_clean(title), url = href })
                table.insert(order, num)
            end
        end
    end

    parsePage(r.body)

    if maxPage > 1 then
        local urls = {}
        for p = 2, maxPage do table.insert(urls, bookUrl .. "?page=" .. p) end
        local results = http_get_batch(urls)
        for _, res2 in ipairs(results) do
            if res2.success then parsePage(res2.body) end
        end
    end

    -- Сайт отдаёт главы от новых к старым — сортируем по возрастанию номера,
    -- чтобы глава 1 оказалась первой в списке.
    local idx = {}
    for i = 1, #res do idx[i] = i end
    table.sort(idx, function(a, b) return order[a] < order[b] end)
    local out = {}
    for _, i in ipairs(idx) do out[#out + 1] = res[i] end
    return out
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "ul.ul-list5 a[href*='/chapter-']")
    return el and el.href or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html, "script", ".ads")
    local el = html_select_first(cleaned, "#chapter-content")
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return {} end
  local genres = {}
  for _, a in ipairs(html_select(html, ".m-info .item a.a1[href^='/genre/']")) do
    local g = string_trim(a.text)
    if g ~= "" then table.insert(genres, g) end
  end
  return genres
end

-- ── Статус / Дата обновления ───────────────────────────────────────────────────

function getBookStatus(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return nil end
  -- Блок статуса: <div class="item">...<span title="Status">...</span><a>OnGoing</a>
  for _, item in ipairs(html_select(html, ".item")) do
    if html_select_first(item.html, "span[title='Status']") then
      local a = html_select_first(item.html, "a")
      if a then
        local t = string_clean(a.text)
        if t == "OnGoing" then return "Ongoing" end
        return t
      end
    end
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local html = fetchBookPage(bookUrl)
  if not html then return nil end
  -- Блок ".lastupdate": "[ Updated 8 minutes ago ]" — относительная дата
  -- (абсолютной даты на странице книги novelfull.net нет)
  local el = html_select_first(html, ".lastupdate")
  if not el then return nil end
  local t = string_trim(el.text)
  t = string.gsub(t, "^%s*%[?%s*", "")
  t = string.gsub(t, "%s*%]?%s*$", "")
  t = string.gsub(t, "^[Uu]pdated%s+", "")
  t = string_trim(t)
  return (t ~= "" and t) or nil
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
        { value = "Adventure",     label = "Adventure"     },
        { value = "Adult",         label = "Adult"         },
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

  local items = buildCatalogItems(r.body)
  return { items = items, hasNext = #items == 22 }
end
