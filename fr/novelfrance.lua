-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "novelfrance"
name     = "NovelFrance"
version  = "1.0.1"
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

-- Извлечение __NEXT_DATA__ из HTML
local function fetchNextData(url)
    local r = http_get(url)
    if not r or not r.success then return nil end
    local json_str = r.body:match('<script[^>]+id="__NEXT_DATA__"[^>]*>([^<]+)</script>')
    if not json_str then return nil end
    return json_parse(json_str)
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".?\n", " ")
    text = regex_replace(text, "(?i)\A[\s\p{Z}\uFEFF]((Chapitre\s+\d+|Chapter\s+\d+)[^\n\r]*[\n\r\s]*)+", " ")
    text = regex_replace(text, "(?im)^\s*(Traducteur|Éditeur|Relecteur|Source)[:\s][^\n\r]{0,70}(\r?\n|$)", " ")
    text = regex_replace(text, "(?i)(discord\.gg/\S+|https://discord\.gg/\S+)", " ")
    text = string_trim(text)
    return text
end

-- ── Каталог ──────────────────────────────────────────────────────────────────
function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "/browse?page=" .. tostring(page)
    local nd = fetchNextData(url)
    if not nd then return { items = {}, hasNext = false } end
    
    local props = nd.props and nd.props.pageProps
    local data = props and props.initialData
    if not data then return { items = {}, hasNext = false } end

    local items = {}
    for _, novel in ipairs(data.searchResults.novels or {}) do
        local slug = novel.slug or ""
        if slug ~= "" then
            table.insert(items, {
                title = string_clean(novel.title or ""),
                url   = absUrl("/novel/" .. slug),
                cover = absUrl(novel.coverImage or "")
            })
        end
    end

    return { items = items, hasNext = data.searchResults.hasMore == true }
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
    local nd = fetchNextData(bookUrl)
    if not nd then return nil end
    return nd.props and nd.props.pageProps and nd.props.pageProps.initialNovel
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
    local nd = fetchNextData(bookUrl)
    if not nd then return {} end
    
    local props = nd.props and nd.props.pageProps
    local resp = props and props.initialChaptersResponse
    if not resp then return {} end

    -- Безопасно извлекаем слаг новеллы
    local novelSlug = (props and props.initialNovel and props.initialNovel.slug) or (bookUrl:match("novel/([^/]+)") or "")

    local chapters = {}
    for _, ch in ipairs(resp.chapters or {}) do
        local slug = ch.slug or ""
        if slug ~= "" then
            table.insert(chapters, {
                title = string_clean(ch.title or ("Chapitre " .. tostring(ch.chapterNumber))),
                url   = absUrl("/novel/" .. novelSlug .. "/" .. slug)
            })
        end
    end

    -- Сайт отдает в обратном порядке (новые → старые), разворачиваем
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
    local json_str = html and html:match('<script[^>]+id="__NEXT_DATA__"[^>]*>([^<]+)</script>')
    -- Если в html нет данных, грузим напрямую
    if not json_str or json_str == "" then
        local r = http_get(chapterUrl)
        if r and r.success then
            json_str = r.body:match('<script[^>]+id="__NEXT_DATA__"[^>]*>([^<]+)</script>')
        end
    end

    if not json_str then return "" end
    local data = json_parse(json_str)
    if not data then return "" end

    local ch = data.props and data.props.pageProps and data.props.pageProps.initialChapter
    if not ch then return "" end

    local paragraphs = {}
    -- Поддержка разных структур контента
    if ch.paragraphs and type(ch.paragraphs) == "table" then
        for _, p in ipairs(ch.paragraphs) do
            if p.content and type(p.content) == "string" and p.content ~= "" then
                table.insert(paragraphs, string_trim(p.content))
            end
        end
    elseif ch.content and type(ch.content) == "string" then
        table.insert(paragraphs, string_trim(ch.content))
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

    local nd = fetchNextData(url)
    if not nd then return { items = {}, hasNext = false } end

    local props = nd.props and nd.props.pageProps
    local data  = props and props.initialResults
    if not data then return { items = {}, hasNext = false } end

    local items = {}
    for _, novel in ipairs(data.novels or {}) do
        local slug = novel.slug or ""
        if slug ~= "" then
            table.insert(items, {
                title = string_clean(novel.title or ""),
                url   = absUrl("/novel/" .. slug),
                cover = absUrl(novel.coverImage or "")
            })
        end
    end

    return { items = items, hasNext = data.hasMore == true }
end