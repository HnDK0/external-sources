-- ── Метаданные ────────────────────────────────────────────────────────────────
id        = "NovelBin"
name      = "Novel Bin"
version   = "1.1.0"
baseUrl   = "https://novelbin.com/"
language  = "en"
icon      = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbin.png"

-- ── Кэш страниц (1 запрос вместо 4–5) ────────────────────────────────────────

local _pageCache = {}

local function fetchPage(url)
  if _pageCache[url] then return _pageCache[url] end
  local r = http_get(url)
  if r.success then
    _pageCache[url] = r.body
    return r.body
  end
  return nil
end

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function transformCoverUrl(coverUrl, bookUrl)
  if not bookUrl or bookUrl == "" then return coverUrl end
  local slug = bookUrl:match("([^/?#]+)%.html$") or bookUrl:match("([^/?#]+)/?$")
  if slug then
    return "https://images.novelbin.me/novel/" .. slug .. ".jpg"
  end
  return coverUrl
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?i)Remove\\s+Ads\\s+From\\s+\\$\\d+", "")
  text = string_trim(text)
  return text
end

local function parseCatalogItems(body, useDataSrc)
  local items = {}
  for _, row in ipairs(html_select(body, ".col-novel-main .row")) do
    local titleEl = html_select_first(row.html, ".novel-title a")
    if titleEl then
      local currentUrl = absUrl(titleEl.href)
      local cover = ""
      if useDataSrc then
        cover = html_attr(row.html, "img[data-src]", "data-src")
      end
      if cover == "" then
        cover = html_attr(row.html, "img[src]", "src")
      end
      table.insert(items, {
        title = string_trim(titleEl.text),
        url   = currentUrl,
        cover = transformCoverUrl(cover, currentUrl)
      })
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "sort/top-view-novel"
  if page > 1 then url = url .. "?page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body, true)
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "search?keyword=" .. url_encode(query)
  if page > 1 then url = url .. "&page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body, false)
  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги (все через кэш — 1 запрос) ──────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h3.title")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local url = html_attr(body, "meta[property='og:image']", "content")
  return url ~= "" and absUrl(url) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "div.desc-text")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, li in ipairs(html_select(body, "ul.info.info-meta li, ul.info-meta li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Genre:" then
      for _, a in ipairs(html_select(li.html, "a")) do
        local g = string_trim(a.text)
        if g ~= "" then table.insert(genres, g) end
      end
      break
    end
  end
  return genres
end

-- ── Список глав (AJAX) ────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then
    log_error("getChapterList: failed to load " .. bookUrl)
    return {}
  end

  local ogUrl = html_attr(body, "meta[property='og:url']", "content")
  if ogUrl == "" then
    log_error("getChapterList: no og:url meta")
    return {}
  end

  local m = regex_match(ogUrl, "([^/?#]+)/*$")
  if not m[1] then
    log_error("getChapterList: cannot extract novelId from " .. ogUrl)
    return {}
  end

  local ajaxUrl = baseUrl:gsub("/$", "") .. "/ajax/chapter-archive?novelId=" .. m[1]
  local ar = http_get(ajaxUrl, {
    headers = {
      ["Referer"]          = bookUrl,
      ["X-Requested-With"] = "XMLHttpRequest",
    }
  })
  if not ar.success then
    log_error("getChapterList: AJAX failed code=" .. tostring(ar.code))
    return {}
  end

  -- Главы внутри <template>, берём его innerHTML напрямую
  local tmpl = html_select_first(ar.body, "template[data-chapter-item-template]")
  if not tmpl then
    log_error("getChapterList: template element not found")
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(tmpl.html, "a[href]")) do
    local span = html_select_first(a.html, "span.nchr-text")
    local title = span and string_trim(span.text) or ""
    if title == "" then title = string_trim(a.title or "") end
    if title == "" then title = string_trim(a.text) end
    if title == "" then title = a.href end
    table.insert(chapters, { title = title, url = a.href })
  end

  log_error("getChapterList: found " .. tostring(#chapters) .. " chapters")
  return chapters
end
-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".l-chapter a.chapter-title")
  return el and el.href or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html)
  local el = html_select_first(html, "#chr-content")
  if not el then return "" end
  local cleaned = html_remove(el.html, "script", "style", ".ads", "h3", "h4", ".chapter-warning", ".ad-insert", "[id^=pf-]")
  return applyStandardContentTransforms(html_text(cleaned))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "type",
      label        = "Novel Listing",
      defaultValue = "sort/top-view-novel",
      options = {
        { value = "sort/top-view-novel", label = "Most Popular"    },
        { value = "sort/top-hot-novel",  label = "Hot Novel"       },
        { value = "sort/completed",      label = "Completed Novel" },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "",
      options = {
        { value = "",  label = "All"       },
        { value = "1", label = "Ongoing"   },
        { value = "2", label = "Completed" },
      }
    },
    {
      type        = "checkbox",
      key         = "genre",
      label       = "Genre",
      multiselect = false,
      options = {
        { value = "action",         label = "Action"         },
        { value = "adventure",      label = "Adventure"      },
        { value = "anime-&-comics", label = "Anime & Comics" },
        { value = "comedy",         label = "Comedy"         },
        { value = "drama",          label = "Drama"          },
        { value = "eastern",        label = "Eastern"        },
        { value = "fan-fiction",    label = "Fan-fiction"    },
        { value = "fantasy",        label = "Fantasy"        },
        { value = "game",           label = "Game"           },
        { value = "gender-bender",  label = "Gender Bender"  },
        { value = "harem",          label = "Harem"          },
        { value = "historical",     label = "Historical"     },
        { value = "horror",         label = "Horror"         },
        { value = "isekai",         label = "Isekai"         },
        { value = "josei",          label = "Josei"          },
        { value = "litrpg",         label = "LitRPG"         },
        { value = "magic",          label = "Magic"          },
        { value = "martial-arts",   label = "Martial Arts"   },
        { value = "mature",         label = "Mature"         },
        { value = "mecha",          label = "Mecha"          },
        { value = "military",       label = "Military"       },
        { value = "modern-life",    label = "Modern Life"    },
        { value = "mystery",        label = "Mystery"        },
        { value = "psychological",  label = "Psychological"  },
        { value = "reincarnation",  label = "Reincarnation"  },
        { value = "romance",        label = "Romance"        },
        { value = "school-life",    label = "School Life"    },
        { value = "sci-fi",         label = "Sci-fi"         },
        { value = "seinen",         label = "Seinen"         },
        { value = "shoujo",         label = "Shoujo"         },
        { value = "shounen",        label = "Shounen"        },
        { value = "slice-of-life",  label = "Slice of Life"  },
        { value = "smut",           label = "Smut"           },
        { value = "sports",         label = "Sports"         },
        { value = "supernatural",   label = "Supernatural"   },
        { value = "system",         label = "System"         },
        { value = "thriller",       label = "Thriller"       },
        { value = "tragedy",        label = "Tragedy"        },
        { value = "urban-life",     label = "Urban Life"     },
        { value = "war",            label = "War"            },
        { value = "wuxia",          label = "Wuxia"          },
        { value = "xianxia",        label = "Xianxia"        },
        { value = "xuanhuan",       label = "Xuanhuan"       },
        { value = "yaoi",           label = "Yaoi"           },
        { value = "yuri",           label = "Yuri"           },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local ftype  = filters["type"]   or "sort/top-view-novel"
  local status = filters["status"] or ""
  local genres = filters["genre_included"] or {}
  local genre  = genres[1] or ""

  local basePath = genre ~= "" and ("genre/" .. genre) or ftype

  local url = baseUrl .. basePath
  local sep = "?"
  if status ~= "" and genre ~= "" then
    url = url .. sep .. "status=" .. status
    sep = "&"
  end
  if page > 1 then url = url .. sep .. "page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body, true)
  return { items = items, hasNext = #items > 0 }
end
