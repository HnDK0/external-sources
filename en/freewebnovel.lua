id       = "freewebnovel"
name     = "FreeWebNovel"
version  = "1.0.4"
baseUrl  = "https://freewebnovel.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/freewebnovel.png"

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

local function catalogUrl(basePath, page)
  if page <= 1 then
    return baseUrl .. "/" .. basePath
  end
  return baseUrl .. "/" .. basePath .. "/" .. tostring(page)
end

local function parseItems(html)
  local items = {}
  for _, row in ipairs(html_select(html, ".ul-list1 .li-row, .serach-result .li-row")) do
    local titleEl = html_select_first(row.html, ".tit a")
    if titleEl then
      local cover = absUrl(html_attr(row.html, ".pic img", "src"))
      -- Рейтинг из карточки (каталог, поиск, фильтры):
      -- <div class="core"><span>3.8</span></div>
      local ratingEl = html_select_first(row.html, ".core span")
      local rating = ratingEl and string_clean(ratingEl.text) or ""
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = cover,
        rating = rating
      })
    end
  end
  return items
end

function getCatalogList(index)
  local page = index + 1
  local r = http_get(catalogUrl("sort/most-popular", page))
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "/search?keyword=" .. url_encode(query) .. "&page=" .. tostring(page)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseItems(r.body)
  return { items = items, hasNext = #items > 0 }
end

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.tit")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local src = html_attr(body, ".pic img", "src")
  if not src or src == "" then
    src = html_attr(body, ".pic img", "data-src")
  end
  if not src or src == "" then
    src = html_attr(body, ".books img, .m-imgtxt img", "src")
  end
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".m-desc .txt")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, item in ipairs(html_select(body, ".m-imgtxt .txt .item")) do
    local span = html_select_first(item.html, "span[title='Genre']")
    if span then
      for _, a in ipairs(html_select(item.html, ".right a")) do
        local g = string_trim(a.text)
        if g ~= "" then table.insert(genres, g) end
      end
      break
    end
  end
  return genres
end

-- ── Rating ──────────────────────────────────────────────────────────────

-- Рейтинг книги со страницы книги: <p class="vote">3.8 / 5 ( 653 votes )</p>
-- внутри .score. Извлекаем голое число (шкала 0-5).
function getBookRating(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".score .vote")
  if not el then return nil end
  local n = string.match(string_clean(el.text), "%d+%.?%d*")
  return n or nil
end

local CHAPTERS_PAGE_SIZE = 200

local function fetchChapterPage(bookUrl, page)
  if page > 1 then
    sleep(math.random(150, 350))
  end
  local sep = bookUrl:find("?") and "&" or "?"
  local url = bookUrl .. sep .. "ajax=chapters&page=" .. tostring(page) .. "&pageSize=" .. tostring(CHAPTERS_PAGE_SIZE)
  local r = http_get(url, {
    headers = {
      ["X-Requested-With"] = "XMLHttpRequest",
      ["Accept"]           = "application/json, text/javascript, */*; q=0.01",
    }
  })
  if not r.success then
    log_error("freewebnovel: chapters ajax failed code=" .. tostring(r.code) .. " page=" .. tostring(page))
    return nil
  end
  local data = json_parse(r.body)
  if not data or not data.html then
    log_error("freewebnovel: json_parse failed or missing html, page=" .. tostring(page))
    return nil
  end
  return data
end

function parsePage(bookUrl, page)
  local data = fetchChapterPage(bookUrl, page)
  if not data then return { chapters = {}, totalPages = 1 } end
  local totalPages = tonumber(data.totalPage) or 1
  local chapters = {}
  for _, a in ipairs(html_select(data.html, "a[href]")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local title = a:attr("title")
      if not title or title == "" then title = string_clean(a.text) end
      table.insert(chapters, {
        title = string_clean(title),
        url   = chUrl
      })
    end
  end
  return { chapters = chapters, totalPages = totalPages }
end

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads", ".advertisement", ".chapter-nav", ".nav-links", "h4", "sub")
  local el = html_select_first(cleaned, "div.txt")
  if not el then
    el = html_select_first(cleaned, "#chapter-content, #chr-content")
  end
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end

function getFilterList()
  return {
    {
      type         = "select",
      key          = "type",
      label        = "Novel Type",
      defaultValue = "sort/most-popular",
      options = {
        { value = "sort/most-popular",                 label = "Most Popular"    },
        { value = "sort/latest-release",               label = "Latest Release"  },
        { value = "sort/latest-release/chinese-novel", label = "Chinese Novel"   },
        { value = "sort/latest-release/korean-novel",  label = "Korean Novel"    },
        { value = "sort/latest-release/japanese-novel",label = "Japanese Novel"  },
        { value = "sort/latest-release/english-novel", label = "English Novel"   },
      }
    },
    {
      type         = "select",
      key          = "genre",
      label        = "Genre",
      defaultValue = "",
      options = {
        { value = "",               label = "All"           },
        { value = "genre/Action",        label = "Action"        },
        { value = "genre/Adult",         label = "Adult"         },
        { value = "genre/Adventure",     label = "Adventure"     },
        { value = "genre/Comedy",        label = "Comedy"        },
        { value = "genre/Drama",         label = "Drama"         },
        { value = "genre/Eastern",       label = "Eastern"       },
        { value = "genre/Ecchi",         label = "Ecchi"         },
        { value = "genre/Fantasy",       label = "Fantasy"       },
        { value = "genre/Game",          label = "Game"          },
        { value = "genre/Gender+Bender", label = "Gender Bender" },
        { value = "genre/Harem",         label = "Harem"         },
        { value = "genre/Historical",    label = "Historical"    },
        { value = "genre/Horror",        label = "Horror"        },
        { value = "genre/Josei",         label = "Josei"         },
        { value = "genre/Martial+Arts",  label = "Martial Arts"  },
        { value = "genre/Mature",        label = "Mature"        },
        { value = "genre/Mecha",         label = "Mecha"         },
        { value = "genre/Mystery",       label = "Mystery"       },
        { value = "genre/Psychological", label = "Psychological" },
        { value = "genre/Reincarnation", label = "Reincarnation" },
        { value = "genre/Romance",       label = "Romance"       },
        { value = "genre/School+Life",   label = "School Life"   },
        { value = "genre/Sci-fi",        label = "Sci-fi"        },
        { value = "genre/Seinen",        label = "Seinen"        },
        { value = "genre/Shoujo",        label = "Shoujo"        },
        { value = "genre/Shounen+Ai",    label = "Shounen Ai"    },
        { value = "genre/Shounen",       label = "Shounen"       },
        { value = "genre/Slice+of+Life", label = "Slice of Life" },
        { value = "genre/Smut",          label = "Smut"          },
        { value = "genre/Sports",        label = "Sports"        },
        { value = "genre/Supernatural",  label = "Supernatural"  },
        { value = "genre/Tragedy",       label = "Tragedy"       },
        { value = "genre/Wuxia",         label = "Wuxia"         },
        { value = "genre/Xianxia",       label = "Xianxia"       },
        { value = "genre/Xuanhuan",      label = "Xuanhuan"      },
        { value = "genre/Yaoi",          label = "Yaoi"          },
      }
    },
  }
end

function getCatalogFiltered(index, filters)
  local page   = index + 1
  local ftype  = filters["type"] or "sort/most-popular"
  local genre  = filters["genre"] or ""

  local basePath = genre ~= "" and genre or ftype

  local r = http_get(catalogUrl(basePath, page))
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseItems(r.body)
  return { items = items, hasNext = #items > 0 }
end
