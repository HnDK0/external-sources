id       = "rewayatclub"
name     = "Rewayat Club"
version  = "1.0.0"
baseUrl  = "https://api.rewayat.club/"
language = "ar"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/rewayatclub.png"

-- Сайт работает через отдельный DRF JSON API (https://api.rewayat.club).
-- HTML-страницы — Nuxt-приложение с клиентским рендерингом, поэтому весь
-- парсинг ведём по API, а не по HTML.
--
-- ВНИМАНИЕ: baseUrl намеренно = api.rewayat.club, а не rewayat.club.
-- Движок сопоставляет источник по совпадению хоста baseUrl и хоста адресов
-- книги/главы (лог устройства: source matched только при обоих хостах =
-- api.rewayat.club). Сайт-слаг человеческих страниц (rewayat.club/novel/<slug>)
-- ОТЛИЧАЕТСЯ от API-слага и не возвращается из API нигде, поэтому плагин
-- физически не может построить читабельный адрес сайта для webviewer'а.
-- Не переключай baseUrl на rewayat.club и не правь адреса книг/глав — это
-- сломает сопоставление источника или даст 404. Чтение на устройстве работает.

local _api = "https://api.rewayat.club/api/"

-- Кэш деталей книги (движок вызывает функции деталей параллельно с одним URL).
local _bookCache = {}

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Обложка приходит относительной (/media/...), префиксим её полным хостом API.
local function coverUrl(poster)
    if not poster or poster == "" then return nil end
    if string_starts_with(poster, "http") then return poster end
    return "https://api.rewayat.club" .. poster
end

-- GET JSON-эндпоинт, возвращает распарсенную таблицу или nil.
local function apiGet(url)
    local r = http_get(url)
    if not r.success then
        log_error("rewayatclub: http_get failed " .. url)
        return nil
    end
    local ok, data = pcall(json_parse, r.body)
    if not ok or not data then
        log_error("rewayatclub: json_parse failed " .. url)
        return nil
    end
    return data
end

-- Детали книги с кэшем (ключ — сам URL API-детали = bookUrl).
local function bookDetails(bookUrl)
    if _bookCache[bookUrl] then return _bookCache[bookUrl] end
    local data = apiGet(bookUrl)
    if data then _bookCache[bookUrl] = data end
    return data
end

-- Строит запрос списка новелл с фильтрами.
local function browseUrl(page, sort, ftype, query)
    local url = _api .. "novels/?type=" .. (ftype or "0")
        .. "&ordering=" .. (sort or "-num_chapters")
        .. "&page=" .. page
    if query and query ~= "" then
        url = url .. "&search=" .. url_encode(query)
    end
    return url
end

-- Общий парсер ответа списка новелл (каталог/поиск/фильтры).
local function parseNovels(url)
    local data = apiGet(url)
    if not data or not data.results then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, n in ipairs(data.results) do
        local slug = n.slug
        if slug and slug ~= "" then
            table.insert(items, {
                title = n.arabic or n.english or "",
                url   = _api .. "novels/" .. slug .. "/",
                cover = coverUrl(n.poster_url)
            })
        end
    end
    -- DRF отдаёт null в `next` на последней странице.
    local hasNext = data.next ~= nil and data.next ~= false
    return { items = items, hasNext = hasNext }
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
    return parseNovels(browseUrl(index + 1, "-num_chapters", "0", nil))
end

function getCatalogSearch(index, query)
    return parseNovels(browseUrl(index + 1, "-num_chapters", "0", query))
end

-- ── Фильтры ───────────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "type",
            label        = "Category",
            defaultValue = "0",
            options = {
                { value = "0", label = "All"             },
                { value = "1", label = "Translated"      },
                { value = "2", label = "Original"        },
                { value = "3", label = "Completed"       },
            }
        },
        {
            type         = "select",
            key          = "sort",
            label        = "Sort by",
            defaultValue = "-num_chapters",
            options = {
                { value = "-num_chapters", label = "Most Chapters" },
                { value = "num_chapters",  label = "Fewest Chapters" },
                { value = "-english",      label = "Title (Z-A)" },
                { value = "english",       label = "Title (A-Z)" },
            }
        },
    }
end

function getCatalogFiltered(index, filters)
    local page  = index + 1
    local ftype = filters["type"] or "0"
    local sort  = filters["sort"] or "-num_chapters"
    return parseNovels(browseUrl(page, sort, ftype, nil))
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local d = bookDetails(bookUrl)
    return d and (d.arabic or d.english) or nil
end

