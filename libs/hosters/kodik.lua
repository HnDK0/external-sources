-- =====================================================================
-- Lib: Kodik — embed page (urlParams/d_sign) -> POST kodikplayer.com/ftor
--      -> quality list of direct links.
-- Extracted from ru/yummyanime.lua (kodikDecode + resolveKodik), the port
-- of the Kodik player flow.
-- Loaded via require_lib("kodik"); uses require_lib("text") (rot18) and
-- the engine base64_decode. No other lib dependencies.
--
-- The embed HTML is already in hand (the caller loads it with its batch),
-- only /ftor is a POST done here. The body is form-urlencoded and stays
-- hand-assembled on purpose — json_encode would send the wrong shape.
-- =====================================================================
local version = "1.0.0"

local TEXT = require_lib("text")

local M = {}

-- src in the /ftor answer is either an absolute URL or ROT-18 over
-- letters + base64 (the engine base64_decode gets a URL string, no binary
-- is needed).
local function kodikDecode(src)
    if src:find("//", 1, true) then return src end
    local url = base64_decode(TEXT.rot18(src))
    if not url or url == "" then return nil end
    if url:sub(1, 2) == "//" then return "https:" .. url end
    return url
end

-- page — the shared http_get_batch response for this iframe (see
-- batchPlayers in the plugin): the Kodik/Alloha embeds are loaded by one
-- batch, without their own headers.
-- Returns a list of { url, quality } or nil.
function M.resolve(iframeUrl, dubbing, page)
    if type(page) ~= "table" or not page.success then
        log_error("kodik: iframe " .. tostring(page and page.code))
        return nil
    end
    local url = iframeUrl
    if url:sub(1, 2) == "//" then url = "https:" .. url end
    local html = page.body
    -- urlParams is a JSON with the d_sign/pd_sign/ref_sign signatures;
    -- without them /ftor answers 500
    local raw = html:match("urlParams%s*=%s*'([^']+)'")
        or html:match('urlParams%s*=%s*"([^"]+)"')
    local params = raw and json_parse(raw) or nil
    if type(params) ~= "table" or type(params.d_sign) ~= "string" or params.d_sign == "" then
        log_error("kodik: urlParams not found")
        return nil
    end
    local vtype = html:match("vInfo%.type%s*=%s*'([^']+)'")
        or html:match('var%s+type%s*=%s*"([^"]+)"')
    local vhash = html:match("vInfo%.hash%s*=%s*'([^']+)'")
    local vid   = html:match('videoId%s*=%s*"([^"]+)"')
        or html:match("vInfo%.id%s*=%s*'([^']+)'")
    if not vtype or not vhash or not vid then
        -- fallback: the iframe path segments are host/type/id/hash
        local seg = {}
        for part in url:gsub("[?#].*$", ""):gmatch("[^/]+") do seg[#seg + 1] = part end
        vtype = vtype or seg[2]
        vid   = vid   or seg[3]
        vhash = vhash or seg[4]
    end
    if not vtype or not vid or not vhash then
        log_error("kodik: type/id/hash not found")
        return nil
    end
    local function field(v)
        return url_encode(type(v) == "string" and v or "")
    end
    -- ponytail: ref/ref_sign are not sent — the server signs them for the
    -- iframe request Referer, while the engine always sends its own
    -- Referer, so the signature mismatches and /ftor answers 500; without
    -- these fields both cases answer 200
    local body = table.concat({
        "d=",        field(params.d),
        "&d_sign=",  field(params.d_sign),
        "&pd=",      field(params.pd),
        "&pd_sign=", field(params.pd_sign),
        "&type=",    url_encode(vtype),
        "&id=",      url_encode(vid),
        "&hash=",    url_encode(vhash),
        "&bad_user=false&cdn_is_working=true",
    })
    local pr = http_post("https://kodikplayer.com/ftor", body)
    if not pr.success then
        log_error("kodik: /ftor " .. tostring(pr.code))
        return nil
    end
    local data = json_parse(pr.body)
    local links = data and data.links
    if type(links) ~= "table" then return nil end
    -- links keys are the qualities as strings ("240".."720"), highest first
    local qs = {}
    for k in pairs(links) do
        if type(k) == "string" and k:match("^%d+$") then qs[#qs + 1] = k end
    end
    table.sort(qs, function(a, b) return tonumber(a) > tonumber(b) end)
    local out = {}
    for _, q in ipairs(qs) do
        local items = links[q]
        if type(items) == "table" then
            for _, it in ipairs(items) do
                local src = type(it) == "table" and it.src or nil
                local hls = type(src) == "string" and kodikDecode(src) or nil
                if hls then
                    -- the Kodik m3u8 answers 200 even without Referer/Origin
                    out[#out + 1] = {
                        url     = hls,
                        quality = "Kodik · " .. dubbing .. " · " .. q .. "p",
                    }
                end
            end
        end
    end
    return out
end

return M
