-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "jaomix"
name     = "Jaomix"
version  = "1.0.2"
baseUrl  = "https://jaomix.ru/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/jaomix.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function transformCover(url)
  if not url or url == "" then return "" end
  return regex_replace(url, "-150x150", "")
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

local AJAX_HEADERS = {
  headers = {
    ["User-Agent"]       = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36",
    ["Accept"]           = "text/html, */*; q=0.01",
    ["Accept-Language"]  = "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
    ["X-Requested-With"] = "XMLHttpRequest",
    ["Origin"]           = "https://jaomix.ru",
    ["Sec-Fetch-Dest"]   = "empty",
    ["Sec-Fetch-Mode"]   = "cors",
    ["Sec-Fetch-Site"]   = "same-origin"
  }
}

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local url
  if index == 0 then
    url = baseUrl
  else
    url = baseUrl .. "?gpage=" .. tostring(index + 1)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, "div.block-home > div.one")) do
    local titleEl = html_select_first(card.html, "div.title-home")
    local bookUrl = absUrl(html_attr(card.html, "div.img-home > a", "href"))
    local cover   = transformCover(absUrl(html_attr(card.html, "div.img-home > a > img", "src")))
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
  local url
  if index == 0 then
    url = baseUrl .. "?searchrn=" .. url_encode(query)
  else
    url = baseUrl .. "?searchrn=" .. url_encode(query) .. "&gpage=" .. tostring(index + 1)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, "div.block-home > div.one")) do
    local titleEl = html_select_first(card.html, "div.title-home")
    local bookUrl = absUrl(html_attr(card.html, "div.img-home > a", "href"))
    local cover   = transformCover(absUrl(html_attr(card.html, "div.img-home > a > img", "src")))
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
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.img-book > img")
  if el then return transformCover(absUrl(el.src)) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "#desc-tab")
  if el then return string_trim(el.text) end
  return nil
end

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local genres = {}
  for _, p in ipairs(html_select(r.body, "#info-book > p")) do
    local text = string_trim(p.text)
    if string_starts_with(text, "Жанры:") then
      local raw = text:gsub("^Жанры:%s*", "")
      for genre in raw:gmatch("[^,]+") do
        local label = string_trim(genre)
        if label ~= "" then table.insert(genres, label) end
      end
      break
    end
  end

  return genres
end

-- ── Список глав (AJAX POST, постранично от конца к началу) ────────────────────

