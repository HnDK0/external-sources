--[[
  kolnovel.lua — ملوك الروايات «Kolnovel» (Kings of Novels)
  Арабские переводы зарубежных (китайских/корейских/японских) веб- и лайт-новелл.

  Движок: WordPress + тема «Shola» (Sora/LightNovel reader).
  Список глав лежит прямо на странице серии в div.eplister, а текст главы —
  в #kol_content на странице чтения главы (у каждой главы есть и PDF-версия
  /pdf/, которую мы не используем).
]]

id       = "kolnovel"
name     = "KOLNOVEL"
version  = "1.0.0"
baseUrl  = "https://kolnovel.com"
language = "ar"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/kolnovel.png"

-- ── Хелперы ───────────────────────────────────────────────────────────────

local _catalogRatings = {}  -- рейтинг из карточек каталога/поиска (span.mdminf):
                            -- страница книги отдаёт неверный рейтинг (0.0/5),
                            -- поэтому для getBookRating берём только кэш карточек

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- Приложение нормализует URL книги (срезает trailing slash) перед вызовом
-- функций деталей; повторяем это для ключей кеша, иначе getBookRating ищет
-- в кеше ключ без слэша и не находит `.../overlord/`.
local function normUrl(u)
    return u:gsub("/+$", "")
end

-- Кэш страницы книги: движок вызывает функции деталей книги параллельно,
-- поэтому один загруженный ответ делим между ними (паттерн fetchPage из гайда).
local _pageCache = {}
local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then _pageCache[url] = r.body end
    return r.success and r.body or nil
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    text = string_trim(text)
    return text
end

-- Парсер карточек каталога и поиска (article.maindet). Рейтинг — из span.mdminf.
local function parseCatalogItems(body, wantCover)
    local items = {}
    for _, card in ipairs(html_select(body, "article.maindet")) do
        local titleEl = html_select_first(card.html, ".mdinfo h2 a")
        if titleEl then
            local bookUrl = absUrl(titleEl.href)
            local title   = string_clean(titleEl.text)
            if bookUrl ~= "" and title ~= "" then
                local item = { title = title, url = bookUrl }
                if wantCover then
                    local img = html_select_first(card.html, "img.ts-post-image")
                    local src = img and img.src or ""
                    -- ленивая загрузка не подменяет src на data: (проверено)
                    if src ~= "" and not string_starts_with(src, "data:") then
                        item.cover = absUrl(src)
                    end
                end
                -- <span class="mdminf"><i class="fas fa-star"></i> 9.6</span>
                -- Шкала 10 → помечаем явно, приложение пересчитает к 0-5.
                local rEl = html_select_first(card.html, "span.mdminf")
                if rEl then
                    local n = string_clean(rEl.text):match("(%d+%.?%d*)")
                    if n then
                        local v = tonumber(n)
                        if v and v > 0 then
                            item.rating = "Rating: " .. n .. "/10"
                            _catalogRatings[normUrl(bookUrl)] = item.rating
                        end
                    end
                end
                table.insert(items, item)
            end
        end
    end
    return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────

function getCatalogList(index)
    local url = baseUrl .. "/series/?order=rating&page=" .. tostring(index + 1)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items   = parseCatalogItems(r.body, true)
    local hasNext = html_select_first(r.body, ".hpage a.r") ~= nil
    return { items = items, hasNext = hasNext }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────
-- WordPress pretty-пагинация: /page/N/?s=QUERY для всех страниц.
-- hasNext — a.next.page-numbers из div.pagination (не .hpage, это каталог).

function getCatalogSearch(index, query)
    local url = baseUrl .. "/page/" .. tostring(index + 1) .. "/?s=" .. url_encode(query)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items   = parseCatalogItems(r.body, true)
    local hasNext = html_select_first(r.body, "a.next.page-numbers") ~= nil
    return { items = items, hasNext = hasNext }
end

-- ── Фильтры каталога ─────────────────────────────────────────────────────
-- Список жанров/типов собираем с /series/ (input[name='genre[]'] / type[]),
-- фильтрация — теми же параметрами через GET.

