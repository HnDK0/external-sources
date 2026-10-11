-- =====================================================================
-- Lib: catalog/pagination helpers for plugin catalogs: hasNextPage,
--      nextIndex/pageUrl (dominant "?page=N" scheme), urlEncode.
-- Loaded via require_lib("catalog"). No dependencies on other libs.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- =====================================================================
-- Pagination
-- =====================================================================

-- "Has next page" for the dominant scheme where a page is considered
-- non-final as long as it returned any item (39 inline copies of
-- `#items > 0`, plus 7 local hasNextPage helpers with the same body).
-- Plugins that know their total page count keep their own comparison.
function M.hasNextPage(items)
    return type(items) == "table" and #items > 0
end

-- Catalog index is 0-based; pages on the wire are 1-based — the
-- dominant `local page = index + 1` from 74 plugins.
function M.nextIndex(index)
    return (index or 0) + 1
end

-- Build a page URL from a template with "{n}" where the 1-based page
-- number goes. Matches the dominant string-concat schemes:
--   ".../catalog?page={n}"        (guide, most sites)
--   "...&pg={n}"                  (en/scribblehub.lua:33)
--   "...&bpage={n}"               (ru/bookhamster.lua:85)
-- Sites with conditional page params or API cursors keep their own code.
function M.pageUrl(template, index)
    return (template:gsub("{n}", tostring(M.nextIndex(index))))
end

-- =====================================================================
-- Query encoding
-- =====================================================================

-- Pure-Lua mirror of the engine global url_encode (Java
-- URLEncoder.encode(s, "UTF-8"): application/x-www-form-urlencoded —
-- space -> "+", unreserved A-Za-z0-9 . - * _ kept, everything else
-- "%XX" uppercase over UTF-8 bytes, "\n" normalized to "\r\n" first).
-- The 73 plugin call sites use the engine global directly; this copy
-- exists for shared libs and parity tests outside the engine.
function M.urlEncode(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("\n", "\r\n")
    return (s:gsub("[^%w%.%-_*]", function(c)
        if c == " " then return "+" end
        return string.format("%%%02X", string.byte(c))
    end))
end

return M
