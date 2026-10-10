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
--
-- Cambios v2.3.0:
--   * Extractores externalizados: require_lib("urls"/"embeds") + engine
--     base64_decode_bytes (reemplaza a DECODE.base64Decode).
--   * Guard en cada función pública para builds viejas sin require_lib.
--
-- Cambios v2.4.0:
--   * Guard ampliado: además de require_lib se comprueba el API del motor
--     base64_decode_bytes (rawget) en la primera función pública.
--
-- Cambios v2.5.0:
--   * driveDirectUrl local eliminado — la copia (union con ar/anime4up,
--     ar/witanime, ar/animephoenix) vive en libs/helpers/urls.lua (COMMON).
-- =====================================================================

id           = "latanime"
name         = "Latanime"
version      = "2.3.1"
baseUrl      = "https://latanime.org"
language     = "es"
content_type = "video"
libs         = { "urls", "embeds" }
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/latanime.png"

-- Таймауты: страницы сайта и эмбеды (сеть в эмуляторе без таймаута зависала).
-- EMBED_TIMEOUT: бюджет должен перекрывать авто-обход CF (15с) — иначе движок
-- отменяет запрос (Canceled) и мы ловим «2 таймаута 12с» на mixdrop и других
-- CF-хостерах.
local PAGE_TIMEOUT   = 15000
local EMBED_TIMEOUT  = 22000

-- =====================================================================
-- GUARD: старые сборки приложения без require_lib.
-- Top-level обязан загрузиться без require_lib (иначе плагин молча
-- пропадает из списка источников). show_error в проде асинхронный
-- (LuaSourceLoader.kt:363 кладёт pendingShowError и возвращает NIL),
-- поэтому после него идёт error(..., 0): он прерывает функцию, а адаптер
-- в catch отдаёт pending-show-error первым (LuaSourceAdapter.kt:262/283/579).
-- =====================================================================
local libErr = nil
local HAS_LIBS = type(require_lib) == "function"

-- Поимённая загрузка либ через pcall: на новых билдах файла либы ещё может
-- не быть на устройстве — require_lib бросает LuaError, и top-level упал бы
-- молча (плагин исчез бы из списка источников). Ошибка сохраняется в libErr.
local function tryLib(name)
    if not HAS_LIBS then return nil end
    local ok, res = pcall(require_lib, name)
    if not ok then libErr = tostring(res) return nil end
    return res
end

local COMMON   = tryLib("urls")
local EMBS     = tryLib("embeds")

local function ensureLibs()
    if not HAS_LIBS then
        show_error("Se requiere actualizar NoveLA", "Este complemento usa bibliotecas comunes (require_lib). Actualice la aplicación a la última versión.")
        error("Se requiere la última versión de la aplicación (require_lib)", 0)
    end
    -- API del motor usado directamente por este plugin (canon guard:
    -- rawget(_G, "<api>") — solo las funciones realmente usadas).
    -- unpack_packed — transitivo vía libs/embeds.lua (embeds y el APK nuevo
    -- se entregan juntos; canon: verificar también las APIs de las libs).
    if rawget(_G, "base64_decode_bytes") == nil then
        show_error("Se requiere actualizar NoveLA", "Este complemento necesita funciones nuevas (base64_decode_bytes). Actualice la aplicación a la última versión.")
        error("Se requiere una versión más reciente de la aplicación: base64_decode_bytes", 0)
    end
    if rawget(_G, "unpack_packed") == nil then
        show_error("Se requiere actualizar NoveLA", "Este complemento necesita funciones nuevas (unpack_packed). Actualice la aplicación a la última versión.")
        error("Se requiere una versión más reciente de la aplicación: unpack_packed", 0)
    end
    if not COMMON or not EMBS then
        show_error("Bibliotecas no cargadas", "Abra la pantalla de extensiones y pulse actualizar; después reinicie la aplicación. " .. (libErr or ""))
        error("Bibliotecas comunes no cargadas", 0)
    end
end

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
    ensureLibs()
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
    ensureLibs()
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
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h2")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "div.serieimgficha img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    ensureLibs()
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
    ensureLibs()
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
    ensureLibs()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "span.btn-estado")
    return el and string_clean(el.text) or nil
end

-- =====================================================================
-- CAPÍTULOS (EPISODIOS)
-- =====================================================================

function getChapterList(bookUrl)
    ensureLibs()
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
-- Google Drive → enlace directo (union de los puertos de ar/anime4up,
-- ar/witanime, ar/animephoenix y la copia local) — lib urls (driveDirectUrl).
local UNSUPPORTED_HOSTS = { "mega.nz", "mega.io", "mediafire", "gofile" }

local function decodePlayerValue(v)
    if not v or v == "" then return nil end
    if v:find("^https?://") then return v end
    if v:sub(1, 2) == "//" then return "https:" .. v end

    -- ?url=BASE64 / ?id=BASE64
    local inner = v:match("[?&]%a+=([%w%+/=_%-]+)$")
    local candidates = { v }
    if inner then table.insert(candidates, 1, inner) end

    for _, c in ipairs(candidates) do
        local decoded = base64_decode_bytes(c)
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
        local h = COMMON.hostOf(url)
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
    ensureLibs()
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
        local drive = COMMON.driveDirectUrl(emb.url)
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
            local ok, a, b, c = pcall(EMBS.extractFromEmbed, emb, pageBody)
            if ok then u, mime, ref = a, b, c
            else log_error("Latanime: error extrayendo " .. emb.name .. ": " .. tostring(a)) end
        end

        -- Reintento con Referer de Latanime (algunos embeds lo exigen)
        if not u then
            local rr = http_get(emb.url, { timeout = EMBED_TIMEOUT, headers = { ["Referer"] = baseUrl .. "/" } })
            if rr.success and rr.body and rr.body ~= "" then
                local ok, a, b, c = pcall(EMBS.extractFromEmbed, emb, rr.body)
                if ok then u, mime, ref = a, b, c end
            end
        end

        if u and not seen[u] then
            seen[u] = true
            table.insert(sources, {
                url     = u,
                mime    = mime,
                quality = emb.name,
                headers = { ["Referer"] = ref or COMMON.origin(emb.url) or (baseUrl .. "/") }
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
    ensureLibs()
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
    ensureLibs()
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
