-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "novelfrance"
name     = "NovelFrance"
version  = "1.0.3"
baseUrl  = "https://novelfrance.fr"
language = "fr"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelfrance.png"

-- ── Хелперы ──────────────────────────────────────────────────────────────────
local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

--  Извлечение данных из RSC payload (Next.js App Router)
local function extractRscData(body, key)
    -- Ищем pattern вида: "key":{...} внутри self.__next_f.push блоков
    -- Ключ может быть в начале строки или после запятой
    local pattern = '"' .. key .. '":(%b{})'
    
    for json_str in body:gmatch(pattern) do
        -- Декодируем экранированные кавычки: \" → "
        local clean = json_str:gsub('\\"', '"'):gsub('\\\\', '\\')
        
        -- Пытаемся распарсить как объект с ключом
        local wrapped = '{' .. key .. ':' .. clean .. '}'
        local data = json_parse(wrapped)
        if data and data[key] then
            return data[key]
        end
        
        -- Пробуем распарсить как чистый объект (если ключ был обёрткой)
        local direct = json_parse(clean)
        if direct then return direct end
    end
    
    return nil
end

-- Альтернативный метод: поиск по всему телу без %b{} (более надёжный для вложенного JSON)
local function extractRscDataRobust(body, key)
    -- Ищем "key": и затем извлекаем объект, считая скобки
    local start_pos = body:find('"' .. key .. '":', 1, true)
    if not start_pos then return nil end
    
    local json_start = body:find('{', start_pos)
    if not json_start then return nil end
    
    -- Считаем вложенные скобки
    local depth = 0
    local in_string = false
    local escape_next = false
    
    for i = json_start, #body do
        local char = body:sub(i, i)
        
        if escape_next then
            escape_next = false
        elseif char == '\\' then
            escape_next = true
        elseif char == '"' and not escape_next then
            in_string = not in_string
        elseif not in_string then
            if char == '{' then
                depth = depth + 1
            elseif char == '}' then
                depth = depth - 1
                if depth == 0 then
                    local json_str = body:sub(json_start, i)
                    local clean = json_str:gsub('\\"', '"'):gsub('\\\\', '\\')
                    local data = json_parse(clean)
                    if data then return data end
                    return nil
                end
            end
        end
    end
    return nil
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".?\n", " ")
    text = regex_replace(text, "(?i)\A[\s\p{Z}\uFEFF]((Chapitre\\s+\\d+|Chapter\\s+\\d+)[^\n\r]*[\n\r\s]*)+", " ")
    text = regex_replace(text, "(?im)^\\s*(Traducteur|Éditeur|Relecteur|Source)[:\\s][^\n\r]{0,70}(\r?\n|$)", " ")
    text = regex_replace(text, "(?i)(discord\\.gg/\\S+|https://discord\\.gg/\\S+)", " ")
    text = string_trim(text)
    return text
end

