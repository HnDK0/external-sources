-- =====================================================================
-- Lib: vidbom family (vidbom / vadbom / vedbam / myvid / segavid /
--      vidshare / vidsharer) — embed -> sources:[{file, label}].
-- Merged from two copies: ar/anime4up.lua:578-621 (VIDBOM_PATTERNS,
-- isVidbomLink, resolveVidbom) and ar/witanime.lua:1250-1274
-- (resolveVidbom + its own single-pattern host check).
-- Loaded via require_lib("vidbom"). No dependencies on other libs.
--
-- The body parsing is identical in both copies; the host check is the
-- union: ar/witanime matched only "//v[aie]d[bp][aoe]?m" (the literal
-- reference regex), ar/anime4up the four patterns covering the whole
-- family — the union routes every family domain to this parser.
-- HTTP stays with the caller (only ar/witanime fetches the embed).
-- =====================================================================
local version = "1.0.0"

local M = {}

-- VIDBOM_REGEX of Anime4Up.kt: alternation (|) does not exist in Lua
-- patterns, so instead of one regex there is a list; as in the reference
-- there is no "//" anchor — the host name matches anywhere in the URL
-- (subdomains included), but only after a dot.
local PATTERNS = {
    "v[aie]d[bp][aoe]?m%.",      -- vidbom / vadbom / vedbam
    "myvii?d%.",                 -- myvid / myviid
    "segavid%.",                 -- segavid
    "v[aei][aei]?dshar[er]?%.",  -- vidshare / vidsharer
}

function M.isLink(link)
    if type(link) ~= "string" then return false end
    local low = link:lower()
    for _, p in ipairs(PATTERNS) do
        if low:find(p) then return true end
    end
    return false
end

-- Embed body -> list of { url, quality }, possibly empty.
-- The reference reads script:containsData(sources) and cuts the body by
-- substringAfter("sources: [") + substringBefore("],").
function M.parseSources(body)
    if type(body) ~= "string" then return {} end
    local p = body:find("sources: [", 1, true)
    local rest = p and body:sub(p + 10) or nil
    local data = rest and (rest:match("^(.-)%],") or rest) or nil
    if not data then return {} end
    local out = {}
    for src, label in data:gmatch('file:"([^"]+)".-label:"([^"]*)"') do
        -- Reference: "Vidbom: " + label, longer than 15 chars -> "Vidshare: 480p".
        local quality = "Vidbom: " .. label
        if #quality > 15 then quality = "Vidshare: 480p" end
        out[#out + 1] = { url = src, quality = quality }
    end
    return out
end

return M
