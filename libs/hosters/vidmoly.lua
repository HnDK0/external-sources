-- =====================================================================
-- Lib: vidmoly — embed -> window.location.replace -> player page ->
--      packed-JS media URLs.
-- Merged from ar/anime4up.lua:731-760 (resolveVidmoly).
-- UNVERIFIED: live 2026-10-05 the embed answered a 495-byte stub with
-- window.location.replace and the next step (Cherami/Express) served no
-- player from that network — the scheme is the reference's, it was not
-- confirmed end to end.
-- Loaded via require_lib("vidmoly"); uses require_lib("urls") and
-- require_lib("uqload").
--
-- The embed body is passed in (ar/anime4up gets it from its batch); the
-- redirect fetch (Sec-Fetch-* headers + the Turnstile demo cookie) is
-- done here exactly as in the caller.
-- =====================================================================
local version = "1.0.0"

local urls   = require_lib("urls")
local uqload = require_lib("uqload")

local M = {}

-- Embed body + embed link -> list of stream URLs, or nil + reason
-- ("no embed body" | "no sources after the redirect").
function M.resolve(body, link)
    if type(body) ~= "string" or body == "" then return nil, "no embed body" end
    local target = body:match("window%.location%.replace%(%s*['\"]([^'\"]+)['\"]")
    local embId = type(link) == "string" and (link:match("embed%-([%w_%-]+)") or "") or ""
    local heads = {
        ["Referer"] = link,
        ["Sec-Fetch-Dest"] = "iframe",
        ["Sec-Fetch-Mode"] = "navigate",
        ["Sec-Fetch-Site"] = "same-site",
    }
    -- Turnstile demo cookie of vidmoly: without it the next step serves a stub.
    if embId ~= "" then
        heads["Cookie"] = "cf_turnstile_demo_pass_" .. embId .. "=1"
    end
    if target and target ~= "" then
        local r = http_get(urls.resolve(target, link), { headers = heads, timeout = 10000 })
        if r.success and type(r.body) == "string" and r.body ~= "" then
            body = r.body
        end
    end
    local out = uqload.packedMediaUrls(body)
    if #out == 0 then return nil, "no sources after the redirect" end
    return out
end

return M
