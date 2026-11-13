-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "8book"
name     = "8book 無限小說"
version  = "1.0.0"
baseUrl  = "https://8book.com"
language = "zh"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/8book.png"

-- Traditional Chinese web novels on 8book.com (no "www"), the mirror of
-- 8novel.com with its own catalogue and its own category numbering. The shared
-- engine lives in libs/family/eightnovel.lua (require_lib("eightnovel")); this
-- file only carries metadata, the SITE table and the public wrappers.

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

-- Everything that is specific to 8book.com. Category ids are this site's; the
-- same number means a different category on 8novel.com.
local CFG = {
  id      = "8book",
  short   = "8book",
  baseUrl = baseUrl,
  referer = "https://8book.com/",
  host    = "8book.com",
  sibling = "www.8novel.com",   -- the other site: its cover domains are rewritten to this one
  readers = { "8book.com", "article.8book.com" },
  popular = { "Popular Novels", "熱門小說" },
  girls   = { "Girls' Novels",  "女生小說" },
  categories = {
    { "2",  "Xianxia / Wuxia",          "仙俠武俠" },
    { "8",  "Fantasy",                  "玄幻奇幻" },
    { "3",  "Urban / Romance",          "都市言情" },
    { "4",  "Transmigration / Rebirth", "穿越重生" },
    { "1",  "Magic / Other Worlds",     "魔法異界" },
    { "6",  "Games / Sports",           "游戲競技" },
    { "5",  "Mystery / Supernatural",   "懸疑靈異" },
    { "9",  "Light Novels",             "日輕小說" },
    { "14", "Anime / Fanfiction",       "動漫同人" },
    { "10", "Military / Non-fiction",   "軍事紀實" },
    { "11", "History / Classics",       "歷史名著" },
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
