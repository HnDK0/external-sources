-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "syosetu"
name     = "Syosetu"
version  = "1.0.0"
baseUrl  = "https://yomou.syosetu.com/"
language = "ja"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/narou.png"

-- Контент (главы, детали книг) живёт на ncode.syosetu.com
local NCODE_BASE = "https://ncode.syosetu.com"

local HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

-- ── Хелперы ──────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//")   then return "https:" .. href end
    return url_resolve(NCODE_BASE, href)
end

-- Парсинг карточек новеллы.
-- На ранкинг-страницах: блок .ranking_list → ссылка .novel_h a
-- На поисковых: блок .searchkekka_box → ссылка .novel_h a
local function parseNovelCards(html, containerSelector, linkSelector)
    local items = {}
    for _, container in ipairs(html_select(html, containerSelector)) do
        local a = html_select_first(container.html, linkSelector)
        if a and a.href and a.href ~= "" then
            local novelUrl = absUrl(a.href)
            if string_starts_with(novelUrl, NCODE_BASE) then
                table.insert(items, {
                    title = string_trim(a.text),
                    url   = novelUrl,
                    cover = ""
                })
            end
        end
    end
    return items
end

-- ── Каталог (ранкинг) ─────────────────────────────────────────────────────────

function getCatalogList(index)
    -- Дефолт: суточный общий рейтинг без фильтров
    return getCatalogFiltered(index, {})
end

