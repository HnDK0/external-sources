-- =====================================================================
-- Lib: book metadata normalization (rating, update date, status,
--      genre list) shared by the novel extractors.
-- Loaded via require_lib("meta"). No dependencies on other libs.
--
-- Nothing here maps or invents values: an input the site did not really
-- send comes back as nil (plus a log line) so the app shows nothing
-- instead of a made-up number.
-- =====================================================================
local version = "1.0.0"

local M = {}

local function logErr(msg)
    if type(log_error) == "function" then log_error(msg) end
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- =====================================================================
-- Rating
-- =====================================================================

-- First number in a rating string -> number in the site's own scale
-- (the app rescales), nil when there is none or it is out of range.
-- Covers the formats used by the getBookRating copies: "4.6" (bare
-- number / data-rating attribute), "8/10", "Rating: 7.5/10", "Rating: 9",
-- "Rank: 3" and the comma decimal separator ("4,6" = 4.6).
function M.rating(str)
    if type(str) ~= "string" then return nil end
    local n = str:match("(%d+[%.,]%d+)") or str:match("(%d+)")
    if not n then
        logErr("meta.rating: no number in " .. str:sub(1, 60))
        return nil
    end
    local v = tonumber((n:gsub(",", ".")))
    if not v or v < 0 or v > 10 then
        logErr("meta.rating: out of 0..10 range: " .. str:sub(1, 60))
        return nil
    end
    return v
end

-- =====================================================================
-- Last update date
-- =====================================================================

-- Relative "N <unit> ago" — EN from the normalizeUpdateDate copies
-- (en/novelphoenix.lua:305, en/freewebnovel.lua, en/lightnovelpub.lua,
-- en/wuxiabox.lua, mtl/sonicmtl.lua), RU from ru/ifreedom.lua:120 and
-- ru/jaomix.lua (which matches the unit as a substring, so plurals and
-- the odd abbreviation keep working). Months/years are approximate
-- (30/365 days), as in those copies.
local REL_EN = {
    second = 1, seconds = 1,
    minute = 60, minutes = 60,
    hour = 3600, hours = 3600,
    day = 86400, days = 86400,
    week = 604800, weeks = 604800,
    month = 2592000, months = 2592000,
    year = 31536000, years = 31536000,
}

local REL_RU = {
    { "секунд", 1 }, { "сек", 1 }, { "минут", 60 }, { "мин", 60 },
    { "час", 3600 }, { "ч", 3600 }, { "дн", 86400 },
    { "недел", 604800 }, { "нед", 604800 },
    { "месяц", 2592000 }, { "мес", 2592000 },
    { "год", 31536000 }, { "лет", 31536000 }, { "г", 31536000 },
}

local function relativeDate(str)
    local n, unit = str:match("(%d+)%s+([%a]+)%s+ago")
    if n then
        local secs = REL_EN[unit]
        if not secs then return nil end
        return os.date("%Y-%m-%d", os.time() - tonumber(n) * secs)
    end
    local num, word = str:match("(%d+)%s*([^%d%s]+)%s+назад")
    if not num then return nil end
    for _, pair in ipairs(REL_RU) do
        if word:find(pair[1], 1, true) then
            return os.date("%Y-%m-%d", os.time() - tonumber(num) * pair[2])
        end
    end
    return nil
end

-- Any date-ish string -> "YYYY-MM-DD" or nil (guide:277). Recognized:
-- ISO 8601 anywhere in the string ("2026-08-18T23:00:15.751Z") and the
-- relative forms above ("Updated 3 days ago", "3 дня назад"). Anything
-- else (month names, DD.MM.YY, site-specific wording) is deliberately
-- not guessed — pass the site's own format from the plugin.
function M.normalizeDate(str)
    if type(str) ~= "string" or str == "" then return nil end
    local y, m, d = str:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then return y .. "-" .. m .. "-" .. d end
    local rel = relativeDate(str)
    if rel then return rel end
    logErr("meta.normalizeDate: unrecognized " .. str:sub(1, 60))
    return nil
end

-- =====================================================================
-- Status
-- =====================================================================

-- Status text is shown by the app as-is (guide:264) — no mapping, no
-- case folding by default: plugins return the site's own string. Pass
-- { lower = true } only when the plugin really wants a lowercase label
-- (en/novelfire.lua is the only copy that lowercases).
function M.status(str, opts)
    if type(str) ~= "string" then return nil end
    local s = trim((str:gsub("%s+", " ")))
    if s == "" then return nil end
    if opts and opts.lower then
        if type(string_lower) == "function" then
            s = string_lower(s)
        else
            s = s:lower()
        end
    end
    return s
end

-- =====================================================================
-- Genres
-- =====================================================================

-- Collects genre names out of the elements returned by html_select (or
-- plain strings) — the shared inner loop of the getBookGenres copies
-- (e.g. ar/mangalik.lua:125, ru/allhentai.lua:179): trim/clean the label,
-- drop empties, drop duplicates, keep the site order. The selector and
-- the data source stay in the plugin.
function M.collectGenres(anchors, opts)
    local out, seen = {}, {}
    if type(anchors) ~= "table" then return out end
    for _, el in ipairs(anchors) do
        local raw
        if type(el) == "string" then
            raw = el
        elseif type(el) == "table" then
            raw = el.text
        end
        if type(raw) == "string" and raw ~= "" then
            local name
            if opts and opts.clean and type(string_clean) == "function" then
                name = string_clean(raw)
            elseif type(string_trim) == "function" then
                name = string_trim(raw)
            else
                name = trim(raw)
            end
            if name ~= "" and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out
end

return M
