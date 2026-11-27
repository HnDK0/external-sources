id          = "ranobes"
name        = "Ranobes"
version     = "1.1.0"
baseUrl     = "https://ranobes.top"
language    = "en"
content_type = "novel"
description = "Read web novels and light novels from Ranobes (ranobes.top)"
referer     = "https://ranobes.top/"

-- ── Helpers ────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http://") or string_starts_with(href, "https://") then
    return href
  end
  return url_resolve(baseUrl, href)
end

-- ── Fetching: cache + throttle + retry ────────────────────────────────────
-- Ranobes blocks (403/429/Cloudflare page) after roughly 20 page requests in a
-- few minutes. The old plugin fetched the SAME novel page ~10 times (title,
-- cover, author, genres, ...) and then every chapter-list page, so it hit the
-- limit mid-listing and silently skipped pages. Fix: fetch each URL once
-- (cache), pace real network calls, and retry blocked pages with back-off.

local pageCache   = {}
local networkHits = 0

local function looksBlocked(body)
  if not body or body == "" then return true end
  local head = string.sub(body, 1, 4000)
  if string.find(head, "Just a moment", 1, true) then return true end
  if string.find(head, "cf%-challenge") or string.find(head, "cf_chl") then return true end
  if string.find(head, "Attention Required", 1, true) then return true end
  if string.find(head, "Access denied", 1, true) then return true end
  if string.find(head, "<title>403", 1, true) or string.find(head, "<title>429", 1, true) then return true end
  return false
end

-- opts.cache   : default true
-- opts.validate: function(body) -> bool, extra check that the page is the real one
local function fetchPage(url, opts)
  opts = opts or {}
  local useCache = opts.cache ~= false
  if useCache and pageCache[url] then return pageCache[url] end

  local waits = { 0, 4000, 9000, 18000, 30000 }
  for attempt = 1, #waits do
    if waits[attempt] > 0 then
      sleep(waits[attempt] + math.random(0, 1500))
    elseif networkHits > 0 then
      sleep(math.random(1200, 2200))          -- polite gap between pages
    end
    networkHits = networkHits + 1

    local r = http_get(url)
    local body = r and r.success and r.body or nil
    if body and body ~= "" and not looksBlocked(body)
       and (not opts.validate or opts.validate(body)) then
      if useCache then pageCache[url] = body end
      return body
    end
  end
  return nil
end

local function extractBgUrl(style)
  if not style or style == "" then return "" end
  local m = regex_match(style, "url\\(['\"]?([^'\")\\s]+)['\"]?\\)")
  if m and m[1] then
    local inner = string.match(m[1], "url%(['\"]?([^'\")]+)['\"]?%)")
    if inner and inner ~= "" then return inner end
  end
  return ""
end

local function extractBookId(bookUrl, body)
  if bookUrl then
    local id = string.match(bookUrl, "/novels/(%d+)")
      or string.match(bookUrl, "/chapters/(%d+)")
      or string.match(bookUrl, "%-(%d+)%.html")
    if id then return id end
  end
  if body then
    local chLink = html_select_first(body, "a[href*='/chapters/']")
    if chLink and chLink.href then
      local id = string.match(chLink.href, "/chapters/(%d+)")
      if id then return id end
    end
  end
  return nil
end

local function cleanTitle(raw)
  if not raw then return "" end
  local s = string_clean(raw)
  -- Strip any trailing subtitle separated by " • " if still present
  local main = string.match(s, "^(.-)%s*•%s*.+$")
  if main and main ~= "" then return string_trim(main) end
  return s
end

-- ── Catalog & Search ───────────────────────────────────────────────────────

