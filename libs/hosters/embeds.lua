-- =====================================================================
-- Lib: dispatcher por servidor (extractFromEmbed).
-- Se carga via require_lib("embeds"); internamente carga las libs de
-- cada embebedor (dood, mixdrop, mp4upload, voe) + urls/hls y usa el API
-- del motor unpack_packed (devuelve "" cuando no hay empaquetador).
-- =====================================================================
local version = "1.3.0"

local urls      = require_lib("urls")
local hls       = require_lib("hls")
local dood      = require_lib("dood")
local mixdrop   = require_lib("mixdrop")
local mp4upload = require_lib("mp4upload")
local voe       = require_lib("voe")
local savefiles = require_lib("savefiles")
local bysekoze  = require_lib("bysekoze")

local M = {}

function M.extractFromEmbed(emb, body)
    local host = urls.hostOf(emb.url)
    local name = (emb.name or ""):lower()

    -- engine contract: unpack_packed returns "" when there is no packer;
    -- nil must never reach the concatenation below (it would be a concat
    -- crash instead of a graceful skip).
    local packed = ""
    if body:find("p,a,c,k,e,d", 1, true) then
        local un = unpack_packed(body)
        if type(un) == "string" and un ~= "" then packed = un end
    end
    local both = urls.unescapeSlashes(packed ~= "" and (packed .. "\n" .. body) or body)

    if host:find("dood") or host:find("dsvplay") or name:find("dsv") or name:find("dood")
        or body:find("/pass_md5/", 1, true) then
        local u, mime, ref = dood.resolveDood(emb.url, body)
        if u then return u, mime, ref end
    end

    if host:find("mp4upload") or name:find("mp4upload") then
        local u, mime, ref = mp4upload.extractMp4upload(both)
        if u then return u, mime, ref end
    end

    if host:find("mixdrop") or host:find("mxdrop") or both:find("MDCore.wurl", 1, true) then
        local u, mime, ref = mixdrop.extractMixdrop(both, emb.url)
        if u then return u, mime, ref end
    end

    if host:find("voe") or name == "voe" then
        local u, mime, ref = voe.extractVoe(emb.url, body)
        if u then return u, mime, ref end
    end

    if host:find("savefiles") or name:find("savefiles") then
        local u, mime, ref = savefiles.extractSavefiles(emb.url)
        if u then return u, mime, ref end
    end

    if host:find("bysekoze") or name:find("bysekoze") then
        local u, mime, ref = bysekoze.extractBysekoze(emb.url)
        if u then return u, mime, ref end
    end

    local u, mime = hls.pickStream(both, emb.url)
    if u then return u, mime, urls.origin(emb.url) end
    return nil
end

return M