-- ── Каталог ──────────────────────────────────────────────────────────────────
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/browse?page=" .. tostring(page)
    
    -- 1. Лог запроса
    log_debug("=== getCatalogList DEBUG ===")
    log_debug("Request URL: " .. url)
    
    local r = http_get(url)
    
    -- 2. Проверка ответа
    if not r then
        log_debug("ERROR: http_get returned nil")
        return { items = {}, hasNext = false }
    end
    if not r.success then
        log_debug("ERROR: HTTP failed - " .. tostring(r.error))
        return { items = {}, hasNext = false }
    end
    
    log_debug("HTTP OK, body length: " .. tostring(#r.body))
    
    -- 3. Поиск initialData в теле ответа
    local initialData = extractRscDataRobust(r.body, "initialData")
    
    if not initialData then
        log_debug("ERROR: initialData NOT found in response")
        -- Выводим превью тела для анализа
        local preview = r.body:sub(1, 3000)
        log_debug("Body preview (first 3000 chars):")
        log_debug(preview)
        
        -- Проверяем, есть ли вообще self.__next_f.push
        if r.body:find("self%.__next_f%.push") then
            log_debug("✓ Found self.__next_f.push in body")
        else
            log_debug("✗ self.__next_f.push NOT found")
        end
        
        -- Проверяем ключевые строки
        if r.body:find('"initialData"') then
            log_debug("✓ Found literal \"initialData\" string")
        else
            log_debug("✗ \"initialData\" string NOT found")
        end
        
        return { items = {}, hasNext = false }
    end
    
    log_debug("✓ initialData parsed successfully")
    
    -- 4. Проверка структуры searchResults
    if not initialData.searchResults then
        log_debug("ERROR: initialData.searchResults is nil")
        log_debug("initialData keys: " .. table_concat_keys(initialData))
        return { items = {}, hasNext = false }
    end
    
    log_debug("✓ searchResults found")
    
    -- 5. Извлечение новелл
    local novels = initialData.searchResults.novels or {}
    log_debug("Novels count: " .. tostring(#novels))
    
    local items = {}
    for i, novel in ipairs(novels) do
        local slug = novel.slug
        if slug and slug ~= "" then
            table.insert(items, {
                title = string_clean(novel.title or ""),
                url   = absUrl("/novel/" .. slug),
                cover = absUrl(novel.coverImage or "")
            })
            if i <= 3 then
                log_debug("  [" .. i .. "] " .. (novel.title or "NO TITLE") .. " -> /novel/" .. slug)
            end
        end
    end
    
    local hasMore = initialData.searchResults.hasMore == true
    log_debug("Items extracted: " .. tostring(#items) .. ", hasMore: " .. tostring(hasMore))
    log_debug("=== END DEBUG ===")
    
    return { items = items, hasNext = hasMore }
end

-- Вспомогательная функция для вывода ключей таблицы
function table_concat_keys(t)
    local keys = {}
    for k, _ in pairs(t) do table.insert(keys, tostring(k)) end
    return table.concat(keys, ", ")
end

-- ── Поиск ────────────────────────────────────────────────────────────────────
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local r = http_get(baseUrl .. "/api/search/autocomplete?q=" .. url_encode(query))
    if not r or not r.success then return { items = {}, hasNext = false } end
    local results = json_parse(r.body)
    if not results or type(results) ~= "table" then return { items = {}, hasNext = false } end

    local items = {}
    for _, item in ipairs(results) do
        local slug = item.slug or ""
        if slug ~= "" then
            table.insert(items, {
                title = string_clean(item.title or ""),
                url   = absUrl("/novel/" .. slug),
                cover = absUrl(item.coverImage or "")
            })
        end
    end

    return { items = items, hasNext = false }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────
local function fetchNovelData(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return nil end
    return extractRscDataRobust(r.body, "initialNovel")
end

function getBookTitle(bookUrl)
    local n = fetchNovelData(bookUrl)
    return n and string_clean(n.title) or nil
end

function getBookCoverImageUrl(bookUrl)
    local n = fetchNovelData(bookUrl)
    return n and absUrl(n.coverImage) or nil
end

function getBookDescription(bookUrl)
    local n = fetchNovelData(bookUrl)
    if not n or not n.description then return nil end
    local desc = n.description:gsub("<br%s*/?>", "\n"):gsub("<[^>]+>", "  ")
    desc = string_trim(desc)
    return desc ~= "" and desc or nil
end

function getBookGenres(bookUrl)
    local n = fetchNovelData(bookUrl)
    if not n then return {} end
    local genres = {}
    for _, g in ipairs(n.genres or {}) do
        if g.name and g.name ~= "" then table.insert(genres, g.name) end
    end
    return genres
end

-- ── Список глав ──────────────────────────────────────────────────────────────
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return {} end
    
    -- 🔥 Извлекаем оба ключевых блока
    local initialNovel = extractRscDataRobust(r.body, "initialNovel")
    local initialChapters = extractRscDataRobust(r.body, "initialChaptersResponse")
    
    if not initialChapters or not initialChapters.chapters then return {} end
    
    local novelSlug = initialNovel and initialNovel.slug or bookUrl:match("novel/([^/]+)")
    
    local chapters = {}
    for _, ch in ipairs(initialChapters.chapters) do
        local slug = ch.slug
        if slug and slug ~= "" then
            table.insert(chapters, {
                title = string_clean(ch.title or "Chapitre " .. tostring(ch.chapterNumber)),
                url   = absUrl("/novel/" .. novelSlug .. "/" .. slug)
            })
        end
    end
    
    -- Сайт отдаёт в обратном порядке (новые → старые), разворачиваем
    local reversed = {}
    for i = #chapters, 1, -1 do table.insert(reversed, chapters[i]) end
    return reversed
end

function getChapterListHash(bookUrl)
    local n = fetchNovelData(bookUrl)
    if not n then return nil end
    return n.lastChapterAt or tostring(n._count and n._count.chapters)
end

-- ── Текст главы ──────────────────────────────────────────────────────────────
function getChapterText(html, chapterUrl)
    -- 🔥 Ищем initialChapter в переданном HTML
    local initialChapter = extractRscDataRobust(html or "", "initialChapter")
    
    -- Если не найдено — грузим страницу напрямую
    if not initialChapter then
        local r = http_get(chapterUrl)
        if r and r.success then
            initialChapter = extractRscDataRobust(r.body, "initialChapter")
        end
    end
    
    if not initialChapter then return "" end
    
    -- Поддержка двух форматов контента
    local paragraphs = {}
    
    if initialChapter.paragraphs and type(initialChapter.paragraphs) == "table" then
        for _, p in ipairs(initialChapter.paragraphs) do
            if p.content and type(p.content) == "string" and p.content ~= "" then
                table.insert(paragraphs, string_trim(p.content))
            end
        end
    elseif initialChapter.content and type(initialChapter.content) == "string" then
        table.insert(paragraphs, string_trim(initialChapter.content))
    end
    
    if #paragraphs == 0 then return "" end
    return applyStandardContentTransforms(table.concat(paragraphs, "\n\n"))
end

-- ── Фильтры ──────────────────────────────────────────────────────────────────
function getFilterList()
    return {
        {
            type         = "select",
            key          = "sort",
            label        = "Trier par",
            defaultValue = "updated",
            options = {
                { value = "updated", label = "Dernière mise à jour" },
                { value = "rating",  label = "Meilleure note"         },
                { value = "views",   label = "Plus populaires"        },
                { value = "title",   label = "Titre (A-Z)"            },
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "Statut",
            defaultValue = "all",
            options = {
                { value = "all",       label = "Tous"       },
                { value = "ONGOING",   label = "En cours"   },
                { value = "COMPLETED", label = "Terminé"    },
            }
        },
        {
            type         = "select",
            key          = "minChapters",
            label        = "Chapitres min.",
            defaultValue = "",
            options = {
                { value = "",    label = "Peu importe" },
                { value = "50",  label = "50+"         },
                { value = "100", label = "100+"        },
                { value = "200", label = "200+"        },
                { value = "500", label = "500+"        },
            }
        },
        {
            type         = "select",
            key          = "maxChapters",
            label        = "Chapitres max.",
            defaultValue = "",
            options = {
                { value = "",     label = "Peu importe" },
                { value = "100",  label = "≤ 100"       },
                { value = "200",  label = "≤ 200"       },
                { value = "500",  label = "≤ 500"       },
                { value = "1000", label = "≤ 1000"      },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",        label = "Action"            },
                { value = "aventure",      label = "Aventure"          },
                { value = "romance",       label = "Romance"           },
                { value = "fantaisie",     label = "Fantaisie"         },
                { value = "syst-me",       label = "Système"           },
                { value = "magie",         label = "Magie"             },
                { value = "myst-re",       label = "Mystère"           },
                { value = "psychologique", label = "Psychologique"     },
                { value = "surnaturel",    label = "Surnaturel"        },
                { value = "com-die",       label = "Comédie"           },
                { value = "drama",         label = "Drame"             },
                { value = "sci-fi",        label = "Sci-fi"            },
                { value = "horreur",       label = "Horreur"           },
                { value = "thriller",      label = "Thriller"          },
                { value = "r-incarnation", label = "Réincarnation"     },
                { value = "transmigration",label = "Transmigration"    },
                { value = "anti-h-ros",    label = "Anti-Héros"        },
                { value = "harem",         label = "Harem"             },
                { value = "adulte",        label = "Adulte"            },
                { value = "mature",        label = "Mature"            },
            }
        }
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local sort        = filters["sort"]          or "updated"
    local status      = filters["status"]        or "all"
    local min_ch      = filters["minChapters"]   or ""
    local max_ch      = filters["maxChapters"]   or ""
    local genres_inc  = filters["genres_included"]  or {}
    local genres_exc  = filters["genres_excluded"]  or {}
    
    local url = baseUrl .. "/search?page=" .. tostring(page) .. "&sort=" .. sort
    if status ~= "all" then url = url .. "&status=" .. status end
    if min_ch ~= ""   then url = url .. "&minChapters=" .. url_encode(min_ch) end
    if max_ch ~= ""   then url = url .. "&maxChapters=" .. url_encode(max_ch) end
    if #genres_inc  > 0 then url = url .. "&genres=" .. table.concat(genres_inc, ",") end
    if #genres_exc  > 0 then url = url .. "&excludeGenres=" .. table.concat(genres_exc, ",") end

    local r = http_get(url)
    if not r or not r.success then return { items = {}, hasNext = false } end
    
    -- 🔥 RSC-парсинг для filtered каталога
    local initialResults = extractRscDataRobust(r.body, "initialResults")
    if not initialResults then return { items = {}, hasNext = false } end

    local items = {}
    for _, novel in ipairs(initialResults.novels or {}) do
        local slug = novel.slug or ""
        if slug ~= "" then
            table.insert(items, {
                title = string_clean(novel.title or ""),
                url   = absUrl("/novel/" .. slug),
                cover = absUrl(novel.coverImage or "")
            })
        end
    end

    return { items = items, hasNext = initialResults.hasMore == true }
end