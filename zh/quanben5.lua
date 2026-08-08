-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "quanben5"
name     = "Quanben5"
version  = "1.0.2"
baseUrl  = "https://big5.quanben5.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/quanben5.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Нормализация URL книги: сайт отдаёт 404, если у /n/<slug> нет завершающего
-- слэша (https://big5.quanben5.com/n/yishixiejun → 404, .../n/yishixiejun/ → 200).
-- Движок может обрезать trailing slash при сохранении URL, поэтому добавляем его
-- обратно для путей книг (но не трогаем ссылки на главы с расширением .html).
local function normalizeBookUrl(url)
  if not url or url == "" then return url end
  if string_ends_with(url, ".html") then return url end
  if string_ends_with(url, "/") then return url end
  return url .. "/"
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((第[\\d一二三四五六七八九十百]+[章节]|Chapter\\s+\\d+|Глава\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
text = regex_replace(text, "(?im)^\\s*(翻译|译者|编辑|校对|更新|阅读|最新阅读)[:\\s：][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Кастомный base64 (аналог JS-кодирования сайта) ───────────────────────────
--
-- Алгоритм из JavaScript quanben5.com:
--   staticChars = "PXhw7UT1B0a9kQDKZsjIASmOezxYG4CHo5Jyfg2b8FLpEvRr3WtVnlqMidu6cN"
--   Для каждого символа строки:
--     num0 = indexOf(char) в staticChars
--     если найден → код = staticChars[(num0+3) % 62], иначе код = char
--     добавляем: rand_char + код + rand_char
--
-- Важно: rand_char тоже из staticChars — но при декодировании на сервере
-- они игнорируются (каждый второй символ — полезный).
-- Для детерминированности используем фиксированный "случайный" символ: staticChars[0] = 'P'

local STATIC_CHARS = "PXhw7UT1B0a9kQDKZsjIASmOezxYG4CHo5Jyfg2b8FLpEvRr3WtVnlqMidu6cN"

local function customBase64Encode(str)
  local result = {}
  for i = 1, #str do
    local char = str:sub(i, i)
    local num0 = STATIC_CHARS:find(char, 1, true)
    local code
    if num0 then
      -- Lua: find возвращает 1-based индекс → конвертируем в 0-based для % 62
      local idx0 = num0 - 1
      local newIdx = (idx0 + 3) % 62
      code = STATIC_CHARS:sub(newIdx + 1, newIdx + 1)
    else
      code = char
    end
    -- Вместо случайного символа используем 'P' (первый в staticChars)
    table.insert(result, "P")
    table.insert(result, code)
    table.insert(result, "P")
  end
  return table.concat(result)
end

-- encodeURI: кодирует строку как JavaScript encodeURI
-- Не кодирует: буквы, цифры, ; , / ? : @ & = + $ # - _ . ! ~ * ' ( )
-- Кодирует пробел как %20, % как %25, китайские символы как %XX%XX%XX
local function encodeURI(input)
  local result = {}
  -- Используем url_encode и потом декодируем то, что не надо кодировать
  -- Проще: итерируем побайтово
  local bytes = {}
  for i = 1, #input do
    bytes[i] = input:byte(i)
  end
  local i = 1
  while i <= #bytes do
    local b = bytes[i]
    local char = string.char(b)
    -- Не кодируем: ASCII буквы, цифры, и специальные символы как в encodeURI
    if (b >= 65 and b <= 90) or   -- A-Z
       (b >= 97 and b <= 122) or  -- a-z
       (b >= 48 and b <= 57) or   -- 0-9
       char == "-" or char == "_" or char == "." or char == "!" or
       char == "~" or char == "*" or char == "'" or char == "(" or
       char == ")" or char == ";" or char == "," or char == "/" or
       char == "?" or char == ":" or char == "@" or char == "&" or
       char == "=" or char == "+" or char == "$" or char == "#" then
      table.insert(result, char)
    else
      table.insert(result, string.format("%%%02X", b))
    end
    i = i + 1
  end
  return table.concat(result)
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url
  if page == 1 then
    url = baseUrl .. "category/1.html"
  else
    url = baseUrl .. "category/1_" .. tostring(page) .. ".html"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".pic_txt_list")) do
    local titleEl = html_select_first(card.html, "h3 a")
    if titleEl then
      local bookUrl = normalizeBookUrl(absUrl(titleEl.href))
      local cover   = html_attr(card.html, ".pic img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск (JSONP API с кастомным base64) ─────────────────────────────────────

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  -- Шаг 1: encodeURI(query)
  local encodedKeywords = encodeURI(query)
  -- Шаг 2: customBase64(encodeURI(query))
  local b64 = customBase64Encode(encodedKeywords)
  -- Шаг 3: encodeURI(base64result) → b параметр
  local bParam = encodeURI(b64)
  local timestamp = tostring(os_time())

  local searchUrl = baseUrl .. "?c=book&a=search.json&callback=search&t=" .. timestamp
    .. "&keywords=" .. encodedKeywords .. "&b=" .. bParam

  local r = http_get(searchUrl, {
    headers = { ["Referer"] = baseUrl .. "search.html" }
  })
  if not r.success then return { items = {}, hasNext = false } end

  -- Парсим JSONP: search({...})
  -- Ищем "content":"<html>" внутри
  local jsonBody = r.body
  local contentStart = jsonBody:find('"content":"', 1, true)
  if not contentStart then return { items = {}, hasNext = false } end

  local valueStart = contentStart + 11  -- длина '"content":"'
  -- Ищем конец строки (незаэкранированную кавычку)
  local valueEnd = valueStart
  while valueEnd <= #jsonBody do
    local c = jsonBody:sub(valueEnd, valueEnd)
    if c == '"' and jsonBody:sub(valueEnd - 1, valueEnd - 1) ~= '\\' then
      break
    end
    valueEnd = valueEnd + 1
  end

  local htmlContent = jsonBody:sub(valueStart, valueEnd - 1)
  -- Убираем экранирование
  htmlContent = htmlContent:gsub('\\"', '"'):gsub('\\/', '/'):gsub('\\n', '\n')
  -- Декодируем \uXXXX через встроенный API
  htmlContent = unescape_unicode(htmlContent)

  local items = {}
  for _, card in ipairs(html_select(htmlContent, ".pic_txt_list")) do
    local titleEl = html_select_first(card.html, "h3 a")
    if titleEl then
      local href = titleEl.href
      if href == "" then href = html_attr(card.html, "h3 a", "href") end
      local bookUrl = normalizeBookUrl(absUrl(href))
      local cover   = html_attr(card.html, ".pic img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = false }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local src = html_attr(r.body, ".box .pic img", "src")
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  local cleaned = html_remove(r.body, ".box .description h2")
  local el = html_select_first(cleaned, ".box .description")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Список глав (отдельная страница /xiaoshuo.html) ───────────────────────────

function getChapterList(bookUrl)
  local chaptersUrl = normalizeBookUrl(bookUrl):gsub("/?$", "") .. "/xiaoshuo.html"

  local r = http_get(chaptersUrl)
  if not r.success then
    log_error("quanben5 getChapterList: failed " .. chaptersUrl)
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "ul.list li a")) do
    local chUrl = absUrl(a.href)
    local t = string_trim(a.text)
    if chUrl ~= "" then
      table.insert(chapters, { title = t, url = chUrl })
    end
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(normalizeBookUrl(bookUrl))
  if not r.success then return nil end
  -- Берём href последней главы из списка на странице книги
  local els = html_select(r.body, "ul.list li a")
  if #els > 0 then
    return els[#els].href
  end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "#ad", "script", "style")
  local el = html_select_first(cleaned, "#content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end