function getBookCoverImageUrl(bookUrl)
    local d = bookDetails(bookUrl)
    return d and coverUrl(d.poster_url) or nil
end

function getBookDescription(bookUrl)
    local d = bookDetails(bookUrl)
    return d and d.about or nil
end

function getBookGenres(bookUrl)
    local d = bookDetails(bookUrl)
    if not d or not d.genre then return nil end
    local out = {}
    for _, g in ipairs(d.genre) do
        local name = g.arabic or g.english
        if name and name ~= "" then table.insert(out, name) end
    end
    return #out > 0 and out or nil
end

function getBookStatus(bookUrl)
    local d = bookDetails(bookUrl)
    if not d or not d.get_novel_status then return nil end
    local s = d.get_novel_status
    if s == "مستمرة"  then return "Ongoing"   end
    if s == "مكتملة"  then return "Completed" end
    if s == "متوقفة"  then return "On Hiatus" end
    if s == "مجمدة"   then return "On Hiatus" end
    return s
end

-- ── Список глав (parsePage, постраничная догрузка движком) ────────────────────
--
-- Сервер генерирует /api/chapters/ медленно и время растёт с page_size
-- (page_size=10000 ~8с и не влезает в таймаут устройства, а параллельный
-- http_get_batch ронял часть страниц). Движок этой читалки умеет постранично
-- догружать список через parsePage — каждая страница = один последовательный
-- запрос (лениво, без батча и без потери глав).

function parsePage(bookUrl, page)
    local slug = (bookUrl or ""):match("novels/([^/]+)")
    if not slug then return { chapters = {}, totalPages = 1 } end
    local pageSize = 200  -- page_size>200 уже таймаутится на устройстве (логи: при 300 страница 4 падала с SocketTimeoutException)
    local data = apiGet(_api .. "chapters/" .. slug
        .. "/?ordering=number&page_size=" .. pageSize .. "&page=" .. tostring(page))
    if not data or not data.results then return { chapters = {}, totalPages = 1 } end

    -- API отдаёт главы по возрастанию номера, поэтому страница сайта = page.
    local count = tonumber(data.count or 0)
    local totalPages = math.max(1, math.floor((count + pageSize - 1) / pageSize))

    local chapters = {}
    for _, ch in ipairs(data.results) do
        local num = tostring(ch.number or "")
        local title = ch.title or ""
        if title == "" then title = num
        else title = num .. " - " .. title end
        table.insert(chapters, {
            title = title,
            url   = _api .. "chapters/" .. slug .. "/" .. num
        })
    end

    return { chapters = chapters, totalPages = totalPages }
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
    -- Движок этой читалки сам парсит JSON ответа и передаёт сюда уже таблицу.
    -- Поддерживаем оба варианта: html/url могут быть и строкой, и таблицей.
    local data = nil
    local function toData(v)
        if not v then return nil end
        if type(v) == "table" then return v end
        if type(v) == "string" and string_trim(v) ~= "" then
            local ok, val = pcall(json_parse, v)
            if ok and val then return val end
        end
        return nil
    end
    -- Движок передаёт тело в первом аргументе (getChapterText body-паттерн),
    -- но в этой читалке содержимое главы может прийти и как url (apiGet урки уже таблица).
    if not data then data = toData(html) end
    if not data and url and url ~= "" then
        data = toData(url)
        -- Если url — строка (сырой URL), а не тело — догружаем по нему.
        if not data then data = apiGet(url) end
    end
    if not data or not data.content then return "" end

    -- content = список блоков; каждый блок = список <p>-фрагментов.
    -- Каждый непустой <p>-фрагмент — ОДИН отдельный абзац (пустые <p><br/>
    -- — разделители, их пропускаем). Так текст выходит чистым, без двойных
    -- пустых строк и мусорных промежутков от склеивания всего блока в кучу.
    local paras = {}
    for _, block in ipairs(data.content) do
        if type(block) == "table" then
            for _, frag in ipairs(block) do
                local s = (type(frag) == "string") and frag or ""
                s = s:gsub("<p>", "")
                s = s:gsub("<br%s*/?>", "")
                s = s:gsub("<[^>]+>", "")
                s = s:gsub("&nbsp;", " ")
                if s:gsub("%s", "") ~= "" then
                    table.insert(paras, string_trim(s))
                end
            end
        elseif type(block) == "string" then
            local s = block:gsub("&nbsp;", " ")
            if s:gsub("%s", "") ~= "" then
                table.insert(paras, string_trim(s))
            end
        end
    end
    local text = table.concat(paras, "\n\n")
    text = string_normalize(text)
    return string_trim(text)
end
