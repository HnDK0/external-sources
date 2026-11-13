-- =====================================================================
-- Lib: syosetu family — shared book/chapter layer for ncode.syosetu.com
-- and novel18.syosetu.com. Both use the same markup (p-novel__*), so only
-- metadata and the catalog/search sources differ.
-- Loaded via require_lib("syosetu"); uses fetch/urls.
-- Config (every M.* takes it first):
--   id       string  log prefix (required)
--   baseUrl  string  site origin with trailing slash (required)
--   headers  table   extra HTTP headers (UA, Cookie: over18=yes for R18)
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")
local fetch = require_lib("fetch")

local M = {}

local function logErr(msg)
    if type(log_error) == "function" then log_error(msg) end
end

local function page(cfg, url)
    return fetch.page(url, { headers = cfg.headers })
end

function M.title(cfg, bookUrl)
    local body = page(cfg, bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".p-novel__title")
    return el and string_trim(el.text) or nil
end

function M.cover(cfg, bookUrl)
    local body = page(cfg, bookUrl)
    if not body then return nil end
    -- Server-generated social card: https://sbo.syosetu.com/<ncode>/twitter.png
    local url = html_attr(body, "meta[property='og:image']", "content")
    return url ~= "" and url or nil
end

function M.description(cfg, bookUrl)
    local body = page(cfg, bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "#novel_ex")
    if el and string_trim(el.text) ~= "" then return string_trim(el.text) end
    el = html_select_first(body, ".p-novel__summary")
    return el and string_trim(el.text) or nil
end

function M.chapters(cfg, bookUrl)
    bookUrl = bookUrl:gsub("/+$", "") .. "/"
    local chapters = {}
    local body = page(cfg, bookUrl)
    if not body then
        logErr("getChapterList failed: " .. bookUrl)
        return {}
    end

    -- Single-chapter (short story) novel: body on the book page, no episode list.
    local hasText = html_select_first(body, ".p-novel__text")
    local hasEplist = html_select_first(body, ".p-eplist")

    if hasText and not hasEplist then
        local titleEl = html_select_first(body, ".p-novel__title")
        local title = titleEl and string_trim(titleEl.text) or "Chapter 1"
        chapters[1] = { title = title, url = bookUrl }
        return chapters
    end

    local totalPages = 1
    local lastLink = html_select_first(body, ".c-pager__item--last")
    if lastLink and lastLink.href then
        local p = string.match(lastLink.href, "p=(%d+)")
        if p then totalPages = tonumber(p) end
    end

    local function parsePage(html)
        for _, a in ipairs(html_select(html, ".p-eplist__subtitle")) do
            local href = a.href or ""
            if href ~= "" then
                chapters[#chapters + 1] = {
                    title = string_trim(a.text),
                    url = urls.absUrl(cfg.baseUrl, href),
                }
            end
        end
    end

    parsePage(body)

    for p = 2, totalPages do
        sleep(300)
        local pr = http_get(bookUrl .. "?p=" .. tostring(p), { headers = cfg.headers })
        if pr.success then parsePage(pr.body) end
    end

    return chapters
end

function M.chapterHash(cfg, bookUrl)
    local r = http_get(bookUrl, { headers = cfg.headers })
    if not r.success then return nil end
    local el = html_select_first(r.body, ".p-novel__date-published")
    return el and string_trim(el.text) or nil
end

local function extractText(html)
    local cleaned = html_remove(html,
        "script", "style",
        ".c-ad", ".c-pager", ".p-reaction",
        ".p-bookmark-bar", ".l-footer", "header", ".p-adjust-layout"
    )
    local el = html_select_first(cleaned, ".p-novel__body")
    if not el then return "" end
    return string_trim(string_normalize(html_text(el.html)))
end

function M.chapterText(cfg, html, url)
    local text = extractText(html)
    if text ~= "" then return text end
    -- The caller's HTML may be the age gate (R18) or an empty stub: refetch
    -- with the plugin's own headers (over18=yes) before giving up.
    local body = page(cfg, url)
    if body then text = extractText(body) end
    return text
end

return M
