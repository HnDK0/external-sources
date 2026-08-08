-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ranobespace"
name     = "Ranobe.space"
version  = "1.1.2"
baseUrl  = "https://ranobe.space/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ranobespace.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
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

-- Извлекает id книги из URL вида:
--   https://ranobe.space/ranobe/1246-jobless-reincarnation-...  →  "1246"
local function getBookId(bookUrl)
  return bookUrl:match("/ranobe/(%d+)")
end

-- hasNext: кнопка «Дальше» присутствует и НЕ disabled (на последней странице
-- кнопка имеет атрибут disabled — предположение по разметке, не проверено).
local function hasNextPage(html)
  return html_select_first(html, "button:contains(Дальше):not([disabled])") ~= nil
end

-- Парсит карточку каталога/поиска: a[data-book-transition-id] > h3 title,
-- img.book-cover-image, рейтинг из span.rating (текст вида "9.8").
-- title берём из h3[data-book-transition-title="true"], а не из strong —
-- strong живёт в скрытом overlay .book-cover-copy (показывается при ховере)
-- и может отсутствовать/дублироваться (проверено на фикстурах каталога и поиска).
-- ВАЖНО: href берём из поля el.href (атрибут самой карточки <a>), а не через
-- html_attr(el.html, "a", "href") — el.html в движке это innerHTML карточки,
-- вложенного тега <a> внутри нет, и такой запрос всегда возвращает пустую
-- строку (каталог и поиск возвращали 0 items — баг v1.1.0).
-- ВАЖНО: рейтинг сайта по шкале 1-10, поэтому отдаём "Rating: N/10" (как в
-- getBookRating), а не голое число — голое "9.8" приложение читает как шкалу
-- 0-5 и показывает 0 (формат rating описан в lua-plugin-guide.md).
local function parseCards(html)
  local items = {}
  local cards = html_select(html, "a[data-book-transition-id]")
  for _, el in ipairs(cards) do
    local titleEl   = html_select_first(el.html, 'h3[data-book-transition-title="true"]')
    local href      = el.href or ""
    local cover     = html_attr(el.html, "img.book-cover-image", "src")
    local ratingEl  = html_select_first(el.html, "span.rating")
    local rating    = ratingEl and string_clean(ratingEl.text) or ""
    local title     = titleEl and titleEl.text or ""
    if title ~= "" and href ~= "" then
      local item = {
        title = string_clean(title),
        url   = absUrl(href),
        cover = absUrl(cover)
      }
      if rating ~= "" then item.rating = "Rating: " .. rating .. "/10" end
      table.insert(items, item)
    end
  end
  return items
end

-- ── Каталог / поиск (HTML-страницы /ranobe[?q=...]) ─────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "ranobe"
  if page > 1 then url = url .. "?page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  return {
    items   = parseCards(r.body),
    hasNext = hasNextPage(r.body)
  }
end

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "ranobe?q=" .. url_encode(query)
  if page > 1 then url = url .. "&page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  return {
    items   = parseCards(r.body),
    hasNext = hasNextPage(r.body)
  }
end

-- ── Детали книги (страница книги) ────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local src = html_attr(r.body, ".book-cover img", "src")
  if src == "" then return nil end
  return absUrl(src)
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".book-description-copy")
  if not el then el = html_select_first(r.body, ".book-hero-summary") end
  if not el then return nil end
  return string_trim(html_text(el.html))
end

-- ── Рейтинг книги ─────────────────────────────────────────────────────────────

function getBookRating(bookUrl)
  -- Первый span.rating на странице книги (в hero-блоке) — рейтинг читателей 1-10
  -- (текст вида "9.8"). Проверено на живом сайте.
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "span.rating")
  if not el then return nil end
  local score = string.match(string_clean(el.text), "%d+%.?%d*")
  if not score then return nil end
  return "Rating: " .. score .. "/10"
end

-- ── Список глав (JSON API, постранично через parsePage) ───────────────────────

