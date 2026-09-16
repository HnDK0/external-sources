id       = "seimanga"
name     = "SeiManga"
version  = "1.2.0"
baseUrl  = "https://1.seimanga.me"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/seimanga.png"
content_type = "manga"

-- SeiManga (GroupLe) — взрослая манга на русском.
-- API: $baseUrl/api/catalog/search (JSON), детали/главы/страницы — HTML.
-- Авторизация: cookie-based через 3.grouple.co (не обязательна для чтения).

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
            log_error("seimanga: 403 — требуется авторизация: " .. url)
            if show_error then show_error("Требуется авторизация", "Для доступа к этой странице необходимо войти в аккаунт.") end
        elseif r.code == 404 then
            log_error("seimanga: 404 — страница не найдена: " .. url)
            if show_error then show_error("Ошибка загрузки", "Страница не найдена (404).") end
        else
            log_error("seimanga: HTTP " .. (r.code or "?") .. " — " .. url)
            if show_error then show_error("Ошибка загрузки", "HTTP " .. tostring(r.code) .. ". Попробуйте позже.") end
        end
        return nil
    end
    return r.body
end

local function mangaSlug(bookUrl)
    local slug = string.match(bookUrl, "/([^/?]+)__%d+") or string.match(bookUrl, "/(%d+)$")
    if slug then return slug end
    local segment = string.match(bookUrl, "/([^/]+)$")
    if segment then
        segment = segment:gsub("/+$", "")
        if segment ~= "" then return segment end
    end
    return nil
end

function getCatalogList(index)
    local offset = 50 * index
    local body = fetch(baseUrl .. "/api/catalog/search?offset=" .. offset .. "&sortType=DATE_UPDATE")
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.list) do
        local title = m.name or ""
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName == "" then goto continue end
        local item = {
            title = title,
            url = baseUrl .. "/" .. linkName,
            cover = m.picUrl or "",
        }
        if m.forSale then
            item.locked = true
        end
        local rating = m.rating
        if type(rating) == "table" then rating = rating.rate or rating.value end
        if rating and type(rating) == "number" and rating > 0 then
            item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
        end
        table.insert(items, item)
        ::continue::
    end
    local hasNext = (data.offset or 0) + (data.limit or 50) < (data.total or 0)
    return { items = items, hasNext = hasNext }
end

function getCatalogSearch(index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local offset = 50 * index
    local body = fetch(baseUrl .. "/api/catalog/search?offset=" .. offset .. "&q=" .. url_encode(query))
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.list) do
        local title = m.name or ""
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName == "" then goto continue end
        local item = {
            title = title,
            url = baseUrl .. "/" .. linkName,
            cover = m.picUrl or "",
        }
        if m.forSale then
            item.locked = true
        end
        local rating = m.rating
        if type(rating) == "table" then rating = rating.rate or rating.value end
        if rating and type(rating) == "number" and rating > 0 then
            item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
        end
        table.insert(items, item)
        ::continue::
    end
    return { items = items, hasNext = false }
end

