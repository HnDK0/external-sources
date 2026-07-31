-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "empirenovel"
name     = "Empire Novel"
version  = "2.4.0"
baseUrl  = "https://www.empirenovel.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/empirenovel.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Стандартная очистка текста главы: домен, дублирующийся заголовок главы,
-- строки переводчика, маркер [Chapter N End], ссылки next/previous.
local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+[^\\n\\r]*)[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?im)^\\s*\\[[^\\]\\n]*[Ee]nd[^\\]\\n]*\\]\\s*(\\r?\\n|$)", "")
  text = regex_replace(text, "(?i)^\\s*(next|previous)\\s+chapter\\s*$", "")
  text = string_trim(text)
  text = regex_replace(text, "\\n{3,}", "\n\n")
  return text
end

-- Последняя страница пагинации ("ul.pagination a.page-link"), по умолчанию 1.
local function getLastPage(body)
  local lastPage = 1
  for _, a in ipairs(html_select(body, "ul.pagination a.page-link")) do
    local n = tonumber(string_trim(a.text))
    if n and n > lastPage then lastPage = n end
  end
  return lastPage
end

-- ── Каталог ───────────────────────────────────────────────────────────────────
--
-- Карточка: div.col внутри div.row.row-cols-sm-2.p-2.
-- Название: a[href*="/novel/"] h2.fs-6.fw-bold.
-- Обложка: img.rounded-3.lazyload → data-src (с ведущими/хвостовыми пробелами).

-- Парсинг страницы каталога (используется и в getCatalogList, и в getCatalogFiltered).
local function parseCatalog(body)
  local items = {}
  for _, card in ipairs(html_select(body, "div.row.row-cols-sm-2.p-2 > div.col")) do
    local titleEl = html_select_first(card.html, "a[href*='/novel/'] h2.fs-6.fw-bold, a[href*='/novel/']")
    if titleEl then
      local cover = string_trim(html_attr(card.html, "img.rounded-3.lazyload", "data-src"))
      if cover == "" or cover:find("^data:image") then
        cover = string_trim(html_attr(card.html, "img.rounded-3.lazyload", "src"))
      end
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = (cover ~= "") and absUrl(cover) or nil,
      })
    end
  end

  return { items = items, lastPage = getLastPage(body) }
end

