-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "royal_road"
name     = "Royal Road"
version  = "1.1.0"
baseUrl  = "https://www.royalroad.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/royalroad.png"

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
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Каталог (best-rated, постраничный) ────────────────────────────────────────

function getCatalogList(index)
  local url
  if index == 0 then
    url = baseUrl .. "/fictions/best-rated"
  else
    url = baseUrl .. "/fictions/best-rated?page=" .. tostring(index + 1)
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".fiction-list-item")) do
    local titleEl = html_select_first(card.html, "h2 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, "img", "src")
      -- Рейтинг из карточки: span.star[title="4.83"] либо div[aria-label="Rating: 4.83 out of 5"]
      local rating = html_attr(card.html, "span.star[title]", "title")
      if rating == "" then
        local aria = html_attr(card.html, 'div[aria-label^="Rating:"]', "aria-label")
        if aria ~= "" then
          local m = regex_match(aria, "([\\d.]+)")
          rating = m[1] or ""
        end
      end
      local item = {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = absUrl(cover)
      }
      -- Рейтинга в карточке нет ("Too Few Ratings") — ключ не добавляем (контракт)
      if rating ~= "" then item.rating = rating end
      table.insert(items, item)
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "/fictions/search?title=" .. url_encode(query) .. "&page=" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".fiction-list-item")) do
    local titleEl = html_select_first(card.html, "h2 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, "img", "src")
      -- Рейтинг из карточки: span.star[title="4.83"] либо div[aria-label="Rating: 4.83 out of 5"]
      local rating = html_attr(card.html, "span.star[title]", "title")
      if rating == "" then
        local aria = html_attr(card.html, 'div[aria-label^="Rating:"]', "aria-label")
        if aria ~= "" then
          local m = regex_match(aria, "([\\d.]+)")
          rating = m[1] or ""
        end
      end
      local item = {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = absUrl(cover)
      }
      -- Рейтинга в карточке нет ("Too Few Ratings") — ключ не добавляем (контракт)
      if rating ~= "" then item.rating = rating end
      table.insert(items, item)
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h1.font-white")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local cover = html_attr(r.body, ".cover-art-container img[src]", "src")
  if cover == "" then return nil end
  return absUrl(cover)
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".description")
  return el and string_trim(el.text) or nil
end

