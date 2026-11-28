-- ── Metadata ───────────────────────────────────────────────────────────────────
id       = "botitranslation"
name     = "BotiTranslation"
version  = "1.0.0"
baseUrl  = "https://botitranslation.com/"
language = "en"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/botitranslation.png"
charset  = "UTF-8"

-- ── Libraries ──────────────────────────────────────────────────────────────────

local function lib(id)
  if type(require_lib) ~= "function" then
    show_error("Requires NoveLA update", "Plugin needs shared libraries")
    error("Requires NoveLA (require_lib)", 0)
  end
  return require_lib(id)
end

local function absUrl(href) return lib("urls").absUrl(baseUrl, href) end

local function fetchPage(url) return lib("fetch").page(url) end

local function applyContent(text)
  return lib("content").standardTransforms(text, { domain = baseUrl, lang = "en" })
end

-- ── Helpers ────────────────────────────────────────────────────────────────────

local API = "https://api.mystorywave.com/story-wave-backend/api/v1/"

local function bookIdFromUrl(url)
  if not url then return nil end
  local m = url:match("/book/([%d]+)")
  return m and tonumber(m) or nil
end

-- ── Catalog ────────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local cat = lib("catalog")
  local page = cat.nextIndex(index)

  local url = API .. "content/books?pageNumber=" .. page .. "&pageSize=20"
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local j = json_parse(r.body)
  if not j or j.code ~= 0 then return { items = {}, hasNext = false } end

  local data = j.data
  if not data or not data.list then return { items = {}, hasNext = false } end

  local items = {}
  for _, item in ipairs(data.list) do
    local title = item.title
    if title and #title > 0 then
      local id = item.id
      local slug = string.gsub(title, "[^a-zA-Z0-9]", "-"):lower()
      local bookUrl = baseUrl .. "book/" .. id .. "-" .. slug .. "/"
      table.insert(items, {
        title  = title,
        url    = bookUrl,
        cover  = item.coverImgUrl,
        rating = item.ratingCounts and tonumber(item.ratingCounts) or nil,
      })
    end
  end

  return { items = items, hasNext = cat.hasNextPage(items) }
end

-- ── Search ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local cat = lib("catalog")
  local page = cat.nextIndex(index)

  local url = API .. "content/books/search?pageNumber=" .. page
              .. "&pageSize=20&keyWord=" .. url_encode(query)
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local j = json_parse(r.body)
  if not j or j.code ~= 0 then return { items = {}, hasNext = false } end

  local data = j.data
  if not data or not data.list then return { items = {}, hasNext = false } end

  local items = {}
  for _, item in ipairs(data.list) do
    local title = item.title
    if title and #title > 0 then
      local id = item.id
      local slug = string.gsub(title, "[^a-zA-Z0-9]", "-"):lower()
      local bookUrl = baseUrl .. "book/" .. id .. "-" .. slug .. "/"
      table.insert(items, {
        title  = title,
        url    = bookUrl,
        cover  = item.coverImgUrl,
        rating = item.ratingCounts and tonumber(item.ratingCounts) or nil,
      })
    end
  end

  return { items = items, hasNext = cat.hasNextPage(items) }
end

-- ── Book details ───────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  return j.data.title
end

