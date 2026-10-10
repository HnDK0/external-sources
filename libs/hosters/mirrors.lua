-- =====================================================================
-- Lib: mirror list of a WordPress episode page — <select class="mirror">:
--      value of each option is base64 of <iframe src="..."> (the site
--      runs atob), the option label is kept as the quality hint.
-- Merged from two copies: id/anichin.lua:603-633 (robust: case-insensitive
-- src match, regex_match quirk handling, quote/space validation) and
-- id/animexin.lua:634-650 (plain src="..." match). The robust version is
-- a superset — plain src="..." is caught by the same pattern, single-quoted
-- and unquoted src by the fallbacks — so one implementation covers both.
-- Loaded via require_lib("mirrors"). No dependencies on other libs.
--
-- The embed URL is absolutised against the site base URL passed by the
-- caller (the two sites have different bases); there is no HTTP here.
-- =====================================================================
local version = "1.0.0"

local M = {}

local function absUrl(baseUrl, href)
    if type(href) ~= "string" or href == "" then return "" end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if href:find("^https?://") then return href end
    if href:sub(1, 1) == "/" then return baseUrl .. href end
    return baseUrl .. "/" .. href
end

-- body — the episode page. Markup inside options can be upper-case
-- (<IFRAME SRC=...>), so src is matched without case sensitivity.
-- Returns a list of { label, embed } (embed is absolute), or nil when
-- there is no mirror list on the page.
function M.mirrorOptions(body, baseUrl)
    local select = html_select_first(body, "select.mirror")
    if not select then return nil end
    local out = {}
    for _, opt in ipairs(html_select(select.html, "option[value]")) do
        local value = opt:attr("value")
        if type(value) == "string" and value ~= "" then
            local label = string_clean(html_text(opt.html))
            local decoded = base64_decode(value)
            if type(decoded) == "string" and decoded ~= "" then
                -- regex_match returns FULL matches (m.value), not groups:
                -- m[1] here is 'src="https://…"' with the prefix and quotes.
                -- Cut the URL out; if the engine ever returns a clean group
                -- we keep it as is.
                local m = regex_match(decoded, '(?i)src\\s*=\\s*"([^"]+)"')
                local src = m and m[1] or nil
                if src then src = src:match('^[^"]*"([^"]+)"') or src end
                if not src then src = decoded:match('src=([^%s>]+)') end
                if src then
                    src = src:gsub('^"', ""):gsub('"$', "")
                        :gsub("^'", ""):gsub("'$", "")
                    -- A quote/space inside src is a broken embed: it would
                    -- fail in http_get_batch before the network (HTTP -1),
                    -- so it is not added here.
                    if not src:find("[%s\"'<>]") then
                        out[#out + 1] = { label = label, embed = absUrl(baseUrl, src) }
                    end
                end
            end
        end
    end
    return out
end

return M
