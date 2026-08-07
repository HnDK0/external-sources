-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "webnovel"
name     = "WebNovel"
version  = "1.1.0"
baseUrl  = "https://www.webnovel.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/webnovel.png"

function getUserAgentPreset()
  return "Chrome Desktop"
end

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- Кэш деталей книги: движок вызывает getBookTitle/Cover/Description параллельно
-- с одним URL, кэш убирает повторные запросы.
local _bookCache = {}

local function fetchBookPage(bookUrl)
  if _bookCache[bookUrl] then return _bookCache[bookUrl] end
  local r = http_get(bookUrl)
  if not r.success then return nil end
  _bookCache[bookUrl] = r.body
  return r.body
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?i)webnovel\\.com.*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+[^\\n\\r]*)[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?im)^\\s*\\[[^\\]\\n]*[Ee]nd[^\\]\\n]*\\]\\s*(\\r?\\n|$)", "")
  text = string_trim(text)
  text = regex_replace(text, "\\n{3,}", "\n\n")
  return text
end

-- Парсинг tag-страницы (/tags/*): другой HTML-структура чем /stories/
-- Карточки: a.g_thumb[href][title] внутри li → ul.pr-ret
local function parseTagPage(html)
  local items = {}
  local seen = {}
  for _, a in ipairs(html_select(html, "a.g_thumb[href]")) do
    local title = html_attr(a.html, "a", "title")
    if title == "" then title = html_attr(a.html, "a", "data-bookname") end
    local href = html_attr(a.html, "a", "href")
    if title ~= "" and href ~= "" and not seen[href] then
      seen[href] = true
      local cover = html_attr(a.html, "img", "src")
      table.insert(items, {
        title = string_clean(title),
        url   = absUrl(href),
        cover = absUrl(cover),
      })
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────
-- Карточки в .j_category_wrapper li → .g_thumb[title][href], img[data-original]
-- Пагинация: ?pageIndex=N (20 элементов на странице, JS-рендер пагинации).

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "stories/novel?orderBy=1&pageIndex=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, ".j_category_wrapper li")) do
    local gt = html_select_first(li.html, ".g_thumb")
    if gt then
      local title = gt.title or ""
      local href = gt.href or ""
      if title ~= "" and href ~= "" then
        local cover = html_attr(li.html, ".g_thumb img", "data-original")
        if cover == "" then cover = html_attr(li.html, ".g_thumb img", "src") end
        -- Рейтинг: первый strong внутри p.df.aic → span "4.71" (второй strong — главы)
        local rating = ""
        local rs = html_select_first(li.html, "p.df.aic strong span")
        if rs then rating = string_clean(rs.text) end
        local item = {
          title = string_clean(title),
          url   = absUrl(href),
          cover = absUrl(cover),
        }
        if rating ~= "" then item.rating = rating end
        table.insert(items, item)
      end
    end
  end

  local hasNext = #items >= 20
  return { items = items, hasNext = hasNext }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────
-- Результаты в .j_list_container li → a.g_thumb[href], h3 a[title], img[src]

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "search?keywords=" .. url_encode(query) .. "&pageIndex=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, ".j_list_container li")) do
    local h3a = html_select_first(li.html, "h3 a")
    if h3a then
      local title = h3a.text or ""
      local href = h3a.href or ""
      if title ~= "" and href ~= "" then
        local img = html_select_first(li.html, "a.g_thumb img")
        local cover = ""
        if img then
          cover = img.src or ""
        end
        -- Рейтинг в карточке поиска: p.g_star_num → "4.57" (у фанфиков его нет)
        local rating = ""
        local rs = html_select_first(li.html, ".g_star_num")
        if rs then rating = string_clean(rs.text) end
        local item = {
          title = string_clean(title),
          url   = absUrl(href),
          cover = absUrl(cover),
        }
        if rating ~= "" then item.rating = rating end
        table.insert(items, item)
      end
    end
  end

  local hasNext = #items >= 20
  return { items = items, hasNext = hasNext }
end

-- ── Фильтры каталога ──────────────────────────────────────────────────────────
-- Каталог: /stories/novel-{genre}-{gender}?orderBy={sort}&sourceType={type}&bookStatus={status}&pageIndex={N}
-- Жанры — часть пути, не параметр. Gender и genre объединяются: novel-fantasy-male.

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort Results By",
      defaultValue = "1",
      options = {
        { value = "1", label = "Popular"         },
        { value = "2", label = "Recommended"     },
        { value = "3", label = "Most Collections" },
        { value = "4", label = "Rating"          },
        { value = "5", label = "Time Updated"    },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Content Status",
      defaultValue = "0",
      options = {
        { value = "0", label = "All"       },
        { value = "2", label = "Completed" },
        { value = "1", label = "Ongoing"   },
      }
    },
    {
      type         = "select",
      key          = "genres_gender",
      label        = "Genres (Male/Female)",
      defaultValue = "1",
      options = {
        { value = "1", label = "Male"   },
        { value = "2", label = "Female" },
      }
    },
    {
      type         = "select",
      key          = "genres_male",
      label        = "Male Genres",
      defaultValue = "1",
      options = {
        { value = "1",     label = "All"       },
        { value = "action",     label = "Action"      },
        { value = "acg",        label = "ACG"         },
        { value = "eastern",    label = "Eastern"     },
        { value = "fantasy",    label = "Fantasy"     },
        { value = "games",      label = "Games"       },
        { value = "history",    label = "History"     },
        { value = "horror",     label = "Horror"      },
        { value = "realistic",  label = "Realistic"   },
        { value = "scifi",      label = "Sci-fi"      },
        { value = "sports",     label = "Sports"      },
        { value = "urban",      label = "Urban"       },
        { value = "war",        label = "War"         },
      }
    },
    {
      type         = "select",
      key          = "genres_female",
      label        = "Female Genres",
      defaultValue = "1",
      options = {
        { value = "1",     label = "All"       },
        { value = "fantasy",    label = "Fantasy"  },
        { value = "general",    label = "General"  },
        { value = "history",    label = "History"  },
        { value = "lgbt",       label = "LGBT+"    },
        { value = "scifi",      label = "Sci-fi"   },
        { value = "teen",       label = "Teen"     },
        { value = "urban",      label = "Urban"    },
      }
    },
    {
      type         = "select",
      key          = "type",
      label        = "Content Type",
      defaultValue = "0",
      options = {
        { value = "0", label = "All"                },
        { value = "1", label = "Translate"           },
        { value = "2", label = "Original"            },
        { value = "3", label = "MTL (Machine Translation)" },
      }
    },
    {
      type         = "checkbox",
      key          = "tags",
      label        = "Tags (sort/status ignored)",
      multiselect  = false,
      options = {
        { value = "academy-novel",          label = "Academy"          },
        { value = "action-novel",           label = "Action"           },
        { value = "adventure-novel",        label = "Adventure"        },
        { value = "antihero-novel",         label = "Antihero"         },
        { value = "bloodpumping-novel",     label = "Bloodpumping"     },
        { value = "comedy-novel",           label = "Comedy"           },
        { value = "conquer-novel",          label = "Conquer"          },
        { value = "cultivation-novel",      label = "Cultivation"      },
        { value = "dark-novel",             label = "Dark"             },
        { value = "devil-novel",            label = "Devil"            },
        { value = "ecchi-novel",            label = "Ecchi"            },
        { value = "egoist-novel",           label = "Egoist"           },
        { value = "genius-novel",           label = "Genius"           },
        { value = "harem-novel",            label = "Harem"            },
        { value = "invincible-novel",       label = "Invincible"       },
        { value = "isekai-novel",           label = "Isekai"           },
        { value = "kingdombuilding-novel",  label = "Kingdombuilding"  },
        { value = "levelup-novel",          label = "Levelup"          },
        { value = "magic-novel",            label = "Magic"            },
        { value = "mystery-novel",          label = "Mystery"          },
        { value = "myth-novel",             label = "Myth"             },
        { value = "no-harem-novel",         label = "No Harem"         },
        { value = "overpowered-novel",      label = "Overpowered"      },
        { value = "r18-novel",              label = "R18"              },
        { value = "rarebloodline-novel",    label = "Rarebloodline"    },
        { value = "reincarnation-novel",    label = "Reincarnation"    },
        { value = "romance-novel",          label = "Romance"          },
        { value = "sliceoflife-novel",      label = "Slice of Life"    },
        { value = "smut-novel",             label = "Smut"             },
        { value = "superpowers-novel",      label = "Superpowers"      },
        { value = "system-novel",           label = "System"           },
        { value = "thestrongactingweak-novel", label = "The Strong Acting Weak" },
        { value = "tragedy-novel",          label = "Tragedy"          },
        { value = "transmigration-novel",   label = "Transmigration"   },
        { value = "urban-novel",            label = "Urban"            },
        { value = "villain-novel",          label = "Villain"          },
        { value = "weaktostrong-novel",     label = "Weak to Strong"   },
        { value = "wizards-novel",          label = "Wizards"          },
        { value = "yandere-novel",          label = "Yandere"          },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page       = index + 1
  local sort       = filters["sort"]       or "1"
  local status     = filters["status"]     or "0"
  local gender     = filters["genres_gender"] or "1"
  local genre_m    = filters["genres_male"]   or "1"
  local genre_f    = filters["genres_female"]  or "1"
  local ctype      = filters["type"]       or "0"
  local tags       = filters["tags_included"] or {}

  -- Теги: /tags/{slug} — отдельный маршрут, сортировка/статус не работают
  if #tags > 0 then
    local tag = tags[1]
    local url = baseUrl .. "tags/" .. tag .. "?pageIndex=" .. tostring(page)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseTagPage(r.body)
    return { items = items, hasNext = #items >= 20 }
  end

  -- Обычный каталог: /stories/novel-{genre}-{gender}
  local genrePath = "novel"
  if gender == "1" then
    if genre_m ~= "1" then
      genrePath = "novel-" .. genre_m .. "-male"
    end
  else
    if genre_f ~= "1" then
      genrePath = "novel-" .. genre_f .. "-female"
    end
  end

  local url = baseUrl .. "stories/" .. genrePath
             .. "?orderBy=" .. url_encode(sort)
             .. "&bookStatus=" .. url_encode(status)
             .. "&pageIndex=" .. tostring(page)

  -- sourceType и translateMode: MTL (value "3") требует оба параметра
  if ctype == "3" then
    url = url .. "&translateMode=3&sourceType=1"
  else
    url = url .. "&sourceType=" .. url_encode(ctype)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, li in ipairs(html_select(r.body, ".j_category_wrapper li")) do
    local gt = html_select_first(li.html, ".g_thumb")
    if gt then
      local title = gt.title or ""
      local href = gt.href or ""
      if title ~= "" and href ~= "" then
        local cover = html_attr(li.html, ".g_thumb img", "data-original")
        if cover == "" then cover = html_attr(li.html, ".g_thumb img", "src") end
        -- Рейтинг: первый strong внутри p.df.aic → span "4.71"
        local rating = ""
        local rs = html_select_first(li.html, "p.df.aic strong span")
        if rs then rating = string_clean(rs.text) end
        local item = {
          title = string_clean(title),
          url   = absUrl(href),
          cover = absUrl(cover),
        }
        if rating ~= "" then item.rating = rating end
        table.insert(items, item)
      end
    end
  end

  local hasNext = #items >= 20
  return { items = items, hasNext = hasNext }
end

function getBookTitle(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local og = html_attr(body, "meta[property='og:title']", "content")
  if og ~= "" then return string_clean(og) end
  local h1 = html_select_first(body, "h1")
  if h1 then return string_clean(h1.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local og = html_attr(body, "meta[property='og:image']", "content")
  if og ~= "" then return absUrl(og) end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local meta = html_attr(body, "meta[name='description']", "content")
  if meta ~= "" then
    meta = regex_replace(meta, "(?i)^Read\\s+['\"]?.+?['\"]?\\s+Online\\s+for\\s+Free,\\s+written\\s+by\\s+the\\s+author\\s+.+?,\\s+This\\s+book\\s+is\\s+a\\s+\\w+\\s+Novel,\\s+covering\\s+.+?\\s+and\\s+the\\s+synopsis\\s+is:\\s*", "")
    return string_trim(meta)
  end
  return nil
end

function getBookGenres(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, a in ipairs(html_select(body, ".m-tags a, .book-info a[href*='/tags/']")) do
    local g = string_trim(a.text)
    if g ~= "" then table.insert(genres, g) end
  end
  return genres
end

-- ── Rating ─────────────────────────────────────────────────────────────────────

-- Рейтинг книги со страницы книги: <p class="_score">…<strong>4.71</strong></p>
-- (сильное — точное число; если рейтинга нет, strong пустой и сайт показывает
-- "Not enough ratings" — тогда nil).
-- Фолбэк: JSON-LD AggregateRating (только если ._score отсутствует вовсе).
function getBookRating(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local strong = html_select_first(body, "._score strong")
  if strong then
    local v = string_clean(strong.text)
    if v ~= "" then return v end
    return nil
  end
  local m = regex_match(body, '"aggregateRating"\\s*:\\s*\\{[^}]*?"ratingValue"\\s*:\\s*"([^"]+)"')
  if m then return m[1] or nil end
  return nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────
-- Все главы на одной странице /catalog.
-- Селектор: .content-list li a[href][title], номер в i._num
-- Платные главы: svg use[href*="lock"] или svg use[xlink:href*="lock"]

function getChapterList(bookUrl)
  local catalogUrl = bookUrl .. "/catalog"
  local r = http_get(catalogUrl)
  if not r.success then return {} end

  local chapters = {}
  for _, li in ipairs(html_select(r.body, ".content-list li")) do
    local a = html_select_first(li.html, "a[href]")
    if a then
      local href = a.href or ""
      local title = a.title or ""
      if href ~= "" and title ~= "" then
        local isLocked = html_select_first(li.html, "svg") ~= nil
        if isLocked then
          title = title .. " 🔒"
        end
        table.insert(chapters, {
          title = string_clean(title),
          url   = absUrl(href),
        })
      end
    end
  end

  return chapters
end

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl .. "/catalog")
  if not r.success then return nil end
  local lis = html_select(r.body, ".content-list li")
  if #lis == 0 then return nil end
  local lastA = html_select_first(lis[#lis].html, "a[href]")
  return lastA and absUrl(lastA.href) or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────
-- Контейнер: .cha-words (div > p), заголовок: .cha-tit
-- Удаляем .para-comment (комментарии к абзацам) перед извлечением.

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".para-comment", "nav", "header", "footer")
  local el = html_select_first(cleaned, ".cha-words")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end
