-- =====================================================================
-- Lib: catalog filter helpers: unified KEY constants, schema builders
--      (select/checkbox/text/tristate), common OPTIONS, safe getter.
-- Schema per lua-plugin-guide.md «Фильтры каталога» (getFilterList).
-- Loaded via require_lib("filters"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- =====================================================================
-- Unified filter keys
-- =====================================================================

-- Keys as Kotlin delivers them into the `filters` table of
-- getCatalogFiltered (guide: checkbox/tristate/tag_input values arrive
-- under "<key>_included"/"<key>_excluded", selects/switches/text under
-- "<key>"). Genres are unified on "genre_included" — already the read
-- key in 28 plugins; declare checkbox filters with key = "genre".
M.KEY = {
    genre  = "genre_included",
    status = "status",
    type   = "type",
    sort   = "sort",
}

-- =====================================================================
-- Schema builders (getFilterList elements)
-- =====================================================================

-- Select one value: { type, key, label, defaultValue, options }.
function M.select(key, label, options, default)
    return { type = "select", key = key, label = label, defaultValue = default, options = options }
end

-- Multi-include checkbox: values arrive as filters[key .. "_included"]
-- (so a checkbox with key "genre" is read via M.KEY.genre).
function M.checkbox(key, label, options)
    return { type = "checkbox", key = key, label = label, options = options }
end

-- Free-text input; `default` maps to defaultValue ("" when omitted,
-- per the guide's author example).
function M.text(key, label, default)
    return { type = "text", key = key, label = label, defaultValue = default or "" }
end

-- Include/exclude/ignore per option: values arrive as
-- filters[key .. "_included"] / filters[key .. "_excluded"].
function M.tristate(key, label, options)
    return { type = "tristate", key = key, label = label, options = options }
end

-- =====================================================================
-- Common option sets
-- =====================================================================

-- Anime type / airing status — from en/hianimes.lua:386-401
-- (the only general-purpose pair found across plugins); sort — the
-- generic trio from the guide's select example. Sites with their own
-- vocabularies keep local option tables.
M.OPTIONS = {
    type = {
        { value = "All",     label = "All" },
        { value = "TV",      label = "TV" },
        { value = "Movie",   label = "Movie" },
        { value = "OVA",     label = "OVA" },
        { value = "Special", label = "Special" },
        { value = "ONA",     label = "ONA" },
        { value = "Music",   label = "Music" },
    },
    status = {
        { value = "All",       label = "All" },
        { value = "Airing",    label = "Airing" },
        { value = "Completed", label = "Completed" },
        { value = "Upcoming",  label = "Upcoming" },
    },
    sort = {
        { value = "latest",  label = "Latest Update" },
        { value = "popular", label = "Most Popular" },
        { value = "rating",  label = "Top Rated" },
    },
}

-- =====================================================================
-- Value access
-- =====================================================================

-- Safe getter for a filter value with default: tolerates nil/empty
-- `filters` (Kotlin may pass nothing when the user never opened the
-- filter sheet). Works for select strings and checkbox/tristate arrays.
function M.get(filters, key, default)
    if type(filters) ~= "table" then return default end
    local v = filters[key]
    if v == nil then return default end
    return v
end

return M
