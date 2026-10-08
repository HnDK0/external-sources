-- =====================================================================
-- Plugin: Latanime (v2.2 - Reproductor con extractores por servidor)
-- Target: NoveLA (content_type = "video")
-- Base URL: https://latanime.org
--
-- Cambios v2.2 (solo reproductor):
--   * Corregidos los patrones Lua rotos (`\s` -> `%s`).
--   * Desempaquetador de JS "p,a,c,k,e,d" (mixdrop, savefiles, mp4upload...).
--   * Extractores: mp4upload, mixdrop, dood/dsvplay, voe + generico m3u8/mp4.
--   * Reintento con Referer de Latanime y log por servidor.
--   * Se omiten mega / mediafire / gofile (no son streams directos).
-- =====================================================================

id           = "latanime"
name         = "Latanime"
version      = "2.2.2"
baseUrl      = "https://latanime.org"
language     = "es"
content_type = "video"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/latanime.png"

-- Таймауты: страницы сайта и эмбеды (сеть в эмуляторе без таймаута зависала).
local PAGE_TIMEOUT   = 15000
local EMBED_TIMEOUT  = 12000

-- =====================================================================
-- FUNCIONES DE AYUDA (HELPERS)
-- =====================================================================

local function absUrl(href)
    if not href or href == "" then return "" end
    if href:sub(1, 2) == "//" then return "https:" .. href end
    if href:find("^https?://") then return href end
    if href:sub(1, 1) == "/" then return baseUrl .. href end
    return baseUrl .. "/" .. href
end

local function cleanText(text)
    if not text then return "" end
    text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", " ")
    return text
end

local string_clean = cleanText
local string_trim = cleanText

local function urlEncode(str)
    if type(str) ~= "string" then return str end
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end
local url_encode = urlEncode

local function origin(url)
    local scheme, host = url:match("^(https?)://([^/?#]+)")
    if not scheme then return nil end
    return scheme .. "://" .. host .. "/"
end

-- Decodificador Base64 nativo
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64_CHARS do B64_INDEX[B64_CHARS:sub(i, i)] = i - 1 end

local function base64Decode(data)
    data = data:gsub("%s", ""):gsub("%-", "+"):gsub("_", "/")
    local out = {}
    for i = 1, #data, 4 do
        local c1, c2, c3, c4 = data:sub(i, i), data:sub(i+1, i+1), data:sub(i+2, i+2), data:sub(i+3, i+3)
        local v1, v2, v3, v4 = B64_INDEX[c1] or 0, B64_INDEX[c2] or 0, B64_INDEX[c3], B64_INDEX[c4]
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out+1] = string.char(math.floor(n / 65536) % 256)
        if v3 then out[#out+1] = string.char(math.floor(n / 256) % 256) end
        if v4 then out[#out+1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url, { timeout = PAGE_TIMEOUT })
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    log_error("Latanime: Error de red (HTTP " .. tostring(r.code) .. ") en " .. url)
    return nil
end

-- =====================================================================
-- CATÁLOGO Y BÚSQUEDA
-- =====================================================================

local function parseCards(body)
    local items = {}
    for _, a in ipairs(html_select(body, "a")) do
        local href = a.href
        if href and href:find("/anime/") then
            local h3 = html_select_first(a.html, "h3")
            local title = h3 and string_clean(h3.text) or ""
            if title ~= "" then
                local cover = html_attr(a.html, "img", "data-src")
                if cover == "" then cover = html_attr(a.html, "img", "src") end

                table.insert(items, {
                    title = title,
                    url   = absUrl(href),
                    cover = absUrl(cover)
                })
            end
        end
    end
    return items
end

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/animes?p=" .. page
    local r = http_get(url, { timeout = PAGE_TIMEOUT })
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCards(r.body)
    local hasNext = r.body:find("animes%p=" .. (page + 1)) ~= nil or r.body:find("animes%?p=" .. (page + 1)) ~= nil
    if #items == 0 then hasNext = false end
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    if index > 0 or not query or query == "" then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/buscar?q=" .. url_encode(query)
    local r = http_get(url, { timeout = PAGE_TIMEOUT })
    if not r.success then return { items = {}, hasNext = false } end
    return { items = parseCards(r.body), hasNext = false }
end

-- =====================================================================
-- DETALLES DEL LIBRO (ANIME)
-- =====================================================================

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h2")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "div.serieimgficha img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local desc = body:match('<p[^>]*class="[^"]*opacity%-75[^"]*"[^>]*>(.-)</p>')
    if desc then
        desc = desc:gsub('<[^>]+>', '')
        return string_clean(desc)
    end
    return nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, 'a[href*="/genero/"]')) do
        local div = html_select_first(a.html, "div.btn")
        if div then
            local g = string_clean(div.text)
            if g ~= "" then table.insert(genres, g) end
        end
    end
    return genres
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "span.btn-estado")
    return el and string_clean(el.text) or nil
