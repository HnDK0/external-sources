-- ── Metadata ───────────────────────────────────────────────────────────────────
id       = "chikari"
name     = "Chikari Novel"
version  = "1.0.11"
baseUrl  = "https://chikari.moe/"
language = "en"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/chikari.png"

-- Text novels on chikari.moe. The shared engine lives in
-- libs/family/chikari.lua (require_lib("chikari")); this file only carries
-- metadata, config and the public wrappers.

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead.
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

local CONFIG = {
  id      = "chikari",
  baseUrl = baseUrl,
  mode    = "novel",
}

-- ── Catalog ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  return LIB("chikari").list(CONFIG, index)
end

function getCatalogSearch(index, query)
  return LIB("chikari").search(CONFIG, index, query)
end

function getFilterList()
  return LIB("chikari").filters()
end

function getCatalogFiltered(index, filters)
  return LIB("chikari").filtered(CONFIG, index, filters)
end

-- ── Book detail ───────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
  return LIB("chikari").title(CONFIG, bookUrl)
end

function getBookCoverImageUrl(bookUrl)
  return LIB("chikari").cover(CONFIG, bookUrl)
end

function getBookDescription(bookUrl)
  return LIB("chikari").description(CONFIG, bookUrl)
end

function getBookGenres(bookUrl)
  return LIB("chikari").genres(CONFIG, bookUrl)
end

function getBookAuthor(bookUrl)
  return LIB("chikari").author(CONFIG, bookUrl)
end

function getBookStatus(bookUrl)
  return LIB("chikari").status(CONFIG, bookUrl)
end

function getBookRating(bookUrl)
  return LIB("chikari").rating(CONFIG, bookUrl)
end

function getBookLastUpdate(bookUrl)
  return LIB("chikari").lastUpdate(CONFIG, bookUrl)
end

-- ── Chapters ──────────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  return LIB("chikari").chapters(CONFIG, bookUrl)
end

function getChapterText(html, url)
  return LIB("chikari").chapterText(CONFIG, html, url)
end
