-- =====================================================================
-- Lib: eightnovel family — shared engine for 8novel.com and 8book.com.
-- Loaded via require_lib("eightnovel"); uses urls/catalog/meta.
--
-- Both sites run the same engine (8book is the mirror of 8novel) with
-- their own catalogue, their own category numbering and their own search
-- page, so only the SITE table differs. Every entry point takes it first:
--   M.catalog(cfg, index)           M.search(cfg, index, query)
--   M.filtered(cfg, index, filters) M.filters(cfg)
--   M.title/cover/description/genres/status/lastUpdate (cfg, bookUrl)
--   M.chapterList(cfg, bookUrl)     M.chapterListHash(cfg, bookUrl)
--   M.chapterText(cfg, html, url)
--
-- Config:
--   id         string  log prefix and cache namespace (required)
--   short      string  site label in error notices
--   baseUrl    string  site origin, no trailing slash (required)
--   referer    string  Referer sent with every request
--   host       string  host of baseUrl
--   sibling    string  the other site's domain (covers pointing at it are
--                      rewritten to this one)
--   readers    table   reader domains tried in order, main one first
--   popular    table   { English, Chinese } name of the home-page list
--   girls      table   { English, Chinese } name of the home-page list
--   categories table   { { id, English, Chinese }, ... } of THIS site
--                      (the same number means another category elsewhere)
--
-- SITE FACTS (confirmed on the real 8novel pages)
--   Lists ..... /booklists/{update|newrelease|rank|finish}/N.html
--               /booklists/{recommend|female}/N.html  (home-page blocks)
--               /booklists/{id}/N.html                (one category)
--               /booklists/list/{cat}_{status}_{sort}/N.html  (advanced)
--               /booklists/list/{A..Z|0}/N.html       (by first letter)
--   Cards ..... div.col-lg-4 > a[href=/novelbooks/ID] + img + li.nowraphide
--               div.picsize > a[href][title] > img   (search results)
--   Pager ..... <a href="2.html"><span class='mdi mdi-skip-next'>; the last
--               page has the arrow without <a>. Search links carry a token:
--               /search/?key=_21453_27966&page=2 (valid for every page)
--   Book page . /novelbooks/{id}/ with og:novel:* metas and #chapters
--   Reader .... /read/{bookId}/?{chapterId}; the text is NOT in that page:
--               a script computes it (see M.chapterText).
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")
local catalog = require_lib("catalog")
local meta = require_lib("meta")

local M = {}

local ACCEPT_HTML = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

-- false: chapters are stored as site.webmanifest?n=BOOK&c=CHAPTER
-- true : chapters are stored as /read/BOOK/?CHAPTER (only if the site does
--        not redirect readers to a mirror domain)
local USE_DIRECT_READ_URLS = false

local PAGE_TTL_MS    = 60000
local PAGE_CACHE_MAX = 4
local READER_TTL_MS  = 20 * 60 * 1000

-- ── Utilities ────────────────────────────────────────────────────────

