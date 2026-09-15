-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "mangalib"
name     = "MangaLib"
version  = "1.7.1"
baseUrl  = "https://mangalib.me/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/mangalib.png"
content_type = "manga"

-- MangaLib — манга на русском (LibGroup, api.cdnlibs.org).
-- Клон RanobeLib с siteId=1 для манги вместо ранобе.
-- Авторизация: Bearer Token (опционально, для 18+ контента).

local apiBase  = "https://api.cdnlibs.org/api/manga/"
local siteId   = "1"
local apiHeaders = {
  ["Site-Id"]          = siteId,
  ["User-Agent"]       = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36",
  ["Accept"]           = "application/json, text/plain, */*",
  ["Accept-Language"]  = "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
  ["Referer"]          = "https://mangalib.me/",
  ["Origin"]           = "https://mangalib.me",
  ["Sec-Fetch-Dest"]   = "empty",
  ["Sec-Fetch-Mode"]   = "cors",
  ["Sec-Fetch-Site"]   = "cross-site",
}

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function normalizeCover(raw)
  if not raw or raw == "" then return "" end
  if string_starts_with(raw, "//")   then return "https:" .. raw end
  if string_starts_with(raw, "http") then return raw end
  return "https://" .. raw
end

local function proxyCover(raw)
  if not raw or raw == "" then return "" end
  local url = normalizeCover(raw)
  return "https://images.weserv.nl/?url=" .. url:gsub("^https?://", "")
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)(?:^|\\n)[^<\\n]*" .. domain .. ".*?\\n", "\n")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = string_trim(text)
  return text
end

local function pickTitle(data)
  return data.rus_name or data.eng_name or data.name or ""
end

local function extractSlug(bookUrl)
  local clean = bookUrl:gsub("/?$", "")
  local last = clean:match("([^/]+)$")
  if not last then return nil end
  -- Handle "123--slug" and "manga--slug" format → strip prefix
  return last:match("%-%-(.+)$") or last
end

