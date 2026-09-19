id       = "seimanga"
name     = "SeiManga"
version  = "2.0.1"
baseUrl  = "https://1.seimanga.me"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/readmanga.png"
content_type = "manga"

-- GroupLe Engine Core v2.0.0
-- Общее ядро для всех плагинов GroupLe (readmanga, selfmanga, mintmanga, seimanga, rumix, allhentai).
-- CSS-селекторы для деталей книги, PAGES_REGEX для страниц (по образцу Mihon GroupLe.kt).
-- SeiManga (GroupLe). Копия ядра grouple.lua.

-- ══════════════════════════════════════════════════════
-- ХЕЛПЕРЫ
-- ══════════════════════════════════════════════════════

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    if not string_starts_with(href, "/") then href = "/" .. href end
    return url_resolve(baseUrl, href)
end

local defaultHeaders = {
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    ["Accept-Language"] = "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
}

local function ensureAuth()
    if not get_cookies then return true end
    local cookies = get_cookies(baseUrl)
    if cookies and cookies.remember_me then return true end
    http_get(baseUrl .. "/internal/auth", { headers = defaultHeaders })
    return true
end

local function fetch(url)
    ensureAuth()
    local r = http_get(url, { headers = defaultHeaders })
    if not r.success then
        if r.code == 403 then
            log_error(name .. ": 403 — требуется авторизация: " .. url)
            if show_error then show_error("Требуется авторизация", "Для доступа необходимо войти в аккаунт.") end
        elseif r.code == 404 then
            log_error(name .. ": 404 — " .. url)
            if show_error then show_error("Ошибка загрузки", "Страница не найдена (404).") end
        else
            log_error(name .. ": HTTP " .. (r.code or "?") .. " — " .. url)
            if show_error then show_error("Ошибка загрузки", "HTTP " .. tostring(r.code) .. ".") end
        end
        return nil
    end
    return r.body
end

-- slug: /name__123 → name, /32529 → 32529, /sosed/vol1/7 → sosed
local function mangaSlug(bookUrl)
    local slug = bookUrl:match("/([^/?]+)__%d+")
    if slug then return slug end
    local num = bookUrl:match("/(%d+)$")
    if num then return num end
    local segment = bookUrl:match("/([^/]+)$")
    if segment then
        segment = segment:gsub("/+$", "")
        if segment:match("^%d+$") then
            local first = bookUrl:match("://[^/]+/([^/]+)")
            if first then return first end
        end
        if segment ~= "" then return segment end
    end
    return nil
end

-- ══════════════════════════════════════════════════════
-- КАТАЛОГ (JSON API)
-- ══════════════════════════════════════════════════════

local function parseCatalog(body)
    if not body then return {}, false end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then return {}, false end
    local items = {}
    for _, m in ipairs(data.list) do
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName ~= "" then
            local item = {
                title = m.name or "",
                url = baseUrl .. "/" .. linkName,
                cover = m.picUrl or "",
            }
            if m.forSale then item.locked = true end
            local rating = m.rating
            if type(rating) == "table" then rating = rating.rate or rating.value end
            if rating and type(rating) == "number" and rating > 0 then
                item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
            end
            table.insert(items, item)
        end
    end
    local hasNext = (data.offset or 0) + (data.limit or 50) < (data.total or 0)
    return items, hasNext
end

function getCatalogList(index)
    local body = fetch(baseUrl .. "/api/catalog/search?offset=" .. 50 * index .. "&sortType=DATE_UPDATE")
    local items, hasNext = parseCatalog(body)
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local body = fetch(baseUrl .. "/api/catalog/search?offset=0&q=" .. url_encode(query))
    local items = parseCatalog(body)
    return { items = items, hasNext = false }
end

function getFilterList() return FILTERS end

