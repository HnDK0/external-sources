-- ── Метаданные ────────────────────────────────────────────────────────────────
id        = "NovelBin"
name      = "Novel Bin"
version   = "1.0.5"
baseUrl   = "https://novelbin.com/"
language  = "en"
icon      = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelbin.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function transformCoverUrl(coverUrl, bookUrl)
  if not bookUrl or bookUrl == "" then return coverUrl end
  local slug = bookUrl:match("([^/]+)%.html$") or bookUrl:match("([^/]+)$")
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

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "h3.title")
  if el then return string_trim(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local url = html_attr(r.body, "meta[property='og:image']", "content")
  if url ~= "" then return absUrl(url) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div.desc-text")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (AJAX_BASED) ──────────────────────────────────────────────────

function getChapterList(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then
    log_error("getChapterList: failed to load " .. bookUrl)
    return {}
  end

  local ogUrl = html_attr(r.body, "meta[property='og:url']", "content")
  if ogUrl == "" then
    log_error("getChapterList: no og:url meta")
    return {}
  end

  local m = regex_match(ogUrl, "([^/?#]+)/*$")
  if not m[1] then
    log_error("getChapterList: cannot extract novelId from " .. ogUrl)
    return {}
  end

  local ajaxUrl = "https://novelbin.com/ajax/chapter-archive?novelId=" .. m[1]
  local ar = http_get(ajaxUrl)
  if not ar.success then
    log_error("getChapterList: AJAX failed code=" .. tostring(ar.code))
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(ar.body, "ul.list-chapter li a")) do
    local title = string_trim(a.text)
    if title == "" then title = a.href end
    table.insert(chapters, { title = title, url = a.href })
  end

  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".l-chapter a.chapter-title")
  if el then return el.href end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html)
  local cleaned = html_remove(html, "script", "style", ".ads", "h3", ".chapter-warning", ".ad-insert", "[id^=pf-]")
  local el = html_select_first(cleaned, "#chr-content")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

-- ── Жанры книги ───────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end
  local genres = {}
  for _, li in ipairs(html_select(r.body, "ul.info.info-meta li, ul.info-meta li")) do
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