local function parseCatalogItems(html)
  local items = {}
  local seen = {}
  local cards = html_select(html, ".block.story.shortstory, .shortstory, .story")
  for _, card in ipairs(cards) do
    local titleEl = html_select_first(card.html, "h2.title a, .title a, a[href*='/novels/']")
    if titleEl and titleEl.href and titleEl.href ~= "" then
      local url = absUrl(titleEl.href)
      if not seen[url] then
        seen[url] = true
        local cover = ""
        local img = html_select_first(card.html, "figure.cover, .cover")
        if img then
          cover = extractBgUrl(html_attr(img, "style"))
          if cover == "" then cover = html_attr(img, "data-src") end
          if cover == "" then cover = html_attr(img, "src") end
        end
        if cover == "" then
          cover = html_attr(card.html, "img", "data-src")
        end
        if cover == "" then
          cover = html_attr(card.html, "img", "src")
        end

        local rating = ""
        local rateEl = html_select_first(card.html, ".rate_num, .current-rating")
        if rateEl then
          local n = string.match(string_clean(rateEl.text), "%d+%.?%d*")
          if n then rating = n end
        end

        table.insert(items, {
          title  = cleanTitle(titleEl.text),
          url    = url,
          cover  = absUrl(cover),
          rating = rating,
        })
      end
    end
  end
  return items
end

local function hasNextCatalogPage(html, items, currentPage)
  if not items or #items == 0 then return false end
  local nextPage = tostring(currentPage + 1)
  local pages = html_select(html, ".pages a, .navigation a")
  for _, a in ipairs(pages) do
    if string_trim(a.text) == nextPage then
      return true
    end
    if a.href and string.match(a.href, "/page/" .. nextPage .. "/?") then
      return true
    end
  end
  return #items >= 10
end

function getCatalogList(index)
  local page = (tonumber(index) or 0) + 1
  local url = baseUrl .. "/novels/"
  if page > 1 then
    url = baseUrl .. "/novels/page/" .. tostring(page) .. "/"
  end
  local r = http_get(url)
  if not r or not r.success or not r.body then
    return { items = {}, hasNext = false }
  end
  local items = parseCatalogItems(r.body)
  return {
    items   = items,
    hasNext = hasNextCatalogPage(r.body, items, page),
  }
end

function getCatalogSearch(index, query)
  local page = (tonumber(index) or 0) + 1
  local q = string_trim(query or "")
  if q == "" then return { items = {}, hasNext = false } end

  local form = table.concat({
    "do=search",
    "subaction=search",
    "story=" .. url_encode(q),
    "catlist[]=1",
    "search_start=" .. tostring(page),
    "full_search=0",
    "result_from=" .. tostring((page - 1) * 10 + 1),
  }, "&")

  local r = http_post(baseUrl .. "/index.php?do=search", form, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Referer"]      = baseUrl .. "/",
    },
  })

  if r and r.success and r.body then
    local items = parseCatalogItems(r.body)
    if #items > 0 then
      return {
        items   = items,
        hasNext = hasNextCatalogPage(r.body, items, page),
      }
    end
  end

  -- Fallback GET search route if POST returns empty
  local getUrl = baseUrl .. "/search/" .. url_encode(q) .. "/"
  if page > 1 then
    getUrl = getUrl .. "page/" .. tostring(page) .. "/"
  end
  local r2 = http_get(getUrl)
  if not r2 or not r2.success or not r2.body then
    return { items = {}, hasNext = false }
  end
  local items2 = parseCatalogItems(r2.body)
  return {
    items   = items2,
    hasNext = hasNextCatalogPage(r2.body, items2, page),
  }
end

