-- =====================================================================
-- Lib: readmanga family — shared engine for the readmanga.me clone
--      family (ru/readmanga, ru/seimanga, ru/mintmanga, ru/selfmanga,
--      ru/allhentai, ru/rumix). All six sites serve the same catalog
--      JSON API (/api/catalog/search), the same book page markup
--      (cr-hero-*) and the same rm_h.readerInit reader, so the plugins
--      only keep metadata, this config and their site-specific hooks.
-- Loaded via require_lib("readmanga"); uses require_lib("urls") and
-- require_lib("meta").
--
-- config (first argument of every M.* function):
--   baseUrl            string   site origin (required)
--   name               string   label for log lines (default "readmanga")
--   filters            table    full getFilterList() override (allhentai)
--   extraFilterGroups  array    extra { key, param } include/exclude groups
--                               appended to the four common ones; the API
--                               param is "include"/"exclude" .. param
--   coverFallback      fn(body) -> href|nil  last-resort cover href,
--                                            resolved against baseUrl
--                                            (rumix)
--   paywallGuards      array    extra { pattern, title, message, log? }
--                               blockers checked in getPageList (mintmanga
--                               18+); `log` overrides the log wording
--   retryReader        bool     refetch the chapter with mtr=true when the
--                               readerInit marker is missing (selfmanga)
--   pageErrors         bool     verbose show_error() on reader failures
--                               (mintmanga); off = silent return, as in
--                               readmanga/seimanga/allhentai/rumix
--
-- Status is NOT mapped anywhere: the app shows the site's own string
-- (guide «getBookStatus»), and live pages already return labels
-- ("Завершён", "Продолжается") or nothing at all (rumix has no status
-- markup) — inventing a normalized value would show data the site never
-- sent.
-- =====================================================================
local version = "1.0.0"

local urls = require_lib("urls")
local meta = require_lib("meta")

local M = {}

-- ── Shared request headers (mobile Chrome, ru accept-language) ───────
local DEFAULT_HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.004) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    ["Accept-Language"] = "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
}

-- Label used in log lines; falls back to the family name.
local function siteName(config)
    if type(config) == "table" and type(config.name) == "string" then
        return config.name
    end
    return "readmanga"
end

local function origin(config)
    return type(config) == "table" and config.baseUrl or ""
end

local function absUrl(config, href)
    return urls.absUrl(origin(config), href)
end

-- ── HTTP ─────────────────────────────────────────────────────────────

-- Guest session: without remember_me the catalog API answers with an
-- empty/limited list, so the first request is always /internal/auth.
local function ensureAuth(config)
    if not get_cookies then return true end
    local cookies = get_cookies(origin(config))
    if cookies and cookies.remember_me then return true end
    http_get(origin(config) .. "/internal/auth", { headers = DEFAULT_HEADERS })
    return true
end

local function fetch(config, url)
    ensureAuth(config)
    local r = http_get(url, { headers = DEFAULT_HEADERS })
    if not r.success then
        if r.code == 403 then
            log_error(siteName(config) .. ": 403 — требуется авторизация: " .. url)
            if show_error then show_error("Требуется авторизация", "Для доступа необходимо войти в аккаунт.") end
        elseif r.code == 404 then
            log_error(siteName(config) .. ": 404 — " .. url)
            if show_error then show_error("Ошибка загрузки", "Страница не найдена (404).") end
        else
            log_error(siteName(config) .. ": HTTP " .. (r.code or "?") .. " — " .. url)
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

-- ── Catalog (JSON API) ───────────────────────────────────────────────

local function parseCatalog(config, body)
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
                url = origin(config) .. "/" .. linkName,
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

function M.getCatalogList(config, index)
    local body = fetch(config, origin(config) .. "/api/catalog/search?offset=" .. 50 * index .. "&sortType=DATE_UPDATE")
    local items, hasNext = parseCatalog(config, body)
    return { items = items, hasNext = hasNext }
end

function M.getCatalogSearch(config, index, query)
    if index > 0 then return { items = {}, hasNext = false } end
    local body = fetch(config, origin(config) .. "/api/catalog/search?offset=0&q=" .. url_encode(query))
    local items = parseCatalog(config, body)
    return { items = items, hasNext = false }
