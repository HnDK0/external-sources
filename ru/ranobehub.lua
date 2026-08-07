-- ── Метаданные ────────────────────────────────────────────────────────────────
id       = "ranobehub"
name     = "RanobeHub"
version  = "1.0.3"
baseUrl  = "https://ranobehub.org"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ranobehub.png"

-- ── Константы ─────────────────────────────────────────────────────────────────

local apiBase = "https://ranobehub.org/api/"

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function extractId(bookUrl)
  local segment = bookUrl:gsub(baseUrl .. "/ranobe/", ""):match("^([^/?#]+)")
  if not segment then return nil end
  return segment:match("^(%d+)")
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = string_trim(text)
  return text
end

local function pickTitle(names, fallback)
  if not names then return fallback or "" end
  return names.rus or names.eng or names.original or fallback or ""
end

local function parseResource(data)
  local items = {}
  if not data or not data.resource then return items end
  for _, novel in ipairs(data.resource) do
    local title = pickTitle(novel.names, novel.name)
    local id    = tostring(novel.id or "")
    local cover = novel.poster and novel.poster.medium or ""
    if title ~= "" and id ~= "" then
      table.insert(items, {
        title = string_clean(title),
        url   = baseUrl .. "/ranobe/" .. id,
        cover = absUrl(cover)
      })
    end
  end
  return items
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

-- Собирает URL /api/search. Важно: API на page=1 отвечает 301 без тела
-- (редиректит на URL без параметра page), поэтому для первой страницы page не
-- передаём вовсе — это ровно цель редиректа; http_get движка может не следовать
-- 301. Для остальных страниц page = N+1 (движок передаёт index с 0).
local function searchUrl(page, queryString)
  local url = apiBase .. "search?" .. queryString
  if page > 1 then url = url .. "&page=" .. tostring(page) end
  return url
end

local function defaultQueryString()
  return "sort=computed_rating&status=0&take=40"
end

local function parseSearchResponse(body)
  local data = json_parse(body)
  if not data then return { items = {}, hasNext = false } end
  local items = parseResource(data)
  -- hasNext считаем по пагинации API (currentPage < lastPage), а не по наличию
  -- items: на последней странице карточки ещё есть, но следующей страницы нет —
  -- иначе движок сделает лишний запрос за концом списка.
  local pag = data.pagination
  local hasNext = (pag and pag.currentPage and pag.lastPage
                   and pag.currentPage < pag.lastPage) or false
  return { items = items, hasNext = hasNext }
end

function getCatalogList(index)
  local r = http_get(searchUrl(index + 1, defaultQueryString()))
  if not r.success then return { items = {}, hasNext = false } end
  return parseSearchResponse(r.body)
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end
  local url = apiBase .. "fulltext/global?query=" .. url_encode(query) .. "&take=10"
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end
  local results = json_parse(r.body)
  if not results then return { items = {}, hasNext = false } end
  local items = {}
  for _, block in ipairs(results) do
    if type(block) == "table" then
      local meta = block.meta
      if meta and meta.key == "ranobe" and block.data then
        for _, novel in ipairs(block.data) do
          local title = pickTitle(novel.names, novel.name)
          local id    = tostring(novel.id or "")
          local cover = novel.image and novel.image:gsub("/small", "/medium") or ""
          if title ~= "" and id ~= "" then
            table.insert(items, {
              title = string_clean(title),
              url   = baseUrl .. "/ranobe/" .. id,
              cover = absUrl(cover)
            })
          end
        end
      end
    end
  end
  return { items = items, hasNext = false }
end

-- ── Детали книги ──────────────────────────────────────────────────────────────

local function fetchBookData(bookUrl)
  local id = extractId(bookUrl)
  if not id then return nil end
  local r = http_get(apiBase .. "ranobe/" .. id)
  if not r.success then return nil end
  local parsed = json_parse(r.body)
  return parsed and parsed.data or nil
end

function getBookTitle(bookUrl)
  local data = fetchBookData(bookUrl)
  if not data then return nil end
  local title = pickTitle(data.names, data.name)
  return title ~= "" and string_clean(title) or nil