function getFilterList()
  return {
    {
      type         = "select",
      key          = "section",
      label        = "Browse",
      defaultValue = "novels",
      options = {
        { value = "novels",      label = "All Novels"       },
        { value = "updates",     label = "Latest Updates"   },
        { value = "ranking",     label = "Popular"          },
        { value = "now-reading", label = "Now Reading"      },
        { value = "completed",   label = "Completed Novels" },
      },
    },
    {
      type         = "select",
      key          = "genre",
      label        = "Genre",
      defaultValue = "",
      options = {
        { value = "",              label = "Any"           },
        { value = "Action",        label = "Action"        },
        { value = "Adventure",     label = "Adventure"     },
        { value = "Comedy",        label = "Comedy"        },
        { value = "Drama",         label = "Drama"         },
        { value = "Fantasy",       label = "Fantasy"       },
        { value = "Harem",         label = "Harem"         },
        { value = "Historical",    label = "Historical"    },
        { value = "Horror",        label = "Horror"        },
        { value = "Josei",         label = "Josei"         },
        { value = "Martial Arts",  label = "Martial Arts"  },
        { value = "Mature",        label = "Mature"        },
        { value = "Mecha",         label = "Mecha"         },
        { value = "Mystery",       label = "Mystery"       },
        { value = "Psychological", label = "Psychological" },
        { value = "Romance",       label = "Romance"       },
        { value = "School Life",   label = "School Life"   },
        { value = "Sci-Fi",        label = "Sci-Fi"        },
        { value = "Seinen",        label = "Seinen"        },
        { value = "Shoujo",        label = "Shoujo"        },
        { value = "Shounen",       label = "Shounen"       },
        { value = "Slice of Life", label = "Slice of Life" },
        { value = "Supernatural",  label = "Supernatural"  },
        { value = "Tragedy",       label = "Tragedy"       },
        { value = "Xuanhuan",      label = "Xuanhuan"      },
        { value = "Xianxia",       label = "Xianxia"       },
      },
    },
  }
end

function getCatalogFiltered(index, filters)
  local page = (tonumber(index) or 0) + 1
  local genre = filters and filters["genre"] or ""
  local section = filters and filters["section"] or "novels"

  local path
  if genre ~= "" then
    path = "/tags/genre/" .. url_encode(genre) .. "/"
  elseif section == "completed" then
    path = "/tags/status-trs/Completed/"
  elseif section == "updates" or section == "ranking" or section == "now-reading" then
    path = "/" .. section .. "/"
  else
    path = "/novels/"
  end

  local url = baseUrl .. path
  if page > 1 then
    url = url .. "page/" .. tostring(page) .. "/"
  end

  local r = http_get(url)
  if not r or not r.success or not r.body then
    return { items = {}, hasNext = false }
  end
  local items = parseCatalogItems(r.body)
  return {
    items   = items,
    hasNext = hasNextCatalogPage(r.body, items, page),
  }
end

-- ── Book Details ───────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h1.title")
  if not el then return nil end
  local cleaned = html_remove(el.html, "span.subtitle", "span[hidden]")
  local t = cleanTitle(html_text(cleaned))
  if t == "" then t = cleanTitle(el.text) end
  return t ~= "" and t or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end

  -- Full-resolution cover link on novel page
  local hs = html_select_first(body, ".r-fullstory-poster a.highslide")
  if hs and hs.href and hs.href ~= "" then
    return absUrl(hs.href)
  end

  -- Background-image cover fallback
  local fig = html_select_first(body, ".r-fullstory-poster figure.cover, .poster figure.cover")
  if fig then
    local bg = extractBgUrl(html_attr(fig, "style"))
    if bg ~= "" then return absUrl(bg) end
  end

  -- <img> fallback
  local src = html_attr(body, ".r-fullstory-poster img, .poster img", "src")
  if not src or src == "" then
    src = html_attr(body, ".r-fullstory-poster img, .poster img", "data-src")
  end
  return (src and src ~= "") and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".moreless__full")
  if not el then
    el = html_select_first(body, ".moreless__short, [itemprop='description']")
  end
  if not el then return nil end
  local cleaned = html_remove(el.html, "a.moreless__toggle", "a")
  local txt = string_trim(html_text(cleaned))
  return txt ~= "" and txt or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  local seen = {}
  local links = html_select(body, "#mc-fs-genre a")
  if not links or #links == 0 then links = html_select(body, ".r-fullstory-genres a") end
  for _, a in ipairs(links or {}) do
    local g = string_clean(a.text)
    if g ~= "" and not seen[g] then
      seen[g] = true
      table.insert(genres, g)
    end
  end
  return genres
end