end

-- =====================================================================
-- CAPÍTULOS (EPISODIOS)
-- =====================================================================

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local chapters = {}
    local seen = {}

    for _, a in ipairs(html_select(body, "a")) do
        local href = a.href
        if href and href:find("/ver/") then
            local div = html_select_first(a.html, "div.cap-layout")
            if div then
                local text = string_clean(div.text)
                local ep_num = tonumber(text:match("Capitulo%s*(%d+)"))
                if ep_num and not seen[href] then
                    seen[href] = true
                    table.insert(chapters, { title = "Capítulo " .. ep_num, url = absUrl(href), num = ep_num })
                end
            end
        end
    end

    table.sort(chapters, function(x, y) return x.num < y.num end)

    local final_chapters = {}
    for _, ch in ipairs(chapters) do
        table.insert(final_chapters, { title = ch.title, url = ch.url })
    end
    return final_chapters
end

-- =====================================================================
-- REPRODUCTOR: EXTRACTORES
-- =====================================================================

local function unescapeSlashes(s)
    local r = s:gsub("\\/", "/")
    r = r:gsub("\\u0026", "&")
    return r
end

local function hostOf(url)
    return ((url or ""):match("^https?://([^/?#:]+)") or ""):lower()
end

-- URL relativa / protocol-relative -> absoluta (respecto al embed)
local function resolve(u, embedUrl)
    u = unescapeSlashes(u)
    if u:sub(1, 2) == "//" then return "https:" .. u end
    if u:find("^https?://") then return u end
    local o = origin(embedUrl or "")
    if o then
        o = o:gsub("/$", "")
        return o .. (u:sub(1, 1) == "/" and u or ("/" .. u))
    end
    return u
end

-- ── Desempaquetador P.A.C.K.E.R ("eval(function(p,a,c,k,e,d)...") ──────────

local DIGITS = {}
for i = 0, 9 do DIGITS[string.char(48 + i)] = i end
for i = 0, 25 do
    DIGITS[string.char(97 + i)] = 10 + i
    DIGITS[string.char(65 + i)] = 36 + i
end

local function parseBase(word, radix)
    local n = 0
    for i = 1, #word do
        local d = DIGITS[word:sub(i, i)]
        if d == nil or d >= radix then return nil end
        n = n * radix + d
    end
    return n
end

