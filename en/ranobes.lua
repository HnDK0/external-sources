-- ── Metadatos ─────────────────────────────────────────────────────────────────
-- Ranobes (ranobes.net) — novelas web traducidas al inglés. Motor DLE + módulo DLE Filter.
--   Catálogo : /updates/ = "últimas actualizaciones" (17 filas por página, ~26 páginas). Cada fila
--              apunta al CAPÍTULO; la URL de la novela se deriva de la del capítulo:
--              /<slug>-<id>/<cap>.html  →  /novels/<id>-<slug>.html
--   Listados : /novels/ y /f/<filtros>/  → article.shortstory (10 por página, 400+ páginas)
--   Búsqueda : filtro l.title (el /search/ nativo se llena por JS y no trae resultados en el HTML)
--   Filtros  : /f/clave=valor/…/sort=date/order=desc  (formato copiado de una URL real del sitio)
--   Ficha    : /novels/<id>-<slug>.html
--   Capítulos: /chapters/<id>/page/N/ → window.__DATA__ (JSON), 25 por página, el más nuevo primero
--   Texto    : #arrticle (<p> + bloques de publicidad .free-support-top)
-- El sitio tiene espejos (ranobes.net / ranobes.top): todas las URLs se normalizan a baseUrl.
--
-- Anti-bot del sitio: si marca tu IP por exceso de peticiones ("violation") responde con una página
-- "Security check" (título "Just a moment...", formulario #vb-challenge-form, widget Cloudflare
-- Turnstile). Solo una persona puede resolverla (en un WebView/navegador): el plugin NO intenta saltarla.
-- Con el código de NoveLA a la vista, lo que corresponde hacer desde el plugin es:
--   1) cf_options.trigger_markers: el interceptor de Cloudflare de la app solo reconoce los marcadores de
--      Cloudflare; esta página no los tiene, así que la app nunca abría su WebView y el plugin recibía la
--      página del reto en lugar del capítulo. Con estos marcadores la app lanza su flujo de verificación.
--   2) Si el reto sigue sin resolverse, show_error(…, url): el lector muestra un diálogo con un botón que
--      abre esa URL en el WebView de la app (las cookies se comparten con las peticiones del plugin).
--   3) Espaciar las peticiones propias y no guardar la página del reto como si fuera una ficha o capítulo.
--   4) Ajuste opcional "Chapter list = Lite": no recorre las ~N/25 páginas de capítulos (ver más abajo).
id       = "ranobes"
name     = "Ranobes"
version  = "1.1.0"
baseUrl  = "https://ranobes.net"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/ranobes.png"

-- Marcadores del "Security check" propio del sitio (la app los usa para activar su verificación en WebView)
cf_options = {
    trigger_markers = { 'id="vb-challenge-form"', 'name="vb_challenge"' },
}

-- ── Hélpers ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Los enlaces absolutos de las páginas usan el dominio con que se pidió la página. Se reescriben
-- al dominio del plugin para que la identidad de un libro (su URL) no cambie según el espejo.
local function toBase(u)
    if not u or u == "" then return "" end
    return (regex_replace(absUrl(u), "^https?://(?:www\\.)?ranobes\\.[a-z]+", baseUrl))
end

-- Milisegundos actuales (si el motor devolviera segundos se convierten)
local function nowMs()
    local t = os_time()
    if t < 100000000000 then t = t * 1000 end
    return t
end

-- Ritmo de peticiones: al menos MIN_GAP_MS entre dos peticiones propias del plugin (listados, fichas,
-- páginas de capítulos). Cargar los capítulos de una novela larga son decenas de páginas seguidas, que
-- es justo lo que dispara el anti-bot del sitio.
local MIN_GAP_MS = 800
local _lastReq = 0
local function throttle()
    local wait = MIN_GAP_MS - (nowMs() - _lastReq)
    if wait > 0 then sleep(math.floor(wait)) end
    _lastReq = nowMs()
end

-- ¿Es la página "Security check" del sitio? (formulario del reto y su token oculto)
local function isSecurityCheck(body)
    if not body or body == "" then return false end
    return body:find('id="vb-challenge-form"', 1, true) ~= nil
        or body:find('name="vb_challenge"', 1, true) ~= nil
end

-- Si el bypass de la app no pudo con el reto, http_get devuelve code = -1 y el mensaje de la excepción
local function bypassFailed(r)
    return r ~= nil and r.code == -1
        and tostring(r.body or ""):lower():find("cloudflare verification failed", 1, true) ~= nil
end

local function isChallenge(r)
    return r ~= nil and (isSecurityCheck(r.body) or bypassFailed(r))
end

-- URL del último reto visto durante la llamada en curso. Los puntos de entrada que el motor revisa
-- (catálogo, parsePage, getChapterText) lo convierten en un diálogo con botón al WebView.
local _challengeUrl = nil

local CHALLENGE_TITLE = "Ranobes — Security check"
local CHALLENGE_TEXT  = "Ranobes pidió una verificación (Security check / Turnstile) para tu IP.\n\n"
    .. "Pulsa «Open», resuélvela en el WebView (incluido el botón «I'm not a robot.») y vuelve a intentarlo. "
    .. "Si reaparece enseguida, espera unos minutos: el sitio limita las peticiones por IP."

local function reportSecurityCheck(url)
    _challengeUrl = url
    log_error("ranobes: el sitio pidió su 'Security check' (Turnstile) en " .. tostring(url)
        .. " — resuélvelo una vez en el WebView/navegador y reintenta; si sigue, espera unos minutos")
end

local function beginCall() _challengeUrl = nil end

local function finishCall()
    if _challengeUrl then
        show_error(CHALLENGE_TITLE, CHALLENGE_TEXT, _challengeUrl)
        _challengeUrl = nil
    end
end

-- Caché de la ficha (título/portada/descripción/géneros/estado/rating). NUNCA para capítulos.
local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    throttle()
    local r = http_get(url)
    if isChallenge(r) then
        reportSecurityCheck(url)
        return nil
    end
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

-- id numérico de la novela: /novels/1207224-my-strange-life-role-playing-game.html → 1207224
local function bookIdOf(bookUrl)
    local s = tostring(bookUrl or "")
    return s:match("/novels/(%d+)%-") or s:match("/novels/(%d+)")
end

-- Codifica un valor para un segmento de ruta (espacios como %20, nunca "+")
local function enc(v)
    return (tostring(url_encode(tostring(v))):gsub("%+", "%%20"))
end

-- Portada guardada como estilo: style="background-image: url(https://…/x.webp);"
local function coverFromStyle(style)
    if not style or style == "" then return "" end
    local u = style:match("url%(%s*['\"]?([^'\")%s]+)")
    if not u then return "" end
    return toBase(u)
end

