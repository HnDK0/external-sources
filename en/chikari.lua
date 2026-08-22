-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "chikari"
name     = "Chikari"
version  = "1.0.9"
baseUrl  = "https://chikari.moe/"
language = "en"
icon     = "https://chikari.moe/icon-192.png"

-- Chikari — текстовые новеллы. Движок сайта отличается от раздела картинок
-- (/api/series, где контент — массив изображений); текстовые новеллы живут в
-- /api/novels. Все данные (каталог, поиск, фильтры, карточка, список глав и
-- текст главы) берутся из этого JSON API.

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Chikari — SPA на SvelteKit; все /api/* — AJAX-эндпоинты. Чтобы Cloudflare и
-- сервер трактовали запрос как легитимный браузерный fetch (а не бот-запрос,
-- который зависает/челленджится и даёт SocketTimeout 30s), шлём те же заголовки,
-- что реальный фронтенд: Accept: application/json + Sec-Fetch-* / Origin.
-- User-Agent / Referer / Accept-Language движок добавляет сам — не дублируем.
-- Только легитимные заголовки: API требует Accept + Origin. Sec-Fetch-* убраны —
-- это браузерные заголовки, нативный клиент их слать не должен; их наличие при
-- не-браузерном TLS/HTTP2-отпечатке повышает бот-скор Cloudflare и провоцирует
-- транзистные сбросы HTTP/2-стрима (StreamResetException: CANCEL).
local API_HEADERS = {
  Accept = "application/json",
  Origin = "https://chikari.moe",
}

-- Каталог/поиск/карточка грузят страницы последовательно; Cloudflare
-- иногда сбрасывает HTTP/2-стрим одного из подряд идущих запросов
-- (StreamResetException: CANCEL, ~30с висяка). Это транзитная ошибка,
-- не связанная с заголовками (те корректны — см. API_HEADERS, подтверждено
-- живым логом: offset=0/60 отдают 200). Делаем ограниченный повтор, чтобы
-- пагинация не ломалась на случайном сбое стрима.
local function fetchJson(url)
  local lastErr = nil
  for attempt = 1, 3 do
    local r = http_get(url, { headers = API_HEADERS })
    if r.success then
      local bodyLen = r.body and #r.body or 0
      log_info("[chikari] fetchJson OK url=" .. tostring(url)
               .. " code=" .. tostring(r.code) .. " bodyLen=" .. bodyLen
               .. " attempt=" .. attempt
               .. " head=" .. (r.body and r.body:sub(1, 200) or ""))
      return json_parse(r.body)
    end
    lastErr = r.error
    log_error("[chikari] fetchJson FAIL url=" .. tostring(url)
              .. " code=" .. tostring(r.code) .. " err=" .. tostring(r.error)
              .. " attempt=" .. attempt)
    if attempt < 3 then sleep(500) end
  end
  log_error("[chikari] fetchJson GAVE UP url=" .. tostring(url) .. " err=" .. tostring(lastErr))
  return nil
end

-- bookUrl может прийти как "shadow-slave" или как полный URL — берём последний сегмент
local function novelSlug(bookUrl)
  return bookUrl:match("([^/]+)/?$")
end

-- Кэш карточки новеллы в рамках одного вызова (getBook* дёргаются по отдельности)
local _detailCache = {}
local function getDetail(bookUrl)
  if _detailCache[bookUrl] then return _detailCache[bookUrl] end
  local slug = novelSlug(bookUrl)
  if not slug then return nil end
  local d = fetchJson(baseUrl .. "api/novels/" .. slug)
  _detailCache[bookUrl] = d
  return d
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Каталог ────────────────────────────────────────────────────────────────────

local function buildItems(d)
  local items = {}
  if not d or not d.items then return items end
  for _, it in ipairs(d.items) do
    items[#items + 1] = {
      title  = string_clean(it.title or ""),
      url    = it.slug and absUrl("/novel/" .. it.slug) or "",
      cover  = it.cover_url or "",
      -- Рейтинг у Chikari в шкале 0-10. Движок принимает строку
      -- "значение/max" (как ranobelib.lua): голое число "9.5" он считает
      -- шкалой 0-5 и прячет карточку, поэтому явно добавляем "/10".
      rating = it.rating and (tostring(it.rating) .. "/10") or nil,
    }
  end
  return items
end

local function hasNext(d, offset, fetched)
  local total = d and d.total or 0
  return (offset + fetched) < total
end

function getCatalogList(index)
  index = index or 0
  -- Пауза перед запросом: сброс стрима прилетал на 3-й подряд идущий запрос
  -- (бот-эвристика CF копит скор по запросам с одного клиента). 200мс снижают
  -- шанс триггера, латентность незаметна.
  sleep(200)
  local limit = 60
  local offset = index * limit
  local url = baseUrl .. "api/novels?sort=popular&limit=" .. limit .. "&offset=" .. offset
  local d = fetchJson(url)
  local items = buildItems(d)
  return { items = items, hasNext = hasNext(d, offset, #items) }
end

function getCatalogSearch(index, query)
  index = index or 0
  local limit = 36
  local offset = index * limit
  local url = baseUrl .. "api/novels?sort=popular&q=" .. url_encode(query) .. "&limit=" .. limit .. "&offset=" .. offset
  local d = fetchJson(url)
  local items = buildItems(d)
  return { items = items, hasNext = hasNext(d, offset, #items) }
end

-- ── Фильтры ────────────────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort By",
      defaultValue = "popular",
      options = {
        { value = "popular",         label = "Popular" },
        { value = "trending",        label = "Trending" },
        { value = "top_rated",       label = "Top Rated" },
        { value = "updated",         label = "Recently Updated" },
        { value = "added",           label = "Recently Added" },
        { value = "most_bookmarked", label = "Most Bookmarked" },
      },
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",          label = "All" },
        { value = "releasing", label = "Ongoing" },
        { value = "completed", label = "Completed" },
        { value = "hiatus",    label = "On Hiatus" },
        { value = "cancelled", label = "Cancelled" },
      },
    },
    {
      type        = "checkbox",
      key         = "genres",
      label       = "Genres",
      multiselect = true,
      options = {
        { value = "action",        label = "Action" },
        { value = "adventure",     label = "Adventure" },
        { value = "comedy",        label = "Comedy" },
        { value = "drama",         label = "Drama" },
        { value = "ecchi",         label = "Ecchi" },
        { value = "fantasy",       label = "Fantasy" },
        { value = "gender_bender", label = "Gender Bender" },
        { value = "harem",         label = "Harem" },
        { value = "historical",    label = "Historical" },
        { value = "horror",        label = "Horror" },
        { value = "josei",         label = "Josei" },
        { value = "martial_arts",  label = "Martial Arts" },
        { value = "mature",        label = "Mature" },
        { value = "mecha",         label = "Mecha" },
        { value = "mystery",       label = "Mystery" },
        { value = "psychological", label = "Psychological" },
        { value = "romance",       label = "Romance" },
        { value = "school_life",   label = "School Life" },
        { value = "sci-fi",        label = "Sci-Fi" },
        { value = "seinen",        label = "Seinen" },
        { value = "shoujo",        label = "Shoujo" },
        { value = "shoujo_ai",     label = "Shoujo Ai" },
        { value = "shounen",       label = "Shounen" },
        { value = "shounen_ai",    label = "Shounen Ai" },
        { value = "slice_of_life", label = "Slice of Life" },
        { value = "sports",        label = "Sports" },
        { value = "supernatural",  label = "Supernatural" },
        { value = "tragedy",       label = "Tragedy" },
        { value = "yaoi",          label = "Yaoi" },
        { value = "yuri",          label = "Yuri" },
      },
    },
  }
end

function getCatalogFiltered(index, filters)
  index = index or 0
  filters = filters or {}
  local limit = 60
  local offset = index * limit
  local sort = filters["sort"] or "popular"
  local url = baseUrl .. "api/novels?sort=" .. url_encode(sort) .. "&limit=" .. limit .. "&offset=" .. offset
  local status = filters["status"]
  if status and status ~= "" then
    url = url .. "&status=" .. url_encode(status)
  end
  local genres = filters["genres_included"] or {}
  for _, g in ipairs(genres) do
    if g and g ~= "" then
      url = url .. "&genre=" .. url_encode(g)
    end
  end
  local d = fetchJson(url)
  local items = buildItems(d)
  return { items = items, hasNext = hasNext(d, offset, #items) }
end

-- ── Карточка книги ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local d = getDetail(bookUrl)
  if not d then return nil end
  return d.title
end

function getBookCoverImageUrl(bookUrl)
  local d = getDetail(bookUrl)
  if not d then return nil end
  return d.cover_url
end

function getBookDescription(bookUrl)
  local d = getDetail(bookUrl)
  if not d then return nil end
  return d.description
end

function getBookGenres(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.genres then return nil end
  local names = {}
  for _, g in ipairs(d.genres) do
    names[#names + 1] = g.name
  end
  return table.concat(names, ", ")
end

function getBookStatus(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.status then return nil end
  local map = {
    releasing = "Ongoing",
    completed = "Completed",
    hiatus    = "On Hiatus",
    cancelled = "Cancelled",
  }
  return map[d.status] or d.status
end

function getBookRating(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.rating then return nil end
  return tostring(d.rating) .. "/10"
end

function getBookLastUpdate(bookUrl)
  local d = getDetail(bookUrl)
  if not d or not d.last_chapter_at then return nil end
  local y, m, day = string.match(d.last_chapter_at, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return nil end
  return y .. "-" .. m .. "-" .. day
end

-- ── Список глав ────────────────────────────────────────────────────────────────
-- API отдаёт главы пачками (по возрастанию). Лимит 500 — берём весь список
-- одним запросом (ответ ~70KB, отдаётся <1с).

function getChapterList(bookUrl)
  local slug = novelSlug(bookUrl)
  log_info("[chikari] getChapterList bookUrl=" .. tostring(bookUrl) .. " slug=" .. tostring(slug))
  if not slug then return {} end
  local chapters = {}
  local limit = 500
  local offset = 0
  while true do
    local url = baseUrl .. "api/novels/" .. slug .. "/chapters?order=asc&limit=" .. limit .. "&offset=" .. offset
    local d = fetchJson(url)
    local got = (d and d.items) and #d.items or 0
    log_info("[chikari] getChapterList page offset=" .. offset .. " got=" .. got .. " items")
    if not d or not d.items then
      log_error("[chikari] getChapterList BREAK url=" .. url .. " d=" .. (d and "no-items" or "nil"))
      break
    end
    for _, ch in ipairs(d.items) do
      local num = math.floor(ch.number or 0)
      chapters[#chapters + 1] = {
        title = string_clean(ch.title or ("Chapter " .. num)),
        url   = baseUrl .. "api/novels/" .. slug .. "/chapters/" .. num .. "/read",
      }
    end
    if #d.items < limit then break end
    offset = offset + limit
    sleep(100)
  end
  log_info("[chikari] getChapterList DONE total=" .. #chapters)
  return chapters
end

-- ── Текст главы ────────────────────────────────────────────────────────────────
-- Контент главы приходит с /api/novels/<slug>/chapters/<num>/read в поле body
-- (чистый текст, абзацы разделены \n). Движок может передать уже скачанный
-- JSON в html, иначе догружаем сами по url.

function getChapterText(html, url)
  local data = nil
  if html and #html > 0 and html:sub(1, 1) == "{" then
    data = json_parse(html)
  else
    local r = http_get(url, { headers = API_HEADERS })
    if not r.success then return "" end
    data = json_parse(r.body)
  end
  if not data or not data.body then return "" end

  -- Тело главы — чистый текст с \n между абзацами. Движок рендерит
  -- getChapterText как plain text (конвенция репо: все плагины отдают
  -- applyStandardContentTransforms(html_text(...))), поэтому возвращаем
  -- текст как есть. Обёртка в <p> ломает отображение: теги либо видны
  -- как есть, либо схлопываются в одну простыню без переносов.
  return applyStandardContentTransforms(data.body)
end
