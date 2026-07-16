-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ifreedom"
name     = "iFreedom"
version  = "1.1.3"
baseUrl  = "https://ifreedom.su/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ifreedom.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function normalizeNovelUrl(url)
  if not url or url == "" then return "" end
  if url:find("%?") then return url end
  if url:sub(-1) ~= "/" then
    return url .. "/"
  end
  return url
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Перевод|Переводчик|Редакция|Редактор|Аннотация|Сайт|Источник|Студия)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = baseUrl .. "vse-knigi/?sort=" .. url_encode("По рейтингу")
              .. "&bpage=" .. tostring(index + 1)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".booksearch .item-book-slide")) do
    local titleEl = html_select_first(card.html, ".block-book-slide-title")
    local bookUrl = normalizeNovelUrl(absUrl(html_attr(card.html, "a", "href")))
    local cover   = absUrl(html_attr(card.html, "img", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url = baseUrl .. "vse-knigi/?searchname=" .. url_encode(query) .. "&bpage=" .. tostring(index + 1)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".booksearch .item-book-slide")) do
    local titleEl = html_select_first(card.html, ".block-book-slide-title")
    local bookUrl = normalizeNovelUrl(absUrl(html_attr(card.html, "a", "href")))
    local cover   = absUrl(html_attr(card.html, "img", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.book-img.block-book-slide-img > img")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "[data-name=\"Описание\"]")
  if el then return string_trim(el.text) end
  return nil
end

function getBookGenres(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return {} end

  local genres = {}
  for _, block in ipairs(html_select(r.body, "div.book-info-list")) do
    local icon = html_select_first(block.html, "svg.icon-tabler-tag")
    if icon then
      for _, a in ipairs(html_select(block.html, "a")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
      end
    end
  end

  if #genres == 0 then
    for _, a in ipairs(html_select(r.body, "div.genreslist a")) do
      local label = string_trim(a.text)
      if label ~= "" then table.insert(genres, label) end
    end
  end

  return genres
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "div.chapterinfo a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      table.insert(chapters, {
        title = string_clean(a.text),
        url   = chUrl
      })
    end
  end

  local reversed = {}
  for i = #chapters, 1, -1 do
    table.insert(reversed, chapters[i])
  end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.book-info-list:has(svg.icon-tabler-list-check) div")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".pc-adv", ".mob-adv")
  local el = html_select_first(cleaned, ".chapter-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Сортировка",
      defaultValue = "По рейтингу",
      options = {
        { value = "По дате добавления",  label = "По дате добавления"  },
        { value = "По дате обновления",  label = "По дате обновления"  },
        { value = "По количеству глав",  label = "По количеству глав"  },
        { value = "По названию",         label = "По названию"         },
        { value = "По просмотрам",       label = "По просмотрам"       },
        { value = "По рейтингу",         label = "По рейтингу"         },
      }
    },
    {
      type  = "checkbox",
      key   = "status",
      label = "Статус",
      options = {
        { value = "Перевод активен",        label = "Перевод активен"        },
        { value = "Перевод приостановлен",  label = "Перевод приостановлен"  },
        { value = "Произведение завершено", label = "Произведение завершено" },
      }
    },
    {
      type  = "checkbox",
      key   = "lang",
      label = "Язык",
      options = {
        { value = "Английский", label = "Английский" },
        { value = "Китайский",  label = "Китайский"  },
        { value = "Корейский",  label = "Корейский"  },
        { value = "Японский",   label = "Японский"   },
      }
    },
    {
      type  = "checkbox",
      key   = "genre",
      label = "Жанры",
      options = {
        { value = "Боевик",              label = "Боевик"              },
        { value = "Боевые Искусства",    label = "Боевые Искусства"    },
        { value = "Вампиры",             label = "Вампиры"             },
        { value = "Виртуальный Мир",     label = "Виртуальный Мир"     },
        { value = "Гарем",               label = "Гарем"               },
        { value = "Героическое фэнтези", label = "Героическое фэнтези" },
        { value = "Детектив",            label = "Детектив"            },
        { value = "Дзёсэй",              label = "Дзёсэй"              },
        { value = "Драма",               label = "Драма"               },
        { value = "Игра",                label = "Игра"                },
        { value = "История",             label = "История"             },
        { value = "Киберпанк",           label = "Киберпанк"           },
        { value = "Комедия",             label = "Комедия"             },
        { value = "ЛитРПГ",              label = "ЛитРПГ"              },
        { value = "Меха",                label = "Меха"                },
        { value = "Милитари",            label = "Милитари"            },
        { value = "Мистика",             label = "Мистика"             },
        { value = "Научная Фантастика",  label = "Научная Фантастика"  },
        { value = "Повседневность",      label = "Повседневность"      },
        { value = "Постапокалипсис",     label = "Постапокалипсис"     },
        { value = "Приключения",         label = "Приключения"         },
        { value = "Психология",          label = "Психология"          },
        { value = "Романтика",           label = "Романтика"           },
        { value = "Сверхъестественное",  label = "Сверхъестественное"  },
        { value = "Сёдзё",              label = "Сёдзё"               },
        { value = "Сёнэн",              label = "Сёнэн"               },
        { value = "Сёнэн-ай",           label = "Сёнэн-ай"            },
        { value = "Спорт",               label = "Спорт"               },
        { value = "Сэйнэн",             label = "Сэйнэн"              },
        { value = "Сюаньхуа",            label = "Сюаньхуа"            },
        { value = "Трагедия",            label = "Трагедия"            },
        { value = "Триллер",             label = "Триллер"             },
        { value = "Ужасы",               label = "Ужасы"               },
        { value = "Фантастика",          label = "Фантастика"          },
        { value = "Фэнтези",             label = "Фэнтези"             },
        { value = "Школьная жизнь",      label = "Школьная жизнь"      },
        { value = "Экшн",                label = "Экшн"                },
        { value = "Эротика",             label = "Эротика"             },
        { value = "Этти",                label = "Этти"                },
        { value = "Яой",                 label = "Яой"                 },
        { value = "Adult",               label = "Adult"               },
        { value = "Mature",              label = "Mature"              },
        { value = "Xianxia",             label = "Xianxia"             },
        { value = "Xuanhuan",            label = "Xuanhuan"            },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local sort   = filters["sort"] or "По рейтингу"
  local status = filters["status_included"] or {}
  local lang   = filters["lang_included"] or {}
  local genre  = filters["genre_included"] or {}

  local url = baseUrl .. "vse-knigi/?sort=" .. url_encode(sort)
              .. "&bpage=" .. tostring(page)

  for _, v in ipairs(status) do url = url .. "&status[]=" .. url_encode(v) end
  for _, v in ipairs(lang)   do url = url .. "&lang[]="   .. url_encode(v) end
  for _, v in ipairs(genre)  do url = url .. "&genre[]="  .. url_encode(v) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".booksearch .item-book-slide")) do
    local titleEl = html_select_first(card.html, ".block-book-slide-title")
    local bookUrl = normalizeNovelUrl(absUrl(html_attr(card.html, "a", "href")))
    local cover   = absUrl(html_attr(card.html, "img", "src"))
    if titleEl and bookUrl ~= "" then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end
