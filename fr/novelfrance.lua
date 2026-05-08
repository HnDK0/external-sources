-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "novelfrance"
name     = "NovelFrance"
version  = "1.0.4"
baseUrl  = "https://novelfrance.fr"
language = "fr"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelfrance.png"

-- ── Хелперы ──────────────────────────────────────────────────────────────────
local function absUrl(href)
    if not href or href == "" then return "" end
    if string.sub(href, 1, 4) == "http" then return href end
    if string.sub(href, 1, 2) == "//" then return "https:" .. href end
    return baseUrl .. href
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string.gsub(text, "<br%s*/?>", "\n")
    text = string.gsub(text, "<[^>]+>", " ")
    text = string.gsub(text, "%s+", " ")
    return string.trim and string.trim(text) or text
end

-- Извлекает slug новеллы из URL /novel/{slug}
local function extractNovelSlug(url)
    local slug = url:match("/novel/([^/]+)")
    return slug or ""
end

-- Извлекает номер главы из URL /novel/{slug}/chapter-{num}
local function extractChapterNumber(url)
    local num = url:match("chapter%-?(%d+)")
    return num and tonumber(num) or 0
end

-- ── Каталог ──────────────────────────────────────────────────────────────────
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/browse?page=" .. tostring(page)
    local r = http_get(url)
    if not r or not r.success then return { items = {}, hasNext = false } end

    -- Ищем все карточки новелл: ссылки /novel/{slug}, у которых внутри есть h3
    local links = html_select(r.body, "main a[href*='/novel/']")
    local items = {}
    local seen = {}

    for _, link in ipairs(links) do
        local href = link.href or ""
        -- Проверяем что это карточка новеллы (имеет h3), а не ссылка из футера
        local titleEl = html_select_first(link.html, "h3")
        if titleEl then
            local slug = extractNovelSlug(href)
            if slug ~= "" and not seen[slug] then
                seen[slug] = true
                table.insert(items, {
                    title = string_clean(titleEl.text),
                    url   = absUrl("/novel/" .. slug),
                    cover = absUrl(html_attr(link.html, "img", "src"))
                })
            end
        end
    end

    -- Определяем hasNext: ищем кнопки с номерами страниц в main
    local hasNext = false
    local allButtons = html_select(r.body, "main button")
    for _, btn in ipairs(allButtons) do
        local text = string_trim(btn.text or "")
        local pageNum = tonumber(text)
        if pageNum and pageNum > page then
            hasNext = true
            break
        end
    end
    -- fallback: если кнопок пагинации нет, но вернулось >= 20 элементов
    if not hasNext and #items >= 20 then
        hasNext = true
    end

    return { items = items, hasNext = hasNext }
end

-- ── Поиск ────────────────────────────────────────────────────────────────────
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local r = http_get(baseUrl .. "/api/search/autocomplete?q=" .. (url_encode and url_encode(query) or query))
    if not r or not r.success then return { items = {}, hasNext = false } end
    
    local ok, results = pcall(json_parse, r.body)
    if not ok or not results or type(results) ~= "table" then return { items = {}, hasNext = false } end

    local items = {}
    for _, item in ipairs(results) do
        local slug = item.slug or ""
        if slug ~= "" then
            table.insert(items, {
                title = item.title or "",
                url   = absUrl("/novel/" .. slug),
                cover = absUrl(item.coverImage or "")
            })
        end
    end

    return { items = items, hasNext = false }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────
