-- =====================================================================
-- Lib: session-cached page fetch. The engine calls getBookTitle /
-- getBookCoverImageUrl / getBookDescription / getBookGenres /
-- getBookStatus / getBookLastUpdate in parallel, each doing its own
-- http_get(bookUrl) — this module keeps one request per URL.
-- Loaded via require_lib("fetch"). No dependencies on other libs.
--
-- Same contract as the inline fetchPage copies (guide:643):
--   * cache lives for the session only, never for getChapterListHash —
--     that one must always use a direct http_get;
--   * only successful responses are cached, a failed call returns nil
--     and the next call retries;
--   * the cache key is the URL. A non-empty `config` that changes the
--     response body (headers, charset, ...) becomes part of the key, so
--     two configs never share a body.
-- =====================================================================
local version = "1.0.0"

local M = {}

local cache = {}

local function logErr(msg)
    if type(log_error) == "function" then log_error(msg) end
end

-- Order-independent encoding of a config table, so {a=1,b=2} and {b=2,a=1}
-- share one cache entry. Cycles are not possible here: http_get configs are
-- plain string/number/bool values and one level of headers table.
local function encode(value)
    local t = type(value)
    if t == "table" then
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = tostring(k) .. "=" .. encode(value[k])
        end
        return "{" .. table.concat(parts, ";") .. "}"
    end
    return tostring(value)
end

local function keyOf(url, config)
    if type(config) ~= "table" then return url end
    local keys = {}
    for k in pairs(config) do keys[#keys + 1] = k end
    if #keys == 0 then return url end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. encode(config[k])
    end
    return url .. "\0" .. table.concat(parts, ";")
end

-- GET `url` (optional http_get `config`) -> response body or nil.
-- ponytail: no TTL — the plugin session is short-lived and every copy in
-- the repo caches for the whole session (only mtl/wtrlab.lua adds a TTL);
-- add one when a caller actually needs staleness control.
function M.page(url, config)
    if type(url) ~= "string" or url == "" then return nil end
    local key = keyOf(url, config)
    local cached = cache[key]
    if cached ~= nil then return cached end
    local r = http_get(url, config)
    if type(r) ~= "table" or not r.success then
        logErr("fetch: GET failed (HTTP " .. tostring(r and r.code) .. ") " .. url)
        return nil
    end
    cache[key] = r.body
    return r.body
end

-- Drop the whole session cache, or every entry of one URL when given
-- (all config variants of that URL).
function M.clear(url)
    if url == nil then
        cache = {}
        return
    end
    local prefix = url .. "\0"
    for key in pairs(cache) do
        if key == url or key:sub(1, #prefix) == prefix then cache[key] = nil end
    end
end

return M