-- API /api/books/{id}/chapters отдаёт максимум 100 глав за запрос
-- (limit=101+ → HTTP 400), пагинация — через offset. Ответ: { items, total,
-- offset, nextOffset }. Для 408 глав totalPages = ceil(408/100) = 5.
-- Движок сам догружает страницы и при обновлении перечитывает только
-- последнюю — getChapterList/getChapterListHash не нужны.
function parsePage(bookUrl, page)
  local bookId = getBookId(bookUrl)
  if not bookId then return { chapters = {}, totalPages = 1 } end

  local offset = (page - 1) * 100
  local apiUrl = baseUrl .. "api/books/" .. bookId ..
                 "/chapters?sort=asc&offset=" .. tostring(offset) .. "&limit=100"
  local r = http_get(apiUrl)
  if not r.success then return { chapters = {}, totalPages = 1 } end

  local parsed = json_parse(r.body)
  if not parsed or not parsed.items then return { chapters = {}, totalPages = 1 } end

  -- sort=asc → внутри страницы старые главы сверху, как ожидает движок
  local chapters = {}
  for _, ch in ipairs(parsed.items) do
    table.insert(chapters, {
      title  = string_clean(ch.title or ""),
      url    = bookUrl .. "/chapter/" .. tostring(ch.id),
      volume = "Том " .. tostring(ch.volume or "")
    })
  end

  local total = tonumber(parsed.total or #parsed.items) or #parsed.items
  local totalPages = math.max(1, math.ceil(total / 100))
  return { chapters = chapters, totalPages = totalPages }
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local el = html_select_first(html, "div.reader-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

-- Значения фильтров проверены на живом сайте (payload каталога и фактические
-- запросы): sort ∈ updated/popular/rating/new/chapters; status 1-4; country 1-4
-- (Япония/Китай/Корея/США); tag=N — включение жанра, несколько = AND.
-- Исключение тегов (tag=-N) сайт НЕ поддерживает, поэтому у тегов только
-- checkbox-включение, без tristate. id жанров совпадают с ranobehub.org.
function getFilterList()
  return {

    -- Сортировка
    {
      type             = "sort",
      key              = "sort",
      label            = "Сортировка",
      defaultValue     = "updated",
      defaultAscending = false,
      options = {
        { value = "updated",  label = "По обновлению"  },
        { value = "popular",  label = "По популярности" },
        { value = "rating",   label = "По рейтингу"     },
        { value = "new",      label = "Сначала новые"   },
        { value = "chapters", label = "По главам"       },
      }
    },

    -- Статус
    {
      type  = "select",
      key   = "status",
      label = "Статус",
      options = {
        { value = "1", label = "В процессе" },
        { value = "2", label = "Завершено"  },
        { value = "3", label = "Заморожено" },
        { value = "4", label = "Неизвестно" },
      }
    },

    -- Страна
    {
      type  = "checkbox",
      key   = "country",
      label = "Страна",
      options = {
        { value = "1", label = "Япония" },
        { value = "2", label = "Китай"  },
        { value = "3", label = "Корея"  },
        { value = "4", label = "США"    },
      }
    },

    -- Жанры
    {
      type         = "checkbox",
      key          = "tags",
      label        = "Жанры",
      multiselect  = true,
      options = {
        { value = "22",  label = "Боевые искусства"   },
        { value = "114", label = "Гарем"              },
        { value = "246", label = "Гендер бендер"      },
        { value = "216", label = "Дзёсэй"             },
        { value = "115", label = "Для взрослых"       },
        { value = "7",   label = "Драма"              },
        { value = "101", label = "Исторический"       },
        { value = "17",  label = "Комедия"            },
        { value = "638", label = "Лоликон"            },
        { value = "922", label = "Магический реализм" },
        { value = "24",  label = "Меха"               },
        { value = "12",  label = "Милитари"           },
        { value = "2",   label = "Мистика"            },
        { value = "13",  label = "Научная фантастика" },
        { value = "747", label = "Непристойность"     },
        { value = "93",  label = "Повседневность"     },
        { value = "11",  label = "Приключение"        },
        { value = "18",  label = "Психология"         },
        { value = "9",   label = "Романтика"          },
        { value = "20",  label = "Сверхъестественное" },
        { value = "15",  label = "Сёдзё"              },
        { value = "23",  label = "Сёдзё-ай"           },
        { value = "189", label = "Сёнэн"              },
        { value = "680", label = "Сёнэн-ай"           },
        { value = "420", label = "Спорт"              },
        { value = "5",   label = "Сэйнэн"             },
        { value = "242", label = "Сюаньхуа"           },
        { value = "364", label = "Сянься"             },
        { value = "19",  label = "Трагедия"           },
        { value = "3",   label = "Триллер"            },
        { value = "1",   label = "Ужасы"              },
        { value = "720", label = "Уся"                },
        { value = "8",   label = "Фэнтези"            },
        { value = "21",  label = "Школьная жизнь"     },
        { value = "14",  label = "Экшн"               },
        { value = "327", label = "Эччи"               },
        { value = "691", label = "Юри"                },
        { value = "682", label = "Яой"                },
        { value = "907", label = "Eastern fantasy"    },
        { value = "999", label = "Isekai"             },
        { value = "993", label = "Video games"        },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page = index + 1

  local qs = "sort=" .. url_encode(filters["sort"] or "updated")

  local status = filters["status"]
  if status and status ~= "" then
    qs = qs .. "&status=" .. url_encode(status)
  end

  -- Несколько стран — через запятую: country=1,2 (проверено на живом сайте)
  local country_inc = filters["country_included"] or {}
  if #country_inc > 0 then
    qs = qs .. "&country=" .. table.concat(country_inc, ",")
  end

  -- Жанры: tag=N на каждый выбранный (AND), отрицательные не поддерживаются
  local tags_inc = filters["tags_included"] or {}
  for _, t in ipairs(tags_inc) do
    qs = qs .. "&tag=" .. t
  end

  local url = baseUrl .. "ranobe?" .. qs
  if page > 1 then url = url .. "&page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  return {
    items   = parseCards(r.body),
    hasNext = hasNextPage(r.body)
  }
end