-- ── Поиск ────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "search.php?order=hyoka&p=" .. tostring(page)
                       .. "&word=" .. url_encode(query)

    local r = http_get(url, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getCatalogSearch: failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    local items = parseNovelCards(r.body, ".searchkekka_box", ".novel_h a")

    -- Проверяем наличие следующей страницы
    local hasNext = false
    for _, a in ipairs(html_select(r.body, ".next_page a")) do
        if string.find(a.text, "次") then
            hasNext = true
            break
        end
    end
    if not hasNext and #items >= 20 then hasNext = true end

    return { items = items, hasNext = hasNext }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getBookTitle: failed code=" .. tostring(r.code))
        return nil
    end
    local el = html_select_first(r.body, ".novel_title")
    if el then return string_trim(el.text) end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    -- Syosetu не предоставляет обложки
    return nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getBookDescription: failed code=" .. tostring(r.code))
        return nil
    end
    -- Многотомник: #novel_ex, однотомник: #novel_synopsis
    local el = html_select_first(r.body, "#novel_ex")
    if el and string_trim(el.text) ~= "" then return string_trim(el.text) end
    el = html_select_first(r.body, "#novel_synopsis")
    if el then return string_trim(el.text) end
    return nil
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

    -- Однотомник: на странице уже есть #novel_honbun (текст главы), списка нет
    local honbun = html_select_first(r.body, "#novel_honbun")
    if honbun then
        local titleEl = html_select_first(r.body, ".novel_title")
        local title = titleEl and string_trim(titleEl.text) or "Chapter 1"
        table.insert(chapters, { title = title, url = bookUrl })
        return chapters
    end

    -- Многотомник: индекс глав.
    -- Структура: <dl class="novel_sublist2">
    --              <dd class="subtitle"><a href="/nXXXX/1/">Название главы</a></dd>
    --            </dl>
    -- Пагинация индекса (100 глав на страницу): ?p=2, ?p=3 ...

    local totalPages = 1
    for _, a in ipairs(html_select(r.body, ".pager_chapter a, .novel_no a")) do
        local href = a.href or ""
        local n = string.match(href, "[?&]p=(%d+)")
        if n then
            local pn = tonumber(n) or 1
            if pn > totalPages then totalPages = pn end
        end
    end

    local function parsePage(html)
        for _, a in ipairs(html_select(html, ".novel_sublist2 .subtitle a")) do
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
    -- Последняя дата обновления в списке глав
    local els = html_select(r.body, ".novel_sublist2 .long_update")
    if #els > 0 then return string_trim(els[#els].text) end
    -- Запасной вариант: суммарное кол-во эпизодов
    local el = html_select_first(r.body, "#novel_total_ep")
    if el then return string_trim(el.text) end
    return nil
end

-- ── Текст главы ──────────────────────────────────────────────────────────────

function getChapterText(html, url)
    -- Проверяем есть ли контент в переданном html
    local honbun = html_select_first(html or "", "#novel_honbun")
    if not honbun then
        log_info("syosetu getChapterText: fetching url=" .. tostring(url))
        local r = http_get(url, { headers = HEADERS })
        if not r.success then
            log_error("syosetu getChapterText: fetch failed code=" .. tostring(r.code))
            return ""
        end
        html = r.body
    end

    -- Заголовок главы (только у многотомников)
    local titleText = ""
    local titleEl = html_select_first(html, ".novel_subtitle")
    if titleEl then titleText = string_trim(titleEl.text) end

    -- Основной текст
    local bodyEl = html_select_first(html, "#novel_honbun")
    if not bodyEl then
        log_error("syosetu getChapterText: #novel_honbun not found")
        return ""
    end

    local cleaned = html_remove(bodyEl.html, "script", "style")
    local text = html_text("<div>" .. cleaned .. "</div>")
    text = string_normalize(text)
    text = string_trim(text)

    if titleText ~= "" then
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
                -- 異世界転生/転移 — префикс "i" чтобы отличить от жанровых номеров
                { value = "i1",   label = "[異世界転生] 恋愛 (Isekai Romance)"                  },
                { value = "i2",   label = "[異世界転生] ファンタジー (Isekai Fantasy)"          },
                { value = "io",   label = "[異世界転生] 文芸・SF・その他 (Isekai Lit/SF/Other)" },
                -- 恋愛
                { value = "101",  label = "[恋愛] 異世界 (Romance - Fantasy World)"             },
                { value = "102",  label = "[恋愛] 現実世界 (Romance - Real World)"              },
                -- ファンタジー
                { value = "201",  label = "[ファンタジー] ハイファンタジー (High Fantasy)"      },
                { value = "202",  label = "[ファンタジー] ローファンタジー (Low Fantasy)"       },
                -- 文芸
                { value = "301",  label = "[文芸] 純文学 (Literary Fiction)"                    },
                { value = "302",  label = "[文芸] ヒューマンドラマ (Human Drama)"               },
                { value = "303",  label = "[文芸] 歴史 (Historical)"                            },
                { value = "304",  label = "[文芸] 推理 (Mystery)"                               },
                { value = "305",  label = "[文芸] ホラー (Horror)"                              },
                { value = "306",  label = "[文芸] アクション (Action)"                          },
                { value = "307",  label = "[文芸] コメディー (Comedy)"                          },
                -- SF
                { value = "401",  label = "[SF] VRゲーム (VR Game)"                             },
                { value = "402",  label = "[SF] 宇宙 (Space)"                                   },
                { value = "403",  label = "[SF] 空想科学 (Science Fiction)"                     },
                { value = "404",  label = "[SF] パニック (Panic/Disaster)"                      },
                -- その他
                { value = "9901", label = "[その他] 童話 (Fairy Tale)"                          },
                { value = "9902", label = "[その他] 詩 (Poetry)"                                },
                { value = "9903", label = "[その他] エッセイ (Essay)"                           },
                { value = "9999", label = "[その他] その他 (Other)"                             },
            }
        },
    }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page     = index + 1
    local period   = filters["period"]   or "daily"
    local modifier = filters["modifier"] or "total"
    local genre    = filters["genre"]    or ""

    -- Реальные URL-паттерны (проверено по yomou.syosetu.com/rank/top/):
    --
    -- 総合ランキング:
    --   /rank/list/type/daily_total/     ← все статусы
    --   /rank/list/type/daily_r/         ← только ongoing
    --   /rank/list/type/daily_er/        ← только completed
    --   /rank/list/type/daily_t/         ← только short story
    --   /rank/list/type/total_total/     ← всё время, все статусы
    --
    -- ジャンル別:
    --   /rank/genrelist/type/daily_101/  ← жанр 101, нет модификатора статуса
    --
    -- 異世界転生:
    --   /rank/isekailist/type/daily_1/   ← "i1" → "1"
    --   /rank/isekailist/type/daily_o/   ← "io" → "o"

    local url

    if genre == "" then
        -- 総合: период + модификатор статуса
        local suffix
        if modifier == "total" then
            suffix = period .. "_total"
        else
            suffix = period .. "_" .. modifier
        end
        url = baseUrl .. "rank/list/type/" .. suffix .. "/?p=" .. tostring(page)

    elseif string_starts_with(genre, "i") then
        -- 異世界転生: "i1" → "1", "i2" → "2", "io" → "o"
        local isekaiSuffix = genre:sub(2)
        url = baseUrl .. "rank/isekailist/type/" .. period .. "_" .. isekaiSuffix
              .. "/?p=" .. tostring(page)

    else
        -- ジャンル別: у жанрового ранкинга нет отдельного модификатора статуса
        url = baseUrl .. "rank/genrelist/type/" .. period .. "_" .. genre
              .. "/?p=" .. tostring(page)
    end

    log_info("syosetu getCatalogFiltered: " .. url)

    local r = http_get(url, { headers = HEADERS })
    if not r.success then
        log_error("syosetu getCatalogFiltered: failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    -- Реальный HTML ранкинга: <div class="ranking_list"> ... <a class="novel_h" href="...">Название</a>
    local items = parseNovelCards(r.body, ".ranking_list", ".novel_h a")

    -- Проверяем наличие следующей страницы
    local hasNext = false
    for _, a in ipairs(html_select(r.body, ".pager a")) do
        if string.find(a.text, "次") then
            hasNext = true
            break
        end
    end
    if not hasNext and #items >= 50 then hasNext = true end

    return { items = items, hasNext = hasNext }
end
