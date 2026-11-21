-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "syosetu"
name     = "Syosetu"
version  = "1.1.2"
baseUrl  = "https://ncode.syosetu.com/"
language = "ja"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr-v2/icons/narou.png"

local HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

-- ── Хелперы ──────────────────────────────────────────────────────────────────

-- Old builds ship no require_lib: keep the plugin loadable (a top-level error
-- would drop it from the source list) and fail with a visible message on the
-- first call instead. Shared libs load lazily and are cached per session.
local _libs
local function LIB(id)
    if type(require_lib) ~= "function" then
        show_error("Requires NoveLA update", "This plugin needs the shared libraries")
        error("Requires NoveLA update (require_lib)", 0)
    end
    if not _libs then _libs = {} end
    if not _libs[id] then _libs[id] = require_lib(id) end
    return _libs[id]
end

local function absUrl(href)
    return LIB("urls").absUrl(baseUrl, href)
end

-- ── Каталог (Ранкинг) ────────────────────────────────────────────────────────
function getCatalogList(index)
    return getCatalogFiltered(index, {})
end

function getCatalogFiltered(index, filters)
    local page     = LIB("catalog").nextIndex(index)
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
    local page = LIB("catalog").nextIndex(index)
    local url = "https://yomou.syosetu.com/search.php?order=hyoka&p=" .. tostring(page) .. "&word=" .. url_encode(query)
    
    log_info("syosetu search: fetching " .. url)
    
    local r = http_get(url, { headers = HEADERS })
    if not r.success then
        log_error("syosetu search: HTTP failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end
    
    local items = {}
    
    -- Ищем ВСЕ ссылки с href и фильтруем по паттерну URL новеллы
    -- Это обходит проблему с селекторами классов и вложенным парсингом
    for _, a in ipairs(html_select(r.body, "a[href]")) do
        local href = a.href or ""
        local title = a.text and string_trim(a.text) or ""
        
        -- Фильтруем только ссылки на новеллы (ncode.syosetu.com/nXXXXX/)
        if href:match("https?://ncode%.syosetu%.com/n[%w]+/?$") or 
           href:match("^/n[%w]+/?$") then
            if title ~= "" then
                table.insert(items, { 
                    title = title, 
                    url = href:sub(1,4)=="http" and href or "https://ncode.syosetu.com" .. href,
                    cover = "" 
                })
            end
        end
    end
    
    -- hasNext: проверяем наличие кнопки NEXT
    local nextLink = html_select_first(r.body, "a.nextlink")
    local hasNext = (nextLink ~= nil)
    
    return { items = items, hasNext = hasNext }
end

-- ── Детали книги, главы, текст ────────────────────────────────────────────────
-- Book/chapter markup is shared with novel18.syosetu.com; the engine lives in
-- libs/family/syosetu.lua and takes the site headers from CONFIG.

local CONFIG = {
    id      = "syosetu",
    baseUrl = baseUrl,
    headers = HEADERS,
}

function getBookTitle(bookUrl)
    return LIB("syosetu").title(CONFIG, bookUrl)
end

function getBookCoverImageUrl(bookUrl)
    return LIB("syosetu").cover(CONFIG, bookUrl)
end

function getBookDescription(bookUrl)
    return LIB("syosetu").description(CONFIG, bookUrl)
end

function getChapterList(bookUrl)
    return LIB("syosetu").chapters(CONFIG, bookUrl)
end

function getChapterListHash(bookUrl)
    return LIB("syosetu").chapterHash(CONFIG, bookUrl)
end

function getChapterText(html, url)
    return LIB("syosetu").chapterText(CONFIG, html, url)
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