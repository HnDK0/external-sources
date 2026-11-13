-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "8novel"
name     = "8novel 無限輕小說"
version  = "1.0.0"
baseUrl  = "https://www.8novel.com"
language = "zh"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/8novel.png"

-- Traditional Chinese web and light novels on 8novel.com: curated lists,
-- advanced search, book pages and chapter reading. The shared engine lives in
-- libs/family/eightnovel.lua (require_lib("eightnovel")); this file only
-- carries metadata, the SITE table and the public wrappers. 8book.com runs
-- the same engine with its own catalogue and has its own plugin (zh/8book.lua).

-- ── Helpers ─────────────────────────────────────────────────────────────────

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

-- Everything that is specific to 8novel.com. The reader domains are tried in
-- order when the first one fails or returns a foreign page (the browser of the
-- user landed on the last two). Category ids are this site's; the same number
-- means a different category on 8book.com.
local CFG = {
  id      = "8novel",
  short   = "8novel",
  baseUrl = baseUrl,
  referer = "https://www.8novel.com/",
  host    = "www.8novel.com",
  sibling = "8book.com",        -- the other site: its cover domains are rewritten to this one
  readers = { "www.8novel.com", "article.8novel.com", "go.gogowell.com" },
  popular = { "Popular Light Novels", "熱門輕小說" },
  girls   = { "Girls' Light Novels",  "女生輕小說" },
  categories = {
    { "1",  "Light Novels",             "日輕小說" },
    { "2",  "Fantasy",                  "玄幻奇幻" },
    { "3",  "Wuxia / Xianxia",          "武俠仙俠" },
    { "4",  "Transmigration / Ancient", "穿越古代" },
    { "7",  "Urban / Modern",           "都市現代" },
    { "5",  "Games / Sports",           "游戲競技" },
    { "6",  "Sci-fi / Mystery",         "科幻懸疑" },
    { "8",  "History",                  "歷史紀實" },
    { "9",  "Anime / Comics",           "動漫綜影" },
    { "10", "Other",                    "其他類型" },
  },
}

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
  return LIB("eightnovel").catalog(CFG, index)
end

function getCatalogSearch(index, query)
  return LIB("eightnovel").search(CFG, index, query)
end

function getFilterList()
  return LIB("eightnovel").filters(CFG)
end

function getCatalogFiltered(index, filters)
  return LIB("eightnovel").filtered(CFG, index, filters)
end

-- ── Book detail ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  return LIB("eightnovel").title(CFG, bookUrl)
end

function getBookCoverImageUrl(bookUrl)
  return LIB("eightnovel").cover(CFG, bookUrl)
end

function getBookDescription(bookUrl)
  return LIB("eightnovel").description(CFG, bookUrl)
end

function getBookGenres(bookUrl)
  return LIB("eightnovel").genres(CFG, bookUrl)
end

function getBookStatus(bookUrl)
  return LIB("eightnovel").status(CFG, bookUrl)
end

function getBookLastUpdate(bookUrl)
  return LIB("eightnovel").lastUpdate(CFG, bookUrl)
end

function getChapterListHash(bookUrl)
  return LIB("eightnovel").chapterListHash(CFG, bookUrl)
end

-- ── Chapters ────────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  return LIB("eightnovel").chapterList(CFG, bookUrl)
end

function getChapterText(html, url)
  return LIB("eightnovel").chapterText(CFG, html, url)
end
