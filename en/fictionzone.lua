-- ── Метаданные ──
id       = "fictionzone"
name     = "Fiction Zone"
version  = "1.1.0"
baseUrl  = "https://fictionzone.net/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/fictionzone.png"

-- ── Хелперы ──

-- Все данные сайта отдаются через JSON API, спрятанный за POST-прокси
-- /api/__api_party/fictionzone (HTML-страницы закрыты Cloudflare, а прямые
-- GET к /platform/* отдают 404). Поэтому плагин ходит ТОЛЬКО через этот прокси.
local PROXY = baseUrl .. "api/__api_party/fictionzone"

-- Кэш деталей книги: 4 функции деталей вызываются движком параллельно с одним
-- bookUrl, а все вызовы одного плагина сериализованы через Mutex — кэш безопасен.
local _detailsCache = {}

-- absUrl: относительные ссылки -> абсолютные (требование AGENTS.md)
local function absUrl(href)
  if not href or href == "" then return "" end
  if href:match("^https?://") then return href end
  if href:match("^//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Универсальный GET к API через прокси. Возвращает payload (.data) или nil.
-- Полный текст главы сайт отдаёт только авторизованному пользователю: анонимный
-- запрос возвращает урезанное превью (~половину). Прокси прокидывает заголовок
-- authorization из тела на upstream, поэтому подставляем Bearer-токен из кук
-- пользователя (fz_access_token), когда он залогинен в NoveLA. Без токена
-- работаем анонимно (превью) — обратно-совместимо.
local function apiGet(path)
  local ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local headers = {
    { "content-type", "application/json" },
    { "x-request-time", ts },
  }
  local cookies = get_cookies(baseUrl)
  local token = cookies and cookies["fz_access_token"] or ""
  if token ~= "" then
    headers[#headers + 1] = { "authorization", "Bearer " .. token }
  end
  local body = json_stringify({
    path = path,
    headers = headers,
    method = "GET",
  })
  local r = http_post(PROXY, body, {
    headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json",
    },
  })
  if not r.success then
    log_error("fictionzone: API request failed: " .. path)
    return nil
  end
  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return nil end
  return parsed.data
end

-- Детали книги по bookUrl (novel/<slug>). Результат кэшируется по slug.
local function getDetails(bookUrl)
  local slug = bookUrl:match("novel/(.+)")
  if not slug then return nil end
  slug = slug:gsub("/.*", "") -- убираем всё после слэша (query/ trailing), если движок что-то добавил
  if _detailsCache[slug] then return _detailsCache[slug] end
  local data = apiGet("/platform/novel-details?slug=" .. slug)
  if data then _detailsCache[slug] = data end
  return data
end

-- Обложка Fiction Zone лежит на img.fictionzone.net, который не резолвится.
-- Рабочий вариант — CDN imageproxy: cdn.fictionzone.net/insecure/rs:fill:300:400/<base64>.webp
-- (увеличенное разрешение для чёткости в каталоге/поиске/деталях)
local function coverUrl(imageB64)
  if not imageB64 or imageB64 == "" then return nil end
  return "https://cdn.fictionzone.net/insecure/rs:fill:300:400/" .. imageB64 .. ".webp"
end

-- ── Каталог ──

function getCatalogList(index)
  local page = index + 1
  local data = apiGet("/platform/browse?page=" .. page
    .. "&page_size=20&sort_by=bookmark_count&sort_order=desc&include_genres=true")
  if not data then return { items = {}, hasNext = false } end

  local items = {}
  for _, n in ipairs(data.novels) do
    items[#items + 1] = {
      title  = n.title,
      url    = absUrl("novel/" .. n.slug),
      cover  = coverUrl(n.image),
      rating = n.rating,
    }
  end
  return { items = items, hasNext = data.pagination.has_next }
end

function getCatalogSearch(index, query)
  local page = index + 1
  local data = apiGet("/platform/browse?search=" .. url_encode(query)
    .. "&page=" .. page
    .. "&page_size=20&search_in_synopsis=true&sort_by=bookmark_count&sort_order=desc&include_genres=true")
  if not data then return { items = {}, hasNext = false } end

  local items = {}
  for _, n in ipairs(data.novels) do
    items[#items + 1] = {
      title  = n.title,
      url    = absUrl("novel/" .. n.slug),
      cover  = coverUrl(n.image),
      rating = n.rating,
    }
  end
  return { items = items, hasNext = data.pagination.has_next }
end

-- ── Фильтры ──

-- Серверная фильтрация: genre_ids (включение жанров), tag_ids (включение тегов),
-- exclude_tag_ids (исключение тегов) и sort_by. status/type/origin_language API
-- игнорирует (фильтруются на клиенте сайта) — в плагине их нет.
-- Для checkbox движок передаёт значения в filters[key .. "_included"] (массив).
-- ВАЖНО: API принимает несколько значений ОДНИМ параметром через запятую
-- (tag_ids=1,2,3 — логическое ИЛИ), а не повтором параметра: повтор
-- (&tag_ids=1&tag_ids=2) учитывает только первое значение и ломает мульти-выбор.
local function joinIds(vals)
  if type(vals) == "table" then
    local t = {}
    for _, v in ipairs(vals) do t[#t + 1] = tostring(v) end
    return table.concat(t, ",")
  elseif type(vals) == "string" and vals ~= "" then
    return vals
  end
  return nil
end

function getFilterList()
  local filters = {
    {
      type       = "select",
      key        = "sort",
      label      = "Sort",
      defaultValue = "bookmark_count",
      options = {
        { value = "bookmark_count", label = "Most Bookmarked" },
        { value = "created_at",     label = "Latest" },
        { value = "rating",         label = "Top Rated" },
        { value = "chapter_count",  label = "Most Chapters" },
        { value = "review_count",   label = "Most Reviews" },
      },
    },
    {
      type        = "checkbox",
      key         = "genre",
      label       = "Genre",
      multiselect = true,
      options = {
        { value = "3", label = "Fan-Fiction" },
        { value = "1", label = "Fantasy" },
        { value = "8", label = "Romance" },
        { value = "6", label = "Sci-Fi" },
        { value = "2", label = "Urban" },
        { value = "7", label = "Virtual Reality" },
      },
    },
  }

  -- Теги (их ~90) берём динамически из API, чтобы не хардкодить список.
  local tagsData = apiGet("/platform/tags")
  if tagsData then
    local includeOpts = {}
    local excludeOpts = {}
    for _, t in ipairs(tagsData) do
      local opt = { value = tostring(t.id), label = t.name }
      includeOpts[#includeOpts + 1] = opt
      excludeOpts[#excludeOpts + 1] = opt
    end
    filters[#filters + 1] = {
      type        = "checkbox",
      key         = "tag",
      label       = "Tags (include)",
      multiselect = true,
      options     = includeOpts,
    }
    filters[#filters + 1] = {
      type        = "checkbox",
      key         = "tag_exclude",
      label       = "Tags (exclude)",
      multiselect = true,
      options     = excludeOpts,
    }
  end

  return filters
end

function getCatalogFiltered(index, filters)
  local page = index + 1
  local sort = filters["sort"] or "bookmark_count"
  local path = "/platform/browse?page=" .. page
    .. "&page_size=20&sort_by=" .. sort .. "&sort_order=desc&include_genres=true"

  local g = joinIds(filters["genre_included"] or filters["genre"])
  if g then path = path .. "&genre_ids=" .. g end

  local incl = joinIds(filters["tag_included"] or filters["tag"])
  if incl then path = path .. "&tag_ids=" .. incl end

  local excl = joinIds(filters["tag_exclude_included"] or filters["tag_exclude"])
  if excl then path = path .. "&exclude_tag_ids=" .. excl end

  local data = apiGet(path)
  if not data then return { items = {}, hasNext = false } end

  local items = {}
  for _, n in ipairs(data.novels) do
    items[#items + 1] = {
      title  = n.title,
      url    = absUrl("novel/" .. n.slug),
      cover  = coverUrl(n.image),
      rating = n.rating,
    }
  end
  return { items = items, hasNext = data.pagination.has_next }
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
  local d = getDetails(bookUrl)
  if not d then return nil end
  return string_clean(d.title)
end

function getBookCoverImageUrl(bookUrl)
  local d = getDetails(bookUrl)
  if not d then return nil end
  return coverUrl(d.image)
end

function getBookDescription(bookUrl)
  local d = getDetails(bookUrl)
  if not d then return nil end
  return string_trim(d.synopsis)
end

function getBookGenres(bookUrl)
  local d = getDetails(bookUrl)
  if not d then return nil end
  local out = {}
  if d.genres then
    for _, g in ipairs(d.genres) do out[#out + 1] = g.name end
  end
  if d.tags then
    for _, t in ipairs(d.tags) do out[#out + 1] = t.name end
  end
  return out
end

function getBookRating(bookUrl)
  local d = getDetails(bookUrl)
  if not d or d.rating == nil then return nil end
  return tostring(d.rating)
end

function getBookStatus(bookUrl)
  local d = getDetails(bookUrl)
  if not d then return nil end
  local s = d.status
  if s == 1 then return "Ongoing" end
  if s == 0 then return "Completed" end
  return "Unknown"
end

function getBookLastUpdate(bookUrl)
  local d = getDetails(bookUrl)
  if not d or not d.chapter_last_created_at then return nil end
  local ts = d.chapter_last_created_at
  -- поле приходит либо строкой "YYYY-MM-DD HH:MM:SS", либо unix-временем (число)
  if type(ts) == "number" then
    return os.date("!%Y-%m-%d", ts)
  end
  return string.sub(tostring(ts), 1, 10)
end

-- ── Список глав ──

-- Контент главы отдаётся ТОЛЬКО через POST-прокси, а прямой GET по fictionzone.net
-- триггерит Cloudflare. Поэтому url главы указывает на реальную страницу книги
-- (движок её префетчит и вызывает getChapterText), а id книги и главы кодируем
-- в query (?c=<novel_id>.<chapter_id>), чтобы getChapterText сам догрузил текст.
function getChapterList(bookUrl)
  local slug = bookUrl:match("novel/(.+)")
  if slug then slug = slug:gsub("/.*", "") end
  local d = getDetails(bookUrl)
  if not d or not d.id then return {} end
  local nid = d.id
  local data = apiGet("/platform/chapter-lists?novel_id=" .. nid)
  if not data then return {} end

  local items = {}
  for _, c in ipairs(data.chapters) do
    items[#items + 1] = {
      title = c.title,
      url   = baseUrl .. "novel/" .. slug .. "?c=" .. nid .. "." .. c.chapter_id,
    }
  end
  return items
end

-- Быстрый детект новых глав: url последней главы. Без кэша (прямой запрос).
function getChapterListHash(bookUrl)
  local slug = bookUrl:match("novel/(.+)")
  if slug then slug = slug:gsub("/.*", "") end
  local d = getDetails(bookUrl)
  if not d or not d.id then return nil end
  local nid = d.id
  local data = apiGet("/platform/chapter-lists?novel_id=" .. nid)
  if not data or not data.chapters or #data.chapters == 0 then return nil end
  local last = data.chapters[#data.chapters]
  return baseUrl .. "novel/" .. slug .. "?c=" .. nid .. "." .. last.chapter_id
end

-- ── Текст главы ──

function getChapterText(html, url)
  local nid, cid = url:match("c=(%d+)%.(%d+)")
  if not nid or not cid then
    nid, cid = url:match("/r/(%d+)/(%d+)")
  end
  if not nid or not cid then
    log_error("fictionzone: cannot parse chapter url: " .. tostring(url))
    return ""
  end
  local data = apiGet("/platform/chapter-content?novel_id=" .. nid .. "&chapter_id=" .. cid)
  if not data or not data.content then return "" end

  -- content — чистый текст с переносами строк. Движок отображает результат
  -- getChapterText как ТЕКСТ, сохраняя переносы строк (как в syosetu/novelhi/
  -- novelight и др. — они возвращают html_text, а не оборачивают в <p>).
  -- Поэтому НЕ заворачиваем в <p>: иначе движок снимет теги, а вместе с ними
  -- и все переносы строк, и текст превратится в сплошную стену.
  -- Возвращаем текст с реальными \n между абзацами.
  local content = data.content
  content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
  content = string_normalize(content)

  -- В конец залогиненного контента сайт подклеивает рекламную вставку с
  -- акцией ("...Recharge 100 and get 500 VIP coupons!...Immediate recharge..."),
  -- название праздника меняется (Dragon Boat Festival / Ching Ming и т.п.), но
  -- якорные строки "Recharge N and get N VIP coupons" и "Immediate recharge"
  -- стабильны. (?m) — ^/$ на каждой строке, поэтому вычищаем всю строку с
  -- якорем где бы тот ни стоял; вставка всегда в конце. Авторский текст с
  -- однокоренным "recharge" (без "VIP coupons") не затрагивается.
  content = regex_replace(content, "(?m)^.*Recharge \\d+ and get \\d+ VIP coupons.*\\n?", "")
  content = regex_replace(content, "(?m)^.*Immediate recharge.*\\n?", "")

  local paras = {}
  for line in content:gmatch("[^\n]+") do
    local t = string_trim(line)
    if t ~= "" then
      paras[#paras + 1] = t
    end
  end
  return table.concat(paras, "\n\n")
end
