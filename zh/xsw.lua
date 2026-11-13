-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "xsw"
name     = "台灣小說網"
version  = "1.0.0"
baseUrl  = "https://www.xsw.tw"
language = "zh"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/xsw.png"

-- The site runs two hosts with different jobs:
--   www — catalog, search and the full chapter list (/book/<id>/);
--   m   — the book info page (/<id>/) and the chapter text (/<id>/<chid>.html);
--         the desktop book page and the desktop chapter page carry no useful
--         body, and m./img. send only the leaf certificate, so plain HTTP is
--         the only combination that returns content.
-- m. serves the book info page and the chapter body in clear (#nr1); www
-- serves the chapter body as an AES blob that only page JS decrypts. Plain
-- HTTP on m. is what the app's HTTP client can actually load: HTTPS on m.
-- fails certificate validation (the host sends no intermediate).
local MOBILE = "http://m.xsw.tw"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead. Shared libs load lazily and are cached per session.
local _libs
local function LIB(id)
  if type(require_lib) ~= "function" then
    show_error("Requires NoveLA update", "This plugin needs the shared libraries")
    error("Requires NoveLA update (require_lib)", 0)
  end
  if not _libs then _libs = {} end
  if not _libs[id] then _libs[id] = require_lib(id) end
  return _libs[id]
end

local function absUrl(href)
  return LIB("urls").absUrl(baseUrl, href)
end

-- The info page feeds five getters in one adapter run; the shared fetch cache
-- keeps it to a single request. getChapterListHash stays on a direct http_get:
-- the hash must see a fresh list.
local function fetchPage(url)
  return LIB("fetch").page(url)
end

-- Engine global url_encode delegates to the shared catalog lib.
local url_encode = function(s) return LIB("catalog").urlEncode(s) end

local function bookId(bookUrl)
  local id = tostring(bookUrl or ""):match("/book/(%d+)")
  return id or tostring(bookUrl or ""):match("/(%d+)/?$")
end

-- Mobile info page: title, cover, description, genres, status, last update.
local function infoPage(id)
  if not id then return nil end
  return fetchPage(MOBILE .. "/" .. id .. "/")
end

-- Desktop table of contents: title and genre only, but it is served by the
-- host with the full certificate chain, so it backs up the mobile page.
local function tocPage(id)
  if not id then return nil end
  return fetchPage(baseUrl .. "/book/" .. id .. "/")
end

local function standardTransforms(text)
  text = LIB("content").standardTransforms(text, { domain = baseUrl, lang = "zh" })
  -- Site-specific footer lines that the shared credits list does not cover.
  -- Bounded on purpose: a leading [^\n]* would swallow the whole chapter
  -- whenever the page ends up on a single line.
  text = text:gsub("請記住本站[^\n]*\n?", "")
  text = text:gsub("手機用戶請瀏覽[^\n]*\n?", "")
  return string_trim(text)
end

-- #alistbox cards are shared by the catalog pages and the search results.
local function parseCards(body)
  local items = {}
  for _, box in ipairs(html_select(body, "#alistbox")) do
    local a = html_select_first(box.html, ".title h2 a")
    if not a then a = html_select_first(box.html, ".pic a") end
    if a then
      local title = string_clean(a.text)
      title = title:gsub("^《", ""):gsub("》$", "")
      local url = absUrl(a.href)
      if title ~= "" and url ~= "" then
        table.insert(items, {
          title = title,
          url   = url,
          cover = absUrl(html_attr(box.html, ".pic img", "src")),
        })
      end
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = LIB("catalog").nextIndex(index)
  local r = http_get(baseUrl .. "/lastupdate_" .. tostring(page) .. ".html")
  if not r.success then return { items = {}, hasNext = false } end
  local items = parseCards(r.body)
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  -- The search endpoint returns all matches on a single page.
  if index > 0 then return { items = {}, hasNext = false } end

  -- The site's own hint is "rather too few characters than a wrong one": the
  -- full title with a subtitle ("邪物典當鋪：隻收凶物") finds nothing, the part
  -- before the colon finds the book. `searchtype=keywords` is the value the
  -- site's own form submits.
  local function search(q)
    local body = "searchkey=" .. url_encode(q) .. "&searchtype=keywords"
    local r = http_post(baseUrl .. "/modules/article/search.php", body)
    if not r.success then return nil end
    return parseCards(r.body)
  end

  local items = search(query)
  if items == nil then return { items = {}, hasNext = false } end
  if #items == 0 then
    local head = query:match("^([^:：]+)")
    if head and head ~= query and head ~= "" then items = search(head) or items end
  end

  return { items = items, hasNext = false }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  local id = bookId(bookUrl)
  for _, body in ipairs({ infoPage(id) or "", tocPage(id) or "" }) do
    if body ~= "" then
      local el = html_select_first(body, ".block_txt2 h2")
        or html_select_first(body, "h1#_52mb_h1")
        or html_select_first(body, "h1")
      local t = el and string_clean(el.text) or ""
      if t ~= "" then return t end
    end
  end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = infoPage(bookId(bookUrl))
  local src = body and html_attr(body, ".block_img2 img", "src") or ""
  if src == "" then
    -- The mobile page falls back to its placeholder; the desktop page keeps
    -- the real cover for the books the mobile host does not have one for.
    local desk = fetchPage(bookUrl)
    src = desk and html_attr(desk, 'img[src*="img.xsw.tw"]', "src") or ""
  end
  -- /style/noimg.jpg is the site's own "no cover" placeholder; it is returned
  -- as-is so the UI always has something to show.
  return src ~= "" and absUrl(src) or nil
end

function getBookDescription(bookUrl)
  local body = infoPage(bookId(bookUrl))
  if not body then return nil end
  local el = html_select_first(body, ".intro_info")
  local t = el and string_trim(el.text) or ""
  return t ~= "" and t or nil
end

function getBookGenres(bookUrl)
  local id = bookId(bookUrl)
  for _, body in ipairs({ infoPage(id) or "", tocPage(id) or "" }) do
    local g = body ~= "" and (body:match("分類：<a[^>]*>([^<]+)") or body:match("分類：</b>([^<]+)"))
    if g then
      g = string_clean(g)
      if g ~= "" then return { g } end
    end
  end
  return {}
end

-- ── Статус и дата обновления ──────────────────────────────────────────────────

function getBookStatus(bookUrl)
  local body = infoPage(bookId(bookUrl))
  if not body then return nil end
  local s = body:match("狀態：([^<\n]+)")
  return s and string_clean(s) or nil
end

function getBookLastUpdate(bookUrl)
  local body = infoPage(bookId(bookUrl))
  if not body then return nil end
  -- Month and day are not zero-padded on the site ("2026/11/12 0:00:00").
  local y, m, d = body:match("更新：(%d%d%d%d)/(%d%d?)/(%d%d?)")
  if not y then return nil end
  return string.format("%04d-%02d-%02d", y, m, d)
end

-- ── Список глав ───────────────────────────────────────────────────────────────

-- Desktop chapter links: /book/<id>/<chid>.html.
local function chaptersOnDesktop(body, id)
  local out, seen = {}, {}
  for _, a in ipairs(html_select(body, "a[href]")) do
    local bid, ch = tostring(a.href or ""):match("/book/(%d+)/(%d+)%.html")
    if bid == id and ch and not seen[ch] then
      seen[ch] = true
      out[#out + 1] = { id = ch, title = string_clean(a.text or "") }
    end
  end
  return out
end

-- Mobile chapter links: /<id>/<chid>.html.
local function chaptersOnMobile(body, id)
  local out, seen = {}, {}
  for _, a in ipairs(html_select(body, "a[href]")) do
    local bid, ch = tostring(a.href or ""):match("^/(%d+)/(%d+)%.html")
    if bid == id and ch and not seen[ch] then
      seen[ch] = true
      out[#out + 1] = { id = ch, title = string_clean(a.text or "") }
    end
  end
  return out
end

function getChapterList(bookUrl)
  local id = bookId(bookUrl)
  if not id then
    log_error("xsw: cannot extract book id from " .. bookUrl)
    return {}
  end

  local chapters, seen = {}, {}
  local function add(chId, title)
    if not chId or seen[chId] then return end
    seen[chId] = true
    local t = string_clean(title or "")
    if t == "" then t = "第" .. chId .. "章" end
    chapters[#chapters + 1] = { title = t, url = MOBILE .. "/" .. id .. "/" .. chId .. ".html" }
  end

  -- Full table of contents. Only the newest books have it; older ones answer
  -- 404 here and are served from the info page below instead.
  local r = http_get(baseUrl .. "/book/" .. id .. "/")
  if r.success then
    for _, c in ipairs(chaptersOnDesktop(r.body, id)) do add(c.id, c.title) end
  end

  if #chapters == 0 then
    local body = infoPage(id)
    if body then
      for _, c in ipairs(chaptersOnMobile(body, id)) do add(c.id, c.title) end
    end
  end

  table.sort(chapters, function(a, b)
    return (tonumber(a.url:match("/(%d+)%.html$")) or 0) < (tonumber(b.url:match("/(%d+)%.html$")) or 0)
  end)
  return chapters
end

function getChapterListHash(bookUrl)
  local id = bookId(bookUrl)
  if not id then return nil end
  local r = http_get(baseUrl .. "/book/" .. id .. "/")
  if r.success then
    -- Chapter ids grow with publish order: the largest one is the newest.
    local best, bestId = nil, -1
    for _, c in ipairs(chaptersOnDesktop(r.body, id)) do
      local n = tonumber(c.id)
      if n and n > bestId then bestId, best = n, c.title end
    end
    if best then return best end
  end
  local body = infoPage(id)
  return body and body:match("最新：<a[^>]*>([^<]+)") or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  if not html or html == "" then return "" end
  local cleaned = html_remove(html, "script", "style")
  local el = html_select_first(cleaned, "#nr1")
  if not el then return "" end
  local body = el.html or ""

  -- html_text already turns <br> into a line break; pre-replacing <br/> leaks
  -- literal newlines that the extractor then drops, collapsing the chapter
  -- into one line that the cleanup below wipes.
  return standardTransforms(html_text(body))
end
