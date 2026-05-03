-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "syosetu"
name     = "Syosetu"
version  = "1.0.5"
baseUrl  = "https://ncode.syosetu.com/"
language = "ja"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/narou.png"

local HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

-- ── Хелперы ──────────────────────────────────────────────────────────────────
local function absUrl(href)
    if not href or href == "" then return "" end
    if href:sub(1, 4) == "http" then return href end
    if href:sub(1, 2) == "//"   then return "https:" .. href end
    return url_resolve("https://ncode.syosetu.com/", href)
end

-- ── Каталог (Ранкинг) ────────────────────────────────────────────────────────
function getCatalogList(index)
    return getCatalogFiltered(index, {})
end

function getCatalogFiltered(index, filters)
    local page     = index + 1
    local period   = filters["period"]   or "total"
    local modifier = filters["modifier"] or "total"
    local genre    = filters["genre"]    or ""
    local url

    if genre == "" then
        local suffix = (modifier == "total") and (period .. "_total") or (period .. "_" .. modifier)
        url = "https://yomou.syosetu.com/rank/list/type/" .. suffix .. "/?p=" .. tostring(page)
    elseif genre:sub(1, 1) == "i" then
        local isekaiSuffix = genre:sub(2)
        url = "https://yomou.syosetu.com/rank/isekailist/type/" .. period .. "_" .. isekaiSuffix .. "/?p=" .. tostring(page)
    else
        url = "https://yomou.syosetu.com/rank/genrelist/type/" .. period .. "_" .. genre .. "/?p=" .. tostring(page)
    end

    local r = http_get(url, { headers = HEADERS })
    if not r.success then return { items = {}, hasNext = false } end

    local items = {}
    for _, container in ipairs(html_select(r.body, ".p-ranklist-item")) do
        local a = html_select_first(container.html, ".p-ranklist-item__title a")
        if a and a.href then
            local novelUrl = absUrl(a.href)
            if novelUrl:match("/n[%w]+/?$") then
                table.insert(items, { title = string_trim(a.text), url = novelUrl, cover = "" })
            end
        end
    end

    return { items = items, hasNext = #items >= 50 }
end

-- ── Поиск ────────────────────────────────────────────────────────────────────
function getCatalogSearch(index, query)
    local page = index + 1
    local url = "https://yomou.syosetu.com/search.php?order=hyoka&p=" .. tostring(page) .. "&word=" .. url_encode(query)
    
    log_info("syosetu search: fetching " .. url)
    
    local r = http_get(url, { headers = HEADERS })
    if not r.success then
        log_error("syosetu search: HTTP failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    
    log_info("syosetu search: response length=" .. #r.body)
    
    local items = {}
    -- ✅ ИДЕНТИЧНО РАНКИНГУ: вложенный парсинг через container.html
    for _, container in ipairs(html_select(r.body, ".searchkekka_box")) do
        local a = html_select_first(container.html, ".novel_h a.tl")
        if a and a.href and a.text then
            local novelUrl = a.href  -- Ссылки в поиске УЖЕ полные (https://ncode.syosetu.com/...)
            local title = string_trim(a.text)
            
            -- ✅ Фильтр: только новеллы (ncode.syosetu.com/nXXXXX)
            if novelUrl:match("https?://ncode%.syosetu%.com/n[%w]+/?$") or 
               novelUrl:match("^/n[%w]+/?$") then
                log_info("syosetu search: found: " .. title)
                table.insert(items, { 
                    title = title, 
                    url = novelUrl:sub(1,4)=="http" and novelUrl or "https://ncode.syosetu.com" .. novelUrl,
                    cover = "" 
                })
            end
        end
    end
    
    log_info("syosetu search: total items=" .. #items)
    
    -- hasNext: проверяем наличие кнопки NEXT
    local nextLink = html_select_first(r.body, "a.nextlink")
    local hasNext = (nextLink ~= nil)
    
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────
function getBookTitle(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then return nil end
    local el = html_select_first(r.body, ".p-novel__title")
    return el and string_trim(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
    return nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then return nil end
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
        log_error("syosetu getChapterList failed: " .. bookUrl)
        return {}
    end

    -- Проверка на однотомник
    local hasText = html_select_first(r.body, ".p-novel__text")
    local hasEplist = html_select_first(r.body, ".p-eplist")
    
    if hasText and not hasEplist then
        local titleEl = html_select_first(r.body, ".p-novel__title")
        local title = titleEl and string_trim(titleEl.text) or "Chapter 1"
        log_info("syosetu getChapterList: single-chapter novel")
        table.insert(chapters, { title = title, url = bookUrl })
        return chapters
    end

    -- Пагинация
    local totalPages = 1
    local lastLink = html_select_first(r.body, ".c-pager__item--last")
    if lastLink and lastLink.href then
        local p = string.match(lastLink.href, "p=(%d+)")
        if p then totalPages = tonumber(p) end
    end

    local function parsePage(html)
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
        sleep(300)
        local pr = http_get(bookUrl .. "?p=" .. tostring(p), { headers = HEADERS })
        if pr.success then parsePage(pr.body) end
    end

    log_info("syosetu getChapterList: loaded " .. #chapters .. " chapters")
    return chapters
end

-- ── Хэш для обновлений ───────────────────────────────────────────────────────
function getChapterListHash(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then return nil end
    local el = html_select_first(r.body, ".p-novel__date-published")
    return el and string_trim(el.text) or nil
end

-- ── Текст главы ──────────────────────────────────────────────────────────────
function getChapterText(html, url)
    if not html or html == "" then
        local r = http_get(url, { headers = HEADERS })
        if not r.success then return "" end
        html = r.body
    end

    local titleText = ""
    local titleEl = html_select_first(html, ".p-novel__title")
    if titleEl then titleText = string_trim(titleEl.text) end

    local bodyEl = html_select_first(html, ".p-novel__text")
    if not bodyEl then return "" end

    local cleaned = html_remove(bodyEl.html, "script", "style")
    local text = html_text("<div>" .. cleaned .. "</div>")
    text = string_normalize(text)
    text = string_trim(text)

    if titleText ~= "" and not text:find(titleText, 1, true) then
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
            defaultValue = "total",
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