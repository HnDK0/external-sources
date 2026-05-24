-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "scribblehub"
name     = "ScribbleHub"
version  = "1.0.1"
baseUrl  = "https://www.scribblehub.com/"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/scribblehub.png"

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
  local url = baseUrl .. "series-ranking/?sort=1&order=2&pg=" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".search_main_box")) do
    local titleEl = html_select_first(card.html, ".search_title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".search_img img", "src")
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
  local url = baseUrl .. "?s=" .. url_encode(query) .. "&post_type=fictionposts&paged=" .. tostring(page)

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".search_main_box")) do
    local titleEl = html_select_first(card.html, ".search_title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".search_img img", "src")
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
  local el = html_select_first(r.body, "div.fic_title")
  if el then return string_clean(el.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local src = html_attr(r.body, ".fic_image img", "src")
  if src == "" then src = html_attr(r.body, ".novel-cover img", "src") end
  if src ~= "" then return absUrl(src) end
  return nil
end

function getBookDescription(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, ".wi_fic_desc")
  if el then return string_trim(el.text) end
  return nil
end

-- ── Список глав (POST AJAX) ───────────────────────────────────────────────────

function getChapterList(bookUrl)
  -- Извлекаем series ID из URL: /series/12345/title/
  local seriesId = string.match(bookUrl, "/series/(%d+)/")
  if not seriesId then
    log_error("scribblehub: cannot extract seriesId from " .. bookUrl)
    return {}
  end

  local ajaxUrl = baseUrl .. "wp-admin/admin-ajax.php"
  local body = "action=wi_getreleases_pagination&pagenum=-1&mypostid=" .. seriesId

  local r = http_post(ajaxUrl, body, {
    headers = {
      ["Content-Type"]    = "application/x-www-form-urlencoded",
      ["X-Requested-With"] = "XMLHttpRequest",
      ["Origin"]          = baseUrl:gsub("/$", ""),
      ["Referer"]         = bookUrl,
      ["Accept"]          = "*/*",
      ["Accept-Language"] = "en-US,en;q=0.9"
    }
  })
  if not r.success then
    log_error("scribblehub: AJAX failed " .. tostring(r.code))
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, ".toc_w a[href]")) do
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
  local el = html_select_first(r.body, ".fic_stats span.st_item")
  if el then return string_clean(el.text) end
  return nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", ".modern_chapter_ad", "div.modern_chapter_ad")
  local el = html_select_first(cleaned, "#chp_raw")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end
