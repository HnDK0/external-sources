-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ranobelib"
name     = "RanobeLib"
version  = "1.0.5"
baseUrl  = "https://ranobelib.me/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ranobelib.png"

-- ── Константы ─────────────────────────────────────────────────────────────────

local apiBase  = "https://api.cdnlibs.org/api/manga/"
local siteId   = "3"
local apiHeaders = {
  ["Site-Id"]          = siteId,
  ["User-Agent"]       = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36",
  ["Accept"]           = "application/json, text/plain, */*",
  ["Accept-Language"]  = "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
  ["Referer"]          = "https://ranobelib.me/",
  ["Origin"]           = "https://ranobelib.me",
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

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = string_trim(text)
  return text
end

-- Выбирает лучшее из нескольких вариантов названия
local function pickTitle(data)
  return data.rus_name or data.eng_name or data.name or ""
end

-- Извлекает slug книги из URL вида:
--   https://ranobelib.me/ru/book/12345--slug  →  "12345--slug"
--   https://ranobelib.me/ru/12345--slug        →  "12345--slug"
local function extractSlug(bookUrl)
  -- Убираем trailing slash и берём последний сегмент пути
  local clean = bookUrl:gsub("/?$", "")
  return clean:match("([^/]+)$")
end

-- ── Вложенный доступ к JSON по "dot.path" ─────────────────────────────────────
-- Используется для путей вида "cover.default", "meta.has_next_page"
local function getPath(tbl, path)
  if not tbl or not path then return nil end
  local cur = tbl
  for key in path:gmatch("[^.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[key]
  end
  return cur
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
  for _, novel in ipairs(parsed.data) do
    local title = pickTitle(novel)
    local slug  = novel.slug or novel.slug_url or ""
    local cover = getPath(novel, "cover.default") or ""
    if title ~= "" and slug ~= "" then
      table.insert(items, {
        title = string_clean(title),
        url   = baseUrl .. "ru/" .. slug,
        cover = normalizeCover(cover)
      })
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
  for _, novel in ipairs(parsed.data) do
    local title = pickTitle(novel)
    local slug  = novel.slug_url or novel.slug or ""
    local cover = getPath(novel, "cover.default") or ""
    if title ~= "" and slug ~= "" then
      table.insert(items, {
        title = string_clean(title),
        url   = baseUrl .. "ru/" .. slug,
        cover = normalizeCover(cover)
      })
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
  local parsed = json_parse(r.body)
  return parsed and parsed.data or nil
end

function getBookTitle(bookUrl)
  local data = fetchBookJson(bookUrl)
  if not data then return nil end
  -- parseBookData в KT читает data.names.rus/.eng
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
  return cover ~= "" and normalizeCover(cover) or nil
end

function getBookDescription(bookUrl)
  local data = fetchBookJson(bookUrl)
  if not data then return nil end
  local desc = data.summary or data.description or ""
  return string_trim(desc) ~= "" and string_trim(desc) or nil
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

-- ── Список глав (JSON API /api/manga/{slug}/chapters) ────────────────────────

function getChapterList(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then
    log_error("ranobelib: cannot extract slug from " .. bookUrl)
    return {}
  end

  local r = http_get(apiBase .. slug .. "/chapters", { headers = apiHeaders })
  if not r.success then
    log_error("ranobelib: chapters failed code=" .. tostring(r.code))
    return {}
  end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return {} end

  -- Собираем главы с индексом для сортировки
  local raw = {}
  for _, chapter in ipairs(parsed.data) do
    local volume = tostring(chapter.volume or "")
    local number = tostring(chapter.number or "")
    local name   = chapter.name and chapter.name ~= "" and chapter.name or nil
    local bid    = "0"
    -- branch_id берём из первой ветки
    if chapter.branches and chapter.branches[1] then
      bid = tostring(chapter.branches[1].branch_id or "0")
    end

    local title = "Том " .. volume .. " Глава " .. number
    if name then title = title .. " " .. name end

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

  -- Сортировка по index (API может отдавать не по порядку)
  table.sort(raw, function(a, b) return a.index < b.index end)

  local chapters = {}
  for _, item in ipairs(raw) do
    table.insert(chapters, item.result)
  end
  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local slug = extractSlug(bookUrl)
  if not slug then return nil end
  local r = http_get(apiBase .. slug .. "/chapters", { headers = apiHeaders })
  if not r.success then return nil end
  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return nil end
  local chapters = parsed.data
  local last = chapters[#chapters]
  return last and tostring(last.item_number or last.number) or nil
end

-- ── JSON → HTML (рендер структурированного контента главы) ───────────────────
--
-- RanobeLib отдаёт главу как JSON-дерево ProseMirror (type="doc").
-- Рекурсивно обходим узлы и строим HTML.

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
      -- Применяем marks (bold, italic, underline)
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
      -- ID может быть прямо в attrs или в attrs.images[1]
      local imgId = attrs.id
      if not imgId and attrs.images and attrs.images[1] then
        imgId = attrs.images[1].id
      end
      local imgUrl = (imgId and attachMap[tostring(imgId)]) or attrs.src or ""
      if imgUrl ~= "" then
        table.insert(parts, "<img src=\"" .. normalizeCover(imgUrl) .. "\">")
      end

    else
      -- Неизвестный узел-контейнер — просто обходим детей
      if inner ~= "" then table.insert(parts, inner) end
    end
  end

  return table.concat(parts, "")
end

-- ── Текст главы (JSON API /api/manga/{slug}/chapter?...) ─────────────────────

function getChapterText(html, chapterUrl)
  if not chapterUrl or chapterUrl == "" then return "" end

  -- URL вида: https://ranobelib.me/ru/SLUG/read/vVOL/cNUM[?bid=BID]
  local slug   = chapterUrl:match("/ru/([^/]+)/read/")
  local volume = chapterUrl:match("/v([^/]+)/c")
  local number = chapterUrl:match("/c([^?]+)")
  local bid    = chapterUrl:match("[?&]bid=([^&]+)")

  if not slug or not volume or not number then
    log_error("ranobelib: cannot parse chapterUrl: " .. chapterUrl)
    return ""
  end

  local apiUrl = apiBase .. slug .. "/chapter?volume=" .. volume .. "&number=" .. number
  if bid then apiUrl = apiUrl .. "&branch_id=" .. bid end

  local r = http_get(apiUrl, { headers = apiHeaders })
  if not r.success then
    log_error("ranobelib: chapter API failed code=" .. tostring(r.code))
    return ""
  end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return "" end

  local data        = parsed.data
  local contentNode = data.content
  local attachments = data.attachments

  -- Строим карту id → url для вложений (изображений)
  local attachMap = {}
  if attachments then
    for _, att in ipairs(attachments) do
      local attId  = tostring(att.id   or att.name or "")
      local attUrl = att.url or ""
      if attId ~= "" and attUrl ~= "" then
        attachMap[attId] = attUrl
      end
    end
  end

  local resultHtml = ""

  if type(contentNode) == "table" and contentNode.type == "doc" then
    -- ProseMirror JSON-дерево
    resultHtml = jsonToHtml(contentNode.content, attachMap)

  elseif type(contentNode) == "string" and contentNode ~= "" then
    -- Уже HTML-строка — проксируем src изображений
    resultHtml = regex_replace(
      contentNode,
      'src="([^"]+)"',
      function(m)
        local raw = m:match('src="([^"]+)"')
        if not raw then return m end
        return 'src="' .. normalizeCover(raw) .. '"'
      end
    )
  end

  if resultHtml == "" then return "" end

  -- Парсим получившийся HTML и извлекаем текст с абзацами
  return applyStandardContentTransforms(html_text(resultHtml))
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
      type  = "switch",
      key   = "require_chapters",
      label = "Только проекты с главами",
      defaultValue = true,
    },
    {
      type  = "checkbox",
      key   = "types",
      label = "Тип",
      options = {
        { value = "10", label = "Япония"     },
        { value = "11", label = "Корея"      },
        { value = "12", label = "Китай"      },
        { value = "13", label = "Английский" },
        { value = "14", label = "Авторский"  },
        { value = "15", label = "Фанфик"     },
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
        { value = "3", label = "Анонс"              },
        { value = "4", label = "Приостановлен"      },
        { value = "5", label = "Выпуск прекращён"   },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Жанры",
      options = {
        { value = "32",  label = "Арт"                    },
        { value = "91",  label = "Безумие"                },
        { value = "34",  label = "Боевик"                 },
        { value = "35",  label = "Боевые искусства"       },
        { value = "36",  label = "Вампиры"                },
        { value = "89",  label = "Военное"                },
        { value = "37",  label = "Гарем"                  },
        { value = "38",  label = "Гендерная интрига"      },
        { value = "39",  label = "Героическое фэнтези"    },
        { value = "81",  label = "Демоны"                 },
        { value = "40",  label = "Детектив"               },
        { value = "88",  label = "Детское"                },
        { value = "41",  label = "Дзёсэй"                 },
        { value = "43",  label = "Драма"                  },
        { value = "44",  label = "Игра"                   },
        { value = "79",  label = "Исекай"                 },
        { value = "45",  label = "История"                },
        { value = "46",  label = "Киберпанк"              },
        { value = "76",  label = "Кодомо"                 },
        { value = "47",  label = "Комедия"                },
        { value = "83",  label = "Космос"                 },
        { value = "85",  label = "Магия"                  },
        { value = "48",  label = "Махо-сёдзё"             },
        { value = "90",  label = "Машины"                 },
        { value = "49",  label = "Меха"                   },
        { value = "50",  label = "Мистика"                },
        { value = "80",  label = "Музыка"                 },
        { value = "51",  label = "Научная фантастика"     },
        { value = "77",  label = "Омегаверс"              },
        { value = "86",  label = "Пародия"                },
        { value = "52",  label = "Повседневность"         },
        { value = "82",  label = "Полиция"                },
        { value = "53",  label = "Постапокалиптика"       },
        { value = "54",  label = "Приключения"            },
        { value = "55",  label = "Психология"             },
        { value = "56",  label = "Романтика"              },
        { value = "57",  label = "Самурайский боевик"     },
        { value = "58",  label = "Сверхъестественное"     },
        { value = "59",  label = "Сёдзё"                  },
        { value = "60",  label = "Сёдзё-ай"               },
        { value = "61",  label = "Сёнэн"                  },
        { value = "62",  label = "Сёнэн-ай"               },
        { value = "63",  label = "Спорт"                  },
        { value = "87",  label = "Супер сила"             },
        { value = "64",  label = "Сэйнэн"                 },
        { value = "65",  label = "Трагедия"               },
        { value = "66",  label = "Триллер"                },
        { value = "67",  label = "Ужасы"                  },
        { value = "68",  label = "Фантастика"             },
        { value = "69",  label = "Фэнтези"                },
        { value = "84",  label = "Хентай"                 },
        { value = "70",  label = "Школа"                  },
        { value = "71",  label = "Эротика"                },
        { value = "72",  label = "Этти"                   },
        { value = "73",  label = "Юри"                    },
        { value = "74",  label = "Яой"                    },
      }
    },
    {
      type  = "tristate",
      key   = "tags",
      label = "Теги",
      options = {
        { value = "328", label = "Авантюристы"                  },
        { value = "175", label = "Антигерой"                    },
        { value = "333", label = "Бессмертные"                  },
        { value = "218", label = "Боги"                         },
        { value = "309", label = "Борьба за власть"             },
        { value = "360", label = "Брат и сестра"                },
        { value = "339", label = "Ведьма"                       },
        { value = "204", label = "Видеоигры"                    },
        { value = "214", label = "Виртуальная реальность"       },
        { value = "349", label = "Владыка демонов"              },
        { value = "198", label = "Военные"                      },
        { value = "310", label = "Воспоминания из другого мира" },
        { value = "212", label = "Выживание"                    },
        { value = "294", label = "ГГ женщина"                   },
        { value = "292", label = "ГГ имба"                      },
        { value = "295", label = "ГГ мужчина"                   },
        { value = "325", label = "ГГ не ояш"                    },
        { value = "331", label = "ГГ не человек"                },
        { value = "326", label = "ГГ ояш"                       },
        { value = "324", label = "Главный герой бог"            },
        { value = "298", label = "Глупый ГГ"                    },
        { value = "171", label = "Горничные"                    },
        { value = "306", label = "Гуро"                         },
        { value = "197", label = "Гяру"                         },
        { value = "157", label = "Демоны"                       },
        { value = "313", label = "Драконы"                      },
        { value = "317", label = "Древний мир"                  },
        { value = "163", label = "Зверолюди"                    },
        { value = "155", label = "Зомби"                        },
        { value = "323", label = "Исторические фигуры"          },
        { value = "158", label = "Кулинария"                    },
        { value = "161", label = "Культивация"                  },
        { value = "344", label = "ЛГБТ"                         },
        { value = "319", label = "ЛитРПГ"                       },
        { value = "206", label = "Лоли"                         },
        { value = "170", label = "Магия"                        },
        { value = "345", label = "Машинный перевод"             },
        { value = "159", label = "Медицина"                     },
        { value = "330", label = "Межгалактическая война"       },
        { value = "207", label = "Монстр Девушки"               },
        { value = "208", label = "Монстры"                      },
        { value = "316", label = "Мрачный мир"                  },
        { value = "209", label = "Музыка"                       },
        { value = "199", label = "Ниндзя"                       },
        { value = "210", label = "Обратный Гарем"               },
        { value = "200", label = "Офисные Работники"            },
        { value = "341", label = "Пираты"                       },
        { value = "314", label = "Подземелья"                   },
        { value = "311", label = "Политика"                     },
        { value = "201", label = "Полиция"                      },
        { value = "205", label = "Преступники / Криминал"       },
        { value = "196", label = "Призраки / Духи"              },
        { value = "329", label = "Призыватели"                  },
        { value = "321", label = "Прыжки между мирами"          },
        { value = "318", label = "Путешествие в другой мир"     },
        { value = "213", label = "Путешествие во времени"       },
        { value = "355", label = "Рабы"                         },
        { value = "312", label = "Ранги силы"                   },
        { value = "154", label = "Реинкарнация"                 },
        { value = "202", label = "Самураи"                      },
        { value = "315", label = "Скрытие личности"             },
        { value = "174", label = "Средневековье"                },
        { value = "203", label = "Традиционные игры"            },
        { value = "303", label = "Умный ГГ"                     },
        { value = "332", label = "Характерный рост"             },
        { value = "167", label = "Хикикомори"                   },
        { value = "322", label = "Эволюция"                     },
        { value = "327", label = "Элементы РПГ"                 },
        { value = "217", label = "Эльфы"                        },
        { value = "165", label = "Якудза"                       },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page      = index + 1
  local sort_by   = filters["sort_by"]   or "rating_score"
  local sort_type = filters["sort_type"] or "desc"
  local req_ch    = filters["require_chapters"]  -- switch: "true"/"false"/nil

  local types_inc        = filters["types_included"]          or {}
  local scanlate_inc     = filters["scanlateStatus_included"] or {}
  local manga_status_inc = filters["manga_status_included"]   or {}
  local genres_inc       = filters["genres_included"]         or {}
  local genres_exc       = filters["genres_excluded"]         or {}
  local tags_inc         = filters["tags_included"]           or {}
  local tags_exc         = filters["tags_excluded"]           or {}

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
  for _, v in ipairs(tags_inc)         do url = url .. "&tags[]="           .. v end
  for _, v in ipairs(tags_exc)         do url = url .. "&tags_exclude[]="   .. v end

  local r = http_get(url, { headers = apiHeaders })
  if not r.success then return { items = {}, hasNext = false } end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.data then return { items = {}, hasNext = false } end

  local items = {}
  for _, novel in ipairs(parsed.data) do
    local title = pickTitle(novel)
    local slug  = novel.slug_url or novel.slug or ""
    local cover = getPath(novel, "cover.default") or ""
    if title ~= "" and slug ~= "" then
      table.insert(items, {
        title = string_clean(title),
        url   = baseUrl .. "ru/" .. slug,
        cover = normalizeCover(cover)
      })
    end
  end

  local hasNext = getPath(parsed, "meta.has_next_page")
  return { items = items, hasNext = hasNext == true or #items > 0 }
end