function getBookCoverImageUrl(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  return j.data.coverImgUrl
end

function getBookDescription(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  return j.data.synopsis
end

function getBookAuthor(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  return j.data.authorPseudonym
end

function getBookGenres(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return {} end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return {} end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return {} end
  local g = j.data.genreName
  if g and #g > 0 then return { g } end
  return {}
end

function getBookRating(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  return j.data.ratingCounts and tonumber(j.data.ratingCounts) or nil
end

function getBookStatus(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  local s = j.data.status
  if s == 0 then return "Ongoing"
  elseif s == 1 then return "Completed"
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/books/" .. id
  local body = fetchPage(url)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  local ts = j.data.lastUpdateTime
  if not ts then return nil end
  local sec = ts / 1000
  local ok2, res = pcall(os.date, "!%Y-%m-%d", sec)
  if ok2 then return res end
  return nil
end

function getBookExtras(url)
  local id = bookIdFromUrl(url)
  if not id then return nil end
  local url2 = API .. "content/books/" .. id
  local body = fetchPage(url2)
  if not body then return nil end
  local j = json_parse(body)
  if not j or j.code ~= 0 then return nil end
  local d = j.data
  local extras = {}
  local author = d.authorPseudonym
  if author and #author > 0 then extras["author"] = author end
  local g = d.genreName
  if g and #g > 0 then extras["genres"] = g end
  if d.ratingCounts then extras["rating"] = tostring(d.ratingCounts) end
  if d.type and #d.type > 0 then extras["type"] = d.type end
  if d.publishedChapters then extras["chapters"] = tostring(d.publishedChapters) end
  return extras
end

-- ── Chapter list ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return {} end

  local all = {}
  local page = 1
  local totalPages = 1

  while page <= totalPages do
    local url = API .. "content/chapters/page?bookId=" .. id
                .. "&pageNumber=" .. page .. "&pageSize=100"
    local r = http_get(url)
    if not r.success then break end

    local j = json_parse(r.body)
    if not j or j.code ~= 0 then break end
    local data = j.data
    if not data then break end

    if not data.list or #data.list == 0 then break end
    totalPages = data.totalPages or 1

    for _, ch in ipairs(data.list) do
      local chId = ch.id
      local chTitle = ch.title or ("Chapter " .. ch.chapterOrder)
      local slug = string.gsub(chTitle, "[^a-zA-Z0-9]", "-"):lower()
      local chUrl = baseUrl .. "chapter/" .. chId .. "-" .. slug .. "/"
      table.insert(all, {
        title = chTitle,
        url   = chUrl,
      })
    end

    page = page + 1
  end

  -- API returns newest first; reverse to oldest-first
  local reversed = {}
  for i = #all, 1, -1 do
    table.insert(reversed, all[i])
  end
  return reversed
end

function getChapterListHash(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if not id then return nil end
  local url = API .. "content/chapters/page?bookId=" .. id .. "&pageNumber=1&pageSize=1"
  local r = http_get(url)
  if not r.success then return nil end
  local j = json_parse(r.body)
  if not j or j.code ~= 0 then return nil end
  local data = j.data
  if not data then return nil end
  return tostring(data.totalCount or "")
end

-- ── Chapter text ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local chId
  local m = url:match("/chapter/([%d]+)")
  if m then chId = tonumber(m) end
  if not chId then
    if html and #html > 0 then
      local cleaned = html_remove(html, "script", "style")
      local el = html_select_first(cleaned, "div.chapter-content, #chapterContent, .reader-container")
      if el then return applyContent(html_text(el.html)) end
    end
    return ""
  end

  local apiUrl = API .. "content/chapters/" .. chId
  local r = http_get(apiUrl)
  if not r.success then return "" end
  local j = json_parse(r.body)
  if not j or j.code ~= 0 then return "" end
  local content = j.data.content
  if not content then return "" end

  local cleaned = html_remove(content, "script", "style", "ads", "advertisement")
  return applyContent(html_text(cleaned))
end

-- ── Filters ────────────────────────────────────────────────────────────────────

function getFilterList()
  return {
    {
      type         = "select",
      key          = "category",
      label        = "Category",
      defaultValue = "-1",
      options = {
        { value = "-1", label = "All" },
        { value = "original", label = "Original" },
        { value = "translation", label = "Translation" },
      },
    },
    {
      type         = "select",
      key          = "genre",
      label        = "Genre",
      defaultValue = "-1",
      options = {
        { value = "-1", label = "All" },
        { value = "1", label = "Fantasy" },
        { value = "2", label = "Sci-fi" },
        { value = "3", label = "Sports" },
        { value = "4", label = "Urban" },
        { value = "5", label = "Eastern Fantasy" },
        { value = "6", label = "Horror & Thriller" },
        { value = "7", label = "Video Game" },
        { value = "8", label = "History" },
        { value = "9", label = "War" },
        { value = "10", label = "Urban Romance" },
        { value = "11", label = "Fantasy Romance" },
        { value = "12", label = "Historical Romance" },
        { value = "13", label = "Teen" },
        { value = "14", label = "LGBT+" },
        { value = "15", label = "OTHERS+" },
      },
    },
    {
      type         = "select",
      key          = "update",
      label        = "Update time",
      defaultValue = "-1",
      options = {
        { value = "-1", label = "All" },
        { value = "3", label = "3 days" },
        { value = "7", label = "7 days" },
        { value = "15", label = "15 days" },
        { value = "30", label = "30 days" },
      },
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "-1",
      options = {
        { value = "-1", label = "All" },
        { value = "0", label = "Ongoing" },
        { value = "1", label = "Completed" },
      },
    },
  }
end

-- ── Filtered catalog ───────────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local cat = lib("catalog")
  local page = cat.nextIndex(index)

  local url = API .. "content/books?pageNumber=" .. page .. "&pageSize=20"

  local cat_f = filters["category"]
  if cat_f and cat_f ~= "-1" then url = url .. "&category=" .. url_encode(cat_f) end

  local genre_f = filters["genre"]
  if genre_f and genre_f ~= "-1" then url = url .. "&genre=" .. url_encode(genre_f) end

  local update_f = filters["update"]
  if update_f and update_f ~= "-1" then url = url .. "&update=" .. url_encode(update_f) end

  local status_f = filters["status"]
  if status_f and status_f ~= "-1" then url = url .. "&status=" .. url_encode(status_f) end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local j = json_parse(r.body)
  if not j or j.code ~= 0 then return { items = {}, hasNext = false } end

  local data = j.data
  if not data or not data.list then return { items = {}, hasNext = false } end

  local items = {}
  for _, item in ipairs(data.list) do
    local title = item.title
    if title and #title > 0 then
      local id = item.id
      local slug = string.gsub(title, "[^a-zA-Z0-9]", "-"):lower()
      local bookUrl = baseUrl .. "book/" .. id .. "-" .. slug .. "/"
      table.insert(items, {
        title  = title,
        url    = bookUrl,
        cover  = item.coverImgUrl,
        rating = item.ratingCounts and tonumber(item.ratingCounts) or nil,
      })
    end
  end

  return { items = items, hasNext = cat.hasNextPage(items) }
end