-- ── Список глав (NONE — всё на странице книги) ────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then
    log_error("royalroad: getChapterList failed for " .. bookUrl)
    return {}
  end

  local chapters = {}
  -- Таблица глав: tr.chapter-row, первая ячейка содержит ссылку
  for _, a in ipairs(html_select(r.body, "tr.chapter-row td:first-child a[href]")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local title = a.title
      if not title or title == "" then title = string_trim(a.text) end
      table.insert(chapters, { title = string_clean(title), url = chUrl })
    end
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  -- Последняя метка (дата/номер) в заголовке portlet — меняется при новых главах
  local el = html_select_first(r.body, ".portlet-title .actions .label")
  return el and string_clean(el.text) or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", "a", ".ads-title")
  local el = html_select_first(cleaned, ".chapter-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end
-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local genres = {}
  -- span.tags содержит ссылки на жанры/теги
  for _, a in ipairs(html_select(r.body, "span.tags a")) do
    local label = string_trim(a.text)
    if label ~= "" then table.insert(genres, label) end
  end
  return genres
end

-- ── Рейтинг ────────────────────────────────────────────────────────────────

-- Рейтинг книги со страницы книги: <span class="star" aria-label="4.83 stars">
-- Только рейтинг, список глав не парсим (контракт lua-plugin-guide.md:188-192)
function getBookRating(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local label = html_attr(r.body, "span.star[aria-label]", "aria-label")
  if label == "" then return nil end
  local m = regex_match(label, "([\\d.]+)")
  return m[1] and string_trim(m[1]) or nil
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "orderBy",
      label        = "Order by",
      defaultValue = "relevance",
      options = {
        { value = "relevance",    label = "Relevance"       },
        { value = "popularity",   label = "Popularity"      },
        { value = "rating",       label = "Average Rating"  },
        { value = "last_update",  label = "Last Update"     },
        { value = "release_date", label = "Release Date"    },
        { value = "followers",    label = "Followers"       },
        { value = "length",       label = "Number of Pages" },
        { value = "views",        label = "Views"           },
        { value = "title",        label = "Title"           },
        { value = "author",       label = "Author"          },
      }
    },
    {
      type         = "select",
      key          = "dir",
      label        = "Direction",
      defaultValue = "desc",
      options = {
        { value = "asc",  label = "Ascending"  },
        { value = "desc", label = "Descending" },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "ALL",
      options = {
        { value = "ALL",       label = "All"       },
        { value = "COMPLETED", label = "Completed" },
        { value = "DROPPED",   label = "Dropped"   },
        { value = "ONGOING",   label = "Ongoing"   },
        { value = "HIATUS",    label = "Hiatus"    },
        { value = "STUB",      label = "Stub"      },
      }
    },
    {
      type         = "select",
      key          = "type",
      label        = "Type",
      defaultValue = "ALL",
      options = {
        { value = "ALL",        label = "All"         },
        { value = "fanfiction", label = "Fan Fiction" },
        { value = "original",   label = "Original"    },
      }
    },
    {
      type         = "select",
      key          = "minPages",
      label        = "Min Pages",
      defaultValue = "0",
      options = {
        { value = "0",     label = "Any"    },
        { value = "100",   label = "100+"   },
        { value = "500",   label = "500+"   },
        { value = "1000",  label = "1000+"  },
        { value = "2000",  label = "2000+"  },
        { value = "5000",  label = "5000+"  },
        { value = "10000", label = "10000+" },
      }
    },
    {
      type         = "select",
      key          = "maxPages",
      label        = "Max Pages",
      defaultValue = "20000",
      options = {
        { value = "500",   label = "≤ 500"   },
        { value = "1000",  label = "≤ 1000"  },
        { value = "2000",  label = "≤ 2000"  },
        { value = "5000",  label = "≤ 5000"  },
        { value = "10000", label = "≤ 10000" },
        { value = "20000", label = "Any"     },
      }
    },
    {
      type         = "select",
      key          = "minRating",
      label        = "Min Rating",
      defaultValue = "0.0",
      options = {
        { value = "0.0", label = "Any"  },
        { value = "2.0", label = "2.0+" },
        { value = "3.0", label = "3.0+" },
        { value = "3.5", label = "3.5+" },
        { value = "4.0", label = "4.0+" },
        { value = "4.5", label = "4.5+" },
      }
    },
    {
      type         = "select",
      key          = "maxRating",
      label        = "Max Rating",
      defaultValue = "5.0",
      options = {
        { value = "2.0", label = "≤ 2.0" },
        { value = "3.0", label = "≤ 3.0" },
        { value = "3.5", label = "≤ 3.5" },
        { value = "4.0", label = "≤ 4.0" },
        { value = "4.5", label = "≤ 4.5" },
        { value = "5.0", label = "Any"   },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Genres",
      options = {
        { value = "action",        label = "Action"        },
        { value = "adventure",     label = "Adventure"     },
        { value = "comedy",        label = "Comedy"        },
        { value = "contemporary",  label = "Contemporary"  },
        { value = "drama",         label = "Drama"         },
        { value = "fantasy",       label = "Fantasy"       },
        { value = "historical",    label = "Historical"    },
        { value = "horror",        label = "Horror"        },
        { value = "mystery",       label = "Mystery"       },
        { value = "psychological", label = "Psychological" },
        { value = "romance",       label = "Romance"       },
        { value = "satire",        label = "Satire"        },
        { value = "sci_fi",        label = "Sci-fi"        },
        { value = "one_shot",      label = "Short Story"   },
        { value = "tragedy",       label = "Tragedy"       },
      }
    },
    {
      type  = "tristate",
      key   = "tags",
      label = "Tags",
      options = {
        { value = "anti-hero_lead",          label = "Anti-Hero Lead"            },
        { value = "artificial_intelligence", label = "Artificial Intelligence"   },
        { value = "attractive_lead",         label = "Attractive Lead"           },
        { value = "cyberpunk",               label = "Cyberpunk"                 },
        { value = "dungeon",                 label = "Dungeon"                   },
        { value = "dystopia",                label = "Dystopia"                  },
        { value = "female_lead",             label = "Female Lead"               },
        { value = "first_contact",           label = "First Contact"             },
        { value = "gamelit",                 label = "GameLit"                   },
        { value = "gender_bender",           label = "Gender Bender"             },
        { value = "grimdark",                label = "Grimdark"                  },
        { value = "hard_sci-fi",             label = "Hard Sci-fi"               },
        { value = "harem",                   label = "Harem"                     },
        { value = "high_fantasy",            label = "High Fantasy"              },
        { value = "litrpg",                  label = "LitRPG"                    },
        { value = "low_fantasy",             label = "Low Fantasy"               },
        { value = "magic",                   label = "Magic"                     },
        { value = "male_lead",               label = "Male Lead"                 },
        { value = "martial_arts",            label = "Martial Arts"              },
        { value = "multiple_lead",           label = "Multiple Lead Characters"  },
        { value = "mythos",                  label = "Mythos"                    },
        { value = "non-human_lead",          label = "Non-Human Lead"            },
        { value = "summoned_hero",           label = "Portal Fantasy / Isekai"   },
        { value = "post_apocalyptic",        label = "Post Apocalyptic"          },
        { value = "progression",             label = "Progression"               },
        { value = "reader_interactive",      label = "Reader Interactive"        },
        { value = "reincarnation",           label = "Reincarnation"             },
        { value = "ruling_class",            label = "Ruling Class"              },
        { value = "school_life",             label = "School Life"               },
        { value = "secret_identity",         label = "Secret Identity"           },
        { value = "slice_of_life",           label = "Slice of Life"             },
        { value = "soft_sci-fi",             label = "Soft Sci-fi"               },
        { value = "space_opera",             label = "Space Opera"               },
        { value = "sports",                  label = "Sports"                    },
        { value = "steampunk",               label = "Steampunk"                 },
        { value = "strategy",                label = "Strategy"                  },
        { value = "strong_lead",             label = "Strong Lead"               },
        { value = "super_heroes",            label = "Super Heroes"              },
        { value = "supernatural",            label = "Supernatural"              },
        { value = "loop",                    label = "Time Loop"                 },
        { value = "time_travel",             label = "Time Travel"               },
        { value = "urban_fantasy",           label = "Urban Fantasy"             },
        { value = "villainous_lead",         label = "Villainous Lead"           },
        { value = "virtual_reality",         label = "Virtual Reality"           },
        { value = "war_and_military",        label = "War and Military"          },
        { value = "wuxia",                   label = "Wuxia"                     },
        { value = "xianxia",                 label = "Xianxia"                   },
      }
    },
    {
      type  = "tristate",
      key   = "content_warnings",
      label = "Content Warnings",
      options = {
        { value = "profanity",         label = "Profanity"           },
        { value = "sexuality",         label = "Sexual Content"      },
        { value = "graphic_violence",  label = "Graphic Violence"    },
        { value = "sensitive",         label = "Sensitive Content"   },
        { value = "ai_assisted",       label = "AI-Assisted Content" },
        { value = "ai_generated",      label = "AI-Generated Content"},
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page     = index + 1
  local orderBy  = filters["orderBy"]  or "relevance"
  local dir      = filters["dir"]      or "desc"
  local status   = filters["status"]   or "ALL"
  local ftype    = filters["type"]     or "ALL"
  local minPages = filters["minPages"] or "0"
  local maxPages = filters["maxPages"] or "20000"
  local minRating = filters["minRating"] or "0.0"
  local maxRating = filters["maxRating"] or "5.0"

  local genres_inc = filters["genres_included"]           or {}
  local genres_exc = filters["genres_excluded"]           or {}
  local tags_inc   = filters["tags_included"]             or {}
  local tags_exc   = filters["tags_excluded"]             or {}
  local cw_inc     = filters["content_warnings_included"] or {}
  local cw_exc     = filters["content_warnings_excluded"] or {}

  local url = baseUrl .. "/fictions/search?page=" .. tostring(page)

  if orderBy ~= "" then url = url .. "&orderBy=" .. orderBy end
  if dir     ~= "" then url = url .. "&dir="     .. dir     end
  if status  ~= "ALL" then url = url .. "&status=" .. status end
  if ftype   ~= "ALL" then url = url .. "&type="   .. ftype  end

  url = url .. "&minPages="  .. minPages
            .. "&maxPages="  .. maxPages
            .. "&minRating=" .. minRating
            .. "&maxRating=" .. maxRating

  -- genres, tags, content_warnings все идут как tagsAdd/tagsRemove
  for _, v in ipairs(genres_inc) do url = url .. "&tagsAdd="    .. v end
  for _, v in ipairs(genres_exc) do url = url .. "&tagsRemove=" .. v end
  for _, v in ipairs(tags_inc)   do url = url .. "&tagsAdd="    .. v end
  for _, v in ipairs(tags_exc)   do url = url .. "&tagsRemove=" .. v end
  for _, v in ipairs(cw_inc)     do url = url .. "&tagsAdd="    .. v end
  for _, v in ipairs(cw_exc)     do url = url .. "&tagsRemove=" .. v end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".fiction-list-item")) do
    local titleEl = html_select_first(card.html, "h2 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, "img", "src")
      -- Рейтинг из карточки: span.star[title="4.83"] либо div[aria-label="Rating: 4.83 out of 5"]
      local rating = html_attr(card.html, "span.star[title]", "title")
      if rating == "" then
        local aria = html_attr(card.html, 'div[aria-label^="Rating:"]', "aria-label")
        if aria ~= "" then
          local m = regex_match(aria, "([\\d.]+)")
          rating = m[1] or ""
        end
      end
      local item = {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = absUrl(cover)
      }
      -- Рейтинга в карточке нет ("Too Few Ratings") — ключ не добавляем (контракт)
      if rating ~= "" then item.rating = rating end
      table.insert(items, item)
    end
  end

  return { items = items, hasNext = #items > 0 }
end