function getChapterList(bookUrl)
  -- Загружаем страницу книги чтобы узнать количество страниц
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local maxPage = 10 -- fallback
  local opts = html_select(r.body, "select.sel-toc option")
  if #opts == 0 then
    opts = html_select(r.body, "select[onchange*='loadChaptList'] option")
  end
  if #opts > 0 then maxPage = #opts end

  local ajaxUrl = baseUrl .. "wp-admin/admin-ajax.php"
  local allChapters = {}

  -- Загружаем от последней страницы к первой
  for page = maxPage, 1, -1 do
    local headers = AJAX_HEADERS.headers
    headers["Referer"] = bookUrl

    local pr = http_post(
      ajaxUrl,
      "action=loadpagenavchapstt&page=" .. tostring(page),
      {
        headers = headers
      }
    )

    if not pr.success then break end

    -- Собираем главы страницы
    local pageChapters = {}
    for _, a in ipairs(html_select(pr.body, "div.title a[href]")) do
      local chUrl = absUrl(a.href)
      if chUrl ~= "" then
        local titleEl = html_select_first(a.html, "h2")
        table.insert(pageChapters, {
          title = titleEl and string_clean(titleEl.text) or string_clean(a.text),
          url   = chUrl
        })
      end
    end

    if #pageChapters == 0 then break end

    -- Внутри страницы разворачиваем (newest→oldest), затем добавляем
    for i = #pageChapters, 1, -1 do
      table.insert(allChapters, pageChapters[i])
    end

    sleep(math.random(150, 350))
  end

  return allChapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".block-toc-out .columns-toc:first-child .flex-dow-txt:first-child a")
  if el then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".adblock-service", ".lazyblock", ".clear")
  local el = html_select_first(cleaned, ".entry-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end
-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sortby",
      label        = "Сортировка",
      defaultValue = "topweek",
      options = {
        { value = "topweek",  label = "Топ недели"            },
        { value = "alphabet", label = "По алфавиту"           },
        { value = "upd",      label = "По дате обновления"    },
        { value = "new",      label = "По дате создания"      },
        { value = "count",    label = "По просмотрам"         },
        { value = "topyear",  label = "Топ года"              },
        { value = "topday",   label = "Топ дня"               },
        { value = "alltime",  label = "Топ за все время"      },
        { value = "topmonth", label = "Топ месяца"            },
      }
    },
    {
      type         = "select",
      key          = "sortdaycreate",
      label        = "Дата добавления",
      defaultValue = "1",
      options = {
        { value = "1",    label = "Дата добавления"      },
        { value = "30",   label = "Послед. 30 дней"      },
        { value = "3060", label = "От 30 до 60 дней"     },
        { value = "6090", label = "От 60 до 90 дней"     },
        { value = "9012", label = "От 90 до 120 дней"    },
        { value = "1218", label = "От 120 до 180 дней"   },
        { value = "1836", label = "От 180 до 365 дней"   },
        { value = "365",  label = "От 365 дней"          },
      }
    },
    {
      type         = "select",
      key          = "sortcountchapt",
      label        = "Количество глав",
      defaultValue = "1",
      options = {
        { value = "1",    label = "Любое кол-во глав"    },
        { value = "500",  label = "До 500"               },
        { value = "510",  label = "От 500 до 1000"       },
        { value = "1020", label = "От 1000 до 2000"      },
        { value = "2030", label = "От 2000 до 3000"      },
        { value = "3040", label = "От 3000 до 4000"      },
        { value = "400",  label = "От 4000"              },
      }
    },
    {
      type  = "tristate",
      key   = "genre",
      label = "Жанры",
      options = {
        { value = "Боевые Искусства",    label = "Боевые Искусства"    },
        { value = "Виртуальный Мир",     label = "Виртуальный Мир"     },
        { value = "Гарем",               label = "Гарем"               },
        { value = "Детектив",            label = "Детектив"            },
        { value = "Драма",               label = "Драма"               },
        { value = "Игра",                label = "Игра"                },
        { value = "Истории из жизни",    label = "Истории из жизни"    },
        { value = "Исторический",        label = "Исторический"        },
        { value = "История",             label = "История"             },
        { value = "Исэкай",              label = "Исэкай"              },
        { value = "Комедия",             label = "Комедия"             },
        { value = "Меха",                label = "Меха"                },
        { value = "Мистика",             label = "Мистика"             },
        { value = "Научная Фантастика",  label = "Научная Фантастика"  },
        { value = "Повседневность",      label = "Повседневность"      },
        { value = "Постапокалипсис",     label = "Постапокалипсис"     },
        { value = "Приключения",         label = "Приключения"         },
        { value = "Психология",          label = "Психология"          },
        { value = "Романтика",           label = "Романтика"           },
        { value = "Сверхъестественное",  label = "Сверхъестественное"  },
        { value = "Сёнэн",               label = "Сёнэн"               },
        { value = "Спорт",               label = "Спорт"               },
        { value = "Сэйнэн",              label = "Сэйнэн"              },
        { value = "Сюаньхуа",            label = "Сюаньхуа"            },
        { value = "Трагедия",            label = "Трагедия"            },
        { value = "Триллер",             label = "Триллер"             },
        { value = "Фантастика",          label = "Фантастика"          },
        { value = "Фэнтези",             label = "Фэнтези"             },
        { value = "Хоррор",              label = "Хоррор"              },
        { value = "Школьная жизнь",      label = "Школьная жизнь"      },
        { value = "Шоунен",              label = "Шоунен"              },
        { value = "Экшн",                label = "Экшн"                },
        { value = "Этти",                label = "Этти"                },
        { value = "Adult",               label = "Adult"               },
        { value = "Ecchi",               label = "Ecchi"               },
        { value = "Josei",               label = "Josei"               },
        { value = "Mature",              label = "Mature"              },
        { value = "Shoujo",              label = "Shoujo"              },
        { value = "Wuxia",               label = "Wuxia"               },
        { value = "Xianxia",             label = "Xianxia"             },
        { value = "Xuanhuan",            label = "Xuanhuan"            },
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
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page           = index + 1
  local sortby         = filters["sortby"]         or "topweek"
  local sortdaycreate  = filters["sortdaycreate"]  or "1"
  local sortcountchapt = filters["sortcountchapt"] or "1"
  local genre_inc      = filters["genre_included"] or {}
  local genre_exc      = filters["genre_excluded"] or {}
  local lang_inc       = filters["lang_included"]  or {}

  local url = baseUrl .. "?searchrn"

  for i, v in ipairs(lang_inc) do
    url = url .. "&lang[" .. tostring(i - 1) .. "]=" .. url_encode(v)
  end

  for i, v in ipairs(genre_inc) do
    url = url .. "&genre[" .. tostring(i - 1) .. "]=" .. url_encode(v)
  end

  for i, v in ipairs(genre_exc) do
    url = url .. "&delgenre[" .. tostring(i - 1) .. "]=del%20" .. url_encode(v)
  end

  url = url .. "&sortcountchapt=" .. sortcountchapt
              .. "&sortdaycreate="  .. sortdaycreate
              .. "&sortby="         .. sortby
              .. "&gpage="          .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, "div.block-home > div.one")) do
    local titleEl = html_select_first(card.html, "div.title-home")
    local bookUrl = absUrl(html_attr(card.html, "div.img-home > a", "href"))
    local cover   = transformCover(absUrl(html_attr(card.html, "div.img-home > a > img", "src")))
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