function getFilterList()
    local r = http_get(baseUrl .. "/series/")
    if not r.success then return {} end
    local genre_options, type_options = {}, {}
    for _, li in ipairs(html_select(r.body, "li")) do
        local gin = html_select_first(li.html, "input[name='genre[]']")
        if gin then
            local slug = gin:attr("value") or ""
            local lbl  = html_select_first(li.html, "label")
            if slug ~= "" then
                table.insert(genre_options, {
                    value = slug,
                    label = lbl and string_clean(lbl.text) or slug,
                })
            end
        end
        local tin = html_select_first(li.html, "input[name='type[]']")
        if tin then
            local slug = tin:attr("value") or ""
            local lbl  = html_select_first(li.html, "label")
            if slug ~= "" then
                table.insert(type_options, {
                    value = slug,
                    label = lbl and string_clean(lbl.text) or slug,
                })
            end
        end
    end
    return {
        {
            type    = "checkbox",
            key     = "genres",
            label   = "Genres",
            options = genre_options,
        },
        {
            type    = "checkbox",
            key     = "types",
            label   = "Type",
            options = type_options,
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "",
            options = {
                { value = "",          label = "الكل" },
                { value = "ongoing",   label = "Ongoing" },
                { value = "hiatus",    label = "Hiatus" },
                { value = "completed", label = "Completed" },
            }
        },
        {
            type         = "select",
            key          = "order",
            label        = "Order By",
            defaultValue = "",
            options = {
                { value = "",             label = "الإعداد الأولي" },
                { value = "title",        label = "A-Z" },
                { value = "titlereverse", label = "Z-A" },
                { value = "update",       label = "أخر التحديثات" },
                { value = "latest",       label = "أخر ما تم إضافته" },
                { value = "popular",      label = "الرائجة" },
                { value = "rating",       label = "التقييم" },
            }
        },
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local url = baseUrl .. "/series/?page=" .. page
    for _, v in ipairs(filters["genres_included"] or {}) do
        url = url .. "&genre[]=" .. url_encode(v)
    end
    for _, v in ipairs(filters["types_included"] or {}) do
        url = url .. "&type[]=" .. url_encode(v)
    end
    local status = filters["status"] or ""
    local order  = filters["order"]  or ""
    if status ~= "" then url = url .. "&status=" .. status end
    if order  ~= "" then url = url .. "&order="  .. order  end
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items   = parseCatalogItems(r.body, true)
    local hasNext = html_select_first(r.body, ".hpage a.r") ~= nil
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ─────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1.entry-title")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "div.sertothumb img")
    local src = el and el.src or ""
    if src == "" or string_starts_with(src, "data:") then return nil end
    return absUrl(src)
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "div.sersys p")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres = {}
    for _, a in ipairs(html_select(body, ".sertogenre a")) do
        -- Движок вычищает нелатинские символы из жанров, арабские названия
        -- («أكشن») превращаются в пустые строки → не показываются. В href
        -- жанра живёт английский slug (/genre/action/), его и отдаём.
        local slug = a.href and string.match(tostring(a.href), "/genre/([^/]+)") or nil
        if slug and slug ~= "" then table.insert(genres, slug) end
    end
    return genres
end

function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "div.sertostat span")
    return el and string_clean(el.text) or nil
end

function getBookRating(bookUrl)
    -- Рейтинг только из карточек каталога/поиска: страница книги показывает
    -- неверный рейтинг (0.0/5), поэтому его в getBookRating не используем.
    return _catalogRatings[normUrl(bookUrl)] or nil
end

function getBookLastUpdate(bookUrl)
    return nil
end

-- ── Список глав ──────────────────────────────────────────────────────────
-- Главы лежат прямо на странице серии в .eplister (без пагинации), «новые
-- сверху». Первая строка — pinned «أخر ما قرأت», она дублирует последнюю
-- главу → отсекаем по совпадению URL. PDF-версии (/pdf/) не берём.
-- В конце реверс в хронологический порядок (движок ждёт 1-ю главу первой).

function getChapterList(bookUrl)
    local r = http_get(bookUrl)  -- прямой запрос: список глав не кэшируем
    if not r.success then return {} end

    local chapters, seen = {}, {}
    for _, li in ipairs(html_select(r.body, ".eplister ul li")) do
        local a = html_select_first(li.html, "a")
        if a then
            local url = absUrl(a.href)
            if url ~= "" and not string.find(url, "/pdf/", 1, true) and not seen[url] then
                seen[url] = true
                local num = html_select_first(li.html, ".epl-num")
                local title = num and string_clean(num.text) or ""
                if title ~= "" then
                    table.insert(chapters, { title = title, url = url })
                end
            end
        end
    end

    local reversed = {}
    for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
    return reversed
end

function getChapterListHash(bookUrl)
    -- Прямой http_get: хэш должен отражать актуальное состояние списка.
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local count = 0
    for _, li in ipairs(html_select(r.body, ".eplister ul li")) do
        local a = html_select_first(li.html, "a")
        local href = a and a.href or ""
        if href ~= "" and not string.find(href, "/pdf/", 1, true) then
            count = count + 1
        end
    end
    return count > 0 and tostring(count) or nil
end

-- ── Текст главы ──────────────────────────────────────────────────────────
-- Контейнер текста: #kol_content. Собираем абзацы (пустые отбрасываем),
-- прогоняем через стандартные трансформации (доменные строки и пр.).

function getChapterText(html, url)
    if not html or html == "" then return "" end
    local cont = html_select_first(html, "#kol_content")
    if not cont then return "" end
    local parts = {}
    for _, p in ipairs(html_select(cont.html, "p")) do
        local t = string_clean(p.text)
        if t ~= "" then table.insert(parts, t) end
    end
    return applyStandardContentTransforms(table.concat(parts, "\n\n"))
end