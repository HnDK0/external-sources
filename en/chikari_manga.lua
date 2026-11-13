-- ── Metadata ───────────────────────────────────────────────────────────────────
id           = "chikari_manga"
name         = "Chikari Manga"
version      = "1.0.0"
baseUrl      = "https://chikari.moe/"
language     = "en"
content_type = "manga"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/chikari.png"

-- Comics on chikari.moe (manhwa/manhua/manga) share the engine with the novel
-- plugin: libs/family/chikari.lua. The only differences are the type filter,
-- the /api/series detail route and page images instead of chapter text.

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
  id      = "chikari_manga",
  baseUrl = baseUrl,
  mode    = "manga",
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

function getPageList(html, url)
  return LIB("chikari").pageList(CONFIG, html, url)
end