local function trim(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function collapse(s)
  s = tostring(s or "")
  s = s:gsub("%s+", " ")
  return trim(s)
end

local function esc(s)
  return (tostring(s):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function emptyResult() return { items = {}, hasNext = false } end

-- Cut without splitting a UTF-8 character in half
local function cut(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  local i = n
  while i > 0 do
    local b = s:byte(i + 1)
    if b and b >= 128 and b < 192 then i = i - 1 else break end
  end
  return s:sub(1, i) .. "..."
end

local function utf8char(cp)
  cp = tonumber(cp) or 63
  if cp < 0 or cp > 1114111 then return "?" end
  if cp < 128 then return string.char(cp) end
  if cp < 2048 then
    return string.char(192 + math.floor(cp / 64), 128 + cp % 64)
  end
  if cp < 65536 then
    return string.char(224 + math.floor(cp / 4096), 128 + math.floor(cp / 64) % 64, 128 + cp % 64)
  end
  return string.char(240 + math.floor(cp / 262144), 128 + math.floor(cp / 4096) % 64,
                     128 + math.floor(cp / 64) % 64, 128 + cp % 64)
end

local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  ldquo = "\226\128\156", rdquo = "\226\128\157", lsquo = "\226\128\152", rsquo = "\226\128\153",
  hellip = "\226\128\166", mdash = "\226\128\148", ndash = "\226\128\147",
}

local function decodeEntities(s)
  s = tostring(s or "")
  if not s:find("&", 1, true) then return s end
  s = s:gsub("&#[xX](%x+);", function(h) return utf8char(tonumber(h, 16)) end)
  s = s:gsub("&#(%d+);", function(d) return utf8char(tonumber(d)) end)
  s = s:gsub("&(%a+);", function(n) return ENTITIES[n] or ("&" .. n .. ";") end)
  return s
end

-- HTML -> plain text with line breaks (<br>, </p>, </div>).
-- Only real tags are stripped (< followed by a letter, / ! ?): a "<(￣︶￣)>" or a "3 < 5" in the story
-- stays, exactly like in the browser.
local function htmlToText(h)
  h = tostring(h or "")
  h = h:gsub("<[Bb][Rr]%s*/?>", "\n")
  h = h:gsub("</[Pp]>", "\n")
  h = h:gsub("</[Dd][Ii][Vv]>", "\n")
  h = h:gsub("<[%a/!?][^>]*>", "")
  return decodeEntities(h)
end

-- Strips normal spaces, the ideographic space U+3000 (typical Chinese indent) and U+00A0
local function trimLine(s)
  s = tostring(s or "")
  while true do
    if s:sub(1, 3) == "\227\128\128" then
      s = s:sub(4)
    elseif s:sub(1, 2) == "\194\160" then
      s = s:sub(3)
    elseif s:match("^%s") then
      s = s:sub(2)
    else
      break
    end
  end
  while true do
    if s:sub(-3) == "\227\128\128" then
      s = s:sub(1, -4)
    elseif s:sub(-2) == "\194\160" then
      s = s:sub(1, -3)
    elseif s:match("%s$") then
      s = s:sub(1, -2)
    else
      break
    end
  end
  return s
end

-- Splits into lines, cleans each one and appends to `out` the ones that are not empty (nor dropped by `skip`)
local function appendLines(out, text, skip)
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  for raw in (text .. "\n"):gmatch("(.-)\n") do
    local line = trimLine(raw)
    if line ~= "" and not (skip and skip(line)) then out[#out + 1] = line end
  end
end

-- ... and joins them with `sep`
local function joinLines(text, sep, skip)
  local out = {}
  appendLines(out, text, skip)
  return table.concat(out, sep)
end

-- NoveLA's os_time() returns MILLISECONDS (System.currentTimeMillis). Be robust anyway: scale seconds
-- up and survive app builds without the function. Returns a ms clock or nil when there is none.
local function clockMs()
  local ok, v = pcall(os_time)
  if ok and type(v) == "number" and v > 0 then
    if v < 100000000000 then v = v * 1000 end
    return v
  end
  return nil
end

local function nowMs() return clockMs() or 0 end

-- ── URLs ─────────────────────────────────────────────────────────────

local function absUrl(cfg, u)
  u = trim(u)
  if u == "" then return "" end
  return urls.absUrl(cfg.baseUrl, u)
end

-- Cover images. A page of one site may print the domain of the SIBLING site in its meta tags (og:image) and
-- the sibling may be unreachable. Both sites serve the same /pics/... paths, so a cover that points at the
-- sibling domain is requested from this site instead.
local function coverUrl(cfg, u)
  local a = absUrl(cfg, u)
  if a == "" then return "" end
  local h = urls.hostOf(a)
  local s = cfg.sibling
  if h ~= "" and s and h ~= cfg.host and (h == s or h == "www." .. s or "www." .. h == s) then
    return (a:gsub("^https?://[^/?#]+", function() return cfg.baseUrl end, 1))
  end
  return a
end

local function bookIdOf(u) return tostring(u or ""):match("/novelbooks/(%d+)") end
local function bookPageUrl(cfg, id) return cfg.baseUrl .. "/novelbooks/" .. id .. "/" end
-- The app normalises book URLs without the trailing "/": we return them already like that
local function bookUrlOf(cfg, id) return cfg.baseUrl .. "/novelbooks/" .. id end

-- WHY CHAPTER URLS LOOK ODD: before calling M.chapterText() the app opens the chapter URL following
-- redirects and ONLY hands the page to the plugin if the final URL starts with baseUrl. 8novel spreads its
-- readers over mirror domains, so every chapter is stored as a URL of this site that never redirects
-- (site.webmanifest?n=BOOK&c=CHAPTER: a tiny static file, the server ignores the parameters) and
-- M.chapterText() does all the work itself. The chapter URL is the identity of the chapter in the app
-- (progress, downloads): do not change the format once books are in the library.
local function chapterUrl(cfg, bookId, chId)
  if USE_DIRECT_READ_URLS then
    return cfg.baseUrl .. "/read/" .. bookId .. "/?" .. chId
  end
  return cfg.baseUrl .. "/site.webmanifest?n=" .. bookId .. "&c=" .. chId
end

-- Returns bookId, chapterId, catid (the category rarely comes in the URL: it is read from the reader or the
-- book page)
local function parseChapterRef(url)
  url = tostring(url or "")
  local n = url:match("[?&]n=(%d+)")
  local c = url:match("[?&]c=(%d+)")
  local k = url:match("[?&]k=(%d+)")
  if n and c then return n, c, k end
  local b2, c2 = url:match("/read/(%d+)/?%?(%d+)")
  if b2 and c2 then return b2, c2, nil end
  return nil, nil, nil
end

-- ── HTTP ─────────────────────────────────────────────────────────────

local function get(url, headers, noRedirect, timeoutMs)
  local cfg = { headers = headers or {} }
  if noRedirect then cfg.followRedirects = false end
  if timeoutMs then cfg.timeout = timeoutMs end   -- single attempt with this budget (ms)
  local ok, r = pcall(http_get, url, cfg)
  if not ok or type(r) ~= "table" then
    return { success = false, body = "", code = -1, headers = {}, error = tostring(r) }
  end
  r.code = tonumber(r.code) or -1
  if type(r.body) ~= "string" then r.body = "" end
  return r
end

local function headerOf(r, name)
  local h = r.headers
  if type(h) ~= "table" then return nil end
  local v = h[string.lower(name)]
  if type(v) == "table" then v = v[1] end
  if v == nil or v == "" then return nil end
  return tostring(v)
end

-- GET following redirects by hand (to know which domain it ends on); returns (response, finalUrl)
local function fetchFollow(url, headers, maxHops, timeoutMs)
  local cur = url
  local r
  for _ = 1, (maxHops or 4) + 1 do
    r = get(cur, headers, true, timeoutMs)
    if r.code >= 300 and r.code < 400 then
      local loc = headerOf(r, "location")
      if not loc then break end
      cur = urls.absUrl(cur, loc)
    else
      break
    end
  end
  return r, cur
end

-- Short summary of what the site returned (its title if any) for error notices
local function snippet(body, n)
  body = tostring(body or "")
  local t = body:match("<[Tt][Ii][Tt][Ll][Ee][^>]*>(.-)</[Tt][Ii][Tt][Ll][Ee]>")
  if t and collapse(t) ~= "" then return cut(collapse(decodeEntities(t)), n or 70) end
  local s = body:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt].-</[Ss][Cc][Rr][Ii][Pp][Tt]>", " ")
  s = s:gsub("<[^>]*>", " ")
  s = collapse(decodeEntities(s))
  if s == "" then return "(empty)" end
  return cut(s, n or 70)
end

-- ── Page metadata (plain patterns on the <meta> tags, no CSS selectors) ──

local function headOf(html)
  local e = html:find("</head>", 1, true)
  if e then return html:sub(1, e) end
  return html:sub(1, 8000)
end

local function metaContent(head, key)
  local k = esc(key)
  for _, a in ipairs({ "name", "property" }) do
    local v = head:match("<meta%s+" .. a .. "%s*=%s*\"" .. k .. "\"%s+content%s*=%s*\"(.-)\"%s*/?>")
    if not v then
      v = head:match("<meta%s+" .. a .. "%s*=%s*'" .. k .. "'%s+content%s*=%s*'(.-)'%s*/?>")
    end
    if v then return trim(decodeEntities(v)) end
  end
  return nil
end

-- ── Taxonomy ─────────────────────────────────────────────────────────

-- "All Type Novels": the stand-alone pages of the site menu. Every page works on its own; the last two are
-- the home-page blocks ("More"), whose names differ per site.
local function navPages(cfg)
  return {
    { "update",     "Latest Updates",   "最新更新", "/booklists/update/%d.html" },
    { "newrelease", "New Releases",     "新書入庫", "/booklists/newrelease/%d.html" },
    { "rank",       "Hot Ranking",      "熱門排行", "/booklists/rank/%d.html" },
    { "finish",     "Completed Novels", "全本小說", "/booklists/finish/%d.html" },
    { "recommend",  cfg.popular[1],     cfg.popular[2], "/booklists/recommend/%d.html" },
    { "female",     cfg.girls[1],       cfg.girls[2],   "/booklists/female/%d.html" },
  }
end

local STATUSES = {
  { "all",      "All",       "全部" },
  { "ongoing",  "Ongoing",   "連載" },
  { "complete", "Completed", "完結" },
}

local SORTS = {
  { "all", "Default", "全部" },
  { "hot", "Popular", "熱門" },
  { "new", "Newest",  "最新" },
}

local LETTERS = {}
for c = 65, 90 do LETTERS[#LETTERS + 1] = string.char(c) end
LETTERS[#LETTERS + 1] = "0"

local function inList(list, v)
  for _, e in ipairs(list) do
    if e[1] == v then return true end
  end
  return false
end

-- "English (中文)" — keeps the flavour of the site, the Chinese name disambiguates
local function flLabel(en, zh)
  if zh and zh ~= "" then return en .. " (" .. zh .. ")" end
  return en
end

local function opt(value, en, zh)
  return { value = value, label = flLabel(en, zh) }
end

local function hostName(cfg) return (cfg.host:gsub("^www%.", "")) end

-- ── Catalog ──────────────────────────────────────────────────────────

-- Book cards. Templates confirmed in the real HTML, plus a generic fallback:
--   A/E) list cards   div.col-lg-4 > a[href=/novelbooks/ID] > img.cover120 | img.cover5rem and
--                     li.nowraphide (title)    <- /booklists/* (update, newrelease, rank, finish, list/...)
--   B)   search cards div.picsize > a[href][title=TITLE] > img    <- /search/ (24 per page) and home blocks
--   C)   loose links  a[href*=/novelbooks/]   (only for lists, never for search)
-- kind = "list" tries A/E, B, C;  kind = "search" tries B, A/E and never C (a search without results must
-- stay empty instead of showing unrelated books).
local function parseBooks(cfg, html, kind)
  local items, seen = {}, {}
  -- The "everyone is searching" boxes (the same 10 plain links) are never results: the popup
  -- (li.search_top_sm_li) is on EVERY page and the desktop header (li.search_key_top) also on /search/
  html = html:gsub("<li class=\"search_[%w_]*\">.-</li>", "")
  local doc = html_parse(html)
  if not doc or not doc.body then return items end
  local root = doc.body

  local function add(href, title, cover)
    local id = bookIdOf(href)
    if not id or seen[id] then return end
    title = collapse(title)
    if title == "" then return end
    seen[id] = true
    local c = ""
    if cover and trim(cover) ~= "" then c = coverUrl(cfg, cover) end
    items[#items + 1] = { title = title, url = bookUrlOf(cfg, id), cover = c }
  end

  local function templateCards()
    for _, card in ipairs(html_select(root, "div.col-lg-4")) do
      local t = html_select_first(card, "li.nowraphide")
      local link = html_select_first(card, "a[href*='/novelbooks/']")
      if t and link then
        local title = t.text or ""
        if collapse(title) == "" then
          title = tostring(link.title or ""):match("([^\r\n]+)") or ""
        end
        local pic = html_select_first(card, "img")
        add(link.href, title, pic and pic.src or "")
      end
    end
  end

  local function picsizeCards()
    for _, p in ipairs(html_select(root, "div.picsize")) do
      local a = html_select_first(p, "a[href*='/novelbooks/']")
      if a then
        local img = html_select_first(p, "img")
        add(a.href, a.title, img and img.src or "")
      end
    end
  end

  if kind == "search" then
    picsizeCards()
    if #items > 0 then return items end
    templateCards()
    return items
  end

  templateCards()
  if #items > 0 then return items end
  picsizeCards()
  if #items > 0 then return items end

  -- C: loose links. When some have a cover (cards) only those are used and the title comes from the title
  -- attribute, the text of the link itself or another link to the same book (the heading); text links
  -- without cover are only used when there are no cards at all.
  local cards, order, textOf, plain = {}, {}, {}, {}
  for _, a in ipairs(html_select(root, "a[href*='/novelbooks/']")) do
    local id = bookIdOf(a.href)
    if id then
      local title = tostring(a.title or "")
      if title:find("[\r\n]") or #title > 90 then title = "" end   -- that is a summary, not a title
      local txt = collapse(a.text)
      local img = html_select_first(a, "img")
      if img then
        if not cards[id] then
          cards[id] = { title = collapse(title), text = txt, cover = img.src or "", href = a.href }
          order[#order + 1] = id
        end
      else
        if collapse(title) == "" then title = txt end
        title = collapse(title)
        if title ~= "" then
          if not textOf[id] then textOf[id] = title end
          if not plain[id] then plain[id] = { href = a.href, title = title }; plain[#plain + 1] = id end
        end
      end
    end
  end
  if #order > 0 then
    for _, id in ipairs(order) do
      local c = cards[id]
      local title = c.title
      if title == "" then title = textOf[id] or "" end
      if title == "" then title = (c.text:gsub("%s*%d+%s*篇%s*$", "")) end
      add(c.href, title, c.cover)
    end
    if #items > 0 then return items end
  end
  for _, id in ipairs(plain) do add(plain[id].href, plain[id].title, "") end
  return items
end

-- Page number that a pager link encodes: 3.html, ?page=3 or ?p=3 (explicit)
local function explicitPageNumber(h)
  h = decodeEntities(h)
  return tonumber(h:match("[?&]page=(%d+)") or h:match("[?&]p=(%d+)") or h:match("(%d+)%.html"))
end

-- ... or, when there is no explicit form, the last number in the link
local function pageNumberOfHref(h)
  local n = explicitPageNumber(h)
  if n then return n end
  for d in decodeEntities(h):gmatch("(%d+)") do n = tonumber(d) end
  return n
end

-- "Next page" link of the pager.
--  1) the arrow  <a href="2.html"><span class='mdi mdi-skip-next'>   (confirmed on every list and search page;
--     on the last page the arrow has no <a>)
--  2) fallback: inside div.pager, the link whose page number is the current one + 1
--  3) fallback: anywhere in the document, a link with ?page=NEXT (pagers without the "pager" class)
local function pagerNext(html, page)
  local href = html:match("<a[^>]-href=[\"']([^\"']+)[\"'][^>]->%s*<span[^>]-mdi%-skip%-next")
  if href then return decodeEntities(href) end
  local want = (tonumber(page) or 1) + 1
  local blk = html:match("<div[^>]-class=[\"'][^\"']*pager[^\"']*[\"'][^>]*>(.-)</div>")
  if blk then
    for h in blk:gmatch("href%s*=%s*[\"']([^\"']+)[\"']") do
      if pageNumberOfHref(h) == want then return decodeEntities(h) end
    end
  end
  for h in html:gmatch("href%s*=%s*[\"']([^\"']+)[\"']") do
    local d = decodeEntities(h)
    if d:find("[?&]page=") and explicitPageNumber(d) == want and not d:find("/novelbooks/", 1, true) then
      return d
    end
  end
  return nil
end

-- Downloads a list page and returns ({items, hasNext}, nextHref)
local function fetchBooks(cfg, url, page)
  local r = get(url, { Referer = cfg.referer })
  if not r.success or r.body == "" then
    if page == 1 then
      show_error(cfg.short, "Could not load the list (HTTP " .. tostring(r.code) .. ").\n" .. url)
    end
    return emptyResult(), nil
  end
  local items = parseBooks(cfg, r.body, "list")
  local nextHref = pagerNext(r.body, page)
  -- no recognisable pager but a full page: let the app try the next one (if it does not exist the next
  -- fetch returns nothing and the list ends). An empty page never promises another one.
  local guess = nextHref == nil and #items >= 20 and not r.body:find("mdi-skip", 1, true)
  local hasNext = #items > 0 and (nextHref ~= nil or guess)
  return { items = items, hasNext = hasNext }, nextHref
end

-- "site list key#page" -> URL given by the pager of the previous page (the site decides)
local NEXT_URL = {}

local function navPageUrlFn(cfg, path)
  return function(page) return cfg.baseUrl .. string.format(path, page) end
end

local function runList(cfg, key, pageUrl, index)
  local page = catalog.nextIndex(index)
  local pk = cfg.id .. "#" .. key .. "#"
  local url = (page > 1 and NEXT_URL[pk .. page]) or pageUrl(page)
  local res, nextHref = fetchBooks(cfg, url, page)
  if nextHref then NEXT_URL[pk .. (page + 1)] = urls.absUrl(url, nextHref) end
  return res
end

-- Maps the filters of the sheet to (list key, page URL builder)
local function resolveBrowse(cfg, filters)
  local pick = tostring(filters.all_types or "off")

  -- 1) All Type Novels: a stand-alone page (overrides Advanced Search)
  for _, p in ipairs(navPages(cfg)) do
    if p[1] == pick then return pick, navPageUrlFn(cfg, p[4]) end
  end
  local catPage = pick:match("^cat:(%d+)$")
  if catPage and inList(cfg.categories, catPage) then
    return pick, navPageUrlFn(cfg, "/booklists/" .. catPage .. "/%d.html")
  end

  -- 2) Advanced Search: a letter, or category x status x sort
  local letter = tostring(filters.letter or "all")
  if letter ~= "all" and letter:match("^[A-Z0]$") then
    return "letter:" .. letter, navPageUrlFn(cfg, "/booklists/list/" .. letter .. "/%d.html")
  end
  local cat = tostring(filters.category or "all")
  if cat ~= "all" and not inList(cfg.categories, cat) then cat = "all" end
  local status = tostring(filters.status or "all")
  if not inList(STATUSES, status) then status = "all" end
  local sort = tostring(filters.sort or "all")
  if not inList(SORTS, sort) then sort = "all" end
  local combo = cat .. "_" .. status .. "_" .. sort
  return "adv:" .. combo, navPageUrlFn(cfg, "/booklists/list/" .. combo .. "/%d.html")
end

-- Default list (no filter applied): Latest Updates
function M.catalog(cfg, index)
  return runList(cfg, "update", navPageUrlFn(cfg, "/booklists/update/%d.html"), index)
end

function M.filtered(cfg, index, filters)
  local key, pageUrl = resolveBrowse(cfg, filters or {})
  return runList(cfg, key, pageUrl, index)
end

-- The app sorts the options of every filter ALPHABETICALLY by label, so the "neutral" options start with
-- "(" to stay at the top.
function M.filters(cfg)
  local pages = { { value = "off", label = "(Off) Use Advanced Search below" } }
  for _, p in ipairs(navPages(cfg)) do pages[#pages + 1] = opt(p[1], p[2], p[3]) end
  for _, c in ipairs(cfg.categories) do
    pages[#pages + 1] = opt("cat:" .. c[1], "Category · " .. c[2], c[3])
  end

  local cats = { { value = "all", label = "(All categories)" } }
  for _, c in ipairs(cfg.categories) do cats[#cats + 1] = opt(c[1], c[2], c[3]) end
  local statuses = {}
  for _, s in ipairs(STATUSES) do statuses[#statuses + 1] = opt(s[1], s[2], s[3]) end
  local sorts = {}
  for _, s in ipairs(SORTS) do sorts[#sorts + 1] = opt(s[1], s[2], s[3]) end
  local letters = { { value = "all", label = "(Any letter)" } }
  for _, l in ipairs(LETTERS) do
    letters[#letters + 1] = { value = l, label = l == "0" and "0-9 / other (0)" or l }
  end

  return {
    { type = "select", key = "all_types",
      label = "All Type Novels · " .. hostName(cfg) .. " — one page (overrides Advanced Search)",
      defaultValue = "off", options = pages },
    { type = "select", key = "category", label = "Advanced Search · Category",
      defaultValue = "all", options = cats },
    { type = "select", key = "status", label = "Advanced Search · Status",
      defaultValue = "all", options = statuses },
    { type = "select", key = "sort", label = "Advanced Search · Sort",
      defaultValue = "all", options = sorts },
    { type = "select", key = "letter", label = "Advanced Search · First letter (overrides Category/Status/Sort)",
      defaultValue = "all", options = letters },
  }
end

-- ── Search ───────────────────────────────────────────────────────────
-- /search/?key=WORDS  ->  results (24 per page). The pager links carry a token of the site
-- (/search/?key=_21453_27966&page=2) that is valid for ANY page of that search, so it is remembered per
-- query; if the plugin state was lost between pages, page 1 is loaded again to learn it.

local SEARCH_TOKEN = {}   -- "site query" -> its token

local function tokenOf(href)
  return decodeEntities(tostring(href or "")):match("[?&]key=([^&#]+)")
end

local function learnToken(cfg, q, body)
  local href = pagerNext(body, 1)
  local tok = href and tokenOf(href) or nil
  if not tok then
    for h in body:gmatch("href%s*=%s*[\"']([^\"']+)[\"']") do
      local d = decodeEntities(h)
      if d:find("/search/", 1, true) and d:find("[?&]page=") then
        tok = tokenOf(d)
        if tok then break end
      end
    end
  end
  if tok and tok ~= "" then SEARCH_TOKEN[cfg.id .. "\1" .. q] = tok end
end

local function singleBookFromPage(cfg, body)
  local head = headOf(body)
  local name = metaContent(head, "og:novel:book_name")
  local id = metaContent(head, "id")
  if not id then id = (metaContent(head, "og:url") or ""):match("/novelbooks/(%d+)") end
  if name and id and id:match("^%d+$") then
    local cover = metaContent(head, "og:image") or metaContent(head, "pic") or ""
    return { title = collapse(name), url = bookUrlOf(cfg, id), cover = coverUrl(cfg, cover) }
  end
  return nil
end

-- Searches `q` (exactly as the site must receive it). Returns {items, hasNext} or nil on a request failure.
local function searchPage(cfg, q, page)
  local first = cfg.baseUrl .. "/search/?key=" .. catalog.urlEncode(q)
  local url = first
  local tk = cfg.id .. "\1" .. q
  if page > 1 then
    if not SEARCH_TOKEN[tk] then
      local r1 = get(first, { Referer = cfg.referer })
      if r1.success and r1.body ~= "" then learnToken(cfg, q, r1.body) end
    end
    local tok = SEARCH_TOKEN[tk]
    if tok then
      url = cfg.baseUrl .. "/search/?key=" .. tok .. "&page=" .. string.format("%d", page)
    else
      url = first .. "&page=" .. string.format("%d", page)
    end
  end
  local r = get(url, { Referer = cfg.referer })
  if not r.success or r.body == "" then return nil, r end
  -- the site may jump straight to the book page when there is a single match
  local single = page == 1 and singleBookFromPage(cfg, r.body) or nil
  if single then return { items = { single }, hasNext = false }, r end
  local items = parseBooks(cfg, r.body, "search")
  -- only promise another page when the site shows a "next" link: guessing ?page=N could repeat page 1
  local nextHref = pagerNext(r.body, page)
  if nextHref then
    local tok = tokenOf(nextHref)
    if tok then SEARCH_TOKEN[tk] = tok end
  end
  return { items = items, hasNext = #items > 0 and nextHref ~= nil }, r
end

function M.search(cfg, index, query)
  local typed = trim(query)
  if typed == "" then return emptyResult() end
  local page = catalog.nextIndex(index)
  local res, r = searchPage(cfg, typed, page)
  if res then return res end
  if page == 1 then
    show_error(cfg.short, "The search failed (HTTP " .. tostring(r and r.code or "?") .. ").")
  end
  return emptyResult()
end

-- ── Book page ────────────────────────────────────────────────────────
-- The app asks for title, cover, description, genres, status, last update and hash one after another; each
-- used to download the same page. A short session cache serves that burst from one fetch (the chapter text
-- is never cached).

local pageCache, pageCacheOrder = {}, {}

local function fetchBook(cfg, bookUrl)
  local id = bookIdOf(bookUrl)
  if not id then return nil, nil, nil end
  local url = bookPageUrl(cfg, id)
  local now = clockMs()
  if now then
    local e = pageCache[url]
    if e and (now - e.t) < PAGE_TTL_MS then return e.r.body, id, e.r end
  end
  local r = get(url, { Referer = cfg.referer })
  if r.success and r.body ~= "" then
    if now then
      if pageCache[url] == nil then
        pageCacheOrder[#pageCacheOrder + 1] = url
        if #pageCacheOrder > PAGE_CACHE_MAX then pageCache[table.remove(pageCacheOrder, 1)] = nil end
      end
      pageCache[url] = { r = r, t = now }
    end
    return r.body, id, r
  end
  return nil, id, r
end

function M.title(cfg, bookUrl)
  local html = fetchBook(cfg, bookUrl)
  if not html then return nil end
  local head = headOf(html)
  local t = metaContent(head, "og:novel:book_name") or metaContent(head, "og:title") or metaContent(head, "name")
  if not t or collapse(t) == "" then
    local doc = html_parse(html)
    local el = doc and doc.body and html_select_first(doc.body, "li.h2")
    if el then t = el.text end
  end
  if not t or collapse(t) == "" then return nil end
  return collapse(t)
end

function M.cover(cfg, bookUrl)
  local html = fetchBook(cfg, bookUrl)
  if not html then return nil end
  local head = headOf(html)
  local c = metaContent(head, "og:image") or metaContent(head, "pic")
  if c and c ~= "" then return coverUrl(cfg, c) end
  return nil
end

function M.description(cfg, bookUrl)
  local html = fetchBook(cfg, bookUrl)
  if not html then return nil end
  local desc
  local doc = html_parse(html)
  local el = doc and doc.body and html_select_first(doc.body, "li.full_text")
  if el then
    local txt = joinLines(htmlToText(el.html), "\n")
    if txt ~= "" then desc = txt end
  end
  if not desc then
    local d = metaContent(headOf(html), "og:description") or metaContent(headOf(html), "description")
    if d and d ~= "" then desc = joinLines(d, "\n") end
  end
  return desc
end

function M.genres(cfg, bookUrl)
  local html = fetchBook(cfg, bookUrl)
  if not html then return {} end
  local head = headOf(html)
  local c = metaContent(head, "og:novel:category") or metaContent(head, "cat")
  if c and c ~= "" then return { collapse(c) } end
  return {}
end

function M.status(cfg, bookUrl)
  local html = fetchBook(cfg, bookUrl)
  if not html then return nil end
  local doc = html_parse(html)
  local el = doc and doc.body and html_select_first(doc.body, "span.item-info-status")
  if not el then return nil end
  return meta.status(el.text)
end

function M.lastUpdate(cfg, bookUrl)
  local html = fetchBook(cfg, bookUrl)
  if not html then return nil end
  local head = headOf(html)
  return metaContent(head, "og:novel:update_time") or metaContent(head, "update")
end

-- Fingerprint to detect new chapters: total + date + last title (everything is in the <meta> tags).
-- Direct, UNCACHED fetch on purpose: a cached page would keep answering with the state from before the new
-- chapters appeared and the app would never see the update.
function M.chapterListHash(cfg, bookUrl)
  local id = bookIdOf(bookUrl)
  if not id then return nil end
  local r = get(bookPageUrl(cfg, id), { Referer = cfg.referer })
  if not r.success or r.body == "" then return nil end
  local head = headOf(r.body)
  local h = table.concat({
    metaContent(head, "count") or "",
    metaContent(head, "og:novel:update_time") or metaContent(head, "update") or "",
    metaContent(head, "lastchapter") or metaContent(head, "og:novel:latest_chapter_name") or "",
  }, "|")
  if h == "||" then return nil end
  return h
end

-- "正文 / 180" -> "正文"
local function cleanVolume(s)
  s = collapse(s)
  s = s:gsub("%s*/%s*%d+%s*$", "")
  s = trim(s)
  if s == "" then return nil end
  return s
end

function M.chapterList(cfg, bookUrl)
  local html, id, resp = fetchBook(cfg, bookUrl)
  if not html then
    show_error(cfg.short, "Could not open the book page (HTTP " .. tostring(resp and resp.code or "?") .. ").")
    return {}
  end
  local doc = html_parse(html)
  local root = doc.body

  local groups = {}
  local seen = {}

  local function collect(links, vol)
    local g = { vol = vol, items = {} }
    for _, a in ipairs(links) do
      local href = tostring(a.href or "")
      local cid = href:match("%?(%d+)")
      local bid = href:match("/read/(%d+)") or id
      local title = collapse(a.text)
      if cid and title ~= "" and not seen[cid] then
        seen[cid] = true
        g.items[#g.items + 1] = { title = title, bid = bid, cid = cid }
      end
    end
    if #g.items > 0 then groups[#groups + 1] = g end
  end

  for _, folder in ipairs(html_select(root, "#chapters .folder")) do
    local volEl = html_select_first(folder, ".vol-title h3")
    collect(html_select(folder, "a.episode_li"), volEl and cleanVolume(volEl.text) or nil)
  end
  if #groups == 0 then collect(html_select(root, "a.episode_li"), nil) end
  if #groups == 0 then collect(html_select(root, "#chapters a[href*='/read/']"), nil) end
  if #groups == 0 then collect(html_select(root, "a[href*='/read/']"), nil) end   -- layout differs: any reader link

  local multi = #groups > 1
  local out = {}
  for _, g in ipairs(groups) do
    for _, it in ipairs(g.items) do
      out[#out + 1] = {
        title = it.title,
        url = chapterUrl(cfg, it.bid, it.cid),
        volume = multi and g.vol or nil,
      }
    end
  end
  return out
end

-- ── Chapter text ─────────────────────────────────────────────────────
-- Chapter text lives at /txt/{catid}/{bookId}/{chapterId}{5 digits}.html. The 5 digits come from a "decoy"
-- (long digit string at the end of the reader's id list): decoy.substr(chapterId * MUL % MOD, LEN). Verified
-- by running the real reader script for 180 chapters and against the real server. The reader (rtp in
-- /js/read.js) splits on <br>, trims spaces/&nbsp; at the start and DROPS empty lines and lines that START
-- with an HTML comment; the same rules are applied here. The site also injects a watermark line written with
-- look-alike letters.

local readerCache = {}   -- "site:bookId" -> reader context
local catCache = {}      -- "site:bookId" -> /txt/ category id

-- Reads the reader page: id list + decoy (last element) + formula parameters
local function parseReader(body)
  if type(body) ~= "string" or #body < 200 then return nil end
  local best
  for lit in body:gmatch("[\"']([%d,]+)[\"']%.split%(") do
    if not best or #lit > #best then best = lit end
  end
  if not best then return nil end
  local parts = {}
  for tok in best:gmatch("[^,]+") do parts[#parts + 1] = tok end
  if #parts < 2 then return nil end

  local decoy = parts[#parts]
  local ids = {}
  for i = 1, #parts - 1 do ids[i] = parts[i] end
  if #decoy < 20 then   -- no decoy at the end (unexpected format): everything is an id
    ids[#ids + 1] = decoy
    decoy = ""
  end

  -- .substr(ID * MUL % MOD, LEN): variable names change on every page, the values are looked up in
  -- their "var X=N;"
  local function num(tok, default)
    if not tok then return default end
    local v = tonumber(tok)
    if v then return v end
    v = body:match("var%s+" .. esc(tok) .. "%s*=%s*(%d+)%s*[;,]")
    return tonumber(v) or default
  end
  local a1, a2, a3, a4 = body:match("%.substr%(%s*([%w_$]+)%s*%*%s*([%w_$]+)%s*%%%s*([%w_$]+)%s*,%s*([%w_$]+)%s*%)")
  local mul, mod, len = 3, 100, 5
  if a1 then
    mul = num(a2, 3)
    mod = num(a3, 100)
    len = num(a4, 5)
  end
  if mod == 0 then mod = 100 end

  local head = headOf(body)
  return {
    ids = ids,
    decoy = decoy,
    mul = mul,
    mod = mod,
    len = len,
    td = body:match("var%s+td%s*=%s*[\"']([^\"']*)[\"']") or "",
    cat = metaContent(head, "catid"),
    book = metaContent(head, "itemid"),
  }
end

local function suffixFor(ctx, chId)
  if ctx.decoy == "" then return "" end
  local off = (tonumber(chId) * ctx.mul) % ctx.mod
  return ctx.decoy:sub(off + 1, off + ctx.len)
end

local function looksForeign(body)
  local low = body:lower()
  if low:find("wp-content", 1, true) or low:find("wp-includes", 1, true) or low:find("wp-json", 1, true) then
    return true
  end
  if low:find("content=\"wordpress", 1, true) then return true end
  return false
end

-- Look-alike letters the site uses to write its watermark so a simple filter cannot find it:
-- ⑧ΝОνｅ┗.ｃΟｍ = "8NOveL.com" (8novel; 8book is assumed to do the same). They are folded to ASCII only to
-- DETECT it.
local CONFUSABLE = {
  [0x2517] = "L", [0x2514] = "L", [0x2516] = "L", [0x2570] = "L",
  -- Greek
  [0x391] = "A", [0x392] = "B", [0x395] = "E", [0x396] = "Z", [0x397] = "H", [0x399] = "I",
  [0x39A] = "K", [0x39C] = "M", [0x39D] = "N", [0x39F] = "O", [0x3A1] = "P", [0x3A4] = "T",
  [0x3A5] = "Y", [0x3A7] = "X", [0x3B1] = "a", [0x3B9] = "i", [0x3BD] = "v", [0x3BF] = "o",
  [0x3C1] = "p", [0x3C5] = "u", [0x3C7] = "x", [0x3BA] = "k",
  -- Cyrillic
  [0x410] = "A", [0x412] = "B", [0x415] = "E", [0x41A] = "K", [0x41C] = "M", [0x41D] = "H",
  [0x41E] = "O", [0x420] = "P", [0x421] = "C", [0x422] = "T", [0x425] = "X",
  [0x430] = "a", [0x435] = "e", [0x43E] = "o", [0x440] = "p", [0x441] = "c", [0x443] = "y",
  [0x445] = "x", [0x43A] = "k",
}

local function codepointOf(ch)
  local b1, b2, b3, b4 = ch:byte(1, 4)
  if not b2 then return b1 end
  if b1 < 224 then return (b1 - 192) * 64 + (b2 - 128) end
  if b1 < 240 then return (b1 - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128) end
  return (b1 - 240) * 262144 + (b2 - 128) * 4096 + (b3 - 128) * 64 + (b4 - 128)
end

local function foldLookalikes(s)
  return (s:gsub("[\1-\127\194-\244][\128-\191]*", function(ch)
    if #ch == 1 then return ch end
    local cp = codepointOf(ch)
    local m = CONFUSABLE[cp]
    if m then return m end
    if cp >= 0x2460 and cp <= 0x2468 then return tostring(cp - 0x245F) end      -- (1)..(9) in circles
    if cp >= 0xFF01 and cp <= 0xFF5E then return string.char(cp - 0xFEE0) end   -- full-width ASCII
    return ch
  end))
end

-- A line that is not part of the story: the site's watermark or a bare URL
local function isNoiseLine(l)
  if l:lower():match("^https?://%S+$") then return true end
  if #l > 120 then return false end
  local f = foldLookalikes(l):lower()
  return f:find("8nove", 1, true) ~= nil or f:find("novel.com", 1, true) ~= nil
      or f:find("8boo", 1, true) ~= nil   -- 8book.com (watermark layout unknown: same engine, same trick)
end

-- Strips spaces, &nbsp; and ideographic spaces at the start (like rtp in /js/read.js)
local function trimLead(s)
  repeat
    local before = s
    s = s:gsub("^%s+", "")
    s = s:gsub("^&[Nn][Bb][Ss][Pp];", "")
    s = s:gsub("^&#160;", "")
    s = s:gsub("^\227\128\128", "")   -- U+3000
    s = s:gsub("^\194\160", "")       -- U+00A0
  until s == before
  return s
end

-- Splits on <br>, <br/>, <br /> (case-insensitive)
local function splitBr(s)
  local out, pos = {}, 1
  while true do
    local a = s:find("<[Bb][Rr][%s/>]", pos)
    local e = a and s:find(">", a, true)
    if not a or not e then
      out[#out + 1] = s:sub(pos)
      break
    end
    out[#out + 1] = s:sub(pos, a - 1)
    pos = e + 1
  end
  return out
end

-- Turns the raw /txt/ answer into text. Reader rules (rtp): lines separated by <br>; &nbsp;/spaces at the
-- start are trimmed; empty lines and lines that START with an HTML comment are dropped. Also accepts <p>,
-- plain text with line breaks, a full HTML page or a JSON {content=...}; removes the "|N" counter,
-- invisible characters and the watermark.
local function cleanChapter(raw)
  local s = tostring(raw or "")
  s = s:gsub("^\239\187\191", "")
  local first = s:match("^%s*(.)")
  if first == "{" or first == "[" then
    local ok, j = pcall(json_parse, s)
    if ok and type(j) == "table" then
      local v = j.content or j.text or j.data or j.body or j.txt
      if type(v) == "string" then s = v end
    end
  end
  local inner = s:match("<[Bb][Oo][Dd][Yy][^>]*>(.*)</[Bb][Oo][Dd][Yy]>")
  if inner then s = inner end
  s = s:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt].-</[Ss][Cc][Rr][Ii][Pp][Tt]>", "")
  s = s:gsub("<[Ss][Tt][Yy][Ll][Ee].-</[Ss][Tt][Yy][Ll][Ee]>", "")
  s = s:gsub("%s*|%d+%s*$", "")

  local out = {}
  for _, piece in ipairs(splitBr(s)) do
    local p = trimLead(piece)
    if p ~= "" and p:sub(1, 4) ~= "<!--" then
      p = p:gsub("<!%-%-.-%-%->", "")
      local t = htmlToText(p)
      t = t:gsub("\226\128[\139-\143]", "")   -- U+200B..U+200F
      t = t:gsub("\226\129\160", "")          -- U+2060
      t = t:gsub("\239\187\191", "")          -- U+FEFF
      appendLines(out, t, isNoiseLine)
    end
  end
  return table.concat(out, "\n\n")
end

-- Book category (for /txt/{catid}/...) when the reader does not carry it: it comes from the book page
local function bookCategory(cfg, bookId)
  local key = cfg.id .. ":" .. bookId
  if catCache[key] then return catCache[key] end
  local r = get(bookPageUrl(cfg, bookId), { Referer = cfg.referer })
  if r.success then
    local c = metaContent(headOf(r.body), "catid")
    if c and c:match("^%d+$") then
      catCache[key] = c
      return c
    end
  end
  return nil
end

-- Requests the text with an already known reader context. Returns text or (nil, reason).
-- /txt/ is asked first from the domain that served the reader (as the browser does) and, if that fails,
-- from the main domain of the site, which also serves it (confirmed live on www.8novel.com for book 332600).
local function fetchText(cfg, ctx, chId)
  local cat = ctx.cat or ctx.catHint
  if not cat or cat == "" then cat = bookCategory(cfg, ctx.bookId) end
  if not cat or cat == "" then return nil, "no category (catid)" end
  local origin = "https://" .. ctx.host
  if ctx.td and ctx.td ~= "" then
    if ctx.td:sub(1, 2) == "//" then origin = "https:" .. ctx.td
    elseif ctx.td:match("^https?://") then origin = ctx.td end
    origin = origin:gsub("/+$", "")
  end
  local path = "/txt/" .. cat .. "/" .. ctx.bookId .. "/" .. chId .. suffixFor(ctx, chId) .. ".html"
  local origins = { origin }
  if origin ~= cfg.baseUrl then origins[#origins + 1] = cfg.baseUrl end

  local why = {}
  for i, o in ipairs(origins) do
    local tag = urls.hostOf(o)
    if tag == "" then tag = o end
    local r = get(o .. path, {
      Referer = ctx.readerUrl,
      ["X-Requested-With"] = "XMLHttpRequest",
      Accept = "text/html, */*; q=0.01",
    }, false, i > 1 and 12000 or nil)
    if not r.success then
      why[#why + 1] = tag .. ": /txt HTTP " .. tostring(r.code)
    elseif r.body:find("<title>404%.") then
      why[#why + 1] = tag .. ": /txt gave 404"
    elseif looksForeign(r.body) then
      why[#why + 1] = tag .. ": /txt returned a foreign page: " .. snippet(r.body, 60)
    else
      local text = cleanChapter(r.body)
      if #text >= 10 then return text end
      why[#why + 1] = tag .. ": /txt empty: " .. snippet(r.body, 60)
    end
  end
  return nil, table.concat(why, "; ")
end

-- Client-side jump (meta refresh, location.replace/href=...) to another reader: only in small pages (a plain
-- jump) and only when the target is a /read/. Returns an absolute URL or nil
local function clientRedirect(body, baseUrl)
  if #body > 8000 then return nil end
  local t = body:match("[Hh][Tt][Tt][Pp]%-[Ee][Qq][Uu][Ii][Vv]%s*=%s*[\"'][Rr][Ee][Ff][Rr][Ee][Ss][Hh][\"'][^>]-[Cc][Oo][Nn][Tt][Ee][Nn][Tt]%s*=%s*[\"']%s*%d+%s*;%s*[Uu][Rr][Ll]%s*=%s*['\"]?([^\"'>]+)")
  t = t or body:match("location%.replace%(%s*[\"']([^\"']+)[\"']")
  t = t or body:match("location%.href%s*=%s*[\"']([^\"']+)[\"']")
  t = t or body:match("window%.location%s*=%s*[\"']([^\"']+)[\"']")
  if t and t:find("/read/", 1, true) then return urls.absUrl(baseUrl, decodeEntities(trim(t))) end
  return nil
end

local function discoverReader(host, bookId, chId, bookRef, timeoutMs)
  local url = "https://" .. host .. "/read/" .. bookId .. "/?" .. chId
  local r, finalUrl = fetchFollow(url, { Referer = bookRef, Accept = ACCEPT_HTML }, 4, timeoutMs)
  if not r.success then return nil, "/read HTTP " .. tostring(r.code) end
  local ctx = parseReader(r.body)
  if not ctx then
    local jump = clientRedirect(r.body, finalUrl)
    if jump then
      local r2, final2 = fetchFollow(jump, { Referer = finalUrl, Accept = ACCEPT_HTML }, 4, timeoutMs)
      if r2.success then
        ctx = parseReader(r2.body)
        if ctx then r, finalUrl = r2, final2 end
      end
    end
  end
  if not ctx then
    return nil, "/read without a chapter list (looks like a foreign site): " .. snippet(r.body, 60)
  end
  local h = urls.hostOf(finalUrl)
  ctx.host = h ~= "" and h or host
  ctx.readerUrl = finalUrl
  ctx.bookId = bookId
  ctx.stamp = nowMs()
  return ctx
end

function M.chapterText(cfg, html, url)
  local bookId, chId, catHint = parseChapterRef(url)
  if not bookId or not chId then
    show_error(cfg.short, "Unrecognised chapter URL:\n" .. tostring(url))
    return nil
  end
  local bookRef = bookPageUrl(cfg, bookId)
  local key = cfg.id .. ":" .. bookId
  local why = {}

  -- 1) if the app already gave us the reader page (USE_DIRECT_READ_URLS mode) use it
  if type(html) == "string" and html:find("split(", 1, true) then
    local ctx = parseReader(html)
    if ctx then
      local h = urls.hostOf(url)
      ctx.host = h ~= "" and h or cfg.host
      ctx.readerUrl = url
      ctx.bookId = bookId
      ctx.catHint = catHint
      ctx.stamp = nowMs()
      local text, e = fetchText(cfg, ctx, chId)
      if text then
        readerCache[key] = ctx
        return text
      end
      why[#why + 1] = ctx.host .. ": " .. tostring(e)
    end
  end

  -- 2) cached context (same book, earlier chapters)
  local cached = readerCache[key]
  if cached and (nowMs() - (cached.stamp or 0)) < READER_TTL_MS then
    cached.catHint = cached.catHint or catHint
    local text, e = fetchText(cfg, cached, chId)
    if text then return text end
    why[#why + 1] = "cache " .. cached.host .. ": " .. tostring(e)
    readerCache[key] = nil
  end

  -- 3) discover the reader trying the domains in order
  for i, host in ipairs(cfg.readers) do
    -- the first domain uses the app's normal retries; the fallback ones a single 12 s attempt
    local ctx, e = discoverReader(host, bookId, chId, bookRef, i > 1 and 12000 or nil)
    if ctx then
      ctx.catHint = catHint
      local text, e2 = fetchText(cfg, ctx, chId)
      if text then
        readerCache[key] = ctx
        return text
      end
      why[#why + 1] = ctx.host .. ": " .. tostring(e2)
    else
      why[#why + 1] = host .. ": " .. tostring(e)
    end
  end

  show_error(cfg.short, "Could not get the text of chapter " .. chId .. " (book " .. bookId .. ").\n"
    .. "The site spreads its readers over mirror domains and some of them return foreign pages.\n\n"
    .. table.concat(why, "\n"))
  return nil
end

return M