function getCatalogFiltered(index, filters)
    local sort = filters["sort"] or "DATE_UPDATE"
    local params = "offset=" .. 50 * index .. "&sortType=" .. sort

    for _, key in ipairs({"genres", "categories", "limitation", "another"}) do
        local inc = filters[key .. "_included"] or {}
        local exc = filters[key .. "_excluded"] or {}
        for _, v in ipairs(inc) do params = params .. "&includeElementIds=" .. v end
        for _, v in ipairs(exc) do params = params .. "&excludeElementIds=" .. v end
    end

    -- allhentai-style additional filters (includeSearchFilters)
    local add_inc = filters["additional_included"] or {}
    local add_exc = filters["additional_excluded"] or {}
    for _, v in ipairs(add_inc) do params = params .. "&includeSearchFilters=" .. v end
    for _, v in ipairs(add_exc) do params = params .. "&excludeSearchFilters=" .. v end

    local prod = filters["productionStatus"] or ""
    if prod ~= "" then params = params .. "&includeProductionStatuses=" .. prod end
    local trans = filters["translationStatus"] or ""
    if trans ~= "" then params = params .. "&includeTranslationStatuses=" .. trans end
    local year = filters["year"] or ""
    if year ~= "" then params = params .. "&years=" .. year end

    local body = fetch(baseUrl .. "/api/catalog/search?" .. params)
    local items, hasNext = parseCatalog(body)
    return { items = items, hasNext = hasNext }
end

-- ══════════════════════════════════════════════════════
-- ДЕТАЛИ КНИГИ (CSS-селекторы + regex fallback)
-- ══════════════════════════════════════════════════════

local _mangaCache = {}
local _userHashCache = {}

local function fetchMangaDetails(bookUrl)
    local slug = mangaSlug(bookUrl)
    if not slug then return nil end
    if _mangaCache[slug] then return _mangaCache[slug] end
    local body = fetch(bookUrl)
    if not body then return nil end
    _mangaCache[slug] = body
    local hash = body:match("user_hash%s*=%s*'([^']+)'")
    if hash then _userHashCache[slug] = hash end
    return body
end

local function getUserHash(bookUrl)
    local slug = mangaSlug(bookUrl)
    if slug and _userHashCache[slug] then return _userHashCache[slug] end
    fetchMangaDetails(bookUrl)
    return slug and _userHashCache[slug] or nil
end

local function getChapterSearchParams(bookUrl)
    local hash = getUserHash(bookUrl)
    return hash and ("?d=" .. hash .. "&mtr=true") or "?mtr=true"
end

