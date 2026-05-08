-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "novelfrance"
name     = "NovelFrance"
version  = "1.0.8"
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

-- Извлекает путь главы из URL /novel/{slug}/chapter-{num}
-- возвращает "slug/chapter-num" для запроса к API
local function extractChapterApiPath(url)
    local path = url:match("/novel/(.+)")
    return path or ""
end

-- Браузерные заголовки для всех запросов (помогают избежать Cloudflare блокировки)
local browserHeaders = {
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36",
    ["Referer"] = baseUrl,
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    ["Accept-Language"] = "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
    ["Sec-Fetch-Dest"] = "document",
    ["Sec-Fetch-Mode"] = "navigate",
    ["Sec-Fetch-Site"] = "same-origin",
    ["Upgrade-Insecure-Requests"] = "1",
    ["Cache-Control"] = "max-age=0"
}

-- Заголовки для JSON API
local apiHeaders = {
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36",
    ["Referer"] = baseUrl,
    ["Accept"] = "application/json, text/plain, */*",
    ["Accept-Language"] = "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
    ["Sec-Fetch-Dest"] = "empty",
    ["Sec-Fetch-Mode"] = "cors",
    ["Sec-Fetch-Site"] = "same-origin"
}

-- Обёртка для http_get с браузерными заголовками (для HTML страниц)
local function httpGet(url)
    return http_get(url, { headers = browserHeaders })
end

-- ── Каталог ──────────────────────────────────────────────────────────────────
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/browse?page=" .. tostring(page)
    local r = httpGet(url)
    if not r or not r.success then return { items = {}, hasNext = false } end

    -- Ищем все карточки новелл: ссылки /novel/{slug}, у которых внутри есть h3
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
    -- fallback
    if not hasNext and #items >= 20 then
        hasNext = true
    end

    return { items = items, hasNext = hasNext }
end

-- ── Поиск ────────────────────────────────────────────────────────────────────
function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local url = baseUrl .. "/api/search/autocomplete?q=" .. (url_encode and url_encode(query) or query)
    local r = http_get(url, { headers = browserHeaders })
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
    local r = httpGet(bookUrl)
    if not r or not r.success then return nil end
    local el = html_select_first(r.body, "h1")
    return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    local r = httpGet(bookUrl)
    if not r or not r.success then return nil end
    local cover = html_attr(r.body, "main img", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local r = httpGet(bookUrl)
    if not r or not r.success then return nil end
    local cleaned = html_remove(r.body, "script", "style", "nav", "footer", "header")
    local mainEl = html_select_first(cleaned, "main")
    if not mainEl then return nil end
    local text = mainEl.text
    if text and text ~= "" then
        for line in string.gmatch(text, "[^\n]+") do
            local trimmed = string_trim(line)
            if #trimmed > 50 then
                return string_trim(trimmed)
            end
        end
    end
    return nil
end

function getBookGenres(bookUrl)
    local r = httpGet(bookUrl)
    if not r or not r.success then return {} end
    local genres = {}
    local genreLinks = html_select(r.body, "a[href*='/browse?genre=']")
    for _, link in ipairs(genreLinks) do
        local name = string_trim(link.text)
        if name ~= "" then
            table.insert(genres, name)
        end
    end
    return genres
end

-- ── Список глав (через JSON API) ────────────────────────────────────────────
function getChapterList(bookUrl)
    local novelSlug = extractNovelSlug(bookUrl)
    if novelSlug == "" then return {} end
    
    local allChapters = {}
    local skip = 0
    local take = 100
    local hasMore = true
    
    while hasMore do
        local apiUrl = baseUrl .. "/api/chapters/" .. novelSlug
            .. "?skip=" .. skip .. "&take=" .. take .. "&order=asc"
        local r = http_get(apiUrl, { headers = apiHeaders })
        if not r or not r.success then break end
        
        local ok, data = pcall(json_parse, r.body)
        if not ok or not data then break end
        
        if data.chapters and type(data.chapters) == "table" then
            for _, ch in ipairs(data.chapters) do
                local slug = ch.slug or ""
                if slug ~= "" then
                    table.insert(allChapters, {
                        title = string_clean(ch.title or "Chapitre " .. tostring(ch.chapterNumber or "")),
                        url   = absUrl("/novel/" .. novelSlug .. "/" .. slug)
                    })
                end
            end
        end
        
        hasMore = data.hasMore == true
        skip = skip + take
        sleep(50)
    end
    
    return allChapters
end

function getChapterListHash(bookUrl)
    local novelSlug = extractNovelSlug(bookUrl)
    if novelSlug == "" then return nil end
    
    local apiUrl = baseUrl .. "/api/chapters/" .. novelSlug .. "?skip=0&take=1&order=desc"
    local r = http_get(apiUrl, { headers = apiHeaders })
    if not r or not r.success then return nil end
    
    local ok, data = pcall(json_parse, r.body)
    if not ok or not data then return nil end
    
    -- Используем total как хеш
    return tostring(data.total or "")
end

-- ── Текст главы (через JSON API) ────────────────────────────────────────────
function getChapterText(html, chapterUrl)
    local apiPath = extractChapterApiPath(chapterUrl)
    if apiPath == "" then return "" end
    
    local r = http_get(baseUrl .. "/api/chapters/" .. apiPath, { headers = apiHeaders })
    if not r or not r.success then
        -- Fallback: пробуем загрузить через HTML если API не работает
        if html and html ~= "" then
            return getChapterTextFromHtml(html)
        end
        return ""
    end
    
    local ok, data = pcall(json_parse, r.body)
    if not ok or not data then return "" end
    
    if not data.paragraphs or type(data.paragraphs) ~= "table" then return "" end
    
    local paragraphs = {}
    for _, p in ipairs(data.paragraphs) do
        local content = p.content or ""
        if content ~= "" then
            table.insert(paragraphs, string_trim(content))
        end
    end
    
    return table.concat(paragraphs, "\n\n")
end

-- Fallback: парсинг текста главы из HTML (если API недоступен)
local function getChapterTextFromHtml(html)
    local cleaned = html_remove(html, 
        "script", "style", 
        "nav", "footer", "header",
        ".comments-section", "#comments",
        "button"
    )

    local mainEl = html_select_first(cleaned, "main main")
    if not mainEl then
        mainEl = html_select_first(cleaned, "main")
    end
    if not mainEl then return "" end

    local text = html_text(mainEl.html)
    if not text or text == "" then return "" end

    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*Chapitre\\s+\\d+[^\\n\\r]*[\\n\\r\\s]*", "")
    text = regex_replace(text, "(?i)^\\s*\\d+\\s+[^\\n\\r]{0,100}[\\n\\r]", "")
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

    local r = httpGet(url)
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
    local allButtons = html_select(r.body, "main button")
    for _, btn in ipairs(allButtons) do
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