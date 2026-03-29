-- ── Метаданные ───────────────────────────────────────────────────────────────
id       = "wtrlab"
name     = "WTR-LAB"
version  = "1.0.8"
baseUrl  = "https://wtr-lab.com/"
language = "MTL"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/wtr-lab.png"

-- ── Настройки ────────────────────────────────────────────────────────────────
local PREF_MODE = "wtrlab_mode"  -- "ai" | "raw"

local function getMode()
    local v = get_preference(PREF_MODE)
    return (v ~= "" and v) or "ai"
end

-- ── Вспомогательные функции ──────────────────────────────────────────────────

local function absUrl(href)
    if href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

-- ── Каталог ──────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local url = baseUrl .. "novel-list?page=" .. tostring(page)
    local r = http_get(url)
    if not r.success then
        log_error("wtrlab getCatalogList failed: " .. url .. " code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, card in ipairs(html_select(r.body, "div.serie-item")) do
        local titleEl = html_select_first(card.html, "a.title")
        if titleEl then
            local cover = html_attr(card.html, ".image-wrap img", "src")
            table.insert(items, {
                title = string_trim(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(cover)
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local url = baseUrl .. "novel-finder?text=" .. url_encode(query) .. "&page=" .. tostring(page)
    local r = http_get(url)
    if not r.success then
        log_error("wtrlab getCatalogSearch failed code=" .. tostring(r.code))
        return { items = {}, hasNext = false }
    end

    local items = {}
    for _, card in ipairs(html_select(r.body, "div.serie-item")) do
        local titleEl = html_select_first(card.html, "a.title")
        if titleEl then
            local cover = html_attr(card.html, ".image-wrap img", "src")
            table.insert(items, {
                title = string_trim(titleEl.text),
                url   = absUrl(titleEl.href),
                cover = absUrl(cover)
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги ─────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, "h1.long-title")
    if el then return string_trim(el.text) end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local cover = html_attr(r.body, ".image-section .image-wrap img", "src")
    if cover ~= "" then return absUrl(cover) end
    return nil
end

function getBookDescription(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local el = html_select_first(r.body, ".desc-wrap .description")
    if el then return string_trim(el.text) end
    return nil
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    for _, lineEl in ipairs(html_select(r.body, ".detail-line")) do
        local t = lineEl.text
        if string.find(t, "Chapter") or string.find(t, "chapter") then
            return string_trim(t)
        end
    end
    return nil
end

-- ── Список глав ──────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: cannot extract novelId from " .. bookUrl)
        return {}
    end
    local slug = string.match(bookUrl, "/novel/%d+/([^/?#]+)") or ""

    sleep(300)

    local apiUrl = baseUrl .. "api/chapters/" .. novelId
    local r = http_get(apiUrl, { headers = { ["Referer"] = bookUrl } })
    if not r.success then
        log_error("wtrlab: chapters API failed code=" .. tostring(r.code))
        return {}
    end

    local data = json_parse(r.body)
    if not data then
        log_error("wtrlab: cannot parse chapters JSON")
        return {}
    end

    local chaptersData = data.chapters
    if not chaptersData then return {} end

    local chapters = {}
    for i = 1, #chaptersData do
        local ch = chaptersData[i]
        local order = ch.order or i
        local title = ch.title or ("Chapter " .. tostring(order))
        local chUrl = baseUrl .. "novel/" .. novelId .. "/" .. slug .. "/chapter-" .. tostring(order)
        table.insert(chapters, {
            title = tostring(order) .. ": " .. title,
            url   = chUrl
        })
    end

    log_info("wtrlab: loaded " .. tostring(#chapters) .. " chapters for novelId=" .. novelId)
    return chapters
end

-- ── Текст главы ──────────────────────────────────────────────────────────────

local function cleanParagraph(text)
    text = string_normalize(text)
    text = regex_replace(text, "(?i)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = regex_replace(text, "(?i)\\A[\\s\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    return string_trim(text)
end

local function decryptBody(rawBody)
    if not string_starts_with(rawBody, "arr:") then return rawBody end

    log_info("wtrlab: body encrypted (arr:...), sending to proxy")
    local r = http_post(
        "https://wtr-lab-proxy.fly.dev/chapter",
        json_stringify({ payload = rawBody }),
        { headers = { ["Content-Type"] = "application/json" } }
    )
    if not r.success then
        log_error("wtrlab: proxy failed code=" .. tostring(r.code))
        return rawBody
    end

    local data = json_parse(r.body)
    if not data then return rawBody end

    if type(data) == "table" then
        if data[1] ~= nil then return json_stringify(data) end
        if data.body ~= nil then return json_stringify(data.body) end
    end

    return rawBody
end

local function applyGlossaryAndPatches(text, glossary, patches)
    if glossary then
        for idx, term in pairs(glossary) do
            local marker1 = "※" .. tostring(idx) .. "⛬"
            local marker2 = "※" .. tostring(idx) .. "〓"
            text = text:gsub(marker1, term)
            text = text:gsub(marker2, term)
        end
    end
    if patches then
        for _, patch in ipairs(patches) do
            if patch.zh and patch.en then
                text = text:gsub(patch.zh, patch.en)
            end
        end
    end
    return text
end

local function buildParagraphs(rawBody, resolvedBody, glossary, patches)
    local paragraphs = {}
    local bodyArray = json_parse(resolvedBody)

    if type(bodyArray) == "table" and bodyArray[1] ~= nil then
        for _, item in ipairs(bodyArray) do
            if type(item) == "string" then
                local text = cleanParagraph(item)
                if text ~= "[image]" and text ~= "" then
                    text = applyGlossaryAndPatches(text, glossary, patches)
                    if text ~= "" then
                        table.insert(paragraphs, text)
                    end
                end
            end
        end
    else
        for _, line in ipairs(string_split(resolvedBody, "\n")) do
            local text = string_trim(line)
            if text ~= "" then table.insert(paragraphs, text) end
        end
    end

    return paragraphs
end

function getChapterText(html, chapterUrl)
    if not chapterUrl or chapterUrl == "" then
        chapterUrl = html_attr(html, "link[rel='canonical']", "href")
    end
    if not chapterUrl or chapterUrl == "" then
        log_error("wtrlab: no chapterUrl available")
        return ""
    end

    log_info("wtrlab: getChapterText url=" .. chapterUrl)

    local novelId = string.match(chapterUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: 'novel' not found in URL: " .. chapterUrl)
        return ""
    end

    local chapterNo = tonumber(string.match(chapterUrl, "/chapter%-(%d+)")) or 1
    local mode = getMode()
    local translateParam = (mode == "raw") and "web" or "ai"

    log_info("wtrlab: novelId=" .. novelId .. " chapterNo=" .. tostring(chapterNo) ..
             " translate=" .. translateParam)

    local requestBody = json_stringify({
        translate   = translateParam,
        language    = "none",
        raw_id      = novelId,
        chapter_no  = chapterNo,
        retry       = false,
        force_retry = false
    })

    local r = http_post(
        baseUrl .. "api/reader/get",
        requestBody,
        {
            headers = {
                ["Content-Type"] = "application/json",
                ["Referer"]      = chapterUrl,
                ["Origin"]       = regex_replace(baseUrl, "/$", "")
            }
        }
    )

    if not r.success then
        log_error("wtrlab: API reader/get failed code=" .. tostring(r.code))
        return ""
    end

    local json = json_parse(r.body)
    if not json then
        log_error("wtrlab: response is not JSON")
        return ""
    end

    if json.success == false then
        local errCode = json.code or "?"
        local errMsg  = json.error or "Unknown API error"
        log_error("wtrlab: API error [" .. tostring(errCode) .. "]: " .. errMsg)
        error("[" .. tostring(errCode) .. "] " .. errMsg)
    end

    local outerData = json.data
    local data = nil
    if outerData then
        data = outerData.data or outerData
    end
    if not data then
        log_error("wtrlab: no 'data' in response")
        return ""
    end

    local body = data.body
    if not body then
        log_error("wtrlab: no 'body' in data")
        return ""
    end

    local rawBody
    if type(body) == "table" then
        rawBody = json_stringify(body)
    else
        rawBody = tostring(body)
    end

    if rawBody == "" or rawBody == "null" then
        log_error("wtrlab: body is empty")
        return ""
    end

    local resolvedBody = decryptBody(rawBody)

    -- ── v2 глоссарий (правильные имена с сайта) ──────────────────────────────
    -- Строим обратный словарь: любой вариант → правильное имя (translations[1])
    local v2Lookup = {}  -- [variant] = correct name
    local v2Url = baseUrl .. "api/v2/reader/terms/" .. novelId .. ".json"
    local v2r = http_get(v2Url, {
        headers = {
            ["Referer"] = chapterUrl,
            ["Origin"]  = regex_replace(baseUrl, "/$", "")
        }
    })
    if v2r.success then
        local v2data = json_parse(v2r.body)
        local termsArray = nil
        if v2data and type(v2data) == "table" then
            if v2data.glossaries and v2data.glossaries[1] and
               v2data.glossaries[1].data and v2data.glossaries[1].data.terms then
                termsArray = v2data.glossaries[1].data.terms
            end
        end
        if termsArray then
            -- Первый проход: собираем все правильные имена (translations[1])
            -- чтобы не перезаписать их во втором проходе
            local correctNames = {}
            for _, term in ipairs(termsArray) do
                local translations = term[1]
                if type(translations) == "table" and translations[1] and translations[1] ~= "" then
                    correctNames[translations[1]] = true
                end
            end
            -- Второй проход: маппим все варианты (translations[2..n]),
            -- но пропускаем те что являются чьим-то правильным именем (correctNames)
            local count = 0
            for _, term in ipairs(termsArray) do
                local translations = term[1]
                if type(translations) == "table" and translations[1] and translations[1] ~= "" then
                    local correct = translations[1]
                    for i = 2, #translations do
                        local variant = translations[i]
                        if variant ~= "" and not correctNames[variant] then
                            v2Lookup[variant] = correct
                            count = count + 1
                        end
                    end
                end
            end
            log_info("wtrlab: v2 lookup built, " .. tostring(count) .. " variants mapped")
        else
            log_info("wtrlab: v2 glossary: unexpected structure")
        end
    else
        log_info("wtrlab: v2 glossary fetch failed code=" .. tostring(v2r.code) .. ", will use glossary_data as-is")
    end

    -- ── Глоссарий ─────────────────────────────────────────────────────────────
    -- Берём termEntry[1] из glossary_data, затем ищем в v2Lookup —
    -- если этот вариант известен v2, подставляем правильное имя оттуда.
    local glossary = {}
    if data.glossary_data and data.glossary_data.terms then
        local terms = data.glossary_data.terms
        log_info("wtrlab: glossary terms count=" .. tostring(#terms))
        for i = 1, #terms do
            local termEntry = terms[i]
            if type(termEntry) == "table" then
                local idx = i - 1  -- 0-based, совпадает с маркерами ※idx⛬
                local raw = termEntry[1] or ""
                if raw ~= "" then
                    local termValue = v2Lookup[raw] or raw
                    glossary[idx] = termValue
                    if v2Lookup[raw] then
                        log_info("wtrlab: glossary[" .. idx .. "] '" .. raw .. "' -> '" .. termValue .. "' (v2 corrected)")
                    end
                end
            end
        end
    else
        log_info("wtrlab: no glossary_data in response")
    end

    -- ── Патчи ─────────────────────────────────────────────────────────────────
    local patches = {}
    if data.patch then
        log_info("wtrlab: patches count=" .. tostring(#data.patch))
        for _, patchItem in ipairs(data.patch) do
            if patchItem.zh and patchItem.en and patchItem.zh ~= "" then
                log_info("wtrlab: patch '" .. patchItem.zh .. "' → '" .. patchItem.en .. "'")
                table.insert(patches, { zh = patchItem.zh, en = patchItem.en })
            end
        end
    else
        log_info("wtrlab: no patches in response")
    end

    local paragraphs = buildParagraphs(rawBody, resolvedBody, glossary, patches)

    if #paragraphs == 0 then
        log_info("wtrlab: 0 paragraphs parsed")
        return ""
    end

    log_info("wtrlab: parsed " .. tostring(#paragraphs) .. " paragraphs")

    return table.concat(paragraphs, "\n\n")
end

-- ── Settings schema ───────────────────────────────────────────────────────────

function getSettingsSchema()
    return {
        {
            key     = PREF_MODE,
            type    = "select",
            label   = "Translation Mode",
            current = getMode(),
            options = {
                { value = "ai",  label = "AI (Beta)" },
                { value = "raw", label = "Raw (Web)" }
            }
        }
    }
end
-- ── Жанры на странице книги ───────────────────────────────────────────────────

function getBookGenres(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end

    local genres = {}

    -- Основной способ: таблица с td "Genre" → следующий td → ссылки
    for _, row in ipairs(html_select(r.body, "tr")) do
        local tds = html_select(row.html, "td")
        if #tds >= 2 then
            local label = string_trim(tds[1].text)
            if label == "Genre" or label == "Genres" then
                for _, a in ipairs(html_select(tds[2].html, "a")) do
                    local g = string_trim(a.text):gsub(",$", "")
                    if g ~= "" then table.insert(genres, g) end
                end
                break
            end
        end
    end

    -- Запасной: .genre или .genres .genre
    if #genres == 0 then
        for _, el in ipairs(html_select(r.body, ".genre")) do
            local g = string_trim(el.text):gsub(",$", "")
            if g ~= "" then table.insert(genres, g) end
        end
    end

    return genres
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "orderBy",
            label        = "Order by",
            defaultValue = "update",
            options = {
                { value = "update",       label = "Update Date"    },
                { value = "date",         label = "Addition Date"  },
                { value = "random",       label = "Random"         },
                { value = "weekly_rank",  label = "Weekly View"    },
                { value = "monthly_rank", label = "Monthly View"   },
                { value = "view",         label = "All-Time View"  },
                { value = "name",         label = "Name"           },
                { value = "reader",       label = "Reader"         },
                { value = "chapter",      label = "Chapter"        },
                { value = "rating",       label = "Rating"         },
                { value = "total_rate",   label = "Review Count"   },
                { value = "vote",         label = "Vote Count"     },
            }
        },
        {
            type         = "select",
            key          = "order",
            label        = "Order",
            defaultValue = "desc",
            options = {
                { value = "desc", label = "Descending" },
                { value = "asc",  label = "Ascending"  },
            }
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "All"       },
                { value = "ongoing",   label = "Ongoing"   },
                { value = "completed", label = "Completed" },
                { value = "hiatus",    label = "Hiatus"    },
                { value = "dropped",   label = "Dropped"   },
            }
        },
        {
            type         = "select",
            key          = "release_status",
            label        = "Release Status",
            defaultValue = "all",
            options = {
                { value = "all",      label = "All"       },
                { value = "released", label = "Released"  },
                { value = "voting",   label = "On Voting" },
            }
        },
        {
            type         = "select",
            key          = "addition_age",
            label        = "Addition Age",
            defaultValue = "all",
            options = {
                { value = "all",   label = "All"       },
                { value = "day",   label = "< 2 Days"  },
                { value = "week",  label = "< 1 Week"  },
                { value = "month", label = "< 1 Month" },
            }
        },
        {
            type         = "select",
            key          = "min_chapters",
            label        = "Minimum Chapters",
            defaultValue = "",
            options = {
                { value = "",     label = "Any"       },
                { value = "1",    label = "1+"         },
                { value = "10",   label = "10+"        },
                { value = "50",   label = "50+"        },
                { value = "100",  label = "100+"       },
                { value = "200",  label = "200+"       },
                { value = "500",  label = "500+"       },
                { value = "1000", label = "1000+"      },
            }
        },
        {
            type         = "select",
            key          = "min_rating",
            label        = "Minimum Rating",
            defaultValue = "",
            options = {
                { value = "",    label = "Any"   },
                { value = "1.0", label = "1.0+"  },
                { value = "2.0", label = "2.0+"  },
                { value = "3.0", label = "3.0+"  },
                { value = "3.5", label = "3.5+"  },
                { value = "4.0", label = "4.0+"  },
                { value = "4.5", label = "4.5+"  },
            }
        },
        -- ── Жанры (строковые slug-значения с сайта) ──────────────────────────
        {
            type         = "select",
            key          = "genre_operator",
            label        = "Genre (And/Or)",
            defaultValue = "and",
            options = {
                { value = "and", label = "And" },
                { value = "or",  label = "Or"  },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "1",  label = "Action"        },
                { value = "2",  label = "Adult"         },
                { value = "3",  label = "Adventure"     },
                { value = "4",  label = "Comedy"        },
                { value = "5",  label = "Drama"         },
                { value = "6",  label = "Ecchi"         },
                { value = "7",  label = "Erciyuan"      },
                { value = "8",  label = "Fan-fiction"   },
                { value = "9",  label = "Fantasy"       },
                { value = "10", label = "Game"          },
                { value = "11", label = "Gender Bender" },
                { value = "12", label = "Harem"         },
                { value = "13", label = "Historical"    },
                { value = "14", label = "Horror"        },
                { value = "15", label = "Josei"         },
                { value = "16", label = "Martial Arts"  },
                { value = "17", label = "Mature"        },
                { value = "18", label = "Mecha"         },
                { value = "19", label = "Military"      },
                { value = "20", label = "Mystery"       },
                { value = "21", label = "Psychological" },
                { value = "22", label = "Romance"       },
                { value = "23", label = "School Life"   },
                { value = "24", label = "Sci-fi"        },
                { value = "25", label = "Seinen"        },
                { value = "26", label = "Shoujo"        },
                { value = "27", label = "Shoujo-ai"     },
                { value = "28", label = "Shounen"       },
                { value = "29", label = "Shounen-ai"    },
                { value = "30", label = "Slice of Life" },
                { value = "31", label = "Smut"          },
                { value = "32", label = "Sports"        },
                { value = "33", label = "Supernatural"  },
                { value = "34", label = "Tragedy"       },
                { value = "35", label = "Urban Life"    },
                { value = "36", label = "Wuxia"         },
                { value = "37", label = "Xianxia"       },
                { value = "38", label = "Xuanhuan"      },
                { value = "39", label = "Yaoi"          },
                { value = "40", label = "Yuri"          },
            }
        },
        -- ── Теги (числовые ID с сайта) ────────────────────────────────────────
        {
            type         = "select",
            key          = "tag_operator",
            label        = "Tag (And/Or)",
            defaultValue = "and",
            options = {
                { value = "and", label = "And" },
                { value = "or",  label = "Or"  },
            }
        },
        {
            type  = "tristate",
            key   = "tags",
            label = "Tags",
            options = {
                -- Protagonist Archetypes
                { value = "417", label = "Male Protagonist"               },
                { value = "275", label = "Female Protagonist"             },
                { value = "717", label = "Transmigration"                 },
                { value = "578", label = "Reincarnation"                  },
                { value = "577", label = "Reincarnated in Another World"  },
                { value = "721", label = "Transported to Another World"   },
                { value = "506", label = "Overpowered Protagonist"        },
                { value = "134", label = "Clever Protagonist"             },
                { value = "750", label = "Weak to Strong"                 },
                { value = "306", label = "Genius Protagonist"             },
                { value = "560", label = "Protagonist Strong from Start"  },
                { value = "682", label = "Strong to Stronger"             },
                { value = "731", label = "Underestimated Protagonist"     },
                { value = "595", label = "Ruthless Protagonist"           },
                { value = "171", label = "Cunning Protagonist"            },
                { value = "342", label = "Hiding True Abilities"          },
                { value = "343", label = "Hiding True Identity"           },
                { value = "111", label = "Calm Protagonist"               },
                { value = "142", label = "Cold Protagonist"               },
                { value = "197", label = "Determined Protagonist"         },
                { value = "547", label = "Pragmatic Protagonist"          },
                { value = "555", label = "Proactive Protagonist"          },
                { value = "407", label = "Low-key Protagonist"            },
                { value = "611", label = "Secretive Protagonist"          },
                { value = "409", label = "Lucky Protagonist"              },
                { value = "630", label = "Shameless Protagonist"          },
                { value = "43",  label = "Antihero Protagonist"           },
                { value = "246", label = "Evil Protagonist"               },
                { value = "312", label = "God Protagonist"                },
                { value = "329", label = "Harem-seeking Protagonist"      },
                { value = "328", label = "Hard-Working Protagonist"       },
                { value = "268", label = "Fast Learner"                   },
                { value = "606", label = "Second Chance"                  },
                { value = "829", label = "Reborn"                         },
                { value = "248", label = "Evolution"                      },
                -- Power Systems
                { value = "696", label = "System"                         },
                { value = "169", label = "Cultivation"                    },
                { value = "667", label = "Special Abilities"              },
                { value = "297", label = "Game Elements"                  },
                { value = "122", label = "Cheats"                         },
                { value = "410", label = "Magic"                          },
                { value = "267", label = "Fast Cultivation"               },
                { value = "390", label = "Level System"                   },
                { value = "735", label = "Unlimited Flow"                 },
                { value = "693", label = "Survival Game"                  },
                { value = "742", label = "Virtual Reality"                },
                { value = "315", label = "Godly Powers"                   },
                { value = "95",  label = "Body Tempering"                 },
                { value = "341", label = "Hidden Abilities"               },
                { value = "27",  label = "Alchemy"                        },
                { value = "732", label = "Unique Cultivation Technique"   },
                { value = "93",  label = "Bloodlines"                     },
                { value = "830", label = "Reality-Game Fusion"            },
                { value = "827", label = "Class Awakening"                },
                { value = "694", label = "Sword And Magic"                },
                { value = "695", label = "Sword Wielder"                  },
                -- Worldbuilding
                { value = "446", label = "Modern Day"                     },
                { value = "265", label = "Fantasy World"                  },
                { value = "47",  label = "Apocalypse"                     },
                { value = "544", label = "Post-apocalyptic"               },
                { value = "30",  label = "Alternate World"                },
                { value = "459", label = "Multiple Realms"                },
                { value = "756", label = "World Hopping"                  },
                { value = "710", label = "Time Travel"                    },
                { value = "294", label = "Futuristic Setting"             },
                { value = "505", label = "Outer Space"                    },
                { value = "35",  label = "Ancient Times"                  },
                { value = "34",  label = "Ancient China"                  },
                { value = "510", label = "Parallel Worlds"                },
                { value = "221", label = "Dungeons"                       },
                { value = "828", label = "Spiritual Energy Revival"       },
                -- Socio-Political Structures
                { value = "379", label = "Kingdom Building"               },
                { value = "388", label = "Leadership"                     },
                { value = "5",   label = "Academy"                        },
                { value = "536", label = "Politics"                       },
                { value = "748", label = "Wars"                           },
                { value = "437", label = "Military"                       },
                { value = "485", label = "Nobles"                         },
                { value = "594", label = "Royalty"                        },
                { value = "380", label = "Kingdoms"                       },
                { value = "108", label = "Business Management"            },
                { value = "540", label = "Poor to Rich"                   },
                { value = "802", label = "Territory Management"           },
                -- Narrative
                { value = "601", label = "Schemes And Conspiracies"       },
                { value = "692", label = "Survival"                       },
                { value = "585", label = "Revenge"                        },
                { value = "83",  label = "Betrayal"                       },
                -- Beings & Factions
                { value = "191", label = "Demons"                         },
                { value = "452", label = "Monsters"                       },
                { value = "216", label = "Dragons"                        },
                { value = "316", label = "Gods"                           },
                { value = "357", label = "Immortals"                      },
                { value = "80",  label = "Beasts"                         },
                { value = "264", label = "Fantasy Creatures"              },
                { value = "765", label = "Zombies"                        },
                { value = "473", label = "Mythology"                      },
                { value = "233", label = "Elves"                          },
                -- Relationship Tropes
                { value = "257", label = "Family"                         },
                { value = "592", label = "Romantic Subplot"               },
                { value = "198", label = "Devoted Love Interests"         },
                { value = "211", label = "Doting Love Interests"          },
                { value = "225", label = "Early Romance"                  },
                { value = "659", label = "Slow Romance"                   },
                { value = "538", label = "Polygamy"                       },
                { value = "545", label = "Power Couple"                   },
                { value = "681", label = "Strong Love Interests"          },
                { value = "55",  label = "Arranged Marriage"              },
                -- Professional Archetypes
                { value = "640", label = "Showbiz"                        },
                { value = "117", label = "Celebrities"                    },
                { value = "433", label = "Medical Knowledge"              },
                { value = "208", label = "Doctors"                        },
                { value = "428", label = "Master-Disciple Relationship"   },
                { value = "154", label = "Cooking"                        },
                -- Miscellaneous
                { value = "266", label = "Farming"                        },
                { value = "414", label = "Magical Space"                  },
                { value = "459", label = "Multiple Realms"                },
                { value = "442", label = "Misunderstandings"              },
                { value = "455", label = "Multiple Identities"            },
                { value = "474", label = "Naive Protagonist"              },
                { value = "492", label = "Older Love Interests"           },
                { value = "368", label = "Interdimensional Travel"        },
            }
        },
    }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page           = index + 1
    local orderBy        = filters["orderBy"]        or "update"
    local order          = filters["order"]          or "desc"
    local status         = filters["status"]         or "all"
    local release_status = filters["release_status"] or "all"
    local addition_age   = filters["addition_age"]   or "all"
    local min_chapters   = filters["min_chapters"]   or ""
    local min_rating     = filters["min_rating"]     or ""
    local genre_op       = filters["genre_operator"] or "and"
    local tag_op         = filters["tag_operator"]   or "and"

    local genres_inc = filters["genres_included"] or {}
    local genres_exc = filters["genres_excluded"] or {}
    local tags_inc   = filters["tags_included"]   or {}
    local tags_exc   = filters["tags_excluded"]   or {}

    -- WTR-LAB использует _next/data API — нужен buildId со страницы novel-finder
    local finderUrl = baseUrl .. "en/novel-finder"
    local fr = http_get(finderUrl)
    if not fr.success then return { items = {}, hasNext = false } end

    local buildId = string.match(fr.body, '"buildId":"([^"]+)"')
    if not buildId then return { items = {}, hasNext = false } end

    local params = "orderBy=" .. orderBy
                .. "&order="          .. order
                .. "&status="         .. status
                .. "&release_status=" .. release_status
                .. "&addition_age="   .. addition_age
                .. "&page="           .. tostring(page)

    if min_chapters ~= "" then params = params .. "&minc=" .. url_encode(min_chapters) end
    if min_rating   ~= "" then params = params .. "&minr=" .. url_encode(min_rating)   end

    if #genres_inc > 0 then
        params = params .. "&gi=" .. table.concat(genres_inc, ",") .. "&gc=" .. genre_op
    end
    if #genres_exc > 0 then
        params = params .. "&ge=" .. table.concat(genres_exc, ",")
    end
    if #tags_inc > 0 then
        params = params .. "&ti=" .. table.concat(tags_inc, ",") .. "&tc=" .. tag_op
    end
    if #tags_exc > 0 then
        params = params .. "&te=" .. table.concat(tags_exc, ",")
    end

    local apiUrl = baseUrl .. "_next/data/" .. buildId .. "/en/novel-finder.json?" .. params
    local r = http_get(apiUrl)
    if not r.success then return { items = {}, hasNext = false } end

    local data = json_parse(r.body)
    if not data then
        log_error("wtrlab getCatalogFiltered: json_parse failed, body=" .. r.body:sub(1, 300))
        return { items = {}, hasNext = false }
    end

    local pageProps = data.pageProps
    if not pageProps then
        log_error("wtrlab getCatalogFiltered: no pageProps, body=" .. r.body:sub(1, 300))
        return { items = {}, hasNext = false }
    end

    local series = pageProps.series
    if not series then
        log_error("wtrlab getCatalogFiltered: no series, body=" .. r.body:sub(1, 300))
        return { items = {}, hasNext = false }
    end

    local seen = {}
    local items = {}
    for _, novel in ipairs(series) do
        local rawId = tostring(novel.raw_id or "")
        if rawId ~= "" and not seen[rawId] then
            seen[rawId] = true
            local title = (novel.data and novel.data.title) or ""
            local cover = (novel.data and novel.data.image) or ""
            local slug  = novel.slug or ""
            table.insert(items, {
                title = string_clean(title),
                url   = baseUrl .. "en/novel/" .. rawId .. "/" .. slug,
                cover = absUrl(cover)
            })
        end
    end

    return { items = items, hasNext = #items > 0 }
end