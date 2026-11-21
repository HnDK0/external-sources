-- ── Metadata ──────────────────────────────────────────────────────────────────
id       = "syosetu18"
name     = "Syosetu R18"
version  = "1.0.0"
baseUrl  = "https://novel18.syosetu.com/"
language = "ja"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/narou.png"

-- 18+ section of Syosetu (ノクターンノベルズ). Works live on
-- novel18.syosetu.com; catalog and search live on noc.syosetu.com, which is
-- behind the age gate — every request carries the over18=yes cookie.
-- Book/chapter markup is identical to ncode.syosetu.com, so the shared
-- engine in libs/family/syosetu.lua handles detail, chapters and text.

local HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    ["Cookie"]     = "over18=yes",
}

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

local function absUrl(href) return LIB("urls").absUrl(baseUrl, href) end

local CONFIG = {
    id      = "syosetu18",
    baseUrl = baseUrl,
    headers = HEADERS,
}

-- ── Catalog (ranking) ─────────────────────────────────────────────────────────
-- noc ranking has 300 entries per period on one page and no genre/status
-- filters; paginate locally with PAGE items per adapter page.

local RANK_BASE = "https://noc.syosetu.com/rank/list/type/"
local PAGE = 50
local _rankStore = {}

local function rankItems(period)
    local url = RANK_BASE .. period .. "_total/"
    local body = _rankStore[period]
    if body == nil then
        local r = http_get(url, { headers = HEADERS })
        body = r.success and r.body or false
        _rankStore[period] = body
    end

    local items = {}
    if not body then return items end
    for _, row in ipairs(html_select(body, ".rank_h")) do
        local a = html_select_first(row.html, "a.tl")
        if a and a.href and a.href:match("novel18%.syosetu%.com/n[%w]+/?$") then
            items[#items + 1] = {
                title = string_trim(a.text),
                url   = absUrl(a.href),
                cover = "",
            }
        end
    end
    return items
end

function getCatalogList(index)
    return getCatalogFiltered(index, {})
end

function getCatalogFiltered(index, filters)
    filters = filters or {}
    local periods = { daily = true, weekly = true, monthly = true, quarter = true, yearly = true }
    local period = filters["period"]
    if not periods[period] then period = "monthly" end

    local all = rankItems(period)
    local offset = (index or 0) * PAGE
    local items = {}
    for i = offset + 1, math.min(offset + PAGE, #all) do
        items[#items + 1] = all[i]
    end
    return { items = items, hasNext = (offset + PAGE) < #all }
end

-- ── Search ────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = LIB("catalog").nextIndex(index)
    local url = "https://noc.syosetu.com/search/search/?word=" .. url_encode(query)
        .. "&p=" .. tostring(page)
    local r = http_get(url, { headers = HEADERS })
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, row in ipairs(html_select(r.body, ".novel_h")) do
        local a = html_select_first(row.html, "a.tl")
        if a and a.href and a.href:match("novel18%.syosetu%.com/n[%w]+/?$") then
            items[#items + 1] = {
                title = string_trim(a.text),
                url   = absUrl(a.href),
                cover = "",
            }
        end
    end

    return { items = items, hasNext = html_select_first(r.body, "a.nextlink") ~= nil }
end

-- ── Book / chapters / text ───────────────────────────────────────────────────

function getBookTitle(bookUrl)
    return LIB("syosetu").title(CONFIG, bookUrl)
end

function getBookCoverImageUrl(bookUrl)
    return LIB("syosetu").cover(CONFIG, bookUrl)
end

function getBookDescription(bookUrl)
    return LIB("syosetu").description(CONFIG, bookUrl)
end

function getChapterList(bookUrl)
    return LIB("syosetu").chapters(CONFIG, bookUrl)
end

function getChapterListHash(bookUrl)
    return LIB("syosetu").chapterHash(CONFIG, bookUrl)
end

function getChapterText(html, url)
    return LIB("syosetu").chapterText(CONFIG, html, url)
end

-- ── Filters ───────────────────────────────────────────────────────────────────
-- Ranking only supports the period; genre/status lists are not exposed there.

function getFilterList()
    return {
        {
            type         = "select",
            key          = "period",
            label        = "Period",
            defaultValue = "monthly",
            options = {
                { value = "daily",   label = "日間 (Daily)"      },
                { value = "weekly",  label = "週間 (Weekly)"     },
                { value = "monthly", label = "月間 (Monthly)"    },
                { value = "quarter", label = "四半期 (Quarterly)" },
                { value = "yearly",  label = "年間 (Yearly)"     },
            }
        },
    }
end
