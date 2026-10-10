-- M440.in plugin for NoveLA
-- Испанский манга-сайт: каталог/книги через HTML, поиск через JSON API,
-- главы — постраничные изображения (content_type = "manga").

id       = "m440in"
name     = "M440"
version  = "1.1.0"
baseUrl  = "https://m440.in"
language = "es"
content_type = "manga"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/m440in.png"

-- GUARD: старые сборки приложения без движковых API (md5/aes_decrypt).
-- Вызывается из каждой публичной функции; show_error в проде асинхронный,
-- поэтому после него идёт error(..., 0) — адаптер отдаёт pending-show-error.
local function ensureEngine()
    local missing = {}
    if rawget(_G, "md5") == nil then missing[#missing + 1] = "md5" end
    if rawget(_G, "aes_decrypt") == nil then missing[#missing + 1] = "aes_decrypt" end
    if #missing > 0 then
        show_error("Se requiere actualizar NoveLA",
            "Este complemento necesita funciones nuevas (" .. table.concat(missing, ", ") ..
            "). Actualice la aplicación a la última versión.")
        error("Se requiere una versión más reciente de la aplicación: " .. table.concat(missing, ","), 0)
    end
end

-- ── Хелперы ──

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

local function getSlug(bookUrl)
    return string.match(bookUrl, "/manga/([^/]+)")
end

-- Достаёт последний номер страницы из .pagination (ссылка на последнюю страницу
-- — предпоследний элемент списка; последний — «»/след.стр.).
local function getTotalPages(body)
    local el = html_select_first(body, ".pagination li:nth-last-child(2) a")
    local n = el and tonumber(string_clean(el.text))
    return n or 1
end

-- Парсер карточек каталога (.col-sm-6 .media) — общий для каталога и фильтров.
local function parseCatalogItems(body)
    local items = {}
    for _, card in ipairs(html_select(body, ".col-sm-6 .media")) do
        local url = html_attr(card.html, ".media-left a.thumbnail", "href")
        local title = html_attr(card.html, "a.chart-title", "title")
        if title == "" then
            local t = html_select_first(card.html, ".media-heading a")
            if t then title = string_clean(t.text) end
        end
        if url ~= "" and title ~= "" then
            table.insert(items, {
                title  = string_clean(title),
                url    = absUrl(url),
                cover  = absUrl(html_attr(card.html, ".media-left img", "src")),
                rating = html_select_first(card.html, ".label-info") and
                         string_clean(html_select_first(card.html, ".label-info").text) or nil,
            })
        end
    end
    return items
end

-- ── Крипто: расшифровка списка глав (как в exis.js) ─────────────────────────
-- Сайт шифрует JSON список глав: в HTML есть блоб UsaPoncho (JSON {ct, iv, s}),
-- exis.js на клиенте делает CryptoJS.AES.decrypt(UsaPoncho, ReturnStrg(), {format:
-- CryptoJSAesJson}) → двойной JSON (строка, внутри массив глав). Расшифровка —
-- движковые API: md5 (EvpKDF → key 32B + iv 16B) и aes_decrypt (AES-256-CBC/
-- PKCS5, key/iv — сырые байты после фикса B4). Инлайновый Lua-стек (SBOX/
-- арифметический AES и сам MD5) удалён.

local M440_PASSPHRASE = "X^Ib1O*HLVh%3W2t"  -- из exis.js: ReturnStrg()

local function fromHex(s)
    return (s:gsub("%x%x", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- EvpKDF (OpenSSL EVP_BytesToKey, MD5, 1 iter) → key 32B, iv 16B
local function evpKdf(pass, salt)
    local keyPart = ""
    local prev = ""
    while #keyPart < 48 do
        prev = md5(prev .. pass .. salt)
        keyPart = keyPart .. prev
    end
    return keyPart:sub(1, 32), keyPart:sub(33, 48)
end

-- Достаёт JS-строку UsaPoncho из HTML и снимает экранирование (\" \\ \/)
local function extractUsaPoncho(body)
    local s = string.find(body, "UsaPoncho%s*=%s*\"")
    if not s then return nil end
    local start = string.find(body, "\"", s)
    local out, i = {}, start + 1
    while i <= #body do
        local c = body:sub(i, i)
        if c == "\\" then
            out[#out + 1] = body:sub(i + 1, i + 1)
            i = i + 2
        elseif c == '"' then
            break
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Расшифровывает UsaPoncho → массив глав (или nil)
local function decryptChapters(body)
    local jsonText = extractUsaPoncho(body)
    if not jsonText then return nil end
    local ok, poncho = pcall(json_parse, jsonText)
    if not ok or type(poncho) ~= "table" or not poncho.ct then return nil end
    local salt = fromHex(poncho.s or "")
    local key, iv = evpKdf(M440_PASSPHRASE, salt)
    -- aes_decrypt(b64, key, iv): base64 шифротекста декодирует движок,
    -- key/iv — сырые байты из EvpKDF (бинарный режим после фикса B4).
    -- Любой отказ шифра → nil → ниже возврат nil и JS-fallback в parseChapters.
    local pt = aes_decrypt(poncho.ct, key, iv)
    if not pt or pt == "" then return nil end
    -- двойной JSON: plaintext = JSON-строка, внутри массив глав
    local ok1, s1 = pcall(json_parse, pt)
    if not ok1 or type(s1) ~= "string" then return nil end
    local ok2, data = pcall(json_parse, s1)
    if not ok2 or type(data) ~= "table" then return nil end
    local out = {}
    for k = #data, 1, -1 do
        local ch = data[k]
        local vol = ch.volume or ""
        if vol == "0" or vol == "" then vol = nil end
        table.insert(out, {
            title = "#" .. ch.number .. " " .. string_clean(ch.name or ""),
            url   = "",
            volume = vol and ("Vol. " .. vol) or nil,
            id     = tostring(ch.id),
            slug   = ch.slug,
            created_at = tostring(ch.created_at or ""),
        })
    end
    return out
end

-- Ищет на странице книги список глав. Основной путь — расшифровка UsaPoncho
-- (AES, как делает exis.js). Запасной путь — открытый JS-массив
-- var/let/const NAME = [...]. Поля: id, slug, name, number, volume, created_at.
-- Порядок на сайте — DESC (новые сверху), возвращаем хронологический.
local function parseChapters(body)
    local dec = decryptChapters(body)
    if dec and #dec > 0 then return dec end
    local patterns = {
        "var%s+%w+%s*=%s*%[",
        "let%s+%w+%s*=%s*%[",
        "const%s+%w+%s*=%s*%[",
        "jschaptertemp%s*=%s*%[",  -- window.jschaptertemp / без var — тоже
    }
    for _, pat in ipairs(patterns) do
        local pos = 1
        while true do
            local s, e = string.find(body, pat, pos)
            if not s then break end
            -- Находим парную закрывающую скобку (учёт вложенности)
            local depth, i = 0, e
            while i <= #body do
                local c = body:sub(i, i)
                if c == "[" then depth = depth + 1
                elseif c == "]" then
                    depth = depth - 1
                    if depth == 0 then break end
                end
                i = i + 1
            end
            pos = i
            if depth ~= 0 then break end
            local ok, data = pcall(json_parse, body:sub(e, i - 1))
            if ok and type(data) == "table" and data[1]
               and data[1].slug and data[1].number then
                local out = {}
                for k = #data, 1, -1 do
                    local ch = data[k]
                    local vol = ch.volume or ""
                    if vol == "0" or vol == "" then vol = nil end
                    table.insert(out, {
                        title = "#" .. ch.number .. " " .. string_clean(ch.name or ""),
                        url   = "",
                        volume = vol and ("Vol. " .. vol) or nil,
                        id     = tostring(ch.id),
                        slug   = ch.slug,
                        created_at = tostring(ch.created_at or ""),
                    })
                end
                return out
            end
        end
    end
    return nil
end

-- ── Каталог ──

function getCatalogList(index)
    ensureEngine()
    local page = (index or 0) + 1
    local r = http_get(baseUrl .. "/manga-list?page=" .. page)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = page < getTotalPages(r.body) }
end

function getCatalogSearch(index, query)
    ensureEngine()
    if index > 0 then return { items = {}, hasNext = false } end
    local r = http_get(baseUrl .. "/search?q=" .. url_encode(query))
    if not r.success then return { items = {}, hasNext = false } end
    local data = json_parse(r.body)
    if type(data) ~= "table" then return { items = {}, hasNext = false } end

    local items = {}
    for _, m in ipairs(data) do
        local title = m.value or ""
        local slug = m.data or ""
        if title ~= "" and slug ~= "" then
            table.insert(items, {
                title = string_clean(title),
                url   = baseUrl .. "/manga/" .. slug,
                cover = absUrl(html_attr(m.label or "", "img", "src")),
            })
        end
    end
    return { items = items, hasNext = false }
end

function getFilterList()
    ensureEngine()
    local cats = {
        { value = "1",  label = "Action" },          { value = "2",  label = "Adventure" },
        { value = "3",  label = "Comedy" },          { value = "4",  label = "Doujinshi" },
        { value = "5",  label = "Drama" },           { value = "6",  label = "Ecchi" },
        { value = "7",  label = "Fantasy" },         { value = "8",  label = "Gender Bender" },
        { value = "9",  label = "Harem" },           { value = "10", label = "Historical" },
        { value = "11", label = "Horror" },          { value = "12", label = "Josei" },
        { value = "13", label = "Martial Arts" },    { value = "14", label = "Mature" },
        { value = "15", label = "Mecha" },           { value = "16", label = "Mystery" },
        { value = "17", label = "One Shot" },        { value = "18", label = "Psychological" },
        { value = "19", label = "Romance" },         { value = "20", label = "School Life" },
        { value = "21", label = "Sci-fi" },          { value = "22", label = "Seinen" },
        { value = "23", label = "Shoujo" },          { value = "24", label = "Shoujo Ai" },
        { value = "25", label = "Shounen" },         { value = "26", label = "Shounen Ai" },
        { value = "27", label = "Slice of Life" },   { value = "28", label = "Sports" },
        { value = "29", label = "Supernatural" },    { value = "30", label = "Tragedy" },
        { value = "31", label = "Yaoi" },            { value = "32", label = "Yuri" },
        { value = "33", label = "Hentai" },          { value = "34", label = "Smut" },
    }
    local alpha = {}
    for _, ch in ipairs({ "A","B","C","D","E","F","G","H","I","J","K","L","M",
                          "N","O","P","Q","R","S","T","U","V","W","X","Y","Z" }) do
        table.insert(alpha, { value = ch, label = ch })
    end
    table.insert(alpha, { value = "Other", label = "Other" })

    return {
        { type = "select", key = "sortBy", label = "Sort By", defaultValue = "name",
          options = {
              { value = "name",       label = "Name (A-Z)" },
              { value = "views",      label = "Most Viewed" },
              { value = "updated_at", label = "Last Updated" },
              { value = "created_at", label = "Newest" },
          } },
        { type = "checkbox", key = "cat", label = "Categories", options = cats },
        { type = "select", key = "alpha", label = "Alphabet", defaultValue = "A",
          options = alpha },
        { type = "text", key = "author", label = "Author", defaultValue = "" },
        { type = "text", key = "tag", label = "Tag", defaultValue = "" },
        { type = "text", key = "artist", label = "Artist", defaultValue = "" },
    }
end

function getCatalogFiltered(index, filters)
    ensureEngine()
    local page = (index or 0) + 1
    local sortBy = filters["sortBy"] or "name"
    local asc    = filters["sortBy_ascending"] or "true"

    local url = baseUrl .. "/filterList?page=" .. page
        .. "&sortBy=" .. url_encode(sortBy) .. "&asc=" .. asc

    local cats = filters["cat_included"] or {}
    for _, v in ipairs(cats) do url = url .. "&cat=" .. url_encode(v) end

    local alpha = filters["alpha"] or ""
    if alpha ~= "" then url = url .. "&alpha=" .. url_encode(alpha) end
    for _, k in ipairs({ "author", "tag", "artist" }) do
        local v = filters[k] or ""
        if v ~= "" then url = url .. "&" .. k .. "=" .. url_encode(v) end
    end

    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseCatalogItems(r.body)
    return { items = items, hasNext = page < getTotalPages(r.body) }
end

-- ── Страница книги ──

function getBookTitle(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h2.widget-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img[src*='cover']", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".well")
    if el then
        local parts = {}
        for _, p in ipairs(html_select(el.html, "p")) do
            local t = string_trim(p.text)
            if t ~= "" then table.insert(parts, t) end
        end
        if #parts > 0 then return table.concat(parts, "\n") end
    end
    local meta = html_attr(body, "meta[name='description']", "content")
    if meta ~= "" then return string_trim(meta) end
    return nil
end

function getBookGenres(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, "a[href*='/manga-list/category/']")) do
        local label = string_trim(a.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

function getBookStatus(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".label-danger")
    return el and string_clean(el.text) or nil
end

function getBookRating(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local n = string.match(body, "Rating:%s*([%d%.]+)")
    return n or nil
end

function getBookLastUpdate(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local chapters = parseChapters(body)
    if not chapters or #chapters == 0 then return nil end
    -- Новейшая глава — последняя в хронологическом порядке
    local newest = chapters[#chapters]
    local y, m, d = string.match(newest.created_at or "", "(%d%d%d%d)%-(%d%d)%-(%d%d)")
    return y and (y .. "-" .. m .. "-" .. d) or nil
end

-- ── Главы ──

function getChapterList(bookUrl)
    ensureEngine()
    local body = fetchPage(bookUrl)
    if not body then return {} end

    local slug = getSlug(bookUrl)
    local chapters = parseChapters(body)
    if chapters then
        for i, ch in ipairs(chapters) do
            ch.url = absUrl(baseUrl .. "/manga/" .. slug .. "/" .. ch.slug)
            ch.slug = nil
            ch.created_at = nil
            ch.id = nil
        end
        return chapters
    end

    -- Fallback: парсинг DOM по ссылкам на /manga/{slug}/{chapter}
    local out, seen = {}, {}
    for _, a in ipairs(html_select(body, 'a[href*="/manga/' .. slug .. '/"]')) do
        local href = a.href or ""
        if href:match("/manga/" .. slug .. "/[^/]+$") and not seen[href] then
            seen[href] = true
            table.insert(out, { title = string_clean(a.text), url = absUrl(href) })
        end
    end
    -- DOM тоже DESC — разворачиваем в хронологический
    local rev = {}
    for i = #out, 1, -1 do table.insert(rev, out[i]) end
    return rev
end

function getChapterListHash(bookUrl)
    ensureEngine()
    -- Всегда прямой http_get (не fetchPage): кэш даст устаревший хэш
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local chapters = parseChapters(r.body)
    if not chapters or #chapters == 0 then return nil end
    local newest = chapters[#chapters]
    return newest.slug .. "|" .. newest.created_at
end

-- Глава: все картинки страниц лежат в одном HTML в data-src читалки
-- (img[data-src*='chapters/'], порядок = порядок страниц). Один запрос.
function getPageList(html, url)
    ensureEngine()
    local body = html
    if not body or body == "" then
        local r = http_get(url)
        if not r.success then return {} end
        body = r.body
    end

    local pages, seen = {}, {}
    for _, img in ipairs(html_select(body, "img[data-src*='chapters/']")) do
        local src = img:attr("data-src")
        src = absUrl(src)
        if src ~= "" and not seen[src] then
            seen[src] = true
            table.insert(pages, src)
        end
    end
    return pages
end

function getChapterText(html, url)
    ensureEngine()
    return ""  -- манга: картинки через getPageList
end