function getBookTitle(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local v = html_attr(body, 'meta[itemprop="name"]', "content")
    if v ~= "" then return string_trim(v) end
    v = body:match('itemprop="name"%s+content="([^"]+)"')
    return v and string_trim(v) or ""
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local src = html_attr(body, 'img.cr-hero-poster__img, .manga-thumb img, [class*=poster] img', "src")
    if src ~= "" then return absUrl(src) end
    src = body:match('cr-hero-poster__img"[^>]*src="([^"]+)"')
    if src then return absUrl(src) end
    return ""
end

function getBookDescription(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local desc = html_attr(body, 'meta[itemprop="description"]', "content")
    if desc == "" then desc = html_attr(body, 'meta[name="description"]', "content") end
    if desc ~= "" then return string_trim(desc) end
    desc = body:match('itemprop="description"%s+content="([^"]*)"')
    return desc and string_trim(desc) or ""
end

function getBookGenres(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return {} end
    local genres = {}
    local els = html_select(body, "a.cr-tags__item")
    if els and #els > 0 then
        for _, el in ipairs(els) do
            local name = string_clean(el.text)
            if name ~= "" and not genres[name] then
                genres[name] = true
                table.insert(genres, name)
            end
        end
    else
        for slug in body:gmatch('genre/([^/"]+)') do
            local name = slug:gsub("_", " ")
            if name ~= "" and not genres[name] then
                genres[name] = true
                table.insert(genres, name)
            end
        end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local el = html_select_first(body, ".cr-hero-rating__value, [class*=rating] [class*=value]")
    if el then
        local v = string_clean(html_text(el)):match("(%d+%.?%d*)")
        if v then return v .. "/10" end
    end
    local v = body:match('cr-hero-rating__value[^>]*>([%d%.]+)')
    if v then return v .. "/10" end
    return ""
end

function getBookStatus(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local el = html_select_first(body, ".cr-info-details-item__status, [data-production-status]")
    if el then return string_clean(html_text(el)) end
    local status = body:match('data-production-status="[^"]*">([^<]+)')
    return status and string_trim(status) or ""
end

function getBookLastUpdate(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local v = html_attr(body, 'meta[property="article:modified_time"]', "content")
    if v == "" then v = html_attr(body, '[itemprop="datePublished"]', "content") end
    if v ~= "" then return v end
    v = body:match('itemprop="datePublished"%s+content="([^"]*)"')
    return v or ""
end

-- ══════════════════════════════════════════════════════
-- СПИСОК ГЛАВ
-- ══════════════════════════════════════════════════════

function getChapterList(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return {} end

    if body:find("Запрещена публикация произведения по копирайту", 1, true) then
        log_error(name .. ": лицензия — " .. bookUrl)
        if show_error then show_error("Лицензия", "Произведение лицензировано.\nГлавы удалены по требованию правообладателя.") end
        return {}
    end

    local slug = mangaSlug(bookUrl)
    local chapters = {}
    local seen = {}
    local searchParams = getChapterSearchParams(bookUrl)

    -- CSS: #chapters-list a.chapter-link (allhentai-style)
    local els = html_select(body, "#chapters-list a.chapter-link")
    if els and #els > 0 then
        for _, a in ipairs(els) do
            local href = a.href
            if href and href ~= "" then
                local vol, num = href:match("/vol(%d+)/([%d.]+)")
                if vol and num and not seen[vol .. num] then
                    seen[vol .. num] = true
                    local chUrl = absUrl(href)
                    if not chUrl:find("?", 1, true) then
                        chUrl = chUrl .. searchParams
                    else
                        chUrl = chUrl .. "&mtr=true"
                    end
                    table.insert(chapters, {
                        title = "Том " .. vol .. " Глава " .. num,
                        url = chUrl,
                        vol = tonumber(vol),
                        num = tonumber(num),
                    })
                end
            end
        end
    else
        -- Regex fallback: href="/slug/volN/M" (readmanga-style)
        for href in body:gmatch('href="([^"]*' .. slug .. '/vol%d+/%d+[^"]*)"') do
            local vol, num = href:match("/vol(%d+)/(%d+)")
            if vol and num and not seen[vol .. num] then
                seen[vol .. num] = true
                local chUrl = absUrl(href)
                if not chUrl:find("?", 1, true) then
                    chUrl = chUrl .. searchParams
                else
                    chUrl = chUrl .. "&mtr=true"
                end
                table.insert(chapters, {
                    title = "Том " .. vol .. " Глава " .. num,
                    url = chUrl,
                    vol = tonumber(vol),
                    num = tonumber(num),
                })
            end
        end
    end

    if #chapters == 0 then
        if body:find('id="chapters%-list"', 1, true) or body:find("chapters%-list", 1, true) then
            if body:find("возрастным ограничением", 1, true) or body:find("18%+", 1, true) then
                if show_error then show_error("Требуется авторизация", "Контент 18+. Войдите для доступа.") end
            else
                if show_error then show_error("Нет глав", "В этой манге ещё нет ни одной главы.") end
            end
        end
    end

    table.sort(chapters, function(a, b)
        if a.vol ~= b.vol then return a.vol < b.vol end
        return a.num < b.num
    end)
    return chapters
end

function getChapterListHash(bookUrl)
    local chapters = getChapterList(bookUrl)
    return #chapters > 0 and chapters[#chapters].url or ""
end

-- ══════════════════════════════════════════════════════
-- СТРАНИЦЫ ГЛАВЫ (readerInit парсер, по образцу Mihon)
-- ══════════════════════════════════════════════════════

local PAGES_REGEX = "%[['\"]([^'\"]*)['\"],['\"]([^'\"]*)['\"],['\"]([^'\"]*)['\"].-%]"

function getPageList(html, url)
    if not html or html == "" then
        local body = fetch(url)
        if not body then return {} end
        html = body
    end

    if html:find("purchase%-form", 1, true) then
        log_error(name .. ": платная глава — " .. url)
        if show_error then show_error("Платная глава", "Эта глава является платной.") end
        return {}
    end
    if html:find("требуется премиум", 1, true) then
        log_error(name .. ": премиум — " .. url)
        if show_error then show_error("Премиум", "Требуется премиум-подписка.") end
        return {}
    end
    if html:find("Запрещена публикация произведения по копирайту", 1, true) then
        if show_error then show_error("Лицензия", "Главы удалены по требованию правообладателя.") end
        return {}
    end

    local readerMark = nil
    if html:find("rm_h.readerInit(", 1, true) then
        readerMark = "rm_h.readerInit("
    elseif html:find("rm_h.readerDoInit(", 1, true) then
        readerMark = "rm_h.readerDoInit("
    elseif html:find("readerInit(", 1, true) then
        readerMark = "readerInit("
    end
    if not readerMark then return {} end

    local beginIndex = html:find(readerMark, 1, true)
    local endIndex = html:find(");", beginIndex, true)
    if not endIndex then return {} end
    local trimmed = html:sub(beginIndex, endIndex)

    local pages = {}
    local stubCount = 0
    for prefix, path, suffix in trimmed:gmatch(PAGES_REGEX) do
        local imageUrl
        if (not path or path == "") and suffix:find("^/static/") then
            imageUrl = baseUrl .. suffix
        elseif path:find("/manga/$") then
            imageUrl = prefix .. suffix
        else
            imageUrl = path .. prefix .. suffix
        end
        if not imageUrl:find("://") then imageUrl = "https:" .. imageUrl end
        if imageUrl:find("deleted1.png", 1, true)
            or imageUrl:find("deleted2.png", 1, true)
            or imageUrl:find("placeholder", 1, true)
            or imageUrl:find("no-cover", 1, true)
            or imageUrl:find("now_printing", 1, true)
            or imageUrl:find("restricted", 1, true) then
            stubCount = stubCount + 1
        end
        table.insert(pages, imageUrl)
    end

    if #pages > 0 and stubCount == #pages then
        if show_error then show_error("Требуется авторизация", "Для просмотра главы необходима авторизация.") end
        return {}
    end

    return pages
end

function getChapterText(html, url)
    local pages = getPageList(html, url)
    local out = {}
    for _, p in ipairs(pages) do
        table.insert(out, '<img src="' .. p .. '">')
    end
    return table.concat(out, "\n")
end

-- ══════════════════════════════════════════════════════
-- ФИЛЬТРЫ (стандартные GroupLe — замените для allhentai)
-- ══════════════════════════════════════════════════════

FILTERS = {
    {
        type = "select",
        key = "sort",
        label = "Сортировка",
        defaultValue = "DATE_UPDATE",
        options = {
            { value = "RATING",      label = "По рейтингу"      },
            { value = "DATE_UPDATE",  label = "По обновлению"    },
            { value = "NAME",         label = "По алфавиту"      },
            { value = "YEAR",         label = "По году"          },
            { value = "POPULARITY",   label = "По популярности"  },
            { value = "USER_RATING",  label = "По оценке"        },
            { value = "DATE_CREATE",  label = "Новинки"          },
        },
    },
    {
        type  = "tristate",
        key   = "genres",
        label = "Жанры",
        options = {
            { value = "2131", label = "Фэнтези"             },
            { value = "2155", label = "Боевик"              },
            { value = "2136", label = "Комедия"             },
            { value = "2121", label = "Романтика"           },
            { value = "2118", label = "Драма"               },
            { value = "2119", label = "История"             },
            { value = "2152", label = "Детектив"            },
            { value = "2130", label = "Приключения"         },
            { value = "2134", label = "Сёнэн"               },
            { value = "2138", label = "Сэйнэн"              },
            { value = "2142", label = "Гарем"               },
            { value = "2158", label = "Дзёсэй"              },
            { value = "2122", label = "Сёдзё"               },
            { value = "2133", label = "Научная фантастика"   },
            { value = "2144", label = "Психология"          },
            { value = "2150", label = "Триллер"             },
            { value = "2125", label = "Ужасы"               },
            { value = "2127", label = "Школа"               },
            { value = "2149", label = "Этти"                },
            { value = "2129", label = "Спорт"               },
            { value = "2151", label = "Постапокалиптика"    },
            { value = "2153", label = "Трагедия"            },
            { value = "2156", label = "Гендерная интрига"   },
            { value = "2137", label = "Кодомо"              },
            { value = "8032", label = "Киберпанк"           },
            { value = "9450", label = "Исэкай"              },
            { value = "9514", label = "Музыка"              },
            { value = "2159", label = "Сверхъестественное"  },
            { value = "2143", label = "Боевые искусства"    },
            { value = "9524", label = "Пародия"             },
        },
    },
    {
        type  = "tristate",
        key   = "categories",
        label = "Категории",
        options = {
            { value = "9451", label = "Манга"       },
            { value = "3001", label = "Манхва"      },
            { value = "3002", label = "Маньхуа"     },
            { value = "2141", label = "Додзинси"    },
            { value = "3515", label = "Комикс"      },
            { value = "2161", label = "Ёнкома"      },
            { value = "9577", label = "OEL-манга"   },
            { value = "5685", label = "Арт"         },
        },
    },
    {
        type  = "tristate",
        key   = "limitation",
        label = "Возраст",
        options = {
            { value = "0",  label = "6+"   },
            { value = "1",  label = "12+"  },
            { value = "2",  label = "16+"  },
            { value = "3",  label = "18+"  },
            { value = "4",  label = "NC-17" },
        },
    },
    {
        type  = "tristate",
        key   = "another",
        label = "Прочее",
        options = {
            { value = "2160", label = "Веб"            },
            { value = "7290", label = "В цвете"        },
            { value = "2162", label = "Ч/б"            },
            { value = "2163", label = "Цветной"        },
            { value = "9516", label = "Джамп"          },
            { value = "9517", label = "Дзюмп"          },
            { value = "9518", label = "Список"         },
            { value = "9519", label = "Ранобэ"         },
            { value = "9520", label = "Руманга"        },
            { value = "9521", label = "Манхуа"         },
            { value = "9522", label = "Маньхуа"        },
            { value = "9523", label = "Manhwa"         },
        },
    },
    {
        type = "select",
        key = "productionStatus",
        label = "Статус выхода",
        defaultValue = "",
        options = {
            { value = "",          label = "Любые"       },
            { value = "PROGRESS",  label = "Продолжается" },
            { value = "FINISHED",  label = "Завершён"    },
            { value = "PLANNED",   label = "Запланирован" },
            { value = "POSTPONED", label = "Приостановлен" },
            { value = "CANCELED",  label = "Отменён"     },
            { value = "NON_FINISHED", label = "Не окончен" },
        },
    },
    {
        type = "select",
        key = "translationStatus",
        label = "Статус перевода",
        defaultValue = "",
        options = {
            { value = "",         label = "Любые"          },
            { value = "PROGRESS", label = "Продолжается"   },
            { value = "FINISHED", label = "Завершён"       },
            { value = "STARTED",  label = "Начат"          },
            { value = "POSTPONED", label = "Приостановлен" },
            { value = "NONE",     label = "Отсутствует"    },
            { value = "NO_NEED",  label = "Нет необходимости" },
        },
    },
    {
        type = "sort",
        key = "year",
        label = "Год",
        defaultValue = "",
        options = {
            { value = "",           label = "Любой"     },
            { value = "2025,2025",  label = "2025"      },
            { value = "2024,2024",  label = "2024"      },
            { value = "2023,2023",  label = "2023"      },
            { value = "2020,2025",  label = "2020–2025" },
            { value = "2015,2019",  label = "2015–2019" },
            { value = "2010,2014",  label = "2010–2014" },
            { value = "2000,2009",  label = "2000–2009" },
            { value = "1990,1999",  label = "1990–1999" },
            { value = "1980,1989",  label = "1980–1989" },
        },
    },
}
