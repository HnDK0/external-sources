id       = "novelfire"
name     = "NovelFire"
version  = "1.0.5"
baseUrl  = "https://novelfire.net"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelfire.png"

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
    local url = baseUrl .. "/search-adv?ctgcon=and&totalchapter=0&ratcon=min&rating=0&status=-1&sort=rank-top&page=" .. page

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-list > .novel-item")) do
        local titleEl = html_select_first(card.html, ".novel-title")
        local linkEl  = html_select_first(card.html, ".novel-title a")
        local cover   = html_attr(card.html, "img", "data-src")
        if cover == "" then cover = html_attr(card.html, "img", "src") end
        
        if titleEl and linkEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(linkEl.href),
                cover = absUrl(cover)
            })
        end
    end
    return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "/search?keyword=" .. url_encode(query) .. "&page=" .. page

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, card in ipairs(html_select(r.body, ".novel-list.chapters .novel-item")) do
        local titleEl = html_select_first(card.html, ".novel-title")
        local linkEl  = html_select_first(card.html, "a")
        local cover   = html_attr(card.html, "img", "src")
        
        if titleEl and linkEl then
            table.insert(items, {
                title = string_clean(titleEl.text),
                url   = absUrl(linkEl.href),
                cover = absUrl(cover)
            })
        end
    end
    return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.novel-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, "img[src*='server-1']", "src")
    if cover == "" then cover = html_attr(r.body, ".cover img", "src") end
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cleaned = html_remove(r.body, "h4.lined")
    local el = html_select_first(cleaned, ".summary .content, .summary")
    return el and string_trim(el.text) or nil
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    -- ── Шаг 1: получаем post_id со страницы книги ──────────────────────────
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local postId = html_attr(r.body, "#novel-report", "report-post_id")
    if not postId or postId == "" then return {} end

    -- ── Шаг 2: один AJAX запрос — все главы сразу ──────────────────────────
    local ajaxUrl = baseUrl .. "/ajax/listChapterDataAjax"
    local params = "draw=1"
        .. "&columns%5B0%5D%5Bdata%5D=n_sort"
        .. "&columns%5B0%5D%5Bname%5D=cmm_posts_detail.n_sort"
        .. "&columns%5B0%5D%5Bsearchable%5D=true"
        .. "&columns%5B0%5D%5Borderable%5D=true"
        .. "&columns%5B0%5D%5Bsearch%5D%5Bvalue%5D="
        .. "&columns%5B0%5D%5Bsearch%5D%5Bregex%5D=false"
        .. "&columns%5B1%5D%5Bdata%5D=bookmark_created_at"
        .. "&columns%5B1%5D%5Bname%5D=bookmark_chapters.created_at"
        .. "&columns%5B1%5D%5Bsearchable%5D=false"
        .. "&columns%5B1%5D%5Borderable%5D=true"
        .. "&columns%5B1%5D%5Bsearch%5D%5Bvalue%5D="
        .. "&columns%5B1%5D%5Bsearch%5D%5Bregex%5D=false"
        .. "&order%5B0%5D%5Bcolumn%5D=0"
        .. "&order%5B0%5D%5Bdir%5D=asc"
        .. "&order%5B0%5D%5Bname%5D=cmm_posts_detail.n_sort"
        .. "&start=0"
        .. "&length=-1"
        .. "&search%5Bvalue%5D="
        .. "&search%5Bregex%5D=false"
        .. "&post_id=" .. postId
        .. "&only_bookmark=false"

    local bookSlug = bookUrl:match("/([^/]+)$")
    local ar = http_get(ajaxUrl .. "?" .. params)
    if not ar.success then return {} end

    -- ── Шаг 3: парсим JSON ─────────────────────────────────────────────────
    local json = json_parse(ar.body)
    if not json or not json.data then return {} end

    local chapters = {}
    for _, item in ipairs(json.data) do
        local nSort = item.n_sort
        if nSort then
            local title = item.title or ("Chapter " .. tostring(nSort))
            local cleanTitle = string_clean(regex_replace(title, "<[^>]+>", ""))
            local chUrl = baseUrl .. "/book/" .. bookSlug .. "/chapter-" .. tostring(nSort)
            table.insert(chapters, { title = cleanTitle, url = chUrl })
        end
    end

    table.sort(chapters, function(a, b)
        local na = tonumber(a.url:match("chapter%-(%d+)$")) or 0
        local nb = tonumber(b.url:match("chapter%-(%d+)$")) or 0
        return na < nb
    end)

    return chapters
