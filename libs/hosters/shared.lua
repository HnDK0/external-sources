-- =====================================================================
-- Lib: 4shared — embed page -> direct link from the first <source src>.
-- Merged from two copies: ar/anime4up.lua:551-572 and ar/animephoenix.lua:
-- 772-790 (the <source> extraction was identical in both, only the wrapper
-- differed: a pushed candidate vs a URL list); both ports of
-- SharedExtractor.kt.
-- Loaded via require_lib("shared"). No dependencies on other libs.
--
-- The embed body is already in hand (both copies get it from their batch),
-- so there is no HTTP here; logging and the candidate shape stay with the
-- caller.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Embed body + embed link -> absolute stream URL, or nil when there is
-- no <source>. The reference returns attr("src") as is; only
-- protocol-relative/relative values are absolutised, otherwise the player
-- will not open them.
function M.extract(body, embedUrl)
    if type(body) ~= "string" then return nil end
    local src = html_attr(body, "source", "src")
    if type(src) ~= "string" or src == "" then return nil end
    if not string_starts_with(src, "http") then
        if string_starts_with(src, "//") then
            src = "https:" .. src
        else
            src = url_resolve(embedUrl, src)
        end
    end
    return src
end

return M
