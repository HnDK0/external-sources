id       = "novelfull"
name     = "NovelFull"
version  = "1.2.1"
baseUrl  = "https://novelfull.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelfull.png"

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

-- ponytail: кэш страницы книги — движок дёргает 4+ функции деталей параллельно
-- (shared fetch lib кэширует успешные ответы на сессию).
local function fetchBookPage(url)
    return LIB("fetch").page(url)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

-- Standard chapter-text cleanup (domain lines, leading "Chapter N" heading,
-- translator/editor credit lines) from the shared content lib.
local function applyStandardContentTransforms(text)
    return LIB("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- ── HD-коверы каталога (novelping CDN) ────────────────────────────────────────
-- Каталог/поиск отдают cover 100×136: /uploads/thumbs/<slug>-<hashA>-<hashB>.jpg,
-- где хеши — случайные значения из БД движка (общий для клонов «ReadNovel-style»
-- PHP-шаблон; подмена хеша небезопасна: у trial-marriage стандартный thumb, но
-- кастомные бакеты 207×270/og → 404).

-- ponytail: константы темпа общие с предзагрузкой списка глав (см. parsePage)
local BURST_CHUNK  = 6    -- страниц на один параллельный батч (залп >=7 ловит 429)
local BURST_GAP_MS = 250  -- пауза между батчами

local _coverCache = {}

-- Бакет CDN: /novel/<slug>.jpg — оригинал (25-190KB, 369×492); при миссе
-- остаётся стоковая миниатюра novelfull (100×136) — третьей ступени нет,
-- миссов в проверке не встретилось (22/22 каталог + 12/12 популярные).
local COVER_BUCKETS = {
    "https://images.novelping.com/novel",
}

local function upgradeCovers(items)
    -- Slug книги берём из URL айтема, не из cover (в cover-ссылке он срезан).
    local pending = {}
    for _, it in ipairs(items) do
        local slug = string.match(it.url or "", "([^/]+)%.html$")
        if slug and not _coverCache[slug] then
            _coverCache[slug] = it.cover -- по умолчанию: оставляем сток
            pending[#pending + 1] = { slug = slug, original = it.cover }
        end
    end

    for _, bucket in ipairs(COVER_BUCKETS) do
        -- Только те, что ещё не получили ковер из предыдущего бакета.
        local todo = {}
        for _, e in ipairs(pending) do
            if _coverCache[e.slug] == e.original then todo[#todo + 1] = e end
        end
        if #todo == 0 then break end

        -- Проверка существования чанками (тот же ритм, что в burstLoad).
        local i = 1
        while i <= #todo do
            local last = math.min(i + BURST_CHUNK - 1, #todo)
            local urls = {}
            for j = i, last do urls[#urls + 1] = bucket .. "/" .. todo[j].slug .. ".jpg" end
            local rs = http_get_batch(urls)
            local failed = false
            for k, res in ipairs(rs) do
                if res.success then
                    _coverCache[todo[i + k - 1].slug] = urls[k]
                else
                    failed = true
                end
            end
            if failed then
                -- Однократный повтор неудачного чанка с паузой.
                sleep(math.random(600, 900))
                rs = http_get_batch(urls)
                for k, res in ipairs(rs) do
                    if res.success then _coverCache[todo[i + k - 1].slug] = urls[k] end
                end
            end
            if last < #todo then sleep(BURST_GAP_MS) end
            i = last + 1
        end
    end

    for _, it in ipairs(items) do
        local slug = string.match(it.url or "", "([^/]+)%.html$")
        if slug and _coverCache[slug] then it.cover = _coverCache[slug] end
    end
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
    upgradeCovers(items)
    return items
end

function getCatalogList(index)
    local page = LIB("catalog").nextIndex(index)
    local url = baseUrl .. "latest-release-novel"
    if page > 1 then url = url .. "?page=" .. tostring(page) .. "&per-page=22" end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = buildCatalogItems(r.body)
    return { items = items, hasNext = #items == 22 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = LIB("catalog").nextIndex(index)
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
    -- Сначала оригинал с novelping CDN: slug есть в самом URL книги.
    -- Вердикт каталога переиспользуем (_coverCache); на миссе парсим страницу.
    local slug = string.match(bookUrl or "", "([^/]+)%.html$")
    if slug then
        local cached = _coverCache[slug]
        if cached and string_starts_with(cached, "https://images.novelping.com/") then
            return cached
        end
        if not cached then
            local url = COVER_BUCKETS[1] .. "/" .. slug .. ".jpg"
            local r = http_get(url)
            if r.success then
                _coverCache[slug] = url
                return url
            end
        end
    end

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

-- ── Список глав (parsePage, пачками через AJAX) ───────────────────────────────

-- Список отдаётся постраничным AJAX:
--   GET /ajax-chapter-list?novelId=<id>&page=<N>
--   → JSON { code, html, page, pageSize, totalPage, totalChapters }
-- В html-фрагменте ровно главы страницы (по возрастанию номера), страница 1 =
-- самые старые главы → порядок совпадает с ожиданием движка (инверсия не нужна).
--
-- Сайт рейт-лимитит МГНОВЕННЫЕ залпы запросов: HTTP 429 валит ~2/3 страниц,
-- если тянуть их все параллельно (это и был баг «прыгающих» списков глав —
-- старый getChapterList делал http_get_batch на все страницы разом).
-- Последовательно запросы проходят, но 7 тыс. глав (182 страницы) грузятся
-- ~100 c. Решение — пачками: мини-батчи по BURST_CHUNK страниц с паузой между
-- ними; замерено на живом сайте: 182/182 OK за 14.5 c.

local _bursts = {} -- bookUrl → { bodies = { [страница] = JSON-тело }, totalPages = N }

local function chapterAjaxUrl(novelId, page)
    return baseUrl:gsub("/$", "") .. "/ajax-chapter-list?novelId=" .. novelId .. "&page=" .. tostring(page)
end

-- Одиночный AJAX-запрос страницы списка глав (один повтор против случайного 429).
-- Возвращает JSON-тело или nil.
local function fetchAjaxPage(novelId, page)
    local r = http_get(chapterAjaxUrl(novelId, page))
    if not r.success then
        sleep(math.random(600, 900))
        r = http_get(chapterAjaxUrl(novelId, page))
    end
    if not r.success then return nil end
    return r.body
end

-- Парсинг глав из JSON-тела AJAX-страницы.
local function parseChapters(jsonBody)
    local data = json_parse(jsonBody)
    if not data or not data.html then return {} end
    local chapters = {}
    for _, a in ipairs(html_select(data.html, "a[href*='/chapter-']")) do
        local title = a.title or ""
        if title == "" then title = a.text end
        local chUrl = absUrl(a.href)
        if chUrl ~= "" then
            table.insert(chapters, { title = string_clean(title), url = chUrl })
        end
    end
    return chapters
end

-- Первичная загрузка: страницы 1..totalPages тянутся пачками BURST_CHUNK,
-- тела складываются в _bursts[bookUrl], откуда движок раздаёт их
-- последовательными вызовами parsePage (см. empirenovel.lua — тот же приём).
local function burstLoad(bookUrl, novelId, totalPages)
    local bodies = {}
    local p = 1
    while p <= totalPages do
        local last = math.min(p + BURST_CHUNK - 1, totalPages)
        local urls = {}
        for i = p, last do urls[#urls + 1] = chapterAjaxUrl(novelId, i) end
        local rs = http_get_batch(urls)
        local failed = false
        for i, res in ipairs(rs) do
            if res.success then
                bodies[p + i - 1] = res.body
            else
                failed = true
            end
        end
        if failed then
            -- Однократный повтор неудачного чанка с паузой.
            sleep(math.random(600, 900))
            rs = http_get_batch(urls)
            for i, res in ipairs(rs) do
                if res.success then bodies[p + i - 1] = res.body end
            end
        end
        if last < totalPages then sleep(BURST_GAP_MS) end
        p = last + 1
    end
    _bursts[bookUrl] = { bodies = bodies, totalPages = totalPages }
end

function parsePage(bookUrl, page)
    -- Горячий путь: страница уже предзагружена burst-загрузкой.
    local burst = _bursts[bookUrl]
    if burst then
        local body = burst.bodies[page]
        if body then
            if page == burst.totalPages then _bursts[bookUrl] = nil end
            return { chapters = parseChapters(body), totalPages = burst.totalPages }
        end
    end

    -- Холодный путь: novelId и число страниц со страницы книги.
    local html = fetchBookPage(bookUrl)
    if not html then
        log_error("novelfull: parsePage failed to load " .. bookUrl)
        return { chapters = {}, totalPages = 1 }
    end

    local novelId = html_attr(html, "#list-chapter", "data-novel-id")
    if novelId == "" then novelId = html_attr(html, "#rating", "data-novel-id") end
    if novelId == "" then
        log_error("novelfull: novelId not found at " .. bookUrl)
        return { chapters = {}, totalPages = 1 }
    end

    local totalPages = tonumber(html_attr(html, "#list-chapter", "data-total-page")) or 1

    -- Первый вызов (первичная загрузка): тянем все страницы пачками.
    if page == 1 and totalPages > 1 then
        burstLoad(bookUrl, novelId, totalPages)
        local body = _bursts[bookUrl].bodies[1]
        if body then
            return { chapters = parseChapters(body), totalPages = totalPages }
        end
    end

    -- Вне очереди / обновление: одиночный свежий запрос; totalPages берём из
    -- ответа AJAX, чтобы движок увидел выросшее число страниц.
    local jsonBody = fetchAjaxPage(novelId, page)
    if not jsonBody then
        log_error("novelfull: chapters ajax failed page=" .. tostring(page))
        return { chapters = {}, totalPages = totalPages }
    end
    local data = json_parse(jsonBody)
    local freshTotal = data and tonumber(data.totalPage) or totalPages
    return { chapters = parseChapters(jsonBody), totalPages = freshTotal }
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
  -- trim + drop empties — shared meta lib (site order kept).
  return LIB("meta").collectGenres(html_select(html, ".m-info .item a.a1[href^='/genre/']"))
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
        local t = LIB("meta").status(a.text)
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
  -- Блок ".lastupdate": "[ Updated 19 hours ago ]" — относительная дата
  -- (абсолютной даты на странице книги novelfull.net нет)
  local el = html_select_first(html, ".lastupdate")
  if not el then return nil end
  local raw = string_clean(el.text)
  if string.match(raw, "just now") then
    return os.date("%Y-%m-%d")
  end
  -- "N minutes/hours/days ago" → YYYY-MM-DD (shared meta lib; месяцы/годы
  -- приблизительны — 30/365 дней, как и в прежнем локальном парсере).
  return LIB("meta").normalizeDate(raw)
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
  local page   = LIB("catalog").nextIndex(index)
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
