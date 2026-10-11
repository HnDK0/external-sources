-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ifreedom"
name     = "iFreedom"
version  = "1.1.7"
baseUrl  = "https://ifreedom.su/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ifreedom.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

-- Old builds ship no require_lib: keep the plugin loadable (a top-level
-- error would drop it from the source list) and fail with a visible
-- message on the first call instead. require_lib caches loaded libs.
local function lib(id)
  if type(require_lib) ~= "function" then
    show_error("Требуется обновление NoveLA", "Плагину нужны общие библиотеки")
    error("Требуется обновление NoveLA (require_lib)", 0)
  end
  return require_lib(id)
end

local function absUrl(href) return lib("urls").absUrl(baseUrl, href) end

local function normalizeNovelUrl(url)
  if not url or url == "" then return "" end
  if url:find("%?") then return url end
  if url:sub(-1) ~= "/" then
    return url .. "/"
  end
  return url
end

-- Кэш страницы книги: детальные функции (заголовок, обложка, описание, жанры,
-- статус, дата) вызываются движком параллельно с одним URL — fetch.page
-- убирает дублирующиеся HTTP-запросы.
local function fetchPage(url) return lib("fetch").page(url) end

local function applyStandardContentTransforms(text)
  return lib("content").standardTransforms(text, { domain = baseUrl, lang = "ru" })
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url = lib("catalog").pageUrl(
    baseUrl .. "vse-knigi/?sort=" .. url_encode("По рейтингу") .. "&bpage={n}", index)

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

  return { items = items, hasNext = lib("catalog").hasNextPage(items) }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local url = lib("catalog").pageUrl(
    baseUrl .. "vse-knigi/?searchname=" .. url_encode(query) .. "&bpage={n}", index)

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

  return { items = items, hasNext = lib("catalog").hasNextPage(items) }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local html = fetchPage(bookUrl)
  if not html then return nil end
  local el = html_select_first(html, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local html = fetchPage(bookUrl)
  if not html then return nil end
  local el = html_select_first(html, "div.book-img.block-book-slide-img > img")
  if el then return absUrl(el.src) end
  return nil
end

function getBookDescription(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local html = fetchPage(bookUrl)
  if not html then return nil end
  local el = html_select_first(html, "[data-name=\"Описание\"]")
  if el then return string_trim(el.text) end
  return nil
end

function getBookGenres(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local html = fetchPage(bookUrl)
  if not html then return {} end

  local genres = {}
  for _, block in ipairs(html_select(html, "div.book-info-list")) do
    local icon = html_select_first(block.html, "svg.icon-tabler-tag")
    if icon then
      genres = lib("meta").collectGenres(html_select(block.html, "a"))
    end
  end

  if #genres == 0 then
    genres = lib("meta").collectGenres(html_select(html, "div.genreslist a"))
  end

  return genres
end

-- ── Статус и дата обновления ──────────────────────────────────────────────────

-- Статус книги — текст внутри блока .book-info-list (напр. «Книга завершена»,
-- «Перевод активен»). В блоке может быть несколько записей (автор, жанры),
-- статус — та, что содержит ключевые слова статуса. Проверено на живом сайте.
function getBookStatus(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)
  local html = fetchPage(bookUrl)
  if not html then return nil end
  local blocks = html_select(html, ".book-info-list")
  for _, b in ipairs(blocks) do
    local t = string_clean(b.text)
    if t ~= "" and (
        string.find(t, "заверш", 1, true) or string.find(t, "перевод", 1, true)
     or string.find(t, "статус", 1, true)  or string.find(t, "продолжа", 1, true)
     or string.find(t, "издан", 1, true)   or string.find(t, "выпущен", 1, true)) then
      return t
    end
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local html = fetchPage(bookUrl)
  if not html then return nil end

  -- Дата последнего обновления = дата самой свежей главы. Список глав на
  -- странице отсортирован от новых к старым, поэтому первая .chapterinfo —
  -- самая новая. Дата лежит в span.timechapter в формате ДД.ММ.ГГ (иногда ГГГГ).
  local firstChapter = html_select_first(html, "div.chapterinfo")
  if not firstChapter then return nil end
  local timeEl = html_select_first(firstChapter.html, "span.timechapter")
  if not timeEl then return nil end
  local ds = string_trim(timeEl.text)
  if ds == "" then return nil end

  -- Абсолютная дата: ДД.ММ.ГГ или ДД.ММ.ГГГГ
  local d, m, y = string.match(ds, "(%d+)%.(%d+)%.(%d+)")
  if d and m and y then
    if #y == 2 then y = "20" .. y end
    return string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(d))
  end

  -- Запасной вариант: относительная дата «N часов/дней/... назад»
  return lib("meta").normalizeDate(ds)
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  bookUrl = normalizeNovelUrl(bookUrl)

  local r = http_get(bookUrl)
  if not r.success then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "div.chapterinfo a")) do
    local chUrl = absUrl(a.href)
    -- Платные главы ведут на /koshelek/ (страница абонемента), а не на главу —
    -- пропускаем их, иначе движок откроет страницу оплаты вместо текста
    if chUrl ~= "" and not chUrl:find("koshelek") then
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
  local cat    = lib("catalog")
  local page   = cat.nextIndex(index)
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

  return { items = items, hasNext = cat.hasNextPage(items) }
end