local function getPath(tbl, path)
  if not tbl or not path then return nil end
  local cur = tbl
  for key in path:gmatch("[^.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[key]
  end
  return cur
end

local function formatRating(avg)
  if not avg or avg == "" or avg == "0" then return nil end
  return avg .. "/10"
end

local function isErrorResponse(body)
  if not body or body == "" then return true end
  if body:sub(1, 15):find("<!DOCTYPE") or body:sub(1, 6):lower():find("<html") then
    return true
  end
  return false
end

-- ── Каталог (JSON API) ────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = apiBase .. "?site_id[0]=" .. siteId ..
              "&page=" .. tostring(page) ..
              "&sort_by=rating_score&sort_type=desc&chapters[min]=1"

  local r = http_get(url, { headers = apiHeaders })
  if not r.success then return { items = {}, hasNext = false } end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return { items = {}, hasNext = false } end

  local items = {}
  for _, manga in ipairs(parsed.data) do
    local title = pickTitle(manga)
    local slug  = manga.slug or manga.slug_url or ""
    local cover = getPath(manga, "cover.default") or ""
    if title ~= "" and slug ~= "" then
      local item = {
        title = string_clean(title),
        url   = baseUrl .. "ru/" .. slug,
        cover = proxyCover(cover)
      }
      local avg = getPath(manga, "rating.average")
      item.rating = formatRating(avg)
      table.insert(items, item)
    end
  end

  local hasNext = getPath(parsed, "meta.has_next_page")
  return { items = items, hasNext = hasNext == true or #items > 0 }
end

-- ── Поиск (JSON API) ──────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local url = apiBase .. "?site_id[0]=" .. siteId ..
              "&page=" .. tostring(page) ..
              "&q=" .. url_encode(query)

  local r = http_get(url, { headers = apiHeaders })
  if not r.success then return { items = {}, hasNext = false } end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return { items = {}, hasNext = false } end

  local items = {}
  for _, manga in ipairs(parsed.data) do
    local title = pickTitle(manga)
    local slug  = manga.slug_url or manga.slug or ""
    local cover = getPath(manga, "cover.default") or ""
    if title ~= "" and slug ~= "" then
      local item = {
        title = string_clean(title),
        url   = baseUrl .. "ru/" .. slug,
        cover = proxyCover(cover)
      }
      local avg = getPath(manga, "rating.average")
      item.rating = formatRating(avg)
      table.insert(items, item)
    end
  end

  local hasNext = getPath(parsed, "meta.has_next_page")
  return { items = items, hasNext = hasNext == true }
end

-- ── Детали книги (JSON API /api/manga/{slug}) ─────────────────────────────────

local function fetchBookJson(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return nil end
  local r = http_get(apiBase .. slug, { headers = apiHeaders })
  if not r.success then return nil end
  if isErrorResponse(r.body) then return nil end
  local parsed = json_parse(r.body)
  return parsed and parsed.data or nil
end

function getBookTitle(bookUrl)
  local data = fetchBookJson(bookUrl)
  if not data then return nil end
  local names = data.names
  local title
  if names then
    title = names.rus or names.eng or data.rus_name or data.name
  else
    title = data.rus_name or data.eng_name or data.name
  end
  return title and string_clean(title) or nil
end

function getBookCoverImageUrl(bookUrl)
  local data = fetchBookJson(bookUrl)
  if not data then return nil end
  local cover = getPath(data, "cover.default") or ""
  return cover ~= "" and proxyCover(cover) or nil
end

local function extractTextFromTipTap(node)
  if not node then return "" end
  if type(node) == "string" then return node end
  if type(node) ~= "table" then return "" end
  local parts = {}
  if node.type == "text" then
    table.insert(parts, node.text or "")
  end
  if node.content and type(node.content) == "table" then
    for _, child in ipairs(node.content) do
      table.insert(parts, extractTextFromTipTap(child))
    end
  end
  return table.concat(parts, "")
end

local mangaDetailFields = "fields[]=eng_name&fields[]=otherNames&fields[]=summary&fields[]=rate&fields[]=genres&fields[]=tags&fields[]=teams&fields[]=authors&fields[]=publisher&fields[]=userRating&fields[]=manga_status_id&fields[]=status_id&fields[]=artists"

function getBookDescription(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return nil end
  local r = http_get(apiBase .. slug .. "?" .. mangaDetailFields, { headers = apiHeaders })
  if not r.success then return nil end
  if isErrorResponse(r.body) then return nil end
  local parsed = json_parse(r.body)
  local data = parsed and parsed.data
  if not data then return nil end
  local summary = data.summary
  if summary and type(summary) == "table" then
    local desc = extractTextFromTipTap(summary)
    if string_trim(desc) ~= "" then return string_trim(desc) end
  elseif summary and type(summary) == "string" then
    if string_trim(summary) ~= "" then return string_trim(summary) end
  end
  return nil
end

function getBookGenres(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return {} end

  local r = http_get(
    apiBase .. slug .. "?fields[]=genres&fields[]=tags",
    { headers = apiHeaders }
  )
  if not r.success then return {} end

  local parsed = json_parse(r.body)
  local data = parsed and parsed.data
  if not data then return {} end

  local genres = {}
  local function addList(list)
    if not list then return end
    for _, item in ipairs(list) do
      local label = item.name or ""
      label = string_trim(label)
      if label ~= "" then table.insert(genres, label) end
    end
  end

  addList(data.genres)
  addList(data.tags)

  return genres
end

function getBookRating(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return nil end

  local r = http_get(
    apiBase .. slug .. "?fields[]=rate_avg&fields[]=rate",
    { headers = apiHeaders }
  )
  if not r.success then return nil end

  local parsed = json_parse(r.body)
  local avg = getPath(parsed, "data.rating.average")
  return formatRating(avg)
end

local function fetchBookStatusJson(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return nil end
  local r = http_get(apiBase .. slug .. "?fields[]=updated_at", { headers = apiHeaders })
  if not r.success then return nil end
  if isErrorResponse(r.body) then return nil end
  local parsed = json_parse(r.body)
  return parsed and parsed.data or nil
end

function getBookStatus(bookUrl)
  local data = fetchBookStatusJson(bookUrl)
  if not data then return nil end
  local st = data.status
  if type(st) == "table" and st.label then
    local label = string_trim(st.label)
    return label ~= "" and string_clean(label) or nil
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local data = fetchBookStatusJson(bookUrl)
  if not data then return nil end
  local ua = data.updated_at
  if not ua or ua == "" then return nil end
  local date = string.match(ua, "^(%d%d%d%d%-%d%d%-%d%d)")
  return date ~= "" and date or nil
end

-- ── Список глав (JSON API /api/manga/{slug}/chapters) ────────────────────────

function getChapterList(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then
    log_error("mangalib: cannot extract slug from " .. bookUrl)
    return {}
  end

  local r = http_get(apiBase .. slug .. "/chapters", { headers = apiHeaders })
  if not r.success then
    log_error("mangalib: chapters failed code=" .. tostring(r.code))
    return {}
  end

  if isErrorResponse(r.body) then
    show_error("Ошибка загрузки", "Не удалось загрузить список глав.\nВозможно, требуется авторизация.")
    return nil
  end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return {} end

  local raw = {}
  for _, chapter in ipairs(parsed.data) do
    local volume = tostring(chapter.volume or "")
    local number = tostring(chapter.number or "")
    local name   = chapter.name and chapter.name ~= "" and chapter.name or nil
    local bid    = "0"
    local isPaid = false
    if chapter.branches and chapter.branches[1] then
      local br = chapter.branches[1]
      local branchId = br.branch_id
      if branchId ~= nil and branchId ~= "" then
        bid = tostring(branchId)
      end
      local rv = br.restricted_view
      if rv and rv.is_open == false then
        isPaid = true
      end
    end
    if chapter.bundle_id then isPaid = true end

    local title = "Том " .. volume .. " Глава " .. number
    if name then title = title .. " " .. name end
    if isPaid then title = title .. " 🔒" end

    local chUrl = baseUrl .. "ru/" .. slug .. "/read/v" .. volume .. "/c" .. number
    if bid ~= "0" then chUrl = chUrl .. "?bid=" .. bid end

    table.insert(raw, {
      result = {
        title  = string_clean(title),
        url    = chUrl,
        volume = "Том " .. volume
      },
      index = chapter.index or #raw + 1
    })
  end

  table.sort(raw, function(a, b) return a.index < b.index end)

  local chapters = {}
  for _, item in ipairs(raw) do
    table.insert(chapters, item.result)
  end
  return chapters
end

function getChapterListHash(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return nil end
  local r = http_get(apiBase .. slug .. "/chapters", { headers = apiHeaders })
  if not r.success then return nil end
  if isErrorResponse(r.body) then return nil end
  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return nil end
  local chapters = parsed.data
  local last = chapters[#chapters]
  return last and tostring(last.item_number or last.number) or nil
end

-- ── JSON → HTML (рендер структурированного контента главы) ───────────────────

local function jsonToHtml(nodes, attachMap)
  if not nodes then return "" end
  local parts = {}

  for _, node in ipairs(nodes) do
    if type(node) ~= "table" then break end
    local ntype   = node.type or ""
    local content = node.content
    local inner   = jsonToHtml(content, attachMap)

    if ntype == "text" then
      local text = node.text or ""
      if node.marks then
        for _, mark in ipairs(node.marks) do
          local mt = mark.type or ""
          if mt == "bold"      then text = "<b>"  .. text .. "</b>"  end
          if mt == "italic"    then text = "<i>"  .. text .. "</i>"  end
          if mt == "underline" then text = "<u>"  .. text .. "</u>"  end
        end
      end
      table.insert(parts, text)

    elseif ntype == "paragraph"      then table.insert(parts, "<p>"           .. inner .. "</p>")
    elseif ntype == "heading"        then table.insert(parts, "<h2>"          .. inner .. "</h2>")
    elseif ntype == "listItem"       then table.insert(parts, "<li>"          .. inner .. "</li>")
    elseif ntype == "bulletList"     then table.insert(parts, "<ul>"          .. inner .. "</ul>")
    elseif ntype == "orderedList"    then table.insert(parts, "<ol>"          .. inner .. "</ol>")
    elseif ntype == "blockquote"     then table.insert(parts, "<blockquote>"  .. inner .. "</blockquote>")
    elseif ntype == "hardBreak"      then table.insert(parts, "<br>")
    elseif ntype == "horizontalRule" then table.insert(parts, "<hr>")

    elseif ntype == "image" then
      local attrs = node.attrs or {}
      local imgId = attrs.id
      if not imgId and attrs.images and attrs.images[1] then
        imgId = attrs.images[1].id
      end
      local imgUrl = (imgId and attachMap[tostring(imgId)]) or attrs.src or ""
      if imgUrl ~= "" then
        table.insert(parts, "<img src=\"" .. normalizeCover(imgUrl) .. "\">")
      end

    else
      if inner ~= "" then table.insert(parts, inner) end
    end
  end

  return table.concat(parts, "")
end

-- ── Текст главы (JSON API /api/manga/{slug}/chapter?...) ─────────────────────

local function fetchChapterPages(chapterUrl)
  if not chapterUrl or chapterUrl == "" then return {} end

  local slug   = chapterUrl:match("/ru/([^/]+)/read/")
  local volume = chapterUrl:match("/v([^/]+)/c")
  local number = chapterUrl:match("/c([^?]+)")
  local bid    = chapterUrl:match("[?&]bid=([^&]+)")

  if not slug or not volume or not number then return {} end

  local apiUrl = apiBase .. slug .. "/chapter?volume=" .. volume .. "&number=" .. number
  if bid then apiUrl = apiUrl .. "&branch_id=" .. bid end

  log_error("mangalib DEBUG: apiUrl=" .. apiUrl)
  local r = http_get(apiUrl, { headers = apiHeaders })
  log_error("mangalib DEBUG: success=" .. tostring(r.success) .. " code=" .. tostring(r.code) .. " bodyLen=" .. tostring(#(r.body or "")))
  if r.body then
    log_error("mangalib DEBUG: body(first500)=" .. tostring(r.body:sub(1, 500)))
  end
  if not r.success then return {} end

  if isErrorResponse(r.body) then
    log_error("mangalib DEBUG: isErrorResponse=true")
    show_error("Ошибка загрузки", "Не удалось загрузить страницы главы.\nТребуется авторизация.")
    return nil
  end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then
    log_error("mangalib DEBUG: parse failed or no data")
    return {}
  end

  local data = parsed.data
  log_error("mangalib DEBUG: data keys=" .. tostring(data.pages and "has_pages" or "no_pages") .. " restricted_view=" .. tostring(data.restricted_view and "present" or "nil") .. " bundle=" .. tostring(data.bundle and "present" or "nil") .. " content=" .. tostring(data.content and "present" or "nil"))

  local rv = data.restricted_view
  if rv then
    log_error("mangalib DEBUG: restricted_view.is_open=" .. tostring(rv.is_open) .. " price=" .. tostring(rv.price))
  end
  if rv and rv.is_open == false then
    local price = rv.price or 0
    local msg = "Эта глава является платной."
    if price > 0 then msg = msg .. "\nЦена: " .. tostring(price) .. " ₽" end
    msg = msg .. "\nКупить можно на mangalib.me"
    show_error("Платная глава", msg)
    return nil
  end

  if data.bundle and data.bundle.is_open == false then
    local price = data.bundle.price or 0
    local name = data.bundle.name or ""
    local msg = "Эта глава является платной."
    if name ~= "" then msg = msg .. "\nБандл: " .. name end
    if price > 0 then msg = msg .. "\nЦена: " .. tostring(price) .. " ₽" end
    msg = msg .. "\nКупить можно на mangalib.me"
    show_error("Платный том", msg)
    return nil
  end

  if data.pages and type(data.pages) == "table" then
    log_error("mangalib DEBUG: data.pages count=" .. tostring(#data.pages))
    local pages = {}
    for _, page in ipairs(data.pages) do
      local url = page.url
      if url and url ~= "" then
        if not url:find("://") then url = "https://img3.cdnlibs.org" .. url end
        table.insert(pages, url)
      end
    end
    log_error("mangalib DEBUG: returning pages count=" .. tostring(#pages))
    return pages
  end

  local contentNode = data.content
  local attachments = data.attachments
  log_error("mangalib DEBUG: contentNode=" .. tostring(contentNode and "present" or "nil") .. " attachments=" .. tostring(attachments and "present" or "nil"))

  local attachMap = {}
  if attachments then
    for _, att in ipairs(attachments) do
      local attId  = tostring(att.id or att.name or "")
      local attUrl = att.url or ""
      if attId ~= "" and attUrl ~= "" then
        attachMap[attId] = attUrl
      end
    end
  end

  local pages = {}

  local function extractImages(node)
    if not node then return end
    if type(node) == "string" then return end
    if type(node) ~= "table" then return end

    if node.type == "image" then
      local src = node.attrs and node.attrs.src
      if src and src ~= "" then
        local imageUrl = attachMap[src] or src
        if not imageUrl:find("://") then imageUrl = "https:" .. imageUrl end
        table.insert(pages, imageUrl)
      end
    end

    if node.content and type(node.content) == "table" then
      for _, child in ipairs(node.content) do
        extractImages(child)
      end
    end
  end

  if type(contentNode) == "table" and contentNode.content then
    extractImages(contentNode)
  end

  log_error("mangalib DEBUG: final pages count=" .. tostring(#pages))
  return pages
end

function getPageList(html, chapterUrl)
  return fetchChapterPages(chapterUrl)
end

function getChapterText(html, chapterUrl)
  local pages = fetchChapterPages(chapterUrl)
  local out = {}
  for _, p in ipairs(pages) do
    table.insert(out, '<img src="' .. p .. '">')
  end
  return table.concat(out, "\n")
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort_by",
      label        = "Сортировка",
      defaultValue = "rating_score",
      options = {
        { value = "rate_avg",        label = "По рейтингу"         },
        { value = "rating_score",    label = "По популярности"     },
        { value = "views",           label = "По просмотрам"       },
        { value = "chap_count",      label = "Количеству глав"     },
        { value = "last_chapter_at", label = "Дате обновления"     },
        { value = "created_at",      label = "Дате добавления"     },
        { value = "name",            label = "По названию (A-Z)"   },
        { value = "rus_name",        label = "По названию (А-Я)"   },
      }
    },
    {
      type         = "select",
      key          = "sort_type",
      label        = "Порядок",
      defaultValue = "desc",
      options = {
        { value = "desc", label = "По убыванию"   },
        { value = "asc",  label = "По возрастанию" },
      }
    },
    {
      type  = "select",
      key   = "require_chapters",
      label = "Только проекты с главами",
      defaultValue = "true",
      options = {
        { value = "true",  label = "Да" },
        { value = "false", label = "Нет" },
      }
    },
    {
      type  = "checkbox",
      key   = "types",
      label = "Тип",
      options = {
        { value = "1", label = "Манга"      },
        { value = "5", label = "Манхва"     },
        { value = "6", label = "Маньхуа"    },
        { value = "9", label = "Комикс"     },
        { value = "4", label = "OEL-манга"  },
      }
    },
    {
      type  = "checkbox",
      key   = "scanlateStatus",
      label = "Статус перевода",
      options = {
        { value = "1", label = "Продолжается" },
        { value = "2", label = "Завершен"     },
        { value = "3", label = "Заморожен"    },
        { value = "4", label = "Заброшен"     },
      }
    },
    {
      type  = "checkbox",
      key   = "manga_status",
      label = "Статус тайтла",
      options = {
        { value = "1", label = "Онгоинг"            },
        { value = "2", label = "Завершён"            },
        { value = "4", label = "Приостановлен"      },
        { value = "5", label = "Выпуск прекращён"   },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Жанры",
      options = {
        { value = "34", label = "Боевик"                 },
        { value = "35", label = "Боевые искусства"       },
        { value = "36", label = "Вампиры"                },
        { value = "37", label = "Гарем"                  },
        { value = "39", label = "Героическое фэнтези"    },
        { value = "40", label = "Детектив"               },
        { value = "41", label = "Дзёсэй"                 },
        { value = "43", label = "Драма"                  },
        { value = "44", label = "Игра"                   },
        { value = "45", label = "История"                },
        { value = "47", label = "Комедия"                },
        { value = "49", label = "Меха"                   },
        { value = "50", label = "Мистика"                },
        { value = "51", label = "Научная фантастика"     },
        { value = "52", label = "Повседневность"         },
        { value = "53", label = "Постапокалиптика"       },
        { value = "54", label = "Приключения"            },
        { value = "55", label = "Психология"             },
        { value = "56", label = "Романтика"              },
        { value = "57", label = "Самурайский боевик"     },
        { value = "58", label = "Сверхъестественное"     },
        { value = "59", label = "Сёдзё"                  },
        { value = "61", label = "Сёнэн"                  },
        { value = "63", label = "Спорт"                  },
        { value = "64", label = "Сэйнэн"                 },
        { value = "65", label = "Трагедия"               },
        { value = "66", label = "Триллер"                },
        { value = "67", label = "Ужасы"                  },
        { value = "68", label = "Фантастика"             },
        { value = "69", label = "Фэнтези"                },
        { value = "70", label = "Школа"                  },
        { value = "72", label = "Этти"                   },
        { value = "79", label = "Исекай"                 },
        { value = "80", label = "Музыка"                 },
        { value = "81", label = "Демоны"                 },
        { value = "85", label = "Магия"                  },
        { value = "87", label = "Супер сила"             },
        { value = "89", label = "Военное"                },
        { value = "91", label = "Безумие"                },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page      = index + 1
  local sort_by   = filters["sort_by"]   or "rating_score"
  local sort_type = filters["sort_type"] or "desc"
  local req_ch    = filters["require_chapters"]

  local types_inc        = filters["types_included"]          or {}
  local scanlate_inc     = filters["scanlateStatus_included"] or {}
  local manga_status_inc = filters["manga_status_included"]   or {}
  local genres_inc       = filters["genres_included"]         or {}
  local genres_exc       = filters["genres_excluded"]         or {}

  local url = apiBase .. "?site_id[0]=" .. siteId
              .. "&page="      .. tostring(page)
              .. "&sort_by="   .. sort_by
              .. "&sort_type=" .. sort_type

  if req_ch ~= "false" then
    url = url .. "&chapters[min]=1"
  end

  for _, v in ipairs(types_inc)        do url = url .. "&types[]="          .. v end
  for _, v in ipairs(scanlate_inc)     do url = url .. "&scanlateStatus[]=" .. v end
  for _, v in ipairs(manga_status_inc) do url = url .. "&manga_status[]="   .. v end
  for _, v in ipairs(genres_inc)       do url = url .. "&genres[]="         .. v end
  for _, v in ipairs(genres_exc)       do url = url .. "&genres_exclude[]=" .. v end

  local r = http_get(url, { headers = apiHeaders })
  if not r.success then return { items = {}, hasNext = false } end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return { items = {}, hasNext = false } end

  local items = {}
  for _, manga in ipairs(parsed.data) do
    local title = pickTitle(manga)
    local slug  = manga.slug_url or manga.slug or ""
    local cover = getPath(manga, "cover.default") or ""
    if title ~= "" and slug ~= "" then
      local item = {
        title = string_clean(title),
        url   = baseUrl .. "ru/" .. slug,
        cover = proxyCover(cover)
      }
      local avg = getPath(manga, "rating.average")
      item.rating = formatRating(avg)
      table.insert(items, item)
    end
  end

  local hasNext = getPath(parsed, "meta.has_next_page")
  return { items = items, hasNext = hasNext == true or #items > 0 }
end