-- ── Limpieza de texto ─────────────────────────────────────────────────────────

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "\\r\\n?", "\n")
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    -- Créditos tipo "Translator: X" (con los dos puntos: sin ellos se borraría prosa legítima)
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader)\\s*:[^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = regex_replace(text, "\\n{3,}", "\n\n")
    return string_trim(text)
end

local function cleanDescription(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "\\r\\n?", "\n")
    text = regex_replace(text, "\\n{3,}", "\n\n")
    return string_trim(text)
end

-- ── Tarjetas de listado ───────────────────────────────────────────────────────

-- ¿hay página siguiente? En la barra de navegación de DLE la flecha solo es un enlace si existe.
local function hasNextLink(body)
    return html_select_first(body, ".page_next a[href]") ~= nil
end

-- /updates/: cada fila enlaza a un CAPÍTULO. Se deriva la URL de la novela.
local function novelUrlFromChapterUrl(u)
    local slug, id = tostring(u or ""):match("/([^/]+)%-(%d+)/%d+%.html")
    if not slug or not id then return nil end
    return baseUrl .. "/novels/" .. id .. "-" .. slug .. ".html"
end

local function parseUpdates(body)
    local items, seen = {}, {}
    for _, row in ipairs(html_select(body, "div.block.story_line")) do
        local a = html_select_first(row.html, "a[href]")
        local t = html_select_first(row.html, "h3")
        if a and t then
            local url = novelUrlFromChapterUrl(toBase(a.href))
            local title = string_clean(t.text)
            if url and title ~= "" and not seen[url] then
                seen[url] = true
                local item = { title = title, url = url }
                local cover = coverFromStyle(html_attr(row.html, "i.cover", "style"))
                if cover ~= "" then item.cover = cover end
                table.insert(items, item)
            end
        end
    end
    return items
end

-- /novels/, /f/…, /search/…: article.shortstory con el título en h2.title a
local function parseArticles(body)
    local cards = html_select(body, "article.shortstory")
    if #cards == 0 then cards = html_select(body, "article.block.story") end

    local items, seen = {}, {}
    for _, card in ipairs(cards) do
        local a = html_select_first(card.html, ".title a[href]")
        if a then
            local url = toBase(a.href)
            -- solo fichas de novela (/novels/<id>-<slug>.html)
            if url:match("/novels/%d+%-") and not seen[url] then
                local title = string_clean(a.text)
                if title ~= "" then
                    seen[url] = true
                    local item = { title = title, url = url }
                    local cover = coverFromStyle(html_attr(card.html, "figure.cover", "style"))
                    if cover ~= "" then item.cover = cover end
                    local r = html_select_first(card.html, ".rate-drop strong")
                    local rating = r and string_clean(r.text) or ""
                    if rating ~= "" and rating ~= "0" then item.rating = rating end
                    table.insert(items, item)
                end
            end
        end
    end
    return items
end

-- Descarga una página de listado y la parsea con `parser`. La página fuera de rango (404) es el fin.
local function fetchList(url, parser)
    throttle()
    local r = http_get(url)
    if isChallenge(r) then
        reportSecurityCheck(url)
        return { items = {}, hasNext = false }
    end
    if not r.success then
        if r.code ~= 404 then
            log_error("ranobes: HTTP " .. tostring(r.code) .. " en " .. url)
        end
        return { items = {}, hasNext = false }
    end
    local items = parser(r.body)
    if #items == 0 then
        log_info("ranobes: 0 resultados en " .. url .. " (body=" .. #r.body .. " bytes)")
    end
    return { items = items, hasNext = (#items > 0 and hasNextLink(r.body)) }
end

local function pagePath(base, page)
    if page > 1 then return base .. "page/" .. page .. "/" end
    return base
end

-- ── Catálogo ──────────────────────────────────────────────────────────────────
-- Al abrir: últimas actualizaciones (/updates/). Si esa página no diera nada se usa el
-- catálogo completo (/novels/, novelas nuevas primero).

local function catalogListImpl(index)
    local page = index + 1
    local res = fetchList(pagePath(baseUrl .. "/updates/", page), parseUpdates)
    -- con el reto activo no tiene sentido probar otra página: es el mismo bloqueo
    if #res.items > 0 or page > 1 or _challengeUrl then return res end

    log_info("ranobes: /updates/ no dio filas; se usa /novels/")
    return fetchList(baseUrl .. "/novels/", parseArticles)
end

function getCatalogList(index)
    beginCall()
    local res = catalogListImpl(index)
    finishCall()
    return res
end

-- ── Filtros: URL del módulo DLE Filter ────────────────────────────────────────
-- Formato real copiado del sitio:
--   /f/b.languages=English/g.translater=1/n.events=Harem/n.genre=Adult/v.genre=Yaoi/
--      v.languages=Korean%2CJapanese/sort=date/order=desc
-- Prefijos: n.=incluir, v.=excluir, b.=idiomas (incluir), f.=desde, t.=hasta, l.=contiene,
-- g.=casilla (1). Varios valores de una clave van separados por %2C. El orden "a;b" del
-- formulario se parte en sort=a/order=b. La página N va al final: …/page/N/

local DEFAULT_SORT = "date;desc"

local function csv(values)
    local out = {}
    for _, v in ipairs(values or {}) do table.insert(out, enc(v)) end
    return table.concat(out, "%2C")
end

-- specs: { {key, valueString}, … } ya en el orden alfabético que usa el sitio; sort = "a;b"
local function buildFilterUrl(specs, sort, page)
    local segs = {}
    for _, kv in ipairs(specs) do
        if kv[2] and kv[2] ~= "" then table.insert(segs, kv[1] .. "=" .. kv[2]) end
    end

    sort = sort or DEFAULT_SORT
    if #segs == 0 and sort == DEFAULT_SORT then
        return pagePath(baseUrl .. "/novels/", page)
    end

    local sortKey, sortDir = sort:match("^([^;]+);(.+)$")
    if not sortKey then sortKey = sort end
    if sortKey ~= "" then table.insert(segs, "sort=" .. enc(sortKey)) end
    if sortDir then table.insert(segs, "order=" .. enc(sortDir)) end

    local url = baseUrl .. "/f/" .. table.concat(segs, "/")
    if page > 1 then url = url .. "/page/" .. page .. "/" end
    return url
end

-- ── Búsqueda ──────────────────────────────────────────────────────────────────
-- El buscador nativo del sitio (/search/<consulta>/) carga sus resultados por JavaScript: el
-- HTML llega con "found 0 novels" y nada más, así que no sirve desde el plugin. Se usa el filtro
-- "Novel title must contain" (l.title) del catálogo, que sí devuelve la lista ya armada en el
-- HTML y con las mismas tarjetas. Busca la frase completa dentro del título (no palabras sueltas
-- en cualquier orden) y ordena por popularidad para que lo más conocido salga primero.

local SEARCH_SORT = "news_read;desc"

function getCatalogSearch(index, query)
    local q = string_trim(query or "")
    if q == "" then return { items = {}, hasNext = false } end
    beginCall()
    local url = buildFilterUrl({ { "l.title", enc(q) } }, SEARCH_SORT, index + 1)
    local res = fetchList(url, parseArticles)
    finishCall()
    return res
end

-- ── Detalles del libro ────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    -- el h1 lleva un subtítulo (título original) y un separador oculto: fuera
    local h1 = html_select_first(body, "h1.title")
    if h1 then
        local t = string_clean(html_text(html_remove(h1.html, ".subtitle", "[hidden]")))
        if t ~= "" then return t end
    end
    local og = html_attr(body, "meta[property='og:title']", "content")
    if og and og ~= "" then return string_clean(og) end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local cover = html_attr(body, "meta[property='og:image']", "content") or ""
    if cover ~= "" then return toBase(cover) end
    cover = coverFromStyle(html_attr(body, ".r-fullstory-poster figure.cover", "style"))
    return cover ~= "" and cover or nil
end

-- La sinopsis trae al final un pie "WebNovels and Books · <categoría>" (span.grey) que no es parte del texto.
function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end

    local el = html_select_first(body, ".r-desription .moreless")
        or html_select_first(body, ".r-desription .cont-text")
    if el then
        local text = cleanDescription(html_text(html_remove(el.html, "span.grey", "script", "style")))
        if text ~= "" then return text end
    end
    local og = html_attr(body, "meta[property='og:description']", "content") or ""
    og = cleanDescription(og)
    return og ~= "" and og or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local genres = {}
    for _, a in ipairs(html_select(body, "#mc-fs-genre a")) do
        local g = string_clean(a.text)
        if g ~= "" then table.insert(genres, g) end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".rate-stat-num .bold")
    local rating = el and string_clean(el.text) or ""
    if rating == "" then
        local m = regex_match(body, "\"ratingValue\"\\s*:\\s*\"([0-9.]+)\"")
        rating = (m and m[1]) or ""
    end
    if rating == "" or rating == "0" then return nil end
    return rating
end

-- Estado en el original (fila "Status in COO": Ongoing / Completed / Hiatus / Dropped)
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, li in ipairs(html_select(body, ".r-fullstory-spec li")) do
        if string_starts_with(string_clean(li.text), "Status in COO") then
            local a = html_select_first(li.html, "a")
            local s = a and string_clean(a.text) or ""
            if s ~= "" then return s end
        end
    end
    return nil
end

-- ── Capítulos ─────────────────────────────────────────────────────────────────
-- /chapters/<id>/ (y /chapters/<id>/page/N/) embebe window.__DATA__ = { chapters:[…], pages_count,
-- count_all, limit:25, … } con el capítulo MÁS NUEVO primero. La página 1 del sitio = los 25 más nuevos.
-- El motor quiere la página 1 = los más VIEJOS, así que parsePage invierte páginas y orden interno.

-- JSON de window.__DATA__: desde la primera "{" hasta la última "}" antes de </script>
local function extractData(body)
    if not body then return nil end
    local s = body:find("window.__DATA__", 1, true)
    if not s then return nil end
    local open = body:find("{", s, true)
    if not open then return nil end
    local close = body:find("</script>", open, true)
    local chunk = close and body:sub(open, close - 1) or body:sub(open)
    local last = chunk:match("^.*()}")
    if not last then return nil end
    return json_parse(chunk:sub(1, last))
end

-- Filas { title, url, date } en el orden del sitio (más nuevo primero)
local function rowsFromData(data)
    local rows = {}
    if type(data) ~= "table" or type(data.chapters) ~= "table" then return rows end
    for _, ch in ipairs(data.chapters) do
        local url = toBase(ch.link or "")
        if url ~= "" then
            local title = string_clean(ch.title or "")
            if title == "" then title = url:match("/(%d+)%.html") or url end
            table.insert(rows, { title = title, url = url, date = tostring(ch.date or "") })
        end
    end
    return rows
end

local function chaptersUrl(id, sitePage)
    local url = baseUrl .. "/chapters/" .. id .. "/"
    if sitePage > 1 then url = url .. "page/" .. sitePage .. "/" end
    return url
end

-- Una página del sitio → tabla __DATA__ o nil (con un reintento)
local function fetchChapterData(id, sitePage)
    local url = chaptersUrl(id, sitePage)
    for attempt = 1, 2 do
        throttle()
        local r = http_get(url)
        if isChallenge(r) then
            reportSecurityCheck(url)
            return nil
        end
        if r.success then
            local data = extractData(r.body)
            if data and type(data.chapters) == "table" then return data end
            log_error("ranobes: sin window.__DATA__ válido en " .. url)
            return nil
        end
        if r.code == 404 then return nil end
        log_error("ranobes: HTTP " .. tostring(r.code) .. " en " .. url .. " (intento " .. attempt .. ")")
        if attempt == 1 then sleep(300) end
    end
    return nil
end

-- Página 1 del sitio + total de páginas, con vida corta (60 s): dentro de una misma pasada del motor
-- el total es estable, y una actualización posterior lo vuelve a leer.
local _chCache = {}
local function firstChapterData(id)
    local entry = _chCache[id]
    local now = nowMs()
    if entry and now - entry.t < 60000 then return entry end
    local d = fetchChapterData(id, 1)
    if not d then return nil end
    local total = math.floor(tonumber(d.pages_count) or 1)
    if total < 1 then total = 1 end
    entry = { t = now, total = total, data = d }
    _chCache[id] = entry
    return entry
end

local function reversed(rows)
    local out = {}
    for i = #rows, 1, -1 do table.insert(out, rows[i]) end
    return out
end

local function stripDates(rows)
    local out = {}
    for _, r in ipairs(rows) do table.insert(out, { title = r.title, url = r.url }) end
    return out
end

-- Modo completo: lista real (títulos y URLs del sitio). Es el modo por defecto.
local function fullParsePage(bookUrl, page)
    local id = bookIdOf(bookUrl)
    if not id then
        log_error("ranobes: no pude sacar el id de " .. tostring(bookUrl))
        return { chapters = {}, totalPages = 1 }
    end

    local first = firstChapterData(id)
    if not first then return { chapters = {}, totalPages = 1 } end
    local total = first.total

    -- página del motor 1 (más viejos) ↔ última página del sitio
    local sitePage = total - page + 1
    if sitePage < 1 or sitePage > total then return { chapters = {}, totalPages = total } end

    local data = first.data
    if sitePage > 1 then data = fetchChapterData(id, sitePage) end
    if not data then return { chapters = {}, totalPages = total } end

    return { chapters = stripDates(reversed(rowsFromData(data))), totalPages = total }
end

-- ── Modo Lite (opcional, ajuste "Chapter list") ───────────────────────────────
-- La lista real exige recorrer ~N/25 páginas del sitio (28 para 692 capítulos; 120+ en novelas largas),
-- y ese volumen es lo que puede hacer saltar el anti-bot. En Lite la lista se fabrica con UNA petición
-- (el total de capítulos): "Chapter 1" … "Chapter N" por posición (1 = el más viejo), y el capítulo real
-- se busca recién al abrirlo. Costes a tener en cuenta:
--   * Títulos simbólicos: la numeración es la POSICIÓN en el sitio, que no siempre coincide con el
--     número del título real (capítulos especiales, "Two in One"…). Al abrir un capítulo, su primera
--     línea muestra el título real.
--   * La app guarda por capítulo una URL única y la descarga ella misma antes de llamar al plugin. Aquí esa
--     URL es interna (un archivo estático del sitio con ?ranobes_lite=<id>-<posición>), de modo que
--     "abrir en el navegador" no lleva al capítulo. Cambiar de modo en un libro ya agregado requiere
--     volver a agregarlo (las URLs de un modo y otro no se mezclan).
--   * Al abrir un capítulo el plugin consulta la página de lista que lo contiene (se cachea, así que leer
--     capítulos seguidos casi no la repite) y luego pide el capítulo real.

local PREF_KEY       = "ranobes_chapter_list"
local LITE_PAGE_SIZE = 500                                      -- capítulos por "página" virtual de la lista
local LITE_PATH      = "/templates/Dark/images/favicon.ico"     -- archivo estático que sí existe en el sitio

local function liteMode()
    return get_preference(PREF_KEY) == "lite"
end

function getSettingsSchema()
    local cur = get_preference(PREF_KEY)
    if cur ~= "lite" then cur = "full" end
    return {
        {
            key     = PREF_KEY,
            type    = "select",
            label   = "Chapter list (re-add books after changing)",
            current = cur,
            options = {
                { value = "full", label = "Full — real titles (many requests on long novels)" },
                { value = "lite", label = "Lite — numbered chapters, opened on demand" },
            },
        },
    }
end

local function litePlaceholder(id, pos)
    return baseUrl .. LITE_PATH .. "?ranobes_lite=" .. id .. "-" .. pos
end

local function parseLiteUrl(u)
    local id, pos = tostring(u or ""):match("ranobes_lite=(%d+)%-(%d+)")
    if id then return id, tonumber(pos) end
    return nil
end

-- Total de capítulos que informa el sitio (count_all); si faltara, se estima con las páginas
local function liteCount(data)
    local n = math.floor(tonumber(data and data.count_all) or 0)
    if n > 0 then return n end
    local rows = rowsFromData(data)
    local pages = math.floor(tonumber(data and data.pages_count) or 1)
    return (pages - 1) * 25 + #rows
end

local function liteParsePage(bookUrl, page)
    local id = bookIdOf(bookUrl)
    if not id then
        log_error("ranobes: no pude sacar el id de " .. tostring(bookUrl))
        return { chapters = {}, totalPages = 1 }
    end
    local first = firstChapterData(id)
    if not first then return { chapters = {}, totalPages = 1 } end

    local count = liteCount(first.data)
    local total = math.max(1, math.ceil(count / LITE_PAGE_SIZE))
    local from = (page - 1) * LITE_PAGE_SIZE + 1
    local to = math.min(count, page * LITE_PAGE_SIZE)
    local chapters = {}
    for pos = from, to do
        table.insert(chapters, { title = "Chapter " .. pos, url = litePlaceholder(id, pos) })
    end
    return { chapters = chapters, totalPages = total }
end

-- Páginas de lista ya descargadas, por (libro, total, página): con otro total las posiciones se desplazan
local _lpCache, _lpCount = {}, 0

-- Fila { title, url } del capítulo en la posición `pos` (1 = el más viejo), o nil
local function resolveLiteRow(id, pos)
    local first = firstChapterData(id)
    if not first then return nil end
    local count = liteCount(first.data)

    for attempt = 1, 3 do
        if pos < 1 or pos > count then
            log_error("ranobes: el capítulo " .. pos .. " no existe (el sitio informa " .. count .. ")")
            return nil
        end
        local limit = math.floor(tonumber(first.data.limit) or 25)
        if limit < 1 then limit = 25 end
        local idx = count - pos                       -- 0 = el más nuevo
        local sitePage = math.floor(idx / limit) + 1
        local inPage = idx % limit + 1

        local data
        if sitePage == 1 then
            data = first.data
        else
            local key = id .. ":" .. count .. ":" .. sitePage
            data = _lpCache[key]
            if not data then
                data = fetchChapterData(id, sitePage)
                if not data then return nil end
                if _lpCount >= 12 then _lpCache, _lpCount = {}, 0 end
                _lpCache[key] = data
                _lpCount = _lpCount + 1
            end
        end

        if liteCount(data) == count then
            return rowsFromData(data)[inPage]
        end
        -- el sitio cambió de total entre la página 1 y esta: releer la página 1 y rehacer la cuenta
        _chCache[id] = nil
        first = firstChapterData(id)
        if not first then return nil end
        count = liteCount(first.data)
    end
    return nil
end

function parsePage(bookUrl, page)
    beginCall()
    local res
    if liteMode() then
        res = liteParsePage(bookUrl, page)
    else
        res = fullParsePage(bookUrl, page)
    end
    finishCall()
    return res
end

-- Fecha de la última actualización = fecha del capítulo más nuevo (YYYY-MM-DD)
function getBookLastUpdate(bookUrl)
    local id = bookIdOf(bookUrl)
    if not id then return nil end
    local first = firstChapterData(id)
    if not first then return nil end
    local rows = rowsFromData(first.data)
    if #rows == 0 then return nil end
    return rows[1].date:match("^(%d%d%d%d%-%d%d%-%d%d)")
end

-- ── Texto del capítulo ────────────────────────────────────────────────────────
-- #arrticle contiene <p> sueltos, bloques de publicidad (div.free-support-top) y, tras quitar un
-- anuncio, a veces una línea de diálogo SIN <p> (texto suelto entre dos </p><p>). Esas líneas se
-- envuelven en su propio <p> antes de extraer el texto; si no, se pegarían al párrafo siguiente.

local function wrapBareText(inner)
    local function wrap(a, t, b) return a .. "<p>" .. t .. "</p>" .. b end
    -- texto suelto entre un </p> y un <p>
    inner = inner:gsub("(</p>)%s*([^<>%s][^<>]*)%s*(<p>)", wrap)
    -- texto suelto al principio
    inner = inner:gsub("^%s*([^<>%s][^<>]*)%s*(<p>)", function(t, b) return "<p>" .. t .. "</p>" .. b end)
    -- texto suelto al final
    inner = inner:gsub("(</p>)%s*([^<>%s][^<>]*)%s*$", function(a, t) return a .. "<p>" .. t .. "</p>" end)
    return inner
end

-- Texto de una página de capítulo ya descargada
local function chapterTextFromHtml(html, url)
    local cleaned = html_remove(html,
        "script", "style", "ins", "iframe",
        ".free-support-top", "[id^=bg-ssp]", ".adsbygoogle"
    )

    local el = html_select_first(cleaned, "#arrticle")
    if not el then el = html_select_first(cleaned, "div.text") end
    if not el then
        log_error("ranobes: sin #arrticle en " .. tostring(url))
        return ""
    end

    return applyStandardContentTransforms(html_text(wrapBareText(el.html)))
end

-- Modo Lite: la URL interna lleva (libro, posición); aquí se busca y se pide el capítulo real
local function liteChapterText(id, pos)
    local row = resolveLiteRow(id, pos)
    if not row then
        log_error("ranobes: no pude ubicar el capítulo " .. tostring(pos) .. " del libro " .. tostring(id))
        return ""
    end
    throttle()
    local r = http_get(row.url)
    if isChallenge(r) then
        reportSecurityCheck(row.url)
        return ""
    end
    if not r.success then
        log_error("ranobes: HTTP " .. tostring(r.code) .. " en " .. row.url)
        return ""
    end
    local text = chapterTextFromHtml(r.body, row.url)
    if text == "" then return "" end
    return row.title .. "\n\n" .. text
end

function getChapterText(html, url)
    beginCall()
    local text = ""

    local liteId, litePos = parseLiteUrl(url)
    if liteId then
        text = liteChapterText(liteId, litePos)
    elseif html and html ~= "" then
        if isSecurityCheck(html) then
            reportSecurityCheck(url)
        else
            text = chapterTextFromHtml(html, url)
        end
    end

    finishCall()
    return text
end

-- ── Filtros ───────────────────────────────────────────────────────────────────
-- Los del formulario de /novels/ (DLE Filter). Géneros, tags e idiomas son "incluir / excluir"
-- (n./v. en la URL). Las listas salen de /tags/genre/ y /tags/events/ del sitio.

local GENRES = {
    "Action", "Adult", "Adventure", "Comedy", "Drama", "Ecchi",
    "Fantasy", "Game", "Gender Bender", "Harem", "Josei", "Historical",
    "Horror", "Martial Arts", "Mature", "Mecha", "Mystery", "Psychological",
    "Romance", "School Life", "Sci-fi", "Seinen", "Shoujo", "Shounen",
    "Slice of Life", "Shounen Ai", "Sports", "Supernatural", "Smut", "Tragedy",
    "Xianxia", "Xuanhuan", "Wuxia", "Yaoi", "Yuri",
}

-- Etiqueta visible distinta del valor que entiende el filtro (el sitio guarda los ":" como "&#58;"
-- y un nombre con espacio duro)
local TAG_LABELS = {
    ["Avatar&#58; The Last Airbender"] = "Avatar: The Last Airbender",
    ["Fallout&#58; New Vegas"] = "Fallout: New Vegas",
    ["Kenichi&#58; The Mightiest Disciple"] = "Kenichi: The Mightiest Disciple",
    ["Tales of\194\160Demons and Gods"] = "Tales of Demons and Gods",
}

local TAGS = {
    "Abandoned Children", "Ability Steal", "Absent Parents", "Absolute Duo", "Abusive Characters",
    "Academy", "Accelerated Growth", "Acting", "Adapted Manhwa", "Adapted to Anime",
    "Adapted to Drama", "Adapted to Drama CD", "Adapted to Game", "Adapted to Manga", "Adapted to Manhua",
    "Adapted to Manhwa", "Adapted to Movie", "Adapted to Visual Novel", "Adopted Children", "Adopted Protagonist",
    "Adultery", "Adventurers", "Affair", "Against the Gods", "Age Progression",
    "Age Regression", "Aggressive Characters", "Akame ga Kill!", "Aladdin", "Alchemist",
    "Alchemy", "Aliens", "All-Girls School", "Alternate World", "Amnesia",
    "Amorality Protagonist", "Amusement Park", "Anal", "Ancient China", "Ancient Times",
    "Androgynous Characters", "Androids", "Angels", "Angst", "Animal Characteristics",
    "Animal Rearing", "Anti-Magic", "Anti-social Protagonist", "Antihero Protagonist", "Antique Shop",
    "Apartment Life", "Apathetic Protagonist", "Apocalypse", "Apocalyptic", "Appearance Changes",
    "Appearance Different from Actual Age", "Archery", "Aristocracy", "Arms Dealers", "Army",
    "Army Building", "Arranged Marriage", "Arrogant Characters", "Artifact Crafting", "Artifacts",
    "Artifacts Cultivation", "Artificial Intelligence", "Artists", "Asexual Protagonist", "ASOIAF",
    "Assassins", "Astrologers", "Attack on Titan", "Attractive Lead", "Autism",
    "Automatons", "Avatar", "Avatar&#58; The Last Airbender", "Average-looking Protagonist", "Award-winning Work",
    "Awkward Protagonist", "Bands", "Baseball", "Based on a Movie", "Based on a Song",
    "Based on a TV Show", "Based on a Video Game", "Based on a Visual Novel", "Based on an Anime", "Basketball",
    "Battle Academy", "Battle Competition", "Battle Through the Heavens", "BDSM", "Beast Companions",
    "Beast Master", "Beastkin", "Beasts", "Beautiful Couple", "Beautiful Female Lead",
    "Bestiality", "Betrayal", "Bickering Couple", "Biochip", "Bisexual Protagonist",
    "Black Belly", "Blackmail", "Blacksmith", "Bleach", "Blind Dates",
    "Blind Protagonist", "Blood Manipulation", "Bloodlines", "Body Swap", "Body Tempering",
    "Body-double", "Bodyguards", "Books", "Bookworm", "Boss-Subordinate Relationship",
    "Brainwashing", "Breast Fetish", "Broken Engagement", "Brother Complex", "Brotherhood",
    "Buddhism", "Bullying", "Business", "Business Management", "Businessmen",
    "Butlers", "Call of Cthulhu", "Calm Protagonist", "Campione!", "Cannibalism",
    "Card Games", "Carefree Protagonist", "Caring Protagonist", "Cautious Protagonist", "Celebrities",
    "CEO", "Chapters Reviews", "Character Development", "Character Growth", "Charismatic Protagonist",
    "Charlotte (anime)", "Charming Protagonist", "Chat Rooms", "Chatgroup", "Cheats",
    "Chefs", "Child Abuse", "Child Protagonist", "Childcare", "Childhood Friends",
    "Childhood Love", "Childhood Promise", "Childish Protagonist", "Chivalry of a Failed Knight", "Chuunibyou",
    "Clan Building", "Classic", "Clever Protagonist", "Clever Protagonist Cultivation", "Cliche",
    "Clingy Lover", "Clones", "Clubs", "Clumsy Love Interests", "Co-Workers",
    "Cohabitation", "Cold Love Interests", "Cold Protagonist", "Collection of Short Stories", "College or University",
    "Coma", "Comedic Undertone", "Coming of Age", "Complex Family Relationships", "Conditional Power",
    "Confident Protagonist", "Confinement", "Conflicting Loyalties", "Conspiracies", "Contemporary",
    "Contracts", "Cooking", "Corruption", "Cosmic Wars", "Cosplay",
    "Counter-Strike", "Couple Growth", "Court Official", "Cousins", "Cowardly Protagonist",
    "Crafting", "Crazy Protagonist", "Crime", "Criminals", "Cross-dressing",
    "Crossover", "Cruel Characters", "Cryostasis", "Cultivation", "Cunnilingus",
    "Cunning Protagonist", "Curious Protagonist", "Curses", "Cute Children", "Cute Protagonist",
    "Cute Story", "Cyberpunk", "Dancers", "DanMachi", "Dao Companion",
    "Dao Comprehension", "Daoism", "Dark", "Dark Fantasy", "Dark Souls",
    "DC", "DC Universe", "Dead Protagonist", "Death", "Death of Loved Ones",
    "Debts", "Delinquents", "Delusions", "Demi-Humans", "Demon Lord",
    "Demon Slayer", "Demonic Cultivation Technique", "Demons", "Dense Protagonist", "Depictions of Cruelty",
    "Depression", "Destiny", "Detective Conan", "Detectives", "Determined Protagonist",
    "Devils", "Devoted Love Interests", "Different Social Status", "Diplomacy", "Disabilities",
    "Discrimination", "Disfigurement", "Dishonest Protagonist", "Distrustful Protagonist", "Divination",
    "Divination Enlightenment", "Divine Protection", "Divorce", "Doctors", "Dolls or Puppets",
    "Dolls/Puppets", "Domestic Affairs", "Doting Love Interests", "Doting Older Siblings", "Doting Parents",
    "Douluo Dalu", "Dragon Ball", "Dragon Riders", "Dragon Slayers", "Dragons",
    "Dreams", "Drugs", "Druids", "Dungeon Master", "Dungeons",
    "Dwarfs", "Dystopia", "e-Sports", "Early Romance", "Earth Invasion",
    "Eastern Setting", "Easy Going Life", "Economics", "Egoist Protagonist", "Eidetic Memory",
    "Elderly Protagonist", "Elemental Magic", "Elementalists", "Elves", "Emotionally Weak Protagonist",
    "Empires", "Enemies", "Enemies Become Allies", "Enemies Become Lovers", "Engagement",
    "Engineer", "Enlightenment", "Entertainment", "Episodic", "Eunuch",
    "European Ambience", "Evil Gods", "Evil Organizations", "Evil Protagonist", "Evil Religions",
    "Evolution", "Exhibitionism", "Exorcism", "Eye Powers", "Face Slapping",
    "Fairies", "Fairy Tail", "Fallen Angels", "Fallen Nobility", "Fallout",
    "Fallout&#58; New Vegas", "Familial Love", "Familiars", "Family", "Family Business",
    "Family Conflict", "Famous Parents", "Famous Protagonist", "Fanaticism", "Fanfiction",
    "Fantasy Creatures", "Fantasy Magic", "Fantasy World", "Farming", "Fast Cultivation",
    "Fast Learner", "Fat Protagonist", "Fat to Fit", "Fate/Grand Order", "Fate/stay night",
    "Fated Lovers", "Fearless Protagonist", "Fellatio", "Female Lead", "Female Master",
    "Female Protagonist", "Female to Male", "Feng Shui", "Firearms", "First Contact",
    "First Love", "First-time Interc**rse", "First-time Intercourse", "Flashbacks", "Fleet Battles",
    "Folklore", "Food Shopkeeper", "Football", "Forced into a Relationship", "Forced Living Arrangements",
    "Forced Marriage", "Forgetful Protagonist", "Forging", "Former Hero", "Found Family",
    "Fourth Disaster", "Fourth Wall", "Fox Spirits", "Friends Become Enemies", "Friendship",
    "Frieren", "From the first POV", "Full Metal Alchemist", "Futanari", "Future Civilization",
    "Futuristic Setting", "Gacha", "Galge", "Gambling", "Game Elements",
    "Game of Thrones", "Game Ranking System", "GameLit", "Gamers", "Gaming/E-Sport",
    "Gandam", "Gangs", "Gate to Another World", "Genderless Protagonist", "Generals",
    "Genetic Modifications", "Genius Protagonist", "Genshin Impact", "Ghosts", "Gintama",
    "Girl's Love Subplot", "Girls Love", "Gladiators", "Glasses-wearing Love Interests", "Glasses-wearing Protagonist",
    "Goblins", "God Protagonist", "God-human Relationship", "Goddesses", "Godly Powers",
    "Gods", "Godzilla", "Golems", "Gore", "Gothic",
    "Grave Keepers", "Grimdark", "Grinding", "Guardian Relationship", "Guilds",
    "Gunfighters", "Hackers", "Half-human Protagonist", "Handjob", "Handsome Male Lead",
    "Hard Sci-fi", "Hard-Working Protagonist", "Harem", "Harem-seeking Protagonist", "Harry Potter",
    "Harsh Training", "Hated Protagonist", "Healers", "Healing", "Heartwarming",
    "Heaven", "Heavenly Tribulation", "Hell", "Helpful Protagonist", "Hentai",
    "Herbalist", "Heroes", "Heterochromia", "Hidden Abilities", "Hidden Gem",
    "Hidden Identity", "Hiding Identity", "Hiding True Abilities", "Hiding True Identity", "High Fantasy",
    "High School DxD", "Highschool of the Dead", "Hikikomori", "Hokage", "Hollywood",
    "Homunculus", "Honest Protagonist", "Hospital", "Hot-blooded Protagonist", "Human Experimentation",
    "Human Weapon", "Human-Nonhuman Relationship", "Humanoid Protagonist", "Hunter X Hunter", "Hunters",
    "Hypnotism", "Identity Crisis", "Imaginary Friend", "Immortals", "Imperial Harem",
    "Incest", "Incubus", "Indecisive Protagonist", "Industrialization", "Inferiority Complex",
    "Infinite Flow", "Inheritance", "Inscriptions", "Insects", "Interconnected Storylines",
    "Interdimensional Travel", "Introverted Protagonist", "Investigations", "Invisibility", "Is It Wrong to Try to Pick Up Girls in a Dungeon",
    "Isekai", "Jack of All Trades", "Jealousy", "Jiangshi", "Jobless Class",
    "JoJo's Bizarre Adventure", "Jujutsu Kaisen", "Kakashi", "Kanojo Okarishimasu", "Karma",
    "Kendo", "Kenichi&#58; The Mightiest Disciple", "Kidnappings", "Kind Love Interests", "Kingdom Building",
    "Kingdoms", "Kingdoms Knights", "Knights", "Knights Level System", "Kung Fu Panda",
    "Kuudere", "Lack of Common Sense", "Language Barrier", "Late Romance", "Lawyers",
    "Lazy Protagonist", "Leadership", "Legacies", "Legends", "Level System",
    "LGBTQA", "Library", "Life Extension System", "Limited Lifespan", "LitRPG",
    "Little Romance", "Livestreaming", "Living Alone", "Loli", "Lolicon",
    "Loneliness", "Loner Protagonist", "Long Separations", "Lord of Mysteries", "Lost Civilizations",
    "Lottery", "Love at First Sight", "Love Interest Falls in Love First", "Love Rivals", "Love Triangles",
    "Lovers Reunited", "Low Fantasy", "Low-key Protagonist", "Loyal Subordinates", "Lucky Protagonist",
    "Mage", "Magic", "Magic Academy", "Magic Beasts", "Magic Formations",
    "Magic Realism", "Magical Girls", "Magical Space", "Magical Technology", "Mahouka Koukou No Rettousei",
    "Maids", "Male Lead", "Male Protagonist", "Male to Female", "Male Yandere",
    "Maleficent", "Management", "Mangaka", "Manipulative Characters", "Manly Gay Couple",
    "Manton Effect", "Marriage", "Marriage of Convenience", "Martial Peak", "Martial Spirits",
    "Marvel", "Masochistic Characters", "Massacre", "Master-Disciple Relationship", "Master-Servant Relationship",
    "Masturbation", "Matriarchy", "Mature Protagonist", "Medical Knowledge", "Medieval",
    "Memory Manipulation", "Mercenaries", "Merchants", "Military", "Mind Break",
    "Mind Control", "Minecraft", "Mismatched Couple", "Mistaken Identity", "Misunderstandings",
    "MMORPG", "Mob Protagonist", "Models", "Modern Day", "Modern Fantasy",
    "Modern Knowledge", "Modern Time", "Modern World", "Money Grubber", "Monster Girls",
    "Monster Society", "Monster Tamer", "Monsters", "Movies", "Mpreg",
    "Multiple CP", "Multiple Identities", "Multiple Lead Characters", "Multiple Personalities", "Multiple POV",
    "Multiple Protagonists", "Multiple Realms", "Multiple Reincarnated Individuals", "Multiple Timelines", "Multiple Transported Individuals",
    "Multiverse", "Murders", "Music", "Mutants", "Mutated Creatures",
    "Mutations", "Mute Character", "My Hero Academia", "My Wife Is A Beautiful CEO", "Mysterious Family Background",
    "Mysterious Illness", "Mysterious Past", "Mystery Solving", "Mythical", "Mythical Beasts",
    "Mythology", "Mythos", "Naive Protagonist", "Narcissistic Protagonist", "Naruto",
    "Nationalism", "Near-Death Experience", "Necromancer", "Neet", "Netorare",
    "Netorase", "Netori", "Nightmares", "Ninjas", "Nobles",
    "Non-Human lead", "Non-human Protagonist", "Non-humanoid Protagonist", "Non-linear Storytelling", "Not Cheats",
    "Not Harem", "Not Netorare", "Not Netori", "Not Pairing", "Not Romance",
    "Not Yaoi", "Not Yuri", "NPC", "Nudity", "Nurses",
    "Obsessive Love", "Office Romance", "Older Love Interests", "Omegaverse", "One Piece",
    "One-Punch Man", "Oneshot", "Online Romance", "Onmyouji", "Orcs",
    "Organized Crime", "Orgy", "Orphans", "Otaku", "Otome Game",
    "Outcasts", "Outdoor Intercourse", "Outer Space", "Overlord", "Overpowered Protagonist",
    "Overprotective Siblings", "Pacifist Protagonist", "Paizuri", "Parallel Worlds", "Parasites",
    "Parent Complex", "Parody", "Part-Time Job", "Past Plays a Big Role", "Past Trauma",
    "Persistent Love Interests", "Personality Changes", "Perverted Protagonist", "Pets", "Pharmacist",
    "Philosophical", "Phobias", "Phoenixes", "Photography", "Pill Based Cultivation",
    "Pill Concocting", "Pilots", "Pirates", "Planets", "Playboys",
    "Playful Protagonist", "Poetry", "Poisons", "Pokemon", "Police",
    "Polite Protagonist", "Political Systems", "Politics", "Polyandry", "Polygamy",
    "Poor Protagonist", "Poor to Rich", "Popular Love Interests", "Portal Fantasy", "Possession",
    "Possessive Characters", "Post-apocalyptic", "Power Couple", "Power Struggle", "Pragmatic Protagonist",
    "Precognition", "Pregnancy", "Pretend Lovers", "Previous Life", "Previous Life Talent",
    "Priestesses", "Priests", "Prison", "Proactive Protagonist", "Programmer",
    "Progression", "Progression Fantasy", "Prophecies", "Prostit**es", "Prostitutes",
    "Protagonist Falls in Love First", "Protagonist Loyal to Love Interest", "Protagonist NPC", "Protagonist Strong from the Start", "Protagonist with Multiple Bodies",
    "Pseudo Holographic Game", "Pseudo Religions", "Psychic Powers", "Psychopaths", "PUBG",
    "Puppeteers", "Quick Transmigration", "Quiet Characters", "Quirky Characters", "R-15",
    "R-18", "Race Change", "Races", "Racism", "Raids",
    "Rank System", "Rape", "Rape Victim Becomes Lover", "Reader Interactive", "RealRPG",
    "Rebellion", "Rebirth", "Record of Ragnarok", "Reincarnated as a Monster", "Reincarnated as an Object",
    "Reincarnated in a Game World", "Reincarnated in Another World", "Reincarnation", "Religions", "Reluctant Protagonist",
    "Reporters", "Resident Evil", "Resolute Protagonist", "Restaurant", "Resurrection",
    "Return of the Dragon King", "Returning from Another World", "Revenge", "Reverse Harem", "Reverse Rape",
    "Reversible Couple", "Rich Protagonist", "Rich to Poor", "Righteous Protagonist", "Rivalry",
    "Romance", "Romantic Subplot", "Roommates", "Royalty", "RPG",
    "Ruling Class", "Ruthless Protagonist", "RWBY", "S*aves", "Sadistic Characters",
    "Saints", "Salaryman", "Samurai", "Satire", "Saving the World",
    "Schemes And Conspiracies", "Scheming", "Scheming Protagonist", "Schizophrenia", "Sci-Fantasy",
    "Scientists", "SCP", "Sculptors", "Sealed Power", "Second Chance",
    "Secret Crush", "Secret Identity", "Secret Organizations", "Secret Relationship", "Secretive Protagonist",
    "Secrets", "Sect Development", "Sects", "Seduction", "Seeing Things Other Humans Can't",
    "Selfish Protagonist", "Selfless Protagonist", "Seme Protagonist", "Senpai-Kouhai Relationship", "Sentient Objects",
    "Sentimental Protagonist", "Serial Killers", "Servants", "Seven Deadly Sins", "Seven Virtues",
    "Sex Friends", "Sex Slaves", "Sexual Abuse", "Sexual Cultivation Technique", "Shameless Protagonist",
    "Shapeshifters", "Sharing A Body", "Sharp-tongued Characters", "Shield User", "Shikigami",
    "Shinmai Mao no Tastement", "Short Story", "Shota", "Shotacon", "Shoujo-Ai Subplot",
    "Shounen-Ai Subplot", "Showbiz", "Shy Characters", "Sibling Rivalry", "Sibling's Care",
    "Siblings", "Siblings Not Related by Blood", "Sickly Characters", "Sign Language", "Simulation",
    "Singers", "Single Parent", "Sister Complex", "Skill Assimilation", "Skill Books",
    "Skill Creation", "Skyrim", "Slave Harem", "Slave Protagonist", "Slaves",
    "Sleeping", "Sleeping Beauty", "Slow Cultivation", "Slow Growth at Start", "Slow Romance",
    "Smart Couple", "Social Outcasts", "Soft Sci-fi", "Soldiers", "Solo Leveling",
    "Soul Power", "Souls", "Sound Magic", "Space", "Space Opera",
    "Spaceship", "Spatial Manipulation", "Spear Wielder", "Special Abilities", "Spies",
    "Spirit Advisor", "Spirit Users", "Spirits", "Sports Basketball", "Stalkers",
    "Star Trek", "Star Wars", "Steampunk", "Stockholm Syndrome", "Stoic Characters",
    "Store Owner", "Straight Uke", "Strategic Battles", "Strategist", "Strategy",
    "Strength-based Social Hierarchy", "Strong Lead", "Strong Love Interests", "Strong to Stronger", "Stubborn Protagonist",
    "Student Council", "Student-Teacher Relationship", "Subtle Romance", "Succubus", "Sudden Strength Gain",
    "Sudden Wealth", "Suicides", "Summoned Hero", "Summoning Magic", "Super Heroes",
    "Superpowers", "Survival", "Survival Game", "Sword And Magic", "Sword Wielder",
    "System", "System Administration", "System Administrator", "Talent", "Talent Prophecies",
    "Tales of\194\160Demons and Gods", "Teachers", "Teamwork", "Technological Gap", "Tentacles",
    "Terminal Illness", "Territory Management", "Terrorists", "The Asterisk War", "The Devil Is a Part-Timer",
    "The Gamer", "The Modern world", "The Pet Girl of Sakurasou", "The Witcher", "The Wizard of Oz",
    "Thieves", "Threesome", "Thriller", "Time Loop", "Time Manipulation",
    "Time Paradox", "Time Skip", "Time Travel", "Timid Protagonist", "Titans",
    "Tokyo Ghoul", "Tomboyish Female Lead", "Torture", "Tower Climbing", "Toys",
    "Tragic Past", "Transformation Ability", "Transgender", "Transmigration", "Transplanted Memories",
    "Transported into a Game World", "Transported Modern Structure", "Transported to Another World", "Trap", "Travel Between Worlds",
    "Tree Protagonist", "Tribal Society", "Trickster", "Trolls", "Tsundere",
    "Twins", "Twisted Personality", "Type-Moon", "Ugly Protagonist", "Ugly to Beautiful",
    "Unconditional Love", "Undead", "Underestimated Protagonist", "Unique Cultivation Technique", "Unique Weapon User",
    "Unique Weapons", "Unlimited Flow", "Unlucky Protagonist", "Unreliable Narrator", "Unrequited Love",
    "Urban", "Urban Fantasy", "Urban Life", "Valkyries", "Vampires",
    "Villain", "Villainess Noble Girls", "Virtual Reality", "Vocaloid", "Voice Actors",
    "Voyeurism", "War Records", "Warcraft", "Warhammer", "Warhammer 40K",
    "Warlock of The Magus World", "Wars", "Weak Protagonist", "Weak to Strong", "Wealthy Characters",
    "Webnovel Spirity Awards", "Werebeasts", "Westernization", "Wishes", "Witches",
    "Wizards", "World Building", "World Hopping", "World Invasion", "World Travel",
    "World Tree", "Writers", "X-men", "Yandere", "Youkai",
    "Younger Brothers", "Younger Love Interests", "Younger Sisters", "Zombies",
}

local function optionList(values, labels)
    local out = {}
    for _, v in ipairs(values) do
        table.insert(out, { value = v, label = (labels and labels[v]) or v })
    end
    return out
end

function getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Sort results",
            defaultValue = DEFAULT_SORT,
            options = {
                { value = "date;desc",        label = "New novels"                   },
                { value = "editdate;desc",    label = "New modified"                 },
                { value = "rating",           label = "Rating"                       },
                { value = "rating_only;desc", label = "Rating: score only"           },
                { value = "title;asc",        label = "Title (A-Z)"                  },
                { value = "date;asc",         label = "Old novels"                   },
                { value = "news_read;desc",   label = "Views: most → least"          },
                { value = "news_read;asc",    label = "Views: least → most"          },
                { value = "comm_num;desc",    label = "Comments: more → less"        },
                { value = "comm_num;asc",     label = "Comments: less → more"        },
                { value = "d.chap-num;desc",  label = "Chapters: more → less"        },
                { value = "d.chap-num;asc",   label = "Chapters: less → more"        },
                { value = "d.year;desc",      label = "Year: new → old"              },
                { value = "d.year;asc",       label = "Year: old → new"              },
            }
        },
        { type = "text", key = "title", label = "Novel title must contain", defaultValue = "" },
        {
            type    = "tristate",
            key     = "genre",
            label   = "Genres",
            options = optionList(GENRES)
        },
        {
            type  = "tristate",
            key   = "languages",
            label = "Original language",
            options = {
                { value = "Chinese",  label = "Chinese"  },
                { value = "Korean",   label = "Korean"   },
                { value = "English",  label = "English"  },
                { value = "Japanese", label = "Japanese" },
            }
        },
        {
            type         = "select",
            key          = "status_end",
            label        = "Status in original",
            defaultValue = "",
            options = {
                { value = "",          label = "Any"       },
                { value = "Ongoing",   label = "Ongoing"   },
                { value = "Completed", label = "Completed" },
                { value = "Hiatus",    label = "Hiatus"    },
                { value = "Dropped",   label = "Dropped"   },
            }
        },
        {
            type         = "select",
            key          = "status_trs",
            label        = "Translation status",
            defaultValue = "",
            options = {
                { value = "",          label = "Any"       },
                { value = "Active",    label = "Active"    },
                { value = "Completed", label = "Completed" },
                { value = "Unknown",   label = "Unknown"   },
                { value = "Break",     label = "Break"     },
            }
        },
        { type = "text", key = "chap_min", label = "Minimum chapters",     defaultValue = "" },
        { type = "text", key = "chap_max", label = "Maximum chapters",     defaultValue = "" },
        { type = "text", key = "year_min", label = "Year of release from", defaultValue = "" },
        { type = "text", key = "year_max", label = "Year of release up to", defaultValue = "" },
        { type = "switch", key = "only_tl",    label = "Only TL (human translation)", defaultValue = false },
        { type = "switch", key = "mtl_files",  label = "MTL files",                    defaultValue = false },
        { type = "switch", key = "mtl_reader", label = "MTL reader",                   defaultValue = false },
        {
            type    = "tristate",
            key     = "events",
            label   = "Tags",
            options = optionList(TAGS, TAG_LABELS)
        },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1

    local function num(key)
        local v = string_trim(tostring(filters[key] or ""))
        if v:match("^%d+$") then return v end
        return ""
    end
    local function flag(key)
        return (filters[key] == "true") and "1" or ""
    end
    local function pick(key)
        local v = string_trim(tostring(filters[key] or ""))
        if v:match("^[%w%-]+$") then return v end
        return ""
    end

    local title = string_trim(tostring(filters["title"] or ""))

    -- Orden alfabético de claves, igual que las URLs del sitio
    local specs = {
        { "b.languages",  csv(filters["languages_included"]) },
        { "f.chap-num",   num("chap_min") },
        { "f.year",       num("year_min") },
        { "g.mtl-files",  flag("mtl_files") },
        { "g.mtl_reader", flag("mtl_reader") },
        { "g.translater", flag("only_tl") },
        { "l.title",      title ~= "" and enc(title) or "" },
        { "n.events",     csv(filters["events_included"]) },
        { "n.genre",      csv(filters["genre_included"]) },
        { "status-end",   pick("status_end") },
        { "status-trs",   pick("status_trs") },
        { "t.chap-num",   num("chap_max") },
        { "t.year",       num("year_max") },
        { "v.events",     csv(filters["events_excluded"]) },
        { "v.genre",      csv(filters["genre_excluded"]) },
        { "v.languages",  csv(filters["languages_excluded"]) },
    }

    beginCall()
    local url = buildFilterUrl(specs, filters["sort"] or DEFAULT_SORT, page)
    local res = fetchList(url, parseArticles)
    finishCall()
    return res
end
