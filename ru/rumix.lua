-- Loaded via require_lib("readmanga"): the whole engine (catalog API,
-- book details, chapter list, rm_h.readerInit pages, filters) lives in
-- libs/family/readmanga.lua — this file only carries the site metadata,
-- the family config and the site-specific hooks.
id       = "rumix"
name     = "RuMix"
version  = "1.1.0"
baseUrl  = "https://rumix.me"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/readmanga.png"
content_type = "manga"

local CONFIG = {
    baseUrl = baseUrl,
    name    = name,
    -- Rumix posters live under uploads/pics/ and miss the family markup.
    coverFallback = function(body)
        return body:match('src="([^"]*uploads/pics/[^"]*)"')
    end,
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
    if not family then family = require_lib("readmanga") end
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

function getPageList(html, url) return F().getPageList(CONFIG, html, url) end
function getChapterText(html, url) return F().getChapterText(CONFIG, html, url) end