function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return nil end
    local el = html_select_first(r.body, "h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return nil end
    -- Первое изображение в main (обложка)
    local cover = html_attr(r.body, "main img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return nil end
    -- Описание идёт текстом после заголовка h1, до секции с главами
    -- Ищем большой блок текста перед секцией глав
    local cleaned = html_remove(r.body, "script", "style", "nav", "footer", "header")
    local mainEl = html_select_first(cleaned, "main")
    if not mainEl then return nil end
    local text = mainEl.text
    if text and text ~= "" then
        text = applyStandardContentTransforms(text)
        -- Обрезаем слишком длинный текст (описание обычно до 500 символов)
        local desc = ""
        for line in string.gmatch(text, "[^\n]+") do
            local trimmed = string_trim(line)
            if #desc + #trimmed < 1000 then
                desc = desc ~= "" and desc .. " " .. trimmed or trimmed
            else
                break
            end
        end
        return desc ~= "" and desc or nil
    end
    return nil
end

function getBookGenres(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return {} end
    local genres = {}
    -- Жанры — это ссылки с href /browse?genre=...
    local genreLinks = html_select(r.body, "a[href*='/browse?genre=']")
    for _, link in ipairs(genreLinks) do
        local name = string_trim(link.text)
        if name ~= "" then
            table.insert(genres, name)
        end
    end
    return genres
end

-- ── Список глав ──────────────────────────────────────────────────────────────
function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return {} end

    local novelSlug = extractNovelSlug(bookUrl)
    if novelSlug == "" then return {} end

    -- Собираем главы с первой страницы
    local chapters = parseChaptersFromHtml(r.body, novelSlug)

    -- Определяем количество страниц пагинации (кнопки с номерами)
    local paginationBtns = html_select(r.body, "main button")
    local maxPage = 1
    for _, btn in ipairs(paginationBtns) do
        local text = btn.text or ""
        local pageNum = tonumber(text)
        if pageNum and pageNum > maxPage then
            maxPage = pageNum
        end
    end

    -- Загружаем остальные страницы, если есть
    if maxPage > 1 then
        local urls = {}
        for p = 2, maxPage do
            table.insert(urls, bookUrl .. "?page=" .. p)
        end

        local results = http_get_batch(urls)
        for _, res in ipairs(results) do
            if res and res.success then
                local pageChapters = parseChaptersFromHtml(res.body, novelSlug)
                for _, ch in ipairs(pageChapters) do
                    table.insert(chapters, ch)
                end
            end
            sleep(100)
        end
    end

    -- Сайт отдаёт главы от новых к старым, разворачиваем
    local reversed = {}
    for i = #chapters, 1, -1 do
        table.insert(reversed, chapters[i])
    end
    return reversed
end

-- Парсит главы из HTML страницы новеллы
local function parseChaptersFromHtml(html, novelSlug)
    local chapters = {}
    -- Ссылки на главы: /novel/{slug}/chapter-{num}
    local pattern = "/novel/" .. novelSlug .. "/chapter%-"
    local chapterLinks = html_select(html, "a[href*='" .. pattern .. "']")
    
    for _, link in ipairs(chapterLinks) do
        local href = link.href or ""
        local titleText = link.text or ""
        -- Очищаем заголовок: убираем номер главы в начале
        local title = string_trim(titleText)
        if title ~= "" then
            table.insert(chapters, {
                title = string_clean(title),
                url   = absUrl(href)
            })
        end
    end
    return chapters
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r or not r.success then return nil end
    -- Используем URL последней главы как хеш
    local novelSlug = extractNovelSlug(bookUrl)
    if novelSlug == "" then return nil end
    local pattern = "/novel/" .. novelSlug .. "/chapter%-"
    local lastChapter = html_select_first(r.body, "a[href*='" .. pattern .. "']")
    return lastChapter and lastChapter.href or nil
end

-- ── Текст главы ──────────────────────────────────────────────────────────────
function getChapterText(html, chapterUrl)
    if not html or html == "" then
        local r = http_get(chapterUrl)
        if r and r.success then
            html = r.body
        end
    end
    if not html or html == "" then return "" end

    -- Удаляем нежелательные элементы
    local cleaned = html_remove(html, 
        "script", "style", 
        "nav", "footer", "header",
        ".comments-section", "#comments",
        "button"
    )

    -- Ищем контейнер с текстом главы
    -- На странице главы основной текст — внутри вложенного main
    local mainEl = html_select_first(cleaned, "main main")
    if not mainEl then
        mainEl = html_select_first(cleaned, "main")
    end
    if not mainEl then return "" end

    -- Извлекаем текст с сохранением структуры абзацев
    local text = html_text(mainEl.html)
    if not text or text == "" then return "" end

    -- Удаляем паттерны "Chapitre N" в начале
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*Chapitre\\s+\\d+[^\\n\\r]*[\\n\\r\\s]*", "")

    -- Удаляем заголовок главы, если дублируется
    text = regex_replace(text, "(?i)^\\s*\\d+\\s+[^\\n\\r]{0,100}[\\n\\r]", "")

    -- Удаляем ссылки на discord в конце
    text = regex_replace(text, "(?i)Si vous voulez avoir plus d'infos.*?discord\\.gg/[^\\s]*", "")

    text = applyStandardContentTransforms(text)
    return text
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
                { value = "updated", label = "Mis à jour (Nouveauté)" },
                { value = "popular", label = "Les plus populaires"     },
                { value = "rating",  label = "Mieux notés"             },
                { value = "title",   label = "Titre A-Z"               },
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
                { value = "PAUSED",    label = "En pause"   },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",       label = "Action"         },
                { value = "aventure",     label = "Aventure"       },
                { value = "romance",      label = "Romance"        },
                { value = "fantaisie",    label = "Fantaisie"      },
                { value = "syst-me",      label = "Système"        },
                { value = "magie",        label = "Magie"          },
                { value = "myst-re",      label = "Mystère"        },
                { value = "psychologique",label = "Psychologique"  },
                { value = "surnaturel",   label = "Surnaturel"     },
                { value = "com-die",      label = "Comédie"        },
                { value = "drama",        label = "Drame"          },
                { value = "sci-fi",       label = "Sci-fi"         },
                { value = "horreur",      label = "Horreur"        },
                { value = "thriller",     label = "Thriller"       },
                { value = "r-incarnation",label = "Réincarnation"  },
                { value = "transmigration",label = "Transmigration"},
                { value = "anti-h-ros",   label = "Anti-Héros"     },
                { value = "harem",        label = "Harem"          },
                { value = "adulte",       label = "Adulte"         },
                { value = "mature",       label = "Mature"         },
            }
        }
    }