local function unpackAll(body)
    local out = {}
    -- p/r en vez de payload/radix: las variables de un for genérico son const
    -- en Lua 5.4+, y aquí se reasignan (el validador compila con luac 5.4).
    for p, r, _, dict in body:gmatch("}%('(.-)',(%d+),(%d+),'(.-)'%.split%('|'%)") do
        local radix = tonumber(r)
        if radix and radix >= 2 and radix <= 62 then
            local keys = {}
            for k in (dict .. "|"):gmatch("(.-)|") do keys[#keys + 1] = k end
            local payload = p:gsub("\\'", "'"):gsub("\\\\", "\\")
            local text = payload:gsub("[%w_]+", function(w)
                local n = parseBase(w, radix)
                if n then
                    local k = keys[n + 1]
                    if k and k ~= "" then return k end
                end
                return w
            end)
            out[#out + 1] = text
        end
    end
    return table.concat(out, "\n")
end

-- ── Busqueda generica de stream ─────────────────────────────────────────────

local function pickStream(t, embedUrl)
    -- 1) URL absoluta
    local hls = t:match([=[(https?://[^"'%s\<>]+%.m3u8[^"'%s\<>]*)]=])
    if hls then return hls, "hls" end

    -- 2) entre comillas, relativa o protocol-relative
    for _, q in ipairs({ '"', "'" }) do
        for s in t:gmatch(q .. "([^" .. q .. "\r\n]+)" .. q) do
            if #s < 600 and not s:find("%s") and s:lower():find(".m3u8", 1, true) then
                return resolve(s, embedUrl), "hls"
            end
        end
    end

    -- 3) mp4 directo
    local mp4 = t:match([=[(https?://[^"'%s\<>]+%.mp4[^"'%s\<>]*)]=])
    if mp4 then return mp4, "mp4" end
    for _, q in ipairs({ '"', "'" }) do
        for s in t:gmatch(q .. "(//[^" .. q .. "\r\n]+)" .. q) do
            if #s < 600 and not s:find("%s") and s:lower():find(".mp4", 1, true) then
                return resolve(s, embedUrl), "mp4"
            end
        end
    end
    return nil, nil
end

-- ── mp4upload ───────────────────────────────────────────────────────────────

local function extractMp4upload(both)
    local u = both:match('player%.src%(%s*"([^"]+)"')
        or both:match('player%.src%(%s*{.-src%s*:%s*"([^"]+)"')
        or both:match('src%s*:%s*"(https?://[^"]+%.mp4[^"]*)"')
    if u then return u, "mp4", "https://www.mp4upload.com/" end
    return nil
end

-- ── mixdrop ─────────────────────────────────────────────────────────────────

local function extractMixdrop(both, embedUrl)
    local u = both:match('MDCore%.wurl%s*=%s*"([^"]+)"')
    if u then return resolve(u, embedUrl), "mp4", origin(embedUrl) end
    return nil
end

-- ── Doodstream y clones (dsvplay, dood.*) ───────────────────────────────────

local RANDOM_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function extractDood(embedUrl, body)
    local md5 = body:match("(/pass_md5/[^'\"]+)")
    if not md5 then return nil end
    local o = origin(embedUrl)
    if not o then return nil end
    local token = md5:match("([^/]+)$")
    local r = http_get(o:sub(1, -2) .. md5, { timeout = EMBED_TIMEOUT, headers = { ["Referer"] = embedUrl } })
    if not r.success then return nil end
    local start = r.body:gsub("%s+$", ""):gsub("^%s+", "")
    if not start:find("^https?://") then return nil end

    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd) .. "?token=" .. tostring(token) .. "&expiry=" .. tostring(os_time())
    return url, "mp4", o
end

-- ── VOE (JSON ofuscado: rot13 + patrones + base64 + shift + reverse + base64) ─

local function rot13(s)
    return (s:gsub("%a", function(c)
        local b = c:byte()
        local base = b >= 97 and 97 or 65
        return string.char((b - base + 13) % 26 + base)
    end))
end

local function plainRemove(s, pat)
    local out, i = {}, 1
    while true do
        local a, b = s:find(pat, i, true)
        if not a then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, a - 1)
        i = b + 1
    end
    return table.concat(out)
end

local function voeDecode(enc)
    local s = rot13(enc)
    for _, p in ipairs({ "@$", "^^", "~@", "%?", "*~", "!!", "#&" }) do
        s = plainRemove(s, p)
    end
    s = s:gsub("_", "")
    s = base64Decode(s)
    local shifted = {}
    for i = 1, #s do shifted[i] = string.char((s:byte(i) - 3) % 256) end
    s = table.concat(shifted):reverse()
    s = base64Decode(s)
    return json_parse(s)
end

local function extractVoe(embedUrl, body)
    -- salto de dominio: la pagina inicial solo redirige
    if not body:find("application/json", 1, true) and not body:find("hls", 1, true) then
        local hop = body:match("window%.location%.href%s*=%s*'(https?://[^']+)'")
        if hop then
            local r = http_get(hop, { timeout = EMBED_TIMEOUT, headers = { ["Referer"] = embedUrl } })
            if r.success then
                body = r.body
                embedUrl = hop
            end
        end
    end

    local ref = origin(embedUrl)

    -- Formato nuevo
    local jsonText = body:match('<script[^>]-type="application/json"[^>]*>(.-)</script>')
    if jsonText then
        local enc = jsonText:match('^%s*%["(.-)"%]%s*$') or jsonText:match('^%s*"(.-)"%s*$')
        if enc then
            local ok, data = pcall(voeDecode, enc)
            if ok and type(data) == "table" then
                local u = data.source or data.direct_access_url
                if type(u) == "string" and u ~= "" then
                    return u, (u:lower():find(".m3u8", 1, true) and "hls" or "mp4"), ref
                end
            end
        end
    end

    -- Formato antiguo: 'hls': 'BASE64' / 'mp4': 'BASE64'
    local h = body:match("['\"]hls['\"]%s*:%s*['\"]([A-Za-z0-9+/=_%-]+)['\"]")
    if h then
        local u = base64Decode(h)
        if u:find("^https?://") then return u, "hls", ref end
    end
    local m = body:match("['\"]mp4['\"]%s*:%s*['\"]([A-Za-z0-9+/=_%-]+)['\"]")
    if m then
        local u = base64Decode(m)
        if u:find("^https?://") then return u, "mp4", ref end
    end
    return nil
end

-- ── Despachador por servidor ────────────────────────────────────────────────

local function extractFromEmbed(emb, body)
    local host = hostOf(emb.url)
    local name = (emb.name or ""):lower()

    local packed = ""
    if body:find("p,a,c,k,e,d", 1, true) then packed = unpackAll(body) end
    local both = unescapeSlashes(packed ~= "" and (packed .. "\n" .. body) or body)

    if host:find("dood") or host:find("dsvplay") or name:find("dsv") or name:find("dood")
        or body:find("/pass_md5/", 1, true) then
        local u, mime, ref = extractDood(emb.url, body)
        if u then return u, mime, ref end
    end

    if host:find("mp4upload") or name:find("mp4upload") then
        local u, mime, ref = extractMp4upload(both)
        if u then return u, mime, ref end
    end

    if host:find("mixdrop") or host:find("mxdrop") or both:find("MDCore.wurl", 1, true) then
        local u, mime, ref = extractMixdrop(both, emb.url)
        if u then return u, mime, ref end
    end

    if host:find("voe") or name == "voe" then
        local u, mime, ref = extractVoe(emb.url, body)
        if u then return u, mime, ref end
    end

    local u, mime = pickStream(both, emb.url)
    if u then return u, mime, origin(emb.url) end
    return nil
end

-- ── Lista de servidores del episodio ────────────────────────────────────────

-- Servidores sin stream directo por HTTP simple:
--   mega.nz / mega.io — stream cifrado AES-CTR servido por trozos con Range
--                        (el motor no tiene cripto ni peticiones parciales)
--   mediafire          — el enlace pasa por una página de descarga con JS
--   gofile             — token de sesión que emite el JS de la página
-- drive.google YA NO está en la lista: su enlace directo se arma con el id
-- del archivo (drive.usercontent.google.com/download?id=…&export=download&
-- confirm=t, verificado en vivo 2026-10-03 con 206 Partial Content), sin
-- pasar por la vista previa de JS.
local UNSUPPORTED_HOSTS = { "mega.nz", "mega.io", "mediafire", "gofile" }

-- Google Drive → enlace directo (puerto desde ar/animephoenix.lua).
local function driveDirectUrl(link)
    local host = hostOf(link):gsub("^www%.", "")
    if host ~= "drive.google.com" and host ~= "drive.usercontent.google.com" then
        return nil
    end
    local id = link:match("/file/d/([%w_-]+)") or link:match("[?&]id=([%w_-]+)")
    if not id then return nil end
    local u = "https://drive.usercontent.google.com/download?id=" .. id
        .. "&export=download&confirm=t"
    local rk = link:match("[?&]resourcekey=([%w_-]+)")
    if rk then u = u .. "&resourcekey=" .. rk end
    return u
end

local function decodePlayerValue(v)
    if not v or v == "" then return nil end
    if v:find("^https?://") then return v end
    if v:sub(1, 2) == "//" then return "https:" .. v end

    -- ?url=BASE64 / ?id=BASE64
    local inner = v:match("[?&]%a+=([%w%+/=_%-]+)$")
    local candidates = { v }
    if inner then table.insert(candidates, 1, inner) end

    for _, c in ipairs(candidates) do
        local decoded = base64Decode(c)
        if decoded and decoded:find("^https?://") then return decoded end
        if decoded then
            local u = decoded:match("(https?://[^\"'%s]+)")
            if u then return u end
        end
    end
    return nil
end

local function collectEmbeds(body)
    local embeds, seen = {}, {}

    local function add(nameText, url)
        if not url or url == "" or seen[url] then return end
        local h = hostOf(url)
        for _, bad in ipairs(UNSUPPORTED_HOSTS) do
            if h:find(bad, 1, true) then
                log_info("Latanime: servidor omitido (no es stream directo): " .. h)
                return
            end
        end
        seen[url] = true
        local label = string_clean(nameText or "")
        if label == "" then label = h end
        table.insert(embeds, { name = label, url = url })
    end

    for _, el in ipairs(html_select(body, "[data-player]")) do
        add(el.text, decodePlayerValue(el:attr("data-player")))
    end

    if #embeds == 0 then
        for _, f in ipairs(html_select(body, "iframe[src]")) do
            local src = absUrl(f.src)
            if src ~= "" and not src:find(baseUrl, 1, true) then add("iframe", src) end
        end
    end
    return embeds
end

-- =====================================================================
-- REPRODUCTOR
-- =====================================================================

function getVideoList(episodeUrl)
    local body = fetchPage(episodeUrl)
    if not body then return {} end

    local embeds = collectEmbeds(body)
    log_info("Latanime: " .. #embeds .. " servidores en " .. episodeUrl)
    if #embeds == 0 then
        log_error("Latanime: no se encontraron servidores [data-player] en " .. episodeUrl)
        return {}
    end

    local sources, seen = {}, {}

    -- Google Drive se resuelve SIN red (el id va en la propia URL), así que
    -- estos servidores no entran al http_get_batch: pedir la vista previa de JS
    -- sería un gasto inútil y, además, no devuelve la URL directa.
    local embedList = {}
    for _, emb in ipairs(embeds) do
        local drive = driveDirectUrl(emb.url)
        if drive then
            if not seen[drive] then
                seen[drive] = true
                table.insert(sources, {
                    url     = drive,
                    quality = emb.name,
                    headers = { ["Referer"] = "https://drive.google.com/" },
                })
                log_info("Latanime: OK " .. emb.name .. " (drive directo)")
            end
        else
            table.insert(embedList, emb)
        end
    end

    local urls = {}
    for _, emb in ipairs(embedList) do table.insert(urls, emb.url) end
    local results = #urls > 0 and http_get_batch(urls, { timeout = EMBED_TIMEOUT }) or {}

    for i, emb in ipairs(embedList) do
        local res = results and results[i]
        local pageBody = (res and res.success and res.body) or ""
        local u, mime, ref

        if pageBody ~= "" then
            local ok, a, b, c = pcall(extractFromEmbed, emb, pageBody)
            if ok then u, mime, ref = a, b, c
            else log_error("Latanime: error extrayendo " .. emb.name .. ": " .. tostring(a)) end
        end

        -- Reintento con Referer de Latanime (algunos embeds lo exigen)
        if not u then
            local rr = http_get(emb.url, { timeout = EMBED_TIMEOUT, headers = { ["Referer"] = baseUrl .. "/" } })
            if rr.success and rr.body and rr.body ~= "" then
                local ok, a, b, c = pcall(extractFromEmbed, emb, rr.body)
                if ok then u, mime, ref = a, b, c end
            end
        end

        if u and not seen[u] then
            seen[u] = true
            table.insert(sources, {
                url     = u,
                mime    = mime,
                quality = emb.name,
                headers = { ["Referer"] = ref or origin(emb.url) or (baseUrl .. "/") }
            })
            log_info("Latanime: OK " .. emb.name .. " (" .. tostring(mime) .. ")")
        elseif not u then
            log_info("Latanime: sin stream directo en " .. emb.name .. " -> " .. emb.url)
        end
    end

    if #sources == 0 then
        log_error("Latanime: ningun servidor devolvio stream para " .. episodeUrl)
    end
    return sources
end

-- =====================================================================
-- FILTROS
-- =====================================================================

local STATIC_GENRES = {
    { "accion", "Acción" }, { "aventura", "Aventura" }, { "ciencia-ficcion", "Ciencia Ficción" },
    { "comedia", "Comedia" }, { "drama", "Drama" }, { "ecchi", "Ecchi" }, { "escolares", "Escolares" },
    { "fantasia", "Fantasía" }, { "harem", "Harem" }, { "isekai", "Isekai" }, { "magia", "Magia" },
    { "misterio", "Misterio" }, { "romance", "Romance" }, { "shonen", "Shonen" }, { "sobrenatural", "Sobrenatural" }
}

function getFilterList()
    local genreOptions = {}
    for _, g in ipairs(STATIC_GENRES) do
        table.insert(genreOptions, { value = g[1], label = g[2] })
    end
    table.sort(genreOptions, function(a, b) return a.label < b.label end)

    return {
        { type = "select", key = "year", label = "Año", defaultValue = "false",
          options = { { value = "false", label = "Todos" }, { value = "2024", label = "2024" }, { value = "2023", label = "2023" } } },
        { type = "checkbox", key = "genre", label = "Géneros", options = genreOptions },
        { type = "select", key = "category", label = "Categoría", defaultValue = "false",
          options = { { value = "false", label = "Todas" }, { value = "anime", label = "Anime" }, { value = "pelicula", label = "Película" } } }
    }
end

function getCatalogFiltered(index, filters)
    if type(filters) ~= "table" then filters = {} end
    local year = filters["year"] or "false"
    local category = filters["category"] or "false"
    local genres = filters["genre_included"]

    local query = "?fecha=" .. url_encode(year) .. "&categoria=" .. url_encode(category)
    if type(genres) == "table" and #genres > 0 then
        query = query .. "&genero=" .. url_encode(genres[1])
    else
        query = query .. "&genero=false"
    end

    local page = index + 1
    local url = baseUrl .. "/animes" .. query .. "&p=" .. page
    local r = http_get(url, { timeout = PAGE_TIMEOUT })
    if not r.success then return { items = {}, hasNext = false } end

    local items = parseCards(r.body)
    local hasNext = r.body:find("animes%p=" .. (page + 1)) ~= nil or r.body:find("animes%?p=" .. (page + 1)) ~= nil
    if #items == 0 then hasNext = false end
    return { items = items, hasNext = hasNext }
end
