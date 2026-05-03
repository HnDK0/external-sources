-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "syosetu"
name     = "Syosetu"
version  = "1.0.1"
baseUrl  = "https://yomou.syosetu.com/"
language = "ja"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/narou.png"
local NCODE_BASE = "https://ncode.syosetu.com"
local HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

-- ── Хелперы ──────────────────────────────────────────────────────────────────
local function absUrl(href)
    if not href or href == "" then return "" end
    if href:sub(1, 4) == "http" then return href end
    if href:sub(1, 2) == "//"   then return "https:" .. href end
    return url_resolve(NCODE_BASE, href)
end

-- ── Каталог (ранкинг) ────────────────────────────────────────────────────────
function getCatalogList(index)
    return getCatalogFiltered(index, {})
end

function getCatalogFiltered(index, filters)
    local page     = index + 1
    local period   = filters["period"]   or "daily"
    local modifier = filters["modifier"] or "total"
    local genre    = filters["genre"]    or ""
    local url

    if genre == "" then
        local suffix = (modifier == "total") and (period .. "_total") or (period .. "_" .. modifier)
        url = baseUrl .. "rank/list/type/" .. suffix .. "/?p=" .. tostring(page)
    elseif genre:sub(1, 1) == "i" then
        local isekaiSuffix = genre:sub(2)
        url = baseUrl .. "rank/isekailist/type/" .. period .. "_" .. isekaiSuffix .. "/?p=" .. tostring(page)
    else
        url = baseUrl .. "rank/genrelist/type/" .. period .. "_" .. genre .. "/?p=" .. tostring(page)
    end

    log_info("syosetu getCatalogFiltered: " .. url)
    local r = http_get(url, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getCatalogFiltered: failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    -- ✅ Обновлено под новую верстку ранкинга
    local items = {}
    for _, container in ipairs(html_select(r.body, ".p-ranklist-item")) do
        local a = html_select_first(container.html, ".p-ranklist-item__title a")
        if a and a.href then
            local novelUrl = absUrl(a.href)
            if novelUrl:find(NCODE_BASE) or novelUrl:find("/n%d") then
                table.insert(items, { title = string_trim(a.text), url = novelUrl, cover = "" })
            end
        end
    end

    -- На ранкинге Syosetu всегда 50 элементов на страницу, кроме последней
    local hasNext = #items >= 50
    return { items = items, hasNext = hasNext }
end

-- ── Поиск ────────────────────────────────────────────────────────────────────
function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "search.php?order=hyoka&p=" .. tostring(page) .. "&word=" .. url_encode(query)
    local r = http_get(url, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getCatalogSearch: failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    -- ✅ Обновлено под верстку поиска
    local items = {}
    for _, container in ipairs(html_select(r.body, ".searchkekka_box")) do
        local a = html_select_first(container.html, ".novel_h a.tl")
        if a and a.href then
            local novelUrl = absUrl(a.href)
            if novelUrl:find(NCODE_BASE) or novelUrl:find("/n%d") then
                table.insert(items, { title = string_trim(a.text), url = novelUrl, cover = "" })
            end
        end
    end

    -- Поиск выдает 20 результатов. Проверяем наличие кнопки NEXT или кол-во элементов
    local nextLink = html_select_first(r.body, "a.nextlink")
    local hasNext = (nextLink ~= nil) or (#items >= 20)
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────
function getBookTitle(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then return nil end
    -- ✅ Обновлено: h1.p-novel__title
    local el = html_select_first(r.body, ".p-novel__title")
    return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    return nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then return nil end
    -- ✅ Обновлено: #novel_ex или .p-novel__summary
    local el = html_select_first(r.body, "#novel_ex")
    if el and string_trim(el.text) ~= "" then return string_trim(el.text) end
    el = html_select_first(r.body, ".p-novel__summary")
    return el and string_trim(el.text) or nil
end

-- ── Список глав ──────────────────────────────────────────────────────────────
function getChapterList(bookUrl)
    bookUrl = bookUrl:gsub("/+$", "") .. "/"
    local chapters = {}

    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getChapterList: failed code=" .. tostring(r.code))
        return {}
    end

    -- Проверка на однотомник/короткую историю (нет списка, только текст)
    local hasText = html_select_first(r.body, ".p-novel__text")
    local hasList = html_select_first(r.body, ".p-eplist__subtitle")
    if hasText and not hasList then
        local titleEl = html_select_first(r.body, ".p-novel__title")
        local title = titleEl and string_trim(titleEl.text) or "Chapter 1"
        table.insert(chapters, { title = title, url = bookUrl })
        return chapters
    end

    -- Пагинация индекса глав
    local totalPages = 1
    for _, a in ipairs(html_select(r.body, ".c-pager a.c-pager__item")) do
        local n = string.match(a.href or "", "p=(%d+)")
        if n and tonumber(n) > totalPages then totalPages = tonumber(n) end
    end

    local function parsePage(html)
        -- ✅ Обновлено: .p-eplist__subtitle
        for _, a in ipairs(html_select(html, ".p-eplist__subtitle")) do
            local href = a.href or ""
            if href ~= "" then
                table.insert(chapters, {
                    title = string_trim(a.text),
                    url   = absUrl(href)
                })
            end
        end
    end

    parsePage(r.body)

    for p = 2, totalPages do
        sleep(200)
        local pr = http_get(bookUrl .. "?p=" .. tostring(p), { headers = HEADERS })
        if pr.success then
            parsePage(pr.body)
        else
            log_error("syosetu getChapterList: page " .. p .. " failed code=" .. tostring(pr.code))
        end
    end

    log_info("syosetu getChapterList: loaded " .. tostring(#chapters) .. " chapters")
    return chapters
end

-- ── Хэш для обновлений ───────────────────────────────────────────────────────
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then return nil end
    -- ✅ Обновлено: дата последнего обновления теперь в .p-novel__date-published
    local el = html_select_first(r.body, ".p-novel__date-published")
    if el then return string_trim(el.text) end
    return nil
end

-- ── Текст главы ──────────────────────────────────────────────────────────────
function getChapterText(html, url)
    if not html or html == "" then
        local r = http_get(url, { headers = HEADERS })
        if not r.success then
            log_error("syosetu getChapterText: fetch failed code=" .. tostring(r.code))
            return ""
        end
        html = r.body
    end

    -- ✅ Обновлено: заголовок главы
    local titleText = ""
    local titleEl = html_select_first(html, ".p-novel__title")
    if titleEl then titleText = string_trim(titleEl.text) end

    -- ✅ Обновлено: основной текст главы
    local bodyEl = html_select_first(html, ".p-novel__text")
    if not bodyEl then
        log_error("syosetu getChapterText: .p-novel__text not found")
        return ""
    end

    local cleaned = html_remove(bodyEl.html, "script", "style")
    local text = html_text("<div>" .. cleaned .. "</div>")
    text = string_normalize(text)
    text = string_trim(text)

    -- Не дублируем название книги, если оно совпадает с заголовком главы
    if titleText ~= "" and titleText ~= (getBookTitle(url) or "") then
        text = titleText .. "\n\n" .. text
    end

    return text
end

-- ── Фильтры ──────────────────────────────────────────────────────────────────
function getFilterList()
    return {
        {
            type         = "select",
            key          = "period",
            label        = "Period",
            defaultValue = "daily",
            options = {
                { value = "daily",   label = "日間 (Daily)"      },
                { value = "weekly",  label = "週間 (Weekly)"     },
                { value = "monthly", label = "月間 (Monthly)"    },
                { value = "quarter", label = "四半期 (Quarterly)" },
                { value = "yearly",  label = "年間 (Yearly)"     },
                { value = "total",   label = "累計 (All Time)"   },
            }
        },
        {
            type         = "select",
            key          = "modifier",
            label        = "Status",
            defaultValue = "total",
            options = {
                { value = "total", label = "すべて (All)"       },
                { value = "r",     label = "連載中 (Ongoing)"   },
                { value = "er",    label = "完結済 (Completed)" },
                { value = "t",     label = "短編 (Short Story)" },
            }
        },
        {
            type         = "select",
            key          = "genre",
            label        = "Genre",
            defaultValue = "",
            options = {
                { value = "",     label = "総ジャンル (All)"                                    },
                { value = "i1",   label = "[異世界転生] 恋愛 (Isekai Romance)"                  },
                { value = "i2",   label = "[異世界転生] ファンタジー (Isekai Fantasy)"          },
                { value = "io",   label = "[異世界転生] 文芸・SF・その他 (Isekai Lit/SF/Other)" },
                { value = "101",  label = "[恋愛] 異世界 (Romance - Fantasy World)"             },
                { value = "102",  label = "[恋愛] 現実世界 (Romance - Real World)"              },
                { value = "201",  label = "[ファンタジー] ハイファンタジー (High Fantasy)"      },
                { value = "202",  label = "[ファンタジー] ローファンタジー (Low Fantasy)"       },
                { value = "301",  label = "[文芸] 純文学 (Literary Fiction)"                    },
                { value = "302",  label = "[文芸] ヒューマンドラマ (Human Drama)"               },
                { value = "303",  label = "[文芸] 歴史 (Historical)"                            },
                { value = "304",  label = "[文芸] 推理 (Mystery)"                               },
                { value = "305",  label = "[文芸] ホラー (Horror)"                              },
                { value = "306",  label = "[文芸] アクション (Action)"                          },
                { value = "307",  label = "[文芸] コメディー (Comedy)"                          },
                { value = "401",  label = "[SF] VRゲーム (VR Game)"                             },
                { value = "402",  label = "[SF] 宇宙 (Space)"                                   },
                { value = "403",  label = "[SF] 空想科学 (Science Fiction)"                     },
                { value = "404",  label = "[SF] パニック (Panic/Disaster)"                      },
                { value = "9901", label = "[その他] 童話 (Fairy Tale)"                          },
                { value = "9902", label = "[その他] 詩 (Poetry)"                                },
                { value = "9903", label = "[その他] エッセイ (Essay)"                           },
                { value = "9999", label = "[その他] その他 (Other)"                             },
            }
        },
    }
end