end

function getCatalogFiltered(index, filters)
    local page = index + 1
    local sort        = filters["sort"]          or "updated"
    local status      = filters["status"]        or "all"
    local genres_inc  = filters["genres_included"] or {}
    local genres_exc  = filters["genres_excluded"] or {}
    
    local url = baseUrl .. "/search?page=" .. tostring(page)
    
    -- Маппинг sort
    local sortMap = {
        ["updated"] = "updated",
        ["popular"] = "popular",
        ["rating"]  = "rating",
        ["title"]   = "title"
    }
    local sortVal = sortMap[sort] or "updated"
    url = url .. "&sort=" .. sortVal
    
    if status ~= "all" then url = url .. "&status=" .. status end
    if #genres_inc  > 0 then url = url .. "&genres=" .. table.concat(genres_inc, ",") end
    if #genres_exc  > 0 then url = url .. "&excludeGenres=" .. table.concat(genres_exc, ",") end

    local r = http_get(url)
    if not r or not r.success then return { items = {}, hasNext = false } end

    -- Парсим HTML результаты поиска
    local links = html_select(r.body, "main a[href*='/novel/']")
    local items = {}
    local seen = {}

    for _, link in ipairs(links) do
        local href = link.href or ""
        local titleEl = html_select_first(link.html, "h3")
        if titleEl then
            local slug = extractNovelSlug(href)
            if slug ~= "" and not seen[slug] then
                seen[slug] = true
                table.insert(items, {
                    title = string_clean(titleEl.text),
                    url   = absUrl("/novel/" .. slug),
                    cover = absUrl(html_attr(link.html, "img", "src"))
                })
            end
        end
    end

    -- Определяем hasNext
    local hasNext = false
    local paginationLinks = html_select(r.body, "main button")
    for _, btn in ipairs(paginationLinks) do
        local text = btn.text or ""
        local pageNum = tonumber(text)
        if pageNum and pageNum > page then
            hasNext = true
            break
        end
    end
    if not hasNext and #items >= 20 then
        hasNext = true
    end

    return { items = items, hasNext = hasNext }
end