function getBookAuthor(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  for _, li in ipairs(html_select(body, ".r-fullstory-spec li")) do
    local txt = string_clean(li.text)
    if string_starts_with(txt, "Authors:") or string_starts_with(txt, "Author:") then
      local names = {}
      for _, a in ipairs(html_select(li.html, "a")) do
        local name = string_clean(a.text)
        if name ~= "" then table.insert(names, name) end
      end
      if #names > 0 then return table.concat(names, ", ") end
    end
  end
  return nil
end

function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local cooStatus = nil
  for _, li in ipairs(html_select(body, ".r-fullstory-spec li")) do
    local txt = string_clean(li.text)
    if string_starts_with(txt, "Translation:") then
      local val = string.lower(string_clean((string.gsub(txt, "^Translation:%s*", ""))))
      local a = html_select_first(li.html, "a, span.grey")
      if a and a.text and string_clean(a.text) ~= "" then val = string.lower(string_clean(a.text)) end
      if val:find("active") or val:find("ongoing") then return "Ongoing" end
      if val:find("complet") then return "Completed" end
      if val:find("hiatus") or val:find("paus") or val:find("drop") then return "Hiatus" end
    elseif string_starts_with(txt, "Status in COO:") then
      local a = html_select_first(li.html, "a, span.grey")
      if a then cooStatus = string.lower(string_clean(a.text)) end
    end
  end
  if cooStatus then
    if cooStatus:find("complet") then return "Completed" end
    if cooStatus:find("ongoing") or cooStatus:find("active") then return "Ongoing" end
    if cooStatus:find("hiatus") or cooStatus:find("paus") then return "Hiatus" end
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local dt = html_attr(body, ".r-date .up_label time", "datetime")
  if dt and dt ~= "" then
    local ymd = string.match(dt, "^(%d%d%d%d%-%d%d%-%d%d)")
    if ymd then return ymd end
  end
  local el = html_select_first(body, ".r-date .up_label time, .r-date time.grey")
  return el and string_clean(el.text) or nil
end

function getBookRating(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, ".rate-stat-num")
  if el then
    local n = string.match(string_clean(el.text), "%d+%.?%d*")
    if n then return n end
  end
  local fallback = html_select_first(body, ".r-fullstory-s1 .current-rating")
  if fallback then
    local n = string.match(string_clean(fallback.text), "%d+%.?%d*")
    if n then return n end
  end
  return nil
end

function getBookExtras(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local extras = {}

  local sub = html_select_first(body, "h1.title span.subtitle")
  if sub then
    local alt = string_clean(sub.text)
    if alt ~= "" then extras["Alt Title"] = alt end
  end

  local wanted = {
    ["Status in COO"]      = "Status in COO",
    ["Translation"]        = "Translation",
    ["In original"]        = "In Original",
    ["Translated"]         = "Translated",
    ["Year of publishing"] = "Year",
    ["Language"]           = "Language",
    ["Translator"]         = "Translator",
    ["Publishers"]         = "Publishers",
  }

  for _, li in ipairs(html_select(body, ".r-fullstory-spec li")) do
    local txt = string_clean(li.text)
    local k, v = string.match(txt, "^([^:]+):%s*(.+)$")
    if k and v and wanted[k] and v ~= "" then
      extras[wanted[k]] = v
    end
  end

  return extras
end

-- ── Chapters List (Chronological via parsePage) ────────────────────────────

local pagesCountCache = {}   -- bookId -> pages_count
local parsedPageCache = {}   -- bookId .. ":" .. ranobesPage -> chapters (newest-first)

local function parseChaptersData(html)
  local raw = nil
  local m = string.match(html, '<script[^>]-id=["\']chapters%-data["\'][^>]*>(.-)</script>')
  if m and m ~= "" then raw = m end
  if not raw then
    local el = html_select_first(html, "script#chapters-data")
    if el then
      raw = el.text
      if not raw or raw == "" then raw = el.html end
      if raw then
        raw = string.gsub(raw, "^%s*<script[^>]*>", "")
        raw = string.gsub(raw, "</script>%s*$", "")
      end
    end
  end
  if not raw or raw == "" then return nil end
  local ok, data = pcall(json_parse, raw)
  if ok and type(data) == "table" then return data end
  return nil
end

-- Fallback when the JSON block is missing/empty: read the server-rendered list.
local function parseChaptersDom(html)
  local out = {}
  for _, a in ipairs(html_select(html, ".cat_line a, .cat_block.cat_line a")) do
    if a.href and a.href ~= "" and string.find(a.href, "%.html") then
      local t = html_select_first(a.html, "h6.title, .title")
      local title = t and string_clean(t.text) or string_clean(a.text)
      table.insert(out, { title = title, link = a.href })
    end
  end
  return out
end

-- Returns (list newest-first, pagesCount) or (nil, nil) if the page could not be had.
local function loadChapterPage(bookId, ranobesPage)
  local key = bookId .. ":" .. tostring(ranobesPage)
  local url = baseUrl .. "/chapters/" .. bookId .. "/"
  if ranobesPage > 1 then url = url .. "page/" .. tostring(ranobesPage) .. "/" end

  local list, pages
  -- fetchPage retries blocked pages; this loop also retries "page loaded but
  -- list empty" (partial render / soft block) a couple of times.
  for attempt = 1, 3 do
    local html = fetchPage(url, {
      cache = false,
      validate = function(b)
        return string.find(b, "chapters-data", 1, true) ~= nil
            or string.find(b, "cat_line", 1, true) ~= nil
      end,
    })
    if html then
      local data = parseChaptersData(html)
      if data then pages = tonumber(data.pages_count) or pages end
      if data and type(data.chapters) == "table" and #data.chapters > 0 then
        list = data.chapters
      else
        local dom = parseChaptersDom(html)
        if #dom > 0 then list = dom end
      end
      if list then break end
    end
    sleep(math.random(3000, 6000))
  end
  if not list then return nil, pages end
  parsedPageCache[key] = list
  return list, pages
end

function parsePage(bookUrl, page)
  local pageNum = tonumber(page) or 1
  local bookId = extractBookId(bookUrl, nil)
  if not bookId then
    local bookHtml = fetchPage(bookUrl)
    bookId = extractBookId(bookUrl, bookHtml)
  end
  if not bookId then
    return { chapters = {}, totalPages = 1 }
  end

  -- Learn the page count from the newest page (ranobes page 1) once.
  local totalPages = pagesCountCache[bookId]
  if not totalPages then
    local list1, pages1 = loadChapterPage(bookId, 1)
    totalPages = pages1 or 1
    pagesCountCache[bookId] = totalPages
  end

  -- Ranobes lists newest-first (page 1 = latest). Map chronological page
  -- 1..totalPages -> Ranobes page totalPages..1.
  local ranobesPage = totalPages - pageNum + 1
  if ranobesPage < 1 then
    return { chapters = {}, totalPages = totalPages }
  end

  local key = bookId .. ":" .. tostring(ranobesPage)
  local rawList = parsedPageCache[key]
  if not rawList then rawList = loadChapterPage(bookId, ranobesPage) end
  if not rawList then
    return { chapters = {}, totalPages = totalPages }
  end

  local chapters = {}
  local seen = {}
  for i = #rawList, 1, -1 do
    local ch = rawList[i]
    if ch and ch.link and ch.link ~= "" then
      local u = absUrl(ch.link)
      if not seen[u] then
        seen[u] = true
        local title = string_clean(ch.title or "")
        if title == "" then title = "Chapter" end
        table.insert(chapters, { title = title, url = u })
      end
    end
  end

  return { chapters = chapters, totalPages = totalPages }
end

-- ── Chapter Content ────────────────────────────────────────────────────────

function getChapterText(html, url)
  local el = html_select_first(html, "#arrticle")
  if not el then
    el = html_select_first(html, ".text, .story")
  end
  if not el then return "" end

  -- Ads are injected BETWEEN paragraphs as <div>/<script>/<ins>. Reading only
  -- the <p> elements skips them without needing to strip nested tags.
  local parts = {}
  for _, p in ipairs(html_select(el.html, "p")) do
    local t = string_trim(string_clean(p.text or ""))
    if t ~= "" then table.insert(parts, t) end
  end
  if #parts > 0 then
    return table.concat(parts, "\n\n")
  end

  -- Fallback for chapters not wrapped in <p>.
  local cleaned = html_remove(el.html, "script", "style", "div", "ins", "aside", "iframe")
  local txt = html_text(cleaned)
  if not txt then return "" end
  txt = regex_replace(txt, "\n{3,}", "\n\n")
  return string_trim(txt)
end