end

function getBookCoverImageUrl(bookUrl)
  local data = fetchBookData(bookUrl)
  if not data then return nil end
  local cover = data.posters and data.posters.medium or ""
  return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
  local data = fetchBookData(bookUrl)
  if not data then return nil end
  local desc = data.description or ""
  desc = regex_replace(desc, "<[^>]*>", "")
  return string_trim(desc) ~= "" and string_trim(desc) or nil
end

function getBookGenres(bookUrl)
  local data = fetchBookData(bookUrl)
  if not data or not data.tags then return {} end
  local genres = {}
  local function addTags(tagArray)
    if not tagArray then return end
    for _, tag in ipairs(tagArray) do
      local label = (tag.names and (tag.names.rus or tag.names.eng)) or tag.title or ""
      label = string_trim(label)
      if label ~= "" then table.insert(genres, label) end
    end
  end
  addTags(data.tags.genres)
  addTags(data.tags.events)
  return genres
end

-- ── Рейтинг книги ─────────────────────────────────────────────────────────────

function getBookRating(bookUrl)
  -- На странице книги в строке «Оценки» — «Качество перевода» («8.1 (36)»):
  -- оценка читателей по шкале 1-10, скрыта при <3 голосах. Поле rating в JSON
  -- API — счётчик лайков, рейтингом не является, поэтому читаем только HTML.
  local r = http_get(bookUrl)
  if not r.success then return nil end
  local el = html_select_first(r.body, "div[data-tippy-content='Качество перевода']")
  if not el then return nil end
  local score = string.match(string_clean(el.text), "%d+%.?%d*")
  if not score then return nil end
  return "Rating: " .. score .. "/10"
end

-- ── Список глав ───────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local id = extractId(bookUrl)
  if not id then
    log_error("ranobehub: cannot extract id from " .. bookUrl)
    return {}
  end
  local r = http_get(apiBase .. "ranobe/" .. id .. "/contents")
  if not r.success then
    log_error("ranobehub: contents failed code=" .. tostring(r.code))
    return {}
  end
  local data = json_parse(r.body)
  if not data or not data.volumes then return {} end
  local chapters = {}
  for _, volume in ipairs(data.volumes) do
    local volNum = tostring(volume.num or "")
    if volume.chapters then
      for _, chapter in ipairs(volume.chapters) do
        local chNum = tostring(chapter.num or "")
        local title = chapter.name or ("Chapter " .. chNum)
        local chUrl = baseUrl .. "/ranobe/" .. id .. "/" .. volNum .. "/" .. chNum
        table.insert(chapters, {
          title  = string_clean(title),
          url    = chUrl,
          volume = "Том " .. volNum
        })
      end
    end
  end
  return chapters
end

-- ── Хэш для обновлений ────────────────────────────────────────────────────────

