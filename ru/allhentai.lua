-- Loaded via require_lib("readmanga"): the whole engine (catalog API,
-- book details, chapter list, rm_h.readerInit pages, filters) lives in
-- libs/family/readmanga.lua — this file only carries the site metadata,
-- the family config and the site-specific hooks.
id       = "allhentai"
name     = "AllHentai"
version  = "1.1.0"
baseUrl  = "https://20.allhen.online"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/allhentai.png"
content_type = "manga"

-- AllHentai keeps its own filter sheet: different genre/category ids and
-- an extra "additional" group (includeSearchFilters), so the family gets
-- it as a full getFilterList() override.
local ALLHENTAI_FILTERS = {
    {
        type = "select",
        key = "sort",
        label = "Сортировка",
        defaultValue = "DATE_UPDATE",
        options = {
            { value = "RATING",      label = "По популярности"   },
            { value = "NAME",         label = "По алфавиту"      },
            { value = "POPULARITY",   label = "Популярность сейчас" },
            { value = "USER_RATING",  label = "По оценке"        },
            { value = "DATE_CREATE",  label = "Новинки"          },
            { value = "DATE_UPDATE",  label = "По обновлению"    },
        },
    },
    {
        type  = "tristate",
        key   = "genres",
        label = "Жанры",
        options = {
            { value = "855",  label = "Ahegao"             },
            { value = "828",  label = "Анал"               },
            { value = "78",   label = "Бдсм"               },
            { value = "888",  label = "Без цензуры"        },
            { value = "837",  label = "Большая грудь"      },
            { value = "3156", label = "Большая попка"      },
            { value = "884",  label = "Большой член"       },
            { value = "5754", label = "Бондаж"             },
            { value = "811",  label = "В первый раз"       },
            { value = "290",  label = "В цвете"            },
            { value = "87",   label = "Гарем"              },
            { value = "89",   label = "Гендерная интрига"  },
            { value = "88",   label = "Групповой секс"     },
            { value = "95",   label = "Драма"              },
            { value = "5679", label = "Зрелые женщины"     },
            { value = "291",  label = "Измена"             },
            { value = "124",  label = "Изнасилование"      },
            { value = "85",   label = "Инцест"             },
            { value = "93",   label = "Исторический"       },
            { value = "73",   label = "Комедия"            },
            { value = "870",  label = "Маленькая грудь"    },
            { value = "76",   label = "Научная фантастика" },
            { value = "303",  label = "Нетораре"           },
            { value = "853",  label = "Оральный секс"      },
            { value = "74",   label = "Романтика"          },
            { value = "69",   label = "Тентакли"           },
            { value = "1321", label = "Трагедия"           },
            { value = "75",   label = "Ужасы"              },
            { value = "77",   label = "Футанари"           },
            { value = "70",   label = "Фэнтези"           },
            { value = "1059", label = "Чикан"              },
            { value = "798",  label = "Этти"               },
        },
    },
    {
        type  = "tristate",
        key   = "categories",
        label = "Категории",
        options = {
            { value = "626",  label = "3D"        },
            { value = "5777", label = "Анимация"  },
            { value = "3157", label = "Без текста" },
            { value = "1003", label = "Комикс"    },
            { value = "6449", label = "Манга"     },
            { value = "1104", label = "Манхва"    },
            { value = "5902", label = "Маньхуа"   },
            { value = "5896", label = "Руманга"   },
        },
    },
    {
        type  = "tristate",
        key   = "additional",
        label = "Дополнительно",
        options = {
            { value = "HIGH_RATE",         label = "Высокий рейтинг" },
            { value = "SINGLE",            label = "Сингл"           },
            { value = "MATURE",            label = "Для взрослых"    },
            { value = "TRANSLATED",        label = "Переведено"      },
            { value = "ABANDONED_POPULAR", label = "Заброшен перевод" },
            { value = "MANY_CHAPTERS",     label = "Длинная"         },
            { value = "WAIT_UPLOAD",       label = "Ожидает загрузки" },
        },
    },
    {
        type = "select",
        key = "productionStatus",
        label = "Статус выхода",
        defaultValue = "",
        options = {
            { value = "",          label = "Любые"       },
            { value = "PLANNED",   label = "Запланирован" },
            { value = "PROGRESS",  label = "Продолжается" },
            { value = "POSTPONED", label = "Приостановлен" },
            { value = "CANCELED",  label = "Отменён"     },
            { value = "FINISHED",  label = "Завершён"    },
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
            { value = "NONE",     label = "Отсутствует"    },
            { value = "STARTED",  label = "Начат"          },
            { value = "PROGRESS", label = "Продолжается"   },
            { value = "POSTPONED", label = "Приостановлен" },
            { value = "FINISHED", label = "Завершён"       },
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
            { value = "2027,2027",  label = "2027"      },
            { value = "2026,2026",  label = "2026"      },
            { value = "2025,2025",  label = "2025"      },
            { value = "2024,2024",  label = "2024"      },
            { value = "2023,2023",  label = "2023"      },
            { value = "2020,2025",  label = "2020–2025" },
            { value = "2015,2019",  label = "2015–2019" },
            { value = "2010,2014",  label = "2010–2014" },
            { value = "2000,2009",  label = "2000–2009" },
            { value = "1990,1999",  label = "1990–1999" },
            { value = "1988,1989",  label = "1988–1989" },
        },
    },
}

local CONFIG = {
    baseUrl = baseUrl,
    name    = name,
    -- AllHentai ships its own filter vocabulary (hentai genres/categories)
    -- plus the "additional" tristate served through includeSearchFilters.
    filters = ALLHENTAI_FILTERS,
    extraFilterGroups = {
        { key = "additional", param = "SearchFilters" },
    },
}

-- Old builds ship no require_lib: keep the plugin loadable (a top-level
-- error would drop it from the source list) and fail with a visible
-- message on the first call instead.
local family
local function F()
    if type(require_lib) ~= "function" then
        show_error("Требуется обновление NoveLA", "Плагину нужны общие библиотеки")
        error("Требуется обновление NoveLA (require_lib)", 0)
    end
    if not family then family = require_lib("readmanga") end
    return family
end

function getCatalogList(index) return F().getCatalogList(CONFIG, index) end
function getCatalogSearch(index, query) return F().getCatalogSearch(CONFIG, index, query) end
function getFilterList() return F().getFilterList(CONFIG) end
function getCatalogFiltered(index, filters) return F().getCatalogFiltered(CONFIG, index, filters) end

function getBookTitle(bookUrl) return F().getBookTitle(CONFIG, bookUrl) end
function getBookCoverImageUrl(bookUrl) return F().getBookCoverImageUrl(CONFIG, bookUrl) end
function getBookDescription(bookUrl) return F().getBookDescription(CONFIG, bookUrl) end
function getBookGenres(bookUrl) return F().getBookGenres(CONFIG, bookUrl) end
function getBookRating(bookUrl) return F().getBookRating(CONFIG, bookUrl) end
function getBookStatus(bookUrl) return F().getBookStatus(CONFIG, bookUrl) end
function getBookLastUpdate(bookUrl) return F().getBookLastUpdate(CONFIG, bookUrl) end

function getChapterList(bookUrl) return F().getChapterList(CONFIG, bookUrl) end
function getChapterListHash(bookUrl) return F().getChapterListHash(CONFIG, bookUrl) end

function getPageList(html, url) return F().getPageList(CONFIG, html, url) end
function getChapterText(html, url) return F().getChapterText(CONFIG, html, url) end
