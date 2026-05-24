-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "wuxia_world_site"
name     = "WuxiaWorld.site"
version  = "1.0.2"
baseUrl  = "https://wuxiaworld.site/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/wuxiaworld.site.png"

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
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = string_trim(text)
  return text
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "novel/?m_orderby=trending"
  if page > 1 then url = url .. "&page=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".page-item-detail")) do
    local titleEl = html_select_first(card.html, ".post-title h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".c-image-hover img", "data-src")
      if cover == "" then cover = html_attr(card.html, ".c-image-hover img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local url
  if page == 1 then
    url = baseUrl .. "?s=" .. url_encode(query) .. "&post_type=wp-manga"
  else
    url = baseUrl .. "page/" .. tostring(page) .. "/?s=" .. url_encode(query) .. "&post_type=wp-manga"
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".c-tabs-item__content")) do
    local titleEl = html_select_first(card.html, ".post-title h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".c-image-hover img", "data-src")
      if cover == "" then cover = html_attr(card.html, ".c-image-hover img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
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
  local src = html_attr(r.body, ".summary_image img", "data-src")
  if src == "" then src = html_attr(r.body, ".summary_image img", "src") end
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".summary__content")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (POST AJAX) ───────────────────────────────────────────────────

function getChapterList(bookUrl)
  local ajaxUrl = bookUrl:gsub("/?$", "") .. "/ajax/chapters/"

  local r = http_post(ajaxUrl, "", {
    headers = {
      ["Referer"] = bookUrl,
      ["X-Requested-With"] = "XMLHttpRequest"
    }
  })
  if not r.success then
    log_error("wuxiaworld.site: AJAX failed " .. tostring(r.code))
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "li.wp-manga-chapter a[href]")) do
    local chUrl = absUrl(a.href)
    local t = string_trim(a.text)
    if chUrl ~= "" then
      table.insert(chapters, { title = t, url = chUrl })
    end
  end

  -- API отдаёт newest-first → разворачиваем
  local reversed = {}
  for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
  return reversed
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "#btn-read-first")
  if el then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", ".ads", ".advertisement", ".social-share")
  local el = html_select_first(cleaned, ".reading-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  local genres = {}
  for _, a in ipairs(html_select(r.body, ".genres-content a")) do
    local g = string_trim(a.text)
    if g ~= "" then table.insert(genres, g) end
  end
  return genres
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "m_orderby",
      label        = "Order by",
      defaultValue = "trending",
      options = {
        { value = "trending",   label = "Trending"    },
        { value = "latest",     label = "Latest"      },
        { value = "alphabet",   label = "A-Z"         },
        { value = "rating",     label = "Rating"      },
        { value = "views",      label = "Most Views"  },
        { value = "new-manga",  label = "New"         },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",         label = "All"       },
        { value = "on-going", label = "Ongoing"   },
        { value = "end",      label = "Completed" },
        { value = "canceled", label = "Canceled"  },
        { value = "on-hold",  label = "On Hold"   },
      }
    },
    {
      type         = "select",
      key          = "adult",
      label        = "Adult Content",
      defaultValue = "",
      options = {
        { value = "",  label = "All"        },
        { value = "0", label = "No Adult"   },
        { value = "1", label = "Only Adult" },
      }
    },
    {
      type    = "checkbox",
      key     = "genre",
      label   = "Genres",
      options = {
        { value = "action",             label = "Action"          },
        { value = "adult",              label = "Adult"           },
        { value = "adventure",          label = "Adventure"       },
        { value = "comedy",             label = "Comedy"          },
        { value = "drama-genre",        label = "Drama"           },
        { value = "ecchi",              label = "Ecchi"           },
        { value = "fantasy",            label = "Fantasy"         },
        { value = "gender-bender",      label = "Gender Bender"   },
        { value = "harems-novel",       label = "Harem"           },
        { value = "historical",         label = "Historical"      },
        { value = "horror",             label = "Horror"          },
        { value = "isekai",             label = "Isekai"          },
        { value = "josei",              label = "Josei"           },
        { value = "lgbt",               label = "LGBT+"           },
        { value = "magical-realism",    label = "Magical Realism" },
        { value = "manhwa",             label = "Manhwa"          },
        { value = "martial-arts-genre", label = "Martial Arts"    },
        { value = "mature",             label = "Mature"          },
        { value = "mecha",              label = "Mecha"           },
        { value = "mystery",            label = "Mystery"         },
        { value = "psychological",      label = "Psychological"   },
        { value = "reincarnation",      label = "Reincarnation"   },
        { value = "romance",            label = "Romance"         },
        { value = "school-life",        label = "School Life"     },
        { value = "sci-fi",             label = "Sci-fi"          },
        { value = "seinen",             label = "Seinen"          },
        { value = "shoujo-genre",       label = "Shoujo"          },
        { value = "shoujo-ai",          label = "Shoujo Ai"       },
        { value = "shounen",            label = "Shounen"         },
        { value = "shounen-ai",         label = "Shounen Ai"      },
        { value = "slice-of-life",      label = "Slice of Life"   },
        { value = "smut",               label = "Smut"            },
        { value = "sports",             label = "Sports"          },
        { value = "supernatural",       label = "Supernatural"    },
        { value = "teen",               label = "Teen"            },
        { value = "thriller",           label = "Thriller"        },
        { value = "tragedy",            label = "Tragedy"         },
        { value = "video-games",        label = "Video Games"     },
        { value = "wuxia",              label = "Wuxia"           },
        { value = "xianxia",            label = "Xianxia"         },
        { value = "xuanhuan",           label = "Xuanhuan"        },
        { value = "yaoi",               label = "Yaoi"            },
        { value = "yuri",               label = "Yuri"            },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page    = index + 1
  local orderby = filters["m_orderby"] or "trending"
  local status  = filters["status"]    or ""
  local adult   = filters["adult"]     or ""
  local genres  = filters["genre_included"] or {}

  local url = baseUrl .. "?s=&post_type=wp-manga"
  url = url .. "&m_orderby=" .. url_encode(orderby)
  for _, g in ipairs(genres) do
    url = url .. "&genre%5B%5D=" .. url_encode(g)
  end
  if #genres > 0 then url = url .. "&op=1" end
  if adult ~= "" then url = url .. "&adult=" .. url_encode(adult) end
  if status ~= "" then url = url .. "&status%5B%5D=" .. url_encode(status) end
  if page > 1 then url = url .. "&paged=" .. tostring(page) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".c-tabs-item__content")) do
    local titleEl = html_select_first(card.html, ".post-title h3 a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".tab-thumb img", "data-src")
      if cover == "" then cover = html_attr(card.html, ".tab-thumb img", "src") end
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end