function getFilterList()
    return {
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
end

function getCatalogFiltered(index, filters)
    local sort    = filters["sort"] or "DATE_UPDATE"
    local offset  = 50 * index
    local params  = "offset=" .. offset .. "&sortType=" .. sort

    local genres_inc = filters["genres_included"] or {}
    local genres_exc = filters["genres_excluded"] or {}
    for _, v in ipairs(genres_inc) do params = params .. "&includeElementIds=" .. v end
    for _, v in ipairs(genres_exc) do params = params .. "&excludeElementIds=" .. v end

    local cat_inc = filters["categories_included"] or {}
    local cat_exc = filters["categories_excluded"] or {}
    for _, v in ipairs(cat_inc) do params = params .. "&includeElementIds=" .. v end
    for _, v in ipairs(cat_exc) do params = params .. "&excludeElementIds=" .. v end

    local lim_inc = filters["limitation_included"] or {}
    local lim_exc = filters["limitation_excluded"] or {}
    for _, v in ipairs(lim_inc) do params = params .. "&includeElementIds=" .. v end
    for _, v in ipairs(lim_exc) do params = params .. "&excludeElementIds=" .. v end

    local ano_inc = filters["another_included"] or {}
    local ano_exc = filters["another_excluded"] or {}
    for _, v in ipairs(ano_inc) do params = params .. "&includeElementIds=" .. v end
    for _, v in ipairs(ano_exc) do params = params .. "&excludeElementIds=" .. v end

    local prod = filters["productionStatus"] or ""
    if prod ~= "" then params = params .. "&includeProductionStatuses=" .. prod end

    local trans = filters["translationStatus"] or ""
    if trans ~= "" then params = params .. "&includeTranslationStatuses=" .. trans end

    local year = filters["year"] or ""
    if year ~= "" then params = params .. "&years=" .. year end

    local body = fetch(baseUrl .. "/api/catalog/search?" .. params)
    if not body then return { items = {}, hasNext = false } end
    local ok, data = pcall(json_parse, body)
    if not ok or not data or not data.list then
        return { items = {}, hasNext = false }
    end
    local items = {}
    for _, m in ipairs(data.list) do
        local title = m.name or ""
        local eid = m.elementId
        local linkName = eid and eid.linkName or ""
        if linkName == "" then goto continue end
        local item = {
            title = title,
            url = baseUrl .. "/" .. linkName,
            cover = m.picUrl or "",
        }
        if m.forSale then
            item.locked = true
        end
        local rating = m.rating
        if type(rating) == "table" then rating = rating.rate or rating.value end
        if rating and type(rating) == "number" and rating > 0 then
            item.rating = tostring(math.floor(rating * 10 + 0.5) / 10) .. "/10"
        end
        table.insert(items, item)
        ::continue::
    end
    local hasNext = (data.offset or 0) + (data.limit or 50) < (data.total or 0)
    return { items = items, hasNext = hasNext }
end

local _mangaCache = {}

local function fetchMangaDetails(bookUrl)
    local slug = mangaSlug(bookUrl)
    if not slug then log_error("seimanga: no slug from " .. bookUrl); return nil end
    if _mangaCache[slug] then return _mangaCache[slug] end
    local body = fetch(bookUrl)
    if not body then log_error("seimanga: fetch failed for " .. bookUrl); return nil end
    log_error("seimanga: fetched " .. #body .. " bytes for " .. bookUrl)
    _mangaCache[slug] = body
    return body
end

function getBookTitle(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local title = body:match('itemprop="name"%s+content="([^"]+)"')
    if title then return string_trim(title) end
    return ""
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local src = body:match('PICTURE_PREVIEWS_DATA%s*=%s*%{[^}]*"poster"%s*:%s*%[%s*\{[^}]*"src"%s*:%s*"([^"]+)"')
    if src then return absUrl(src) end
    src = body:match('cr-hero-poster__img"[^>]*src="([^"]+)"')
    if src then return absUrl(src) end
    return ""
end

function getBookDescription(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local desc = body:match('itemprop="description"%s+content="([^"]*)"')
    if desc then return string_trim(desc) end
    return ""
end

function getBookGenres(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return {} end
    local genres = {}
    for slug in body:gmatch('genre/([^/"]+)') do
        local name = slug:gsub("_", " ")
        if name ~= "" and not genres[name] then
            genres[name] = true
            table.insert(genres, name)
        end
    end
    return genres
end

function getBookRating(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local v = body:match('cr-hero-rating__value[^>]*>([%d%.]+)')
    if v then
        local n = tonumber(v)
        if n and n > 0 then return v .. "/10" end
    end
    return ""
end

function getBookStatus(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local status = body:match('data-production-status="[^"]*">([^<]+)')
    if status then return string_trim(status) end
    return ""
end

function getBookLastUpdate(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return "" end
    local date = body:match('itemprop="datePublished"%s+content="([^"]*)"')
    if date then return string_trim(date) end
    return ""
end

function getChapterList(bookUrl)
    local body = fetchMangaDetails(bookUrl)
    if not body then return {} end

    if body:find("Запрещена публикация произведения по копирайту", 1, true) then
        log_error("seimanga: лицензировано — главы удалены: " .. bookUrl)
        if show_error then show_error("Лицензия", "Произведение лицензировано.\nГлавы удалены по требованию правообладателя.") end
        return {}
    end

    local slug = mangaSlug(bookUrl)
    local chapters = {}
    local seen = {}
    for href in body:gmatch('href="(/' .. slug .. '/vol(%d+)/(%d+))"') do
        local vol, num = href:match('/vol(%d+)/(%d+)')
        if vol and num and not seen[vol .. num] then
            seen[vol .. num] = true
            table.insert(chapters, {
                title = "Том " .. vol .. " Глава " .. num,
                url = absUrl(href),
                vol = tonumber(vol),
                num = tonumber(num),
            })
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
    if #chapters == 0 then return "" end
    return chapters[#chapters].url
end

function getPageList(html, url)
    if not html or html == "" then
        local fetchUrl = url
        if not fetchUrl:find("mtr=true", 1, true) then
            fetchUrl = fetchUrl .. (fetchUrl:find("?", 1, true) and "&" or "?") .. "mtr=true"
        end
        local body = fetch(fetchUrl)
        if not body then return {} end
        html = body
    end

    local riStart = html:find("readerInit(", 1, true)
    if not riStart then
        local fetchUrl = url
        if not fetchUrl:find("mtr=true", 1, true) then
            fetchUrl = fetchUrl .. (fetchUrl:find("?", 1, true) and "&" or "?") .. "mtr=true"
        end
        local body = fetch(fetchUrl)
        if not body then return {} end
        html = body
        riStart = html:find("readerInit(", 1, true)
        if not riStart then return {} end
    end

    if html:find("purchase%-form", 1, true) or html:find("class=\"alert\"", 1, true) then
        log_error("seimanga: глава платная — " .. url)
        if show_error then show_error("Платная глава", "Эта глава является платной.") end
        return {}
    end

    if html:find("требуется премиум", 1, true) then
        log_error("seimanga: нужна премиум-подписка — " .. url)
        if show_error then show_error("Премиум", "Для доступа к главе требуется премиум-подписка.") end
        return {}
    end

    local pages = {}
    local riStart = html:find("readerInit(", 1, true)
    if not riStart then return {} end
    local arrStart = html:find("[", riStart, true)
    if not arrStart then return {} end
    local depth = 0
    local pos = arrStart
    local arrEnd = nil
    while pos <= #html do
        local c = html:sub(pos, pos)
        if c == "[" then depth = depth + 1
        elseif c == "]" then
            depth = depth - 1
            if depth == 0 then arrEnd = pos; break end
        end
        pos = pos + 1
    end
    if not arrEnd then return {} end
    local pageArray = html:sub(arrStart + 1, arrEnd - 1)
    local entryStart = 1
    while entryStart <= #pageArray do
        local s = pageArray:find("[", entryStart, true)
        if not s then break end
        local e = pageArray:find("]", s + 1, true)
        if not e then break end
        local entry = pageArray:sub(s + 1, e - 1)
        local a, b, c = entry:match("['\"]([^'\"]*)['\"]%s*,%s*['\"]([^'\"]*)['\"]%s*,%s*['\"]([^'\"]*)['\"]")
        if a and b and c then
            local imageUrl = a .. b .. c
            if not imageUrl:find("://") then
                imageUrl = "https:" .. imageUrl
            end
            table.insert(pages, imageUrl)
        end
        entryStart = e + 1
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
