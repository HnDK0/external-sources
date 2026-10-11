-- Loaded via require_lib("novelfire"): the whole engine (catalog/search,
-- book details, AJAX chapter list, reader text, filters) lives in
-- libs/family/novelfire.lua — this file only carries the site metadata,
-- the family config and the wrappers.
id       = "novelfire"
name     = "NovelFire"
version  = "1.1.0"
baseUrl  = "https://novelfire.net"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelfire.png"

local CONFIG = {
    baseUrl = baseUrl,
    name    = name,
    -- Book path segment of chapter URLs and the two book-page selectors
    -- that differ between the copies of this family.
    chapterPath        = "/book",
    statusSelector     = ".header-stats strong",
    lastUpdateSelector = ".chapter-latest-container .update",
}

-- Old builds ship no require_lib: keep the plugin loadable (a top-level
-- error would drop it from the source list) and fail with a visible
-- message on the first call instead.
local family
local function F()
    if type(require_lib) ~= "function" then
        show_error("Требуется обновление NoveLA", "Плагину нужны общие библиотеки")
        error("Требуется обновление NoveLA (require_lib)", 0)
    end
    if not family then family = require_lib("novelfire") end
    return family
end

function getCatalogList(index) return F().getCatalogList(CONFIG, index) end
function getCatalogSearch(index, query) return F().getCatalogSearch(CONFIG, index, query) end
function getFilterList() return F().getFilterList(CONFIG) end
function getCatalogFiltered(index, filters) return F().getCatalogFiltered(CONFIG, index, filters) end

function getBookTitle(bookUrl) return F().getBookTitle(CONFIG, bookUrl) end
function getBookCoverImageUrl(bookUrl) return F().getBookCoverImageUrl(CONFIG, bookUrl) end
function getBookDescription(bookUrl) return F().getBookDescription(CONFIG, bookUrl) end
function getBookGenres(bookUrl) return F().getBookGenres(CONFIG, bookUrl) end
function getBookRating(bookUrl) return F().getBookRating(CONFIG, bookUrl) end
function getBookStatus(bookUrl) return F().getBookStatus(CONFIG, bookUrl) end
function getBookLastUpdate(bookUrl) return F().getBookLastUpdate(CONFIG, bookUrl) end

function getChapterList(bookUrl) return F().getChapterList(CONFIG, bookUrl) end
function getChapterListHash(bookUrl) return F().getChapterListHash(CONFIG, bookUrl) end

function getChapterText(html, url) return F().getChapterText(CONFIG, html, url) end