function getCatalogList(index)
  local page = (index or 0) + 1
  local r = http_get(baseUrl .. "novels-list?page=" .. page)
  if not r.success then return { items = {}, hasNext = false } end

  local res = parseCatalog(r.body)
  return { items = res.items, hasNext = page < res.lastPage and #res.items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────
--
-- Проверено на живом сайте: ?search= на /novels-list игнорируется сервером
-- (возвращается весь каталог). Рабочий поиск — AJAX-эндпоинт /search-live?q=,
-- который отдаёт JSON-массив { name, slug, ... }.

function getCatalogSearch(index, query)
  local r = http_get(baseUrl .. "search-live?q=" .. url_encode(query))
  if not r.success then return { items = {}, hasNext = false } end

  local data = json_parse(r.body)
  if type(data) ~= "table" then return { items = {}, hasNext = false } end

  local items = {}
  for _, item in ipairs(data) do
    local title = string_clean(item.name or "")
    local slug  = item.slug or ""
    if title ~= "" and slug ~= "" then
      table.insert(items, { title = title, url = baseUrl .. "novel/" .. slug })
    end
  end

  -- Эндпоинт не постраничный — результат отдаём целиком.
  return { items = items, hasNext = false }
end

-- ── Фильтры каталога ──────────────────────────────────────────────────────────
--
-- Живая проверка: сервер реально фильтрует только по ?category=<жанр> (ссылки
-- /novels-list?category=...) и ?status=<1|2|3> (Ongoing/Completed/Abandoned).
-- ?sort_by и ?search игнорируются — не выводим их в фильтры.

function getFilterList()
  local categories = {
    { value = "action",        label = "Action"        },
    { value = "adult",         label = "Adult"         },
    { value = "adventure",     label = "Adventure"     },
    { value = "comedy",        label = "Comedy"        },
    { value = "drama",         label = "Drama"         },
    { value = "ecchi",         label = "Ecchi"         },
    { value = "fanfiction",    label = "Fanfiction"    },
    { value = "fantasy",       label = "Fantasy"       },
    { value = "gender-bender", label = "Gender Bender" },
    { value = "harem",         label = "Harem"         },
    { value = "historical",    label = "Historical"    },
    { value = "horror",        label = "Horror"        },
    { value = "isekai",        label = "Isekai"        },
    { value = "josei",         label = "Josei"         },
    { value = "martial-arts",  label = "Martial Arts"  },
    { value = "mature",        label = "Mature"        },
    { value = "mecha",         label = "Mecha"         },
    { value = "modern-life",   label = "Modern Life"   },
    { value = "mystery",       label = "Mystery"       },
    { value = "original",      label = "Original"      },
    { value = "psychological", label = "Psychological" },
    { value = "reincarnation", label = "Reincarnation" },
    { value = "romance",       label = "Romance"       },
    { value = "school-life",   label = "School Life"   },
    { value = "sci-fi",        label = "Sci-Fi"        },
    { value = "seinen",        label = "Seinen"        },
    { value = "shoujo",        label = "Shoujo"        },
    { value = "shoujo-ai",     label = "Shoujo Ai"     },
    { value = "shounen",       label = "Shounen"       },
    { value = "shounen-ai",    label = "Shounen Ai"    },
    { value = "slice-of-life", label = "Slice of Life" },
    { value = "smut",          label = "Smut"          },
    { value = "supernatural",  label = "Supernatural"  },
    { value = "system",        label = "System"        },
    { value = "thriller",      label = "Thriller"      },
    { value = "tragedy",       label = "Tragedy"       },
    { value = "transmigration", label = "Transmigration" },
    { value = "urban",         label = "Urban"         },
    { value = "virtual-reality", label = "Virtual Reality" },
    { value = "wuxia",         label = "Wuxia"         },
    { value = "xianxia",       label = "Xianxia"       },
    { value = "xuanhuan",      label = "Xuanhuan"      },
    { value = "yaoi",          label = "Yaoi"          },
    { value = "yuri",          label = "Yuri"          },
  }

  return {
    {
      key     = "status",
      label   = "Status",
      type    = "select",
      options = {
        { value = "1", label = "Ongoing"   },
        { value = "2", label = "Completed" },
        { value = "3", label = "Abandoned" },
      },
    },
    {
      key     = "category",
      label   = "Category",
      type    = "select",
      options = categories,
    },
  }
end

function getCatalogFiltered(index, filters)
  local page = (index or 0) + 1

  local qs = {}
  local status   = filters["status"]   or ""
  local category = filters["category"] or ""
  if status   ~= "" then table.insert(qs, "status="   .. status)   end
  if category ~= "" then table.insert(qs, "category=" .. category) end
  if page > 1       then table.insert(qs, "page="     .. page)     end

  local url = baseUrl .. "novels-list"
  if #qs > 0 then url = url .. "?" .. table.concat(qs, "&") end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local res = parseCatalog(r.body)
  return { items = res.items, hasNext = page < res.lastPage and #res.items > 0 }
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
  local cover = html_attr(r.body, "meta[property='og:image']", "content")
  if cover ~= "" then return absUrl(cover) end
  cover = string_trim(html_attr(r.body, "img.rounded-3.lazyload[data-src]", "data-src"))
  if cover ~= "" then return absUrl(cover) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return "" end
  local meta = html_attr(r.body, "meta[name='description']", "content")
  if meta == "" then return "" end
  local desc = regex_replace(meta, "(?i)^(Read\\s+(translated\\s+)?version\\s+of\\s+|Read\\s+)", "")
  desc = regex_replace(desc, "(?i)\\s+for\\s+free\\.?\\s*$", "")
  return string_trim(desc)
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────
--
-- На странице книги жанры — ссылки a.category[itemprop='genre']
-- (например <a class="category px-2 py-1 rounded text-uppercase" itemprop="genre">).

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  local genres = {}
  for _, a in ipairs(html_select(r.body, "a.category[itemprop='genre']")) do
    local g = string_clean(a.text)
    if g ~= "" then
      table.insert(genres, g)
    end
  end
  return genres
end

-- ── Список глав (PAGE_BASED, через parsePage) ─────────────────────────────────
--
-- Сайт показывает главы от новых к старым; движок ждёт от старых к новым.
-- Инвертируем порядок страниц (страница 1 движка = последняя страница сайта)
-- и разворачиваем главы внутри каждой страницы.
--
-- Prefetch-burst: у движка все вызовы parsePage идут строго последовательным
-- диапазоном S..totalPages (первичная загрузка 1..N, инкремент обновления —
-- lastKnownPage..newTotalPages). Первая страница диапазона параллельно тянет
-- остаток через http_get_batch и отдаёт его из модульного кэша _bursts.
-- Вызов вне очереди (повторное открытие книги) сбрасывает burst и делает
-- обычный свежий запрос.

local _bursts = {}

-- Извлечение глав из HTML-тела страницы списка.
local function parseChapters(body)
  -- Дата публикации лежит в отдельном div.small.fst-italic под названием главы;
  -- убираем её структурно, чтобы она не попала в заголовок.
  body = html_remove(body, "div.small.fst-italic")

  local raw = {}
  for _, a in ipairs(html_select(body, "ul.list-unstyled.row a[href*='/novel/']")) do
    local href = a.href
    -- Номер главы может быть дробным: /novel/<slug>/11365.1
    if href and string.match(href, "/novel/[^/]+/%d+%.?%d*$") then
      local title = string_clean(a.text)
      -- Страховка: срезать дату/относительное время, если разметка изменится.
      -- Только англ. формат (Aug 8, 2025) и relative time (2 days ago) —
      -- фр. даты с пробелом съели бы номер главы ("Chapitre 11 mai 2025").
      title = regex_replace(title, "\\s*[A-Za-z]{3,9}\\s+\\d{1,2},\\s+\\d{4}\\s*$", "")
      title = regex_replace(title, "\\s+\\d+\\s+(month|day|week|year|hour|minute|second)s?\\s+ago\\s*$", "")
      if title ~= "" then
        table.insert(raw, { title = title, url = absUrl(href) })
      end
    end
  end

  -- Внутри страницы сайт тоже показывает новые сверху → разворачиваем.
  local chapters = {}
  for i = #raw, 1, -1 do
    table.insert(chapters, raw[i])
  end
  return chapters
end

function parsePage(bookUrl, page)
  local burst = _bursts[bookUrl]
  if burst and page == burst.nextPage then
    local body = burst.bodies[page]
    if body then
      burst.nextPage = burst.nextPage + 1
      if burst.nextPage > burst.totalPages then _bursts[bookUrl] = nil end
      return { chapters = parseChapters(body), totalPages = burst.totalPages }
    end
  end
  -- Вызов вне очереди burst или промах кэша — сбрасываем и идём обычным путём.
  if burst then _bursts[bookUrl] = nil end

  local r = http_get(bookUrl)
  if not r.success then return { chapters = {}, totalPages = 1 } end

  local totalPages = getLastPage(r.body)

  -- Страница сайта, соответствующая запрошенной движком.
  local sitePage = totalPages - page + 1

  local body = r.body
  if sitePage > 1 then
    local pr = http_get(bookUrl .. "?page=" .. sitePage)
    if not pr.success then return { chapters = {}, totalPages = totalPages } end
    body = pr.body
  end

  -- Prefetch-burst: остаток диапазона тянем параллельно одним батчем.
  local remaining = totalPages - page
  if remaining > 0 then
    local urls = {}
    for p = 1, remaining do
      local sp = totalPages - (page + p) + 1
      urls[p] = (sp == 1) and bookUrl or (bookUrl .. "?page=" .. sp)
    end
    local rs = http_get_batch(urls)
    local bodies = {}
    for p = 1, remaining do
      if rs[p] and rs[p].success then
        bodies[page + p] = rs[p].body
      end
    end
    _bursts[bookUrl] = { totalPages = totalPages, nextPage = page + 1, bodies = bodies }
    log_info("[empirenovel] prefetch " .. remaining .. " pages for " .. bookUrl)
  end

  return { chapters = parseChapters(body), totalPages = totalPages }
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html,
    "script", "style", "nav", "header", "footer",
    "aside", "form", "div#comments", "div.nav-links",
    "div.post-navigation", "div.code-block",
    "div.sharethis-inline-share-buttons"
  )

  local el = html_select_first(cleaned,
    "div#read-novel, div.chapter-content, div.reading-content, #chapter-content, " ..
    "div.text-content, div.entry-content"
  )
  if not el then return "" end

  local inner = el.html
  inner = regex_replace(inner, "(?s)<figure[^>]*>.*?</figure>", "")
  inner = regex_replace(inner, "(?s)<img[^>]*>", "")
  inner = regex_replace(inner, "(?s)<center[^>]*>.*?</center>", "")

  return applyStandardContentTransforms(html_text(inner))
end