-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
  local r = http_get(bookUrl)
  if not r.success then return {} end

  local genres = {}
  for _, a in ipairs(html_select(r.body, ".fic_genre")) do
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
      defaultValue = "ratings",
      options = {
        { value = "chapters",    label = "Chapters"            },
        { value = "frequency",   label = "Chapters per Week"   },
        { value = "dateadded",   label = "Date Added"          },
        { value = "favorites",   label = "Favorites"           },
        { value = "lastchdate",  label = "Last Updated"        },
        { value = "numofrate",   label = "Number of Ratings"   },
        { value = "pages",       label = "Pages"               },
        { value = "pageviews",   label = "Pageviews"           },
        { value = "ratings",     label = "Ratings"             },
        { value = "readers",     label = "Readers"             },
        { value = "reviews",     label = "Reviews"             },
        { value = "totalwords",  label = "Total Words"         },
      }
    },
    {
      type         = "select",
      key          = "order",
      label        = "Order By",
      defaultValue = "desc",
      options = {
        { value = "desc", label = "Descending" },
        { value = "asc",  label = "Ascending"  },
      }
    },
    {
      type         = "select",
      key          = "storyStatus",
      label        = "Story Status",
      defaultValue = "all",
      options = {
        { value = "all",       label = "All"       },
        { value = "completed", label = "Completed" },
        { value = "ongoing",   label = "Ongoing"   },
        { value = "hiatus",    label = "Hiatus"    },
      }
    },
    {
      type         = "select",
      key          = "genre_operator",
      label        = "Genres (And/Or)",
      defaultValue = "and",
      options = {
        { value = "and", label = "And" },
        { value = "or",  label = "Or"  },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Genres",
      options = {
        { value = "9",    label = "Action"        },
        { value = "902",  label = "Adult"         },
        { value = "8",    label = "Adventure"     },
        { value = "891",  label = "Boys Love"     },
        { value = "7",    label = "Comedy"        },
        { value = "903",  label = "Drama"         },
        { value = "904",  label = "Ecchi"         },
        { value = "38",   label = "Fanfiction"    },
        { value = "19",   label = "Fantasy"       },
        { value = "905",  label = "Gender Bender" },
        { value = "892",  label = "Girls Love"    },
        { value = "1015", label = "Harem"         },
        { value = "21",   label = "Historical"    },
        { value = "22",   label = "Horror"        },
        { value = "37",   label = "Isekai"        },
        { value = "906",  label = "Josei"         },
        { value = "1180", label = "LitRPG"        },
        { value = "907",  label = "Martial Arts"  },
        { value = "20",   label = "Mature"        },
        { value = "908",  label = "Mecha"         },
        { value = "909",  label = "Mystery"       },
        { value = "910",  label = "Psychological" },
        { value = "6",    label = "Romance"       },
        { value = "911",  label = "School Life"   },
        { value = "912",  label = "Sci-fi"        },
        { value = "913",  label = "Seinen"        },
        { value = "914",  label = "Slice of Life" },
        { value = "915",  label = "Smut"          },
        { value = "916",  label = "Sports"        },
        { value = "5",    label = "Supernatural"  },
        { value = "901",  label = "Tragedy"       },
      }
    },
    {
      type         = "select",
      key          = "content_warning_operator",
      label        = "Mature Content (And/Or)",
      defaultValue = "and",
      options = {
        { value = "and", label = "And" },
        { value = "or",  label = "Or"  },
      }
    },
    {
      type  = "tristate",
      key   = "content_warning",
      label = "Mature Content",
      options = {
        { value = "48", label = "Gore"             },
        { value = "50", label = "Sexual Content"   },
        { value = "49", label = "Strong Language"  },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page    = index + 1
  local sort    = filters["sort"]          or "ratings"
  local order   = filters["order"]         or "desc"
  local status  = filters["storyStatus"]   or "all"
  local gmgi    = filters["genre_operator"]         or "and"
  local cmct    = filters["content_warning_operator"] or "and"

  local gi = filters["genres_included"]          or {}
  local ge = filters["genres_excluded"]          or {}
  local ci = filters["content_warning_included"] or {}
  local ce = filters["content_warning_excluded"] or {}

  local url = baseUrl .. "series-finder/?sf=1"
              .. "&sort=" .. sort
              .. "&order=" .. order
              .. "&cp=" .. status
              .. "&pg=" .. tostring(page)

  if #gi > 0 then
    url = url .. "&gi=" .. table.concat(gi, ",")
    url = url .. "&mgi=" .. gmgi
  end
  if #ge > 0 then
    url = url .. "&ge=" .. table.concat(ge, ",")
    if #gi == 0 then url = url .. "&mgi=" .. gmgi end
  end
  if #ci > 0 then
    url = url .. "&cti=" .. table.concat(ci, ",")
    url = url .. "&mct=" .. cmct
  end
  if #ce > 0 then
    url = url .. "&cte=" .. table.concat(ce, ",")
    if #ci == 0 then url = url .. "&mct=" .. cmct end
  end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = {}
  for _, card in ipairs(html_select(r.body, ".search_main_box")) do
    local titleEl = html_select_first(card.html, ".search_title a")
    if titleEl then
      local bookUrl = absUrl(titleEl.href)
      local cover   = html_attr(card.html, ".search_img img", "src")
      local t = string_clean(titleEl.text)
      if bookUrl ~= "" and t ~= "" then
        table.insert(items, { title = t, url = bookUrl, cover = absUrl(cover) })
      end
    end
  end

  return { items = items, hasNext = #items > 0 }
end