end

-- The four tristate groups every site shares; each one maps to
-- include<param>/exclude<param> query params.
local FILTER_GROUPS = {
    { key = "genres",     param = "ElementIds" },
    { key = "categories", param = "ElementIds" },
    { key = "limitation", param = "ElementIds" },
    { key = "another",    param = "ElementIds" },
}

local function filterGroups(config)
    local extra = type(config) == "table" and config.extraFilterGroups or nil
    if type(extra) ~= "table" then return FILTER_GROUPS end
    local out = {}
    for _, g in ipairs(FILTER_GROUPS) do out[#out + 1] = g end
    for _, g in ipairs(extra) do out[#out + 1] = g end
    return out
end

function M.getCatalogFiltered(config, index, filters)
    local flt = type(filters) == "table" and filters or {}
    local sort = flt["sort"] or "DATE_UPDATE"
    local params = "offset=" .. 50 * index .. "&sortType=" .. sort

    for _, g in ipairs(filterGroups(config)) do
        local inc = flt[g.key .. "_included"] or {}
        local exc = flt[g.key .. "_excluded"] or {}
        for _, v in ipairs(inc) do params = params .. "&include" .. g.param .. "=" .. v end
        for _, v in ipairs(exc) do params = params .. "&exclude" .. g.param .. "=" .. v end
    end

    local prod = flt["productionStatus"] or ""
    if prod ~= "" then params = params .. "&includeProductionStatuses=" .. prod end
    local trans = flt["translationStatus"] or ""
    if trans ~= "" then params = params .. "&includeTranslationStatuses=" .. trans end
    local year = flt["year"] or ""
    if year ~= "" then params = params .. "&years=" .. year end

    local body = fetch(config, origin(config) .. "/api/catalog/search?" .. params)
    local items, hasNext = parseCatalog(config, body)
    return { items = items, hasNext = hasNext }
end

-- ── Book details (CSS selectors + regex fallback) ────────────────────

-- Caches are keyed by origin as well: the lib is shared by the whole
-- family and one slug can exist on several sites.
local _mangaCache = {}
local _userHashCache = {}

local function fetchMangaDetails(config, bookUrl)
    local slug = mangaSlug(bookUrl)
    if not slug then return nil end
    local key = origin(config) .. "|" .. slug
    if _mangaCache[key] then return _mangaCache[key] end
    local body = fetch(config, bookUrl)
    if not body then return nil end
    _mangaCache[key] = body
    local hash = body:match("user_hash%s*=%s*'([^']+)'")
    if hash then _userHashCache[key] = hash end
    return body
end

local function getUserHash(config, bookUrl)
    local slug = mangaSlug(bookUrl)
    if not slug then return nil end
    local key = origin(config) .. "|" .. slug
    if _userHashCache[key] then return _userHashCache[key] end
    fetchMangaDetails(config, bookUrl)
    return _userHashCache[key]
end

local function getChapterSearchParams(config, bookUrl)
    local hash = getUserHash(config, bookUrl)
    return hash and ("?d=" .. hash .. "&mtr=true") or "?mtr=true"
end

function M.getBookTitle(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return "" end
    local v = html_attr(body, 'meta[itemprop="name"]', "content")
    if v ~= "" then return string_trim(v) end
    v = body:match('itemprop="name"%s+content="([^"]+)"')
    return v and string_trim(v) or ""
end

function M.getBookCoverImageUrl(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return "" end
    local src = html_attr(body, 'img.cr-hero-poster__img, .manga-thumb img, [class*=poster] img', "src")
    if src ~= "" then return absUrl(config, src) end
    src = body:match('cr-hero-poster__img"[^>]*src="([^"]+)"')
    if src then return absUrl(config, src) end
    -- Site hook: returns a raw cover href for the family markup to miss
    -- (rumix serves posters from uploads/pics/ only); resolved here.
    local fallback = type(config.coverFallback) == "function"
        and config.coverFallback(body) or nil
    if type(fallback) == "string" and fallback ~= "" then
        return absUrl(config, fallback)
    end
    return ""
end

function M.getBookDescription(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return "" end
    local desc = html_attr(body, 'meta[itemprop="description"]', "content")
    if desc == "" then desc = html_attr(body, 'meta[name="description"]', "content") end
    if desc ~= "" then return string_trim(desc) end
    desc = body:match('itemprop="description"%s+content="([^"]*)"')
    return desc and string_trim(desc) or ""
end

function M.getBookGenres(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return {} end
    local els = html_select(body, "a.cr-tags__item")
    if els and #els > 0 then
        return meta.collectGenres(els, { clean = true })
    end
    local slugs = {}
    for slug in body:gmatch('genre/([^/"]+)') do
        slugs[#slugs + 1] = (slug:gsub("_", " "))
    end
    return meta.collectGenres(slugs)
end

function M.getBookRating(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
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

function M.getBookStatus(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return "" end
    local el = html_select_first(body, ".cr-info-details-item__status, [data-production-status]")
    if el then return string_clean(html_text(el)) end
    local status = body:match('data-production-status="[^"]*">([^<]+)')
    return status and string_trim(status) or ""
end

function M.getBookLastUpdate(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return "" end
    local v = html_attr(body, 'meta[property="article:modified_time"]', "content")
    if v == "" then v = html_attr(body, '[itemprop="datePublished"]', "content") end
    if v ~= "" then return v end
    v = body:match('itemprop="datePublished"%s+content="([^"]*)"')
    return v or ""
end

-- ── Chapter list ─────────────────────────────────────────────────────

function M.getChapterList(config, bookUrl)
    local body = fetchMangaDetails(config, bookUrl)
    if not body then return {} end

    if body:find("Запрещена публикация произведения по копирайту", 1, true) then
        log_error(siteName(config) .. ": лицензия — " .. bookUrl)
        if show_error then show_error("Лицензия", "Произведение лицензировано.\nГлавы удалены по требованию правообладателя.") end
        return {}
    end

    local slug = mangaSlug(bookUrl)
    local chapters = {}
    local seen = {}
    local searchParams = getChapterSearchParams(config, bookUrl)

    local function addChapter(href, vol, num)
        if not (vol and num) or seen[vol .. num] then return end
        seen[vol .. num] = true
        local chUrl = absUrl(config, href)
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

    -- CSS: #chapters-list a.chapter-link
    local els = html_select(body, "#chapters-list a.chapter-link")
    if els and #els > 0 then
        for _, a in ipairs(els) do
            local href = a.href
            if href and href ~= "" then
                local vol, num = href:match("/vol(%d+)/([%d.]+)")
                addChapter(href, vol, num)
            end
        end
    else
        -- Regex fallback: href="/slug/volN/M"
        for href in body:gmatch('href="([^"]*' .. slug .. '/vol%d+/%d+[^"]*)"') do
            local vol, num = href:match("/vol(%d+)/(%d+)")
            addChapter(href, vol, num)
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

function M.getChapterListHash(config, bookUrl)
    local chapters = M.getChapterList(config, bookUrl)
    return #chapters > 0 and chapters[#chapters].url or ""
end

-- ── Chapter pages (rm_h.readerInit parser, Mihon-style) ──────────────

local PAGES_REGEX = "%[['\"]([^'\"]*)['\"],['\"]([^'\"]*)['\"],['\"]([^'\"]*)['\"].-%]"

local function readerMarkOf(html)
    if html:find("rm_h.readerInit(", 1, true) then return "rm_h.readerInit(" end
    if html:find("rm_h.readerDoInit(", 1, true) then return "rm_h.readerDoInit(" end
    if html:find("readerInit(", 1, true) then return "readerInit(" end
    return nil
end

-- Reader diagnostics: silent on the family default, loud on the sites
-- that ship the messages to the user (config.pageErrors).
local function pageError(config, url, logMsg, title, message)
    if type(config) ~= "table" or not config.pageErrors then return end
    log_error(siteName(config) .. ": " .. logMsg .. " — " .. url)
    if title and show_error then show_error(title, message) end
end

function M.getPageList(config, html, url)
    if not html or html == "" then
        local body = fetch(config, url)
        if not body then return {} end
        html = body
    end

    if html:find("purchase%-form", 1, true) then
        log_error(siteName(config) .. ": платная глава — " .. url)
        if show_error then show_error("Платная глава", "Эта глава является платной.") end
        return {}
    end
    if html:find("требуется премиум", 1, true) then
        log_error(siteName(config) .. ": премиум — " .. url)
        if show_error then show_error("Премиум", "Требуется премиум-подписка.") end
        return {}
    end
    if html:find("Запрещена публикация произведения по копирайту", 1, true) then
        if show_error then show_error("Лицензия", "Главы удалены по требованию правообладателя.") end
        return {}
    end

    -- Extra site blockers (config.paywallGuards): mintmanga age gate.
    -- `log` overrides the log wording; it defaults to the error title.
    for _, g in ipairs(type(config) == "table" and config.paywallGuards or {}) do
        if html:find(g.pattern, 1, true) then
            log_error(siteName(config) .. ": " .. (g.log or g.title) .. " — " .. url)
            if show_error then show_error(g.title, g.message) end
            return {}
        end
    end

    local readerMark = readerMarkOf(html)
    if not readerMark and type(config) == "table" and config.retryReader then
        -- selfmanga: the 1.selfmanga.live redirect can drop ?mtr=true and
        -- the page arrives without readerInit — refetch with it pinned.
        local fetchUrl = url
        if not fetchUrl:find("mtr=true", 1, true) then
            if fetchUrl:find("?", 1, true) then
                fetchUrl = fetchUrl .. "&mtr=true"
            else
                fetchUrl = fetchUrl .. "?mtr=true"
            end
        end
        local body = fetch(config, fetchUrl)
        if not body then return {} end
        html = body
        readerMark = readerMarkOf(html)
    end
    if not readerMark then
        pageError(config, url, "readerInit не найден",
            "Ошибка чтения", "Не удалось найти данные страниц.")
        return {}
    end

    local beginIndex = html:find(readerMark, 1, true)
    local endIndex = html:find(");", beginIndex, true)
    if not endIndex then
        pageError(config, url, "readerInit не закрыт",
            "Ошибка чтения", "Повреждённые данные readerInit.")
        return {}
    end
    local trimmed = html:sub(beginIndex, endIndex)

    local pages = {}
    local stubCount = 0
    for prefix, path, suffix in trimmed:gmatch(PAGES_REGEX) do
        local imageUrl
        if (not path or path == "") and suffix:find("^/static/") then
            imageUrl = origin(config) .. suffix
        elseif path:find("/manga/$") then
            imageUrl = prefix .. suffix
        else
            imageUrl = path .. prefix .. suffix
        end
        if not imageUrl:find("://") then imageUrl = "https:" .. imageUrl end
        -- DDoS-Guard: one-way.work не требует токен, query params блокируют
        if imageUrl:find("one-way.work", 1, true) then
            imageUrl = imageUrl:match("^([^?]+)")
        end
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

    if #pages == 0 then
        pageError(config, url, "readerInit найден, но страниц нет",
            "Нет страниц", "ReaderInit найден, но страницы не извлечены.")
        return {}
    end

    -- Every page is a placeholder: 18+ content without a session.
    if stubCount == #pages then
        pageError(config, url, "все страницы — заглушки", nil, nil)
        if show_error then show_error("Требуется авторизация", "Для просмотра главы необходима авторизация.") end
        return {}
    end

    return pages
end

function M.getChapterText(config, html, url)
    local pages = M.getPageList(config, html, url)
    local out = {}
    for _, p in ipairs(pages) do
        table.insert(out, '<img src="' .. p .. '">')
    end
    return table.concat(out, "\n")
end

-- ── Filters ──────────────────────────────────────────────────────────

-- Shared filter sheet (identical on readmanga/seimanga/mintmanga/
-- selfmanga/rumix). allhentai ships its own vocabulary and passes it as
-- config.filters.
local BASE_FILTERS = {
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
            { value = "NO_NEED", label = "Нет необходимости" },
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

function M.getFilterList(config)
    if type(config) == "table" and type(config.filters) == "table" then
        return config.filters
    end
    return BASE_FILTERS
end

return M