end

--[[ Старый способ через HTML пагинацию (на случай если AJAX сломается)

function getChapterList(bookUrl)
    local bookSlug = bookUrl:match("/([^/]+)$")
    local firstPageUrl = baseUrl .. "/book/" .. bookSlug .. "/chapters?page=1"

    local r = http_get(firstPageUrl)
    if not r.success then return {} end

    local maxPage = 1
    for _, a in ipairs(html_select(r.body, ".pagination a[href*='?page=']")) do
        local p = tonumber(a.href:match("page=(%d+)"))
        if p and p > maxPage then maxPage = p end
    end

    local function parsePage(html)
        local res = {}
        for _, a in ipairs(html_select(html, "a[href*='/chapter-']")) do
            table.insert(res, { title = string_clean(a.title), url = absUrl(a.href) })
        end
        return res
    end

    local allChapters = parsePage(r.body)

    if maxPage > 1 then
        local CHUNK = 19
        for chunkStart = 2, maxPage, CHUNK do
            local chunkEnd = math.min(chunkStart + CHUNK - 1, maxPage)
            local urls = {}
            for p = chunkStart, chunkEnd do
                table.insert(urls, baseUrl .. "/book/" .. bookSlug .. "/chapters?page=" .. p)
            end
            local results = http_get_batch(urls)
            local sorted = {}
            for _, res in ipairs(results) do
                if res.success then
                    local p = tonumber(res.url and res.url:match("page=(%d+)")) or 0
                    table.insert(sorted, { page = p, body = res.body })
                end
            end
            table.sort(sorted, function(a, b) return a.page < b.page end)
            for _, item in ipairs(sorted) do
                for _, ch in ipairs(parsePage(item.body)) do
                    table.insert(allChapters, ch)
                end
            end
            if chunkEnd < maxPage then sleep(2000) end
        end
    end
    return allChapters
end
]]

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".body p.latest")
    return el and string_clean(el.text) or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    local cleaned = html_remove(html, "script", "nav", ".ads", ".advertisement", 
                                ".disqus", ".comments", ".c-message", ".nav-next", ".nav-previous")
    local el = html_select_first(cleaned, "#content, .chapter-content, div.entry-content")
    if not el then return "" end
    
    -- Ключевой момент: html_text сохраняет переносы строк
    return applyStandardContentTransforms(html_text(el.html))