function getChapterListHash(bookUrl)
  local id = extractId(bookUrl)
  if not id then return nil end
  local r = http_get(apiBase .. "ranobe/" .. id .. "/contents")
  if not r.success then return nil end
  local data = json_parse(r.body)
  if not data or not data.volumes then return nil end
  local volumes = data.volumes
  local lastVol = volumes[#volumes]
  if not lastVol or not lastVol.chapters then return nil end
  local lastCh = lastVol.chapters[#lastVol.chapters]
  return lastCh and tostring(lastCh.num) or nil
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html, url)
  local cleaned = html_remove(html, "script", "style", ".ads-desktop", ".ads-mobile")
  local el = html_select_first(cleaned, "div.ui.text.container[data-container]")
  if el then
    local inner = html_remove(el.html, ".title-wrapper", ".chapter-hoticons", ".tablet.or.lower.hidden")
    return applyStandardContentTransforms(html_text(inner))
  end
  return ""
end

-- ── Список фильтров ───────────────────────────────────────────────────────────

function getFilterList()
  return {

    -- Сортировка
    {
      type             = "sort",
      key              = "sort",
      label            = "Сортировка",
      defaultValue     = "computed_rating",
      defaultAscending = false,
      options = {
        { value = "computed_rating", label = "По рейтингу"           },
        { value = "last_chapter_at", label = "По дате обновления"    },
        { value = "created_at",      label = "По дате добавления"    },
        { value = "name_rus",        label = "По названию"           },
        { value = "views",           label = "По просмотрам"         },
        { value = "count_chapters",  label = "По количеству глав"    },
        { value = "count_of_symbols",label = "По объёму перевода"    },
      }
    },

    -- Статус перевода
    {
      type         = "select",
      key          = "status",
      label        = "Статус перевода",
      defaultValue = "0",
      options = {
        { value = "0", label = "Любой"      },
        { value = "1", label = "В процессе" },
        { value = "2", label = "Завершено"  },
        { value = "3", label = "Заморожено" },
        { value = "4", label = "Неизвестно" },
      }
    },

    -- Страна
    {
      type  = "checkbox",
      key   = "country",
      label = "Страна",
      options = {
        { value = "1", label = "Япония" },
        { value = "2", label = "Китай"  },
        { value = "3", label = "Корея"  },
        { value = "4", label = "США"    },
      }
    },

    -- Жанры
    {
      type  = "tristate",
      key   = "tags",
      label = "Жанры",
      options = {
        { value = "22",  label = "Боевые искусства"   },
        { value = "114", label = "Гарем"              },
        { value = "246", label = "Гендер бендер"      },
        { value = "216", label = "Дзёсэй"             },
        { value = "115", label = "Для взрослых"       },
        { value = "7",   label = "Драма"              },
        { value = "101", label = "Исторический"       },
        { value = "17",  label = "Комедия"            },
        { value = "638", label = "Лоликон"            },
        { value = "922", label = "Магический реализм" },
        { value = "24",  label = "Меха"               },
        { value = "12",  label = "Милитари"           },
        { value = "2",   label = "Мистика"            },
        { value = "13",  label = "Научная фантастика" },
        { value = "747", label = "Непристойность"     },
        { value = "93",  label = "Повседневность"     },
        { value = "11",  label = "Приключение"        },
        { value = "18",  label = "Психология"         },
        { value = "9",   label = "Романтика"          },
        { value = "20",  label = "Сверхъестественное" },
        { value = "15",  label = "Сёдзё"              },
        { value = "23",  label = "Сёдзё-ай"           },
        { value = "189", label = "Сёнэн"              },
        { value = "680", label = "Сёнэн-ай"           },
        { value = "420", label = "Спорт"              },
        { value = "5",   label = "Сэйнэн"             },
        { value = "242", label = "Сюаньхуа"           },
        { value = "364", label = "Сянься"             },
        { value = "19",  label = "Трагедия"           },
        { value = "3",   label = "Триллер"            },
        { value = "1",   label = "Ужасы"              },
        { value = "720", label = "Уся"                },
        { value = "8",   label = "Фэнтези"            },
        { value = "21",  label = "Школьная жизнь"     },
        { value = "14",  label = "Экшн"               },
        { value = "327", label = "Эччи"               },
        { value = "691", label = "Юри"                },
        { value = "682", label = "Яой"                },
        { value = "907", label = "Eastern fantasy"    },
        { value = "999", label = "Isekai"             },
        { value = "993", label = "Video games"        },
      }
    },

    -- События
    {
      type  = "tristate",
      key   = "events",
      label = "События",
      options = {
        { value = "611", label = "[Награжденная работа]"          },
        { value = "338", label = "18+"                            },
        { value = "353", label = "Авантюристы"                    },
        { value = "538", label = "Автоматоны"                     },
        { value = "434", label = "Агрессивные персонажи"          },
        { value = "509", label = "Ад"                             },
        { value = "522", label = "Адаптация в радиопостановку"    },
        { value = "25",  label = "Академия"                       },
        { value = "578", label = "Актеры озвучки"                 },
        { value = "132", label = "Активный главный герой"         },
        { value = "116", label = "Алхимия"                        },
        { value = "28",  label = "Альтернативный мир"             },
        { value = "247", label = "Амнезия/Потеря памяти"          },
        { value = "657", label = "Анабиоз"                        },
        { value = "218", label = "Ангелы"                         },
        { value = "217", label = "Андрогинные персонажи"          },
        { value = "82",  label = "Андроиды"                       },
        { value = "471", label = "Анти-магия"                     },
        { value = "346", label = "Антигерой"                      },
        { value = "572", label = "Антикварный магазин"            },
        { value = "562", label = "Антисоциальный главный герой"   },
        { value = "663", label = "Антиутопия"                     },
        { value = "29",  label = "Апатичный протагонист"          },
        { value = "314", label = "Апокалипсис"                    },
        { value = "285", label = "Аранжированный брак"            },
        { value = "598", label = "Армия"                          },
        { value = "117", label = "Артефакты"                      },
        { value = "460", label = "Артисты"                        },
        { value = "581", label = "Банды"                          },
        { value = "309", label = "Бедный главный герой"           },
        { value = "144", label = "Безжалостный главный герой"     },
        { value = "355", label = "Беззаботный главный герой"      },
        { value = "650", label = "Безусловная любовь"             },
        { value = "131", label = "Беременность"                   },
        { value = "222", label = "Бесполый главный герой"         },
        { value = "275", label = "Бессмертные"                    },
        { value = "619", label = "Бесстрашный протагонист"        },
        { value = "256", label = "Бесстыдный главный герой"       },
        { value = "699", label = "Бесчестный главный герой"       },
        { value = "342", label = "Библиотека"                     },
        { value = "813", label = "Бизнесмен"                      },
        { value = "120", label = "Биочип"                         },
        { value = "822", label = "Бисексуальный главный герой"    },
        { value = "148", label = "Близнецы"                       },
        { value = "211", label = "Боги"                           },
        { value = "356", label = "Богини"                         },
        { value = "369", label = "Боевая академия"                },
        { value = "347", label = "Боевые духи"                    },
        { value = "422", label = "Боевые соревнования"            },
        { value = "336", label = "Божественная защита"            },
        { value = "224", label = "Божественные силы"              },
        { value = "348", label = "Большая разница в возрасте"     },
        { value = "544", label = "Борьба за власть"               },
        { value = "363", label = "Брак"                           },
        { value = "65",  label = "Брак по расчету"                },
        { value = "31",  label = "Братский комплекс"              },
        { value = "413", label = "Братство"                       },
        { value = "518", label = "Братья и сестры"                },
        { value = "742", label = "Буддизм"                        },
        { value = "273", label = "Быстрая культивация"            },
        { value = "221", label = "Быстрообучаемый"                },
        { value = "667", label = "Валькирии"                      },
        { value = "266", label = "Вампиры"                        },
        { value = "169", label = "Ведьмы"                         },
        { value = "289", label = "Вежливый главный герой"         },
        { value = "225", label = "Верные подчиненные"             },
        { value = "183", label = "Взрослый главный герой"         },
        { value = "636", label = "Видит то, чего не видят другие" },
        { value = "313", label = "Виртуальная реальность"         },
        { value = "653", label = "Владелец магазина"              },
        { value = "376", label = "Внезапная сила"                 },
        { value = "802", label = "Внезапное богатство"            },
        { value = "334", label = "Внешний вид не соответствует возрасту" },
        { value = "740", label = "Военные Летописи"               },
        { value = "673", label = "Возвращение из другого мира"    },
        { value = "58",  label = "Войны"                          },
        { value = "477", label = "Волшебники/Волшебницы"          },
        { value = "201", label = "Волшебные звери"                },
        { value = "614", label = "Воображаемый друг"              },
        { value = "326", label = "Воры"                           },
        { value = "78",  label = "Воскрешение"                    },
        { value = "428", label = "Враги становятся возлюбленными" },
        { value = "502", label = "Враги становятся союзниками"    },
        { value = "558", label = "Врата в другой мир"             },
        { value = "286", label = "Врачи"                          },
        { value = "163", label = "Временной парадокс"             },
        { value = "42",  label = "Всемогущий главный герой"       },
        { value = "77",  label = "Вторжение на землю"             },
        { value = "112", label = "Второй шанс"                    },
        { value = "290", label = "Выживание"                      },
        { value = "268", label = "Высокомерные персонажи"         },
        { value = "540", label = "Гадание"                        },
        { value = "302", label = "Геймеры"                        },
        { value = "223", label = "Генералы"                       },
        { value = "620", label = "Генетические модификации"       },
        { value = "566", label = "Гениальный главный герой"       },
        { value = "173", label = "Герои"                          },
        { value = "525", label = "Героиня — сорванец"             },
        { value = "64",  label = "Герой влюбляется первым"        },
        { value = "510", label = "Гетерохромия"                   },
        { value = "323", label = "Гильдии"                        },
        { value = "768", label = "Гипнотизм"                      },
        { value = "486", label = "Главный герой — бог"            },
        { value = "63",  label = "Главный герой — женщина"        },
        { value = "39",  label = "Главный герой — мужчина"        },
        { value = "415", label = "Главный герой — ребенок"        },
        { value = "45",  label = "Главный герой силен с самого начала" },
        { value = "549", label = "Гладиаторы"                     },
        { value = "295", label = "Глуповатый главный герой"       },
        { value = "529", label = "Гоблины"                        },
        { value = "380", label = "Горничные"                      },
        { value = "193", label = "Готовка"                        },
        { value = "303", label = "Гриндинг"                       },
        { value = "792", label = "Даосизм"                        },
        { value = "151", label = "Дарк"                           },
        { value = "220", label = "Дварфы"                         },
        { value = "41",  label = "Дворяне"                        },
        { value = "354", label = "Дворянство/Аристократия"        },
        { value = "6",   label = "Демоны"                         },
        { value = "494", label = "Депрессия"                      },
        { value = "561", label = "Детективы"                      },
        { value = "34",  label = "Дискриминация"                  },
        { value = "200", label = "Долгая разлука"                 },
        { value = "178", label = "Домашние дела"                  },
        { value = "195", label = "Драконы"                        },
        { value = "555", label = "Драконьи всадники"              },
        { value = "102", label = "Древние времена"                },
        { value = "284", label = "Древний Китай"                  },
        { value = "97",  label = "Дружба"                         },
        { value = "170", label = "Друзья детства"                 },
        { value = "507", label = "Друзья становятся врагами"      },
        { value = "46",  label = "Духи/Призраки"                  },
        { value = "136", label = "Души"                           },
        { value = "516", label = "Ёкаи"                           },
        { value = "26",  label = "Есть аниме-адаптация"           },
        { value = "27",  label = "Есть манга-адаптация"           },
        { value = "453", label = "Есть манхва-адаптация"          },
        { value = "298", label = "Есть маньхуа-адаптация"         },
        { value = "421", label = "Есть сериал-адаптация"          },
        { value = "47",  label = "Есть фильм по мотивам"          },
        { value = "127", label = "Жестокость"                     },
        { value = "466", label = "Животные черты"                 },
        { value = "176", label = "Заботливый главный герой"       },
        { value = "177", label = "Заговоры"                       },
        { value = "269", label = "Закалка тела"                   },
        { value = "533", label = "Замкнутый главный герой"        },
        { value = "344", label = "Запечатанная сила"              },
        { value = "443", label = "Застенчивые персонажи"          },
        { value = "119", label = "Звери"                          },
        { value = "192", label = "Звери-компаньоны"               },
        { value = "125", label = "Злой протагонист"               },
        { value = "437", label = "Злые боги"                      },
        { value = "503", label = "Злые организации"               },
        { value = "397", label = "Знаменитости"                   },
        { value = "469", label = "Знаменитый главный герой"       },
        { value = "185", label = "Знания современного мира"       },
        { value = "321", label = "Зомби"                          },
        { value = "162", label = "Игра на выживание"              },
        { value = "301", label = "Игровая система рейтинга"       },
        { value = "152", label = "Игровые элементы"               },
        { value = "330", label = "Из грязи в князи"               },
        { value = "81",  label = "Из слабого в сильного"          },
        { value = "472", label = "Изгои"                          },
        { value = "99",  label = "Изменения личности"             },
        { value = "749", label = "Империи"                        },
        { value = "35",  label = "Инженер"                        },
        { value = "118", label = "Искусственный интеллект"        },
        { value = "123", label = "Культивация"                    },
        { value = "430", label = "Легенды"                        },
        { value = "604", label = "Легкая жизнь"                   },
        { value = "570", label = "Ленивый главный герой"          },
        { value = "424", label = "Лидерство"                      },
        { value = "98",  label = "Любовный треугольник"           },
        { value = "38",  label = "Магия"                          },
        { value = "357", label = "Магические технологии"          },
        { value = "130", label = "Манипулятивные персонажи"       },
        { value = "441", label = "Медицинские знания"             },
        { value = "113", label = "Медленная романтическая линия"  },
        { value = "316", label = "Межпространственные путешествия"},
        { value = "182", label = "Менеджмент"                     },
        { value = "88",  label = "Месть"                          },
        { value = "55",  label = "Меч и магия"                    },
        { value = "468", label = "Мифология"                      },
        { value = "306", label = "ММОРПГ (ЛитРПГ)"                },
        { value = "278", label = "Множество реальностей"          },
        { value = "69",  label = "Монстры"                        },
        { value = "589", label = "Музыка"                         },
        { value = "85",  label = "Навязчивая любовь"              },
        { value = "324", label = "Наемники"                       },
        { value = "66",  label = "Наивный главный герой"          },
        { value = "372", label = "Наследование"                   },
        { value = "140", label = "Недооцененный главный герой"    },
        { value = "202", label = "Недоразумения"                  },
        { value = "308", label = "Некромант"                      },
        { value = "304", label = "Одинокий главный герой"         },
        { value = "86",  label = "Параллельные миры"              },
        { value = "43",  label = "Политика"                       },
        { value = "60",  label = "Постапокалиптика"               },
        { value = "103", label = "Предательство"                  },
        { value = "51",  label = "Призраки"                       },
        { value = "147", label = "Призванный герой"               },
        { value = "296", label = "Полигамия"                      },
        { value = "281", label = "Реинкарнация"                   },
        { value = "204", label = "Реинкарнация в монстра"         },
        { value = "281", label = "Реинкарнация"                   },
        { value = "142", label = "Рыцари"                         },
        { value = "331", label = "Секретные организации"          },
        { value = "251", label = "Семья"                          },
        { value = "282", label = "Сила духа"                      },
        { value = "109", label = "Сильная пара"                   },
        { value = "198", label = "Система уровней"                },
        { value = "252", label = "Скрытие истинных способностей"  },
        { value = "128", label = "Скрытые способности"            },
        { value = "49",  label = "Смерть"                         },
        { value = "40",  label = "Современность"                  },
        { value = "181", label = "Создание королевства"           },
        { value = "71",  label = "Солдаты/Военные"                },
        { value = "54",  label = "Специальные способности"        },
        { value = "32",  label = "Спокойный главный герой"        },
        { value = "184", label = "Средневековье"                  },
        { value = "425", label = "Стратег"                        },
        { value = "160", label = "Стратегические битвы"           },
        { value = "271", label = "Судьба"                         },
        { value = "74",  label = "Таинственная болезнь"           },
        { value = "263", label = "Таинственное прошлое"           },
        { value = "452", label = "Телохранители"                  },
        { value = "515", label = "Террористы"                     },
        { value = "416", label = "Торговцы"                       },
        { value = "89",  label = "Травля/Буллинг"                 },
        { value = "164", label = "Трагическое прошлое"            },
        { value = "37",  label = "Трудолюбивый главный герой"     },
        { value = "84",  label = "Убийства"                       },
        { value = "248", label = "Убийцы"                         },
        { value = "270", label = "Уверенный главный герой"        },
        { value = "337", label = "Укротитель монстров"            },
        { value = "280", label = "Умения из прошлой жизни"        },
        { value = "33",  label = "Умный главный герой"            },
        { value = "340", label = "Уникальное оружие"              },
        { value = "315", label = "Управление бизнесом"            },
        { value = "300", label = "Ускоренный рост"                },
        { value = "345", label = "Учителя"                        },
        { value = "322", label = "Фантастические существа"        },
        { value = "379", label = "Фарминг"                        },
        { value = "210", label = "Феи"                            },
        { value = "374", label = "Фениксы"                        },
        { value = "87",  label = "Философия"                      },
        { value = "126", label = "Фэнтези мир"                    },
        { value = "399", label = "Хакеры"                         },
        { value = "462", label = "Хикикомори/Затворники"          },
        { value = "105", label = "Хитроумный главный герой"       },
        { value = "557", label = "Хозяин подземелий"              },
        { value = "259", label = "Холодный главный герой"         },
        { value = "506", label = "Хорошие отношения с семьей"     },
        { value = "389", label = "Целители"                       },
        { value = "445", label = "Цундэрэ"                        },
        { value = "240", label = "Честный главный герой"          },
        { value = "238", label = "Читы"                           },
        { value = "239", label = "Шеф-повар"                      },
        { value = "21",  label = "Школьная жизнь"                 },
        { value = "407", label = "Шоу-бизнес"                     },
        { value = "563", label = "Шпионы"                         },
        { value = "196", label = "Эволюция"                       },
        { value = "492", label = "Экономика"                      },
        { value = "172", label = "Эльфы"                          },
        { value = "208", label = "Яндере"                         },
        { value = "272", label = "Ярко выраженная романтическая линия" },
        -- EN теги
        { value = "860", label = "Coming of Age"                  },
        { value = "690", label = "Couple Growth"                  },
        { value = "665", label = "Doting Love Interests"          },
        { value = "530", label = "Doting Parents"                 },
        { value = "990", label = "Dungeon/s-exploring"            },
        { value = "994", label = "Gamelit"                        },
        { value = "991", label = "High-fantasy"                   },
        { value = "977", label = "Litrpg"                         },
        { value = "988", label = "Modern"                         },
        { value = "992", label = "Portal-fantasy/isekai"          },
        { value = "987", label = "Suspense"                       },
        { value = "875", label = "Sword-and-sorcery"              },
        { value = "1037",label = "Low-fantasy"                    },
        { value = "1041",label = "Urban-fantasy"                  },
        { value = "1044",label = "Unlimited Flow"                 },
      }
    },
  }
end

-- ── Каталог с фильтрами ───────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page = index + 1

  local sort        = filters["sort"] or "computed_rating"
  local status      = filters["status"] or "0"
  local country_inc = filters["country_included"] or {}

  local tags_inc = {}
  local tags_exc = {}
  for _, key in ipairs({"tags", "events"}) do
    local inc = filters[key .. "_included"] or {}
    local exc = filters[key .. "_excluded"] or {}
    for i = 1, #inc do tags_inc[#tags_inc + 1] = inc[i] end
    for i = 1, #exc do tags_exc[#tags_exc + 1] = exc[i] end
  end

  -- Параметры проверены на живом API: sort/status/country/tags:positive/
  -- tags:negative реально фильтруют выдачу /api/search (см. фикстуры
  -- rh_filt_* — страница 1 vs 2, только Япония, только «Завершено» и т.д.).
  local qs = "sort=" .. url_encode(sort) .. "&status=" .. status .. "&take=40"

  if #country_inc > 0 then
    qs = qs .. "&country=" .. table.concat(country_inc, ",")
  end
  if #tags_inc > 0 then
    qs = qs .. "&tags:positive=" .. table.concat(tags_inc, ",")
  end
  if #tags_exc > 0 then
    qs = qs .. "&tags:negative=" .. table.concat(tags_exc, ",")
  end

  local r = http_get(searchUrl(page, qs))
  if not r.success then return { items = {}, hasNext = false } end
  return parseSearchResponse(r.body)
end