end
-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local genres = {}
  for _, a in ipairs(html_select(r.body, ".categories .property-item")) do
    local label = string_trim(a.text)
    if label ~= "" then table.insert(genres, label) end
  end
  return genres
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort Results By",
      defaultValue = "rank-top",
      options = {
        { value = "rank-top",          label = "Rank (Top)"                 },
        { value = "rating-score-top",  label = "Rating Score (Top)"         },
        { value = "review",            label = "Review Count (Most)"        },
        { value = "comment",           label = "Comment Count (Most)"       },
        { value = "bookmark",          label = "Bookmark Count (Most)"      },
        { value = "today-view",        label = "Today Views (Most)"         },
        { value = "monthly-view",      label = "Monthly Views (Most)"       },
        { value = "total-view",        label = "Total Views (Most)"         },
        { value = "abc",               label = "Title (A>Z)"                },
        { value = "cba",               label = "Title (Z>A)"                },
        { value = "date",              label = "Last Updated (Newest)"      },
        { value = "chapter-count-most",label = "Chapter Count (Most)"       },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Translation Status",
      defaultValue = "-1",
      options = {
        { value = "-1", label = "All"       },
        { value = "1",  label = "Completed" },
        { value = "0",  label = "Ongoing"   },
      }
    },
    {
      type         = "select",
      key          = "genre_operator",
      label        = "Genres (And/Or/Exclude)",
      defaultValue = "and",
      options = {
        { value = "and",     label = "AND"     },
        { value = "or",      label = "OR"      },
        { value = "exclude", label = "EXCLUDE" },
      }
    },
    {
      type         = "select",
      key          = "rating_operator",
      label        = "Rating (Min/Max)",
      defaultValue = "min",
      options = {
        { value = "min", label = "Min" },
        { value = "max", label = "Max" },
      }
    },
    {
      type         = "select",
      key          = "rating",
      label        = "Rating",
      defaultValue = "0",
      options = {
        { value = "0", label = "All" },
        { value = "1", label = "1"   },
        { value = "2", label = "2"   },
        { value = "3", label = "3"   },
        { value = "4", label = "4"   },
        { value = "5", label = "5"   },
      }
    },
    {
      type         = "select",
      key          = "chapters",
      label        = "Chapters",
      defaultValue = "0",
      options = {
        { value = "0",           label = "All"         },
        { value = "1,49",        label = "<50"         },
        { value = "50,100",      label = "50-100"      },
        { value = "100,200",     label = "100-200"     },
        { value = "200,500",     label = "200-500"     },
        { value = "500,1000",    label = "500-1000"    },
        { value = "1001,1000000",label = ">1000"       },
      }
    },
    {
      type  = "checkbox",
      key   = "language",
      label = "Language",
      options = {
        { value = "1", label = "Chinese"  },
        { value = "2", label = "Korean"   },
        { value = "3", label = "Japanese" },
        { value = "4", label = "English"  },
      }
    },
    {
      type  = "checkbox",
      key   = "genres",
      label = "Genres",
      options = {
        { value = "3",  label = "Action"            },
        { value = "28", label = "Adult"             },
        { value = "4",  label = "Adventure"         },
        { value = "46", label = "Anime"             },
        { value = "5",  label = "Comedy"            },
        { value = "24", label = "Drama"             },
        { value = "44", label = "Eastern"           },
        { value = "26", label = "Ecchi"             },
        { value = "48", label = "Fan-fiction"       },
        { value = "6",  label = "Fantasy"           },
        { value = "19", label = "Game"              },
        { value = "25", label = "Gender Bender"     },
        { value = "7",  label = "Harem"             },
        { value = "12", label = "Historical"        },
        { value = "37", label = "Horror"            },
        { value = "49", label = "Isekai"            },
        { value = "2",  label = "Josei"             },
        { value = "45", label = "Lgbt+"             },
        { value = "50", label = "Magic"             },
        { value = "15", label = "Martial Arts"      },
        { value = "8",  label = "Mature"            },
        { value = "34", label = "Mecha"             },
        { value = "16", label = "Mystery"           },
        { value = "9",  label = "Psychological"     },
        { value = "43", label = "Reincarnation"     },
        { value = "1",  label = "Romance"           },
        { value = "21", label = "School Life"       },
        { value = "20", label = "Sci-fi"            },
        { value = "10", label = "Seinen"            },
        { value = "38", label = "Shoujo"            },
        { value = "17", label = "Shounen"           },
        { value = "13", label = "Slice of Life"     },
        { value = "29", label = "Smut"              },
        { value = "42", label = "Sports"            },
        { value = "18", label = "Supernatural"      },
        { value = "58", label = "System"            },
        { value = "32", label = "Tragedy"           },
        { value = "31", label = "Wuxia"             },
        { value = "23", label = "Xianxia"           },
        { value = "22", label = "Xuanhuan"          },
        { value = "14", label = "Yaoi"              },
        { value = "62", label = "Yuri"              },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page           = index + 1
  local sort           = filters["sort"]           or "rank-top"
  local status         = filters["status"]         or "-1"
  local genre_operator = filters["genre_operator"] or "and"
  local rating_op      = filters["rating_operator"] or "min"
  local rating         = filters["rating"]         or "0"
  local chapters       = filters["chapters"]       or "0"
  local languages      = filters["language_included"] or {}
  local genres         = filters["genres_included"]   or {}

  local url = baseUrl .. "/search-adv?ctgcon=" .. genre_operator
              .. "&ratcon=" .. rating_op
              .. "&rating=" .. rating
              .. "&status=" .. status
              .. "&sort="   .. sort
              .. "&totalchapter=" .. url_encode(chapters)
              .. "&page="   .. tostring(page)

  for _, v in ipairs(languages) do url = url .. "&country_id[]=" .. v end
  for _, v in ipairs(genres)    do url = url .. "&categories[]=" .. v end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".novel-list > .novel-item")) do
    local titleEl = html_select_first(card.html, ".novel-title")
    local linkEl  = html_select_first(card.html, ".novel-title a")
    local cover   = html_attr(card.html, "img", "data-src")
    if cover == "" then cover = html_attr(card.html, "img", "src") end
    if titleEl and linkEl then
      table.insert(items, {
        title = string_clean(titleEl.text),
        url   = absUrl(linkEl.href),
        cover = absUrl(cover)
      })
    end
  end

  return { items = items, hasNext = #items > 0 }
end