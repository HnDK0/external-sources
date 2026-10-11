-- Loaded via require_lib("cdnlibs"): the shared engine for the LibGroup
-- CDN family (api.cdnlibs.org, "Site-Id" header, site_id[0] query) lives
-- in libs/family/cdnlibs.lua — this file only carries the site metadata,
-- the family config and the site-specific hooks.
id       = "hentailib"
name     = "HentaiLib"
version  = "1.1.0"
baseUrl  = "https://hentailib.me/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/hentailib.png"
content_type = "manga"

-- TipTap/ProseMirror node -> plain text; used by getBookDescription for
-- the structured `summary` field.
local function tipTapText(node)
    if not node then return "" end
    if type(node) == "string" then return node end
    if type(node) ~= "table" then return "" end
    local parts = {}
    if node.type == "text" then parts[#parts + 1] = node.text or "" end
    if node.content and type(node.content) == "table" then
        for _, child in ipairs(node.content) do
            parts[#parts + 1] = tipTapText(child)
        end
    end
    return table.concat(parts, "")
end

local CONFIG = {
    id              = "hentailib",
    baseUrl         = baseUrl,
    siteId          = "4",
    mode            = "manga",
    pageCdnPrefix   = "https://img3h.hentaicdn.org",
    -- HentaiLib serves the chapter under another slug than the book URL.
    resolveSlugUrl  = true,
    textExtractor   = tipTapText,
    -- 18+ books: the API request fails without a session; check the site
    -- page for the age gate and tell the user to sign in.
    ageGateFallback = function(bookUrl, body)
        if body:find("возрастным ограничением", 1, true) or body:find("Предупреждение", 1, true) then
            if show_error then show_error("Требуется авторизация", "Контент 18+. Войдите для доступа.") end
        end
    end,
}

-- Old builds ship no require_lib: keep the plugin loadable (a top-level
-- error would drop it from the source list) and fail with a visible
-- message on the first call instead. setup() binds CONFIG and installs
-- the shared entry points as globals; the wrappers below only serve
-- until that first call.
local family
local function F()
    if type(require_lib) ~= "function" then
        show_error("Требуется обновление NoveLA", "Плагину нужны общие библиотеки")
        error("Требуется обновление NoveLA (require_lib)", 0)
    end
    if not family then family = require_lib("cdnlibs").setup(CONFIG) end
    return family
end

function getCatalogList(index) return F().getCatalogList(index) end
function getCatalogSearch(index, query) return F().getCatalogSearch(index, query) end
function getCatalogFiltered(index, filters) return F().getCatalogFiltered(index, filters) end

function getBookTitle(bookUrl) return F().getBookTitle(bookUrl) end
function getBookCoverImageUrl(bookUrl) return F().getBookCoverImageUrl(bookUrl) end
function getBookDescription(bookUrl) return F().getBookDescription(bookUrl) end
function getBookGenres(bookUrl) return F().getBookGenres(bookUrl) end
function getBookRating(bookUrl) return F().getBookRating(bookUrl) end
function getBookStatus(bookUrl) return F().getBookStatus(bookUrl) end
function getBookLastUpdate(bookUrl) return F().getBookLastUpdate(bookUrl) end

function getChapterList(bookUrl) return F().getChapterList(bookUrl) end
function getChapterListHash(bookUrl) return F().getChapterListHash(bookUrl) end
function getPageList(html, chapterUrl) return F().getPageList(html, chapterUrl) end
function getChapterText(html, chapterUrl) return F().getChapterText(html, chapterUrl) end

-- Site-specific filter definitions (not part of the family lib).

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort_by",
      label        = "Сортировка",
      defaultValue = "rating_score",
      options = {
        { value = "rate_avg",        label = "По рейтингу"         },
        { value = "rating_score",    label = "По популярности"     },
        { value = "views",           label = "По просмотрам"       },
        { value = "chap_count",      label = "Количеству глав"     },
        { value = "last_chapter_at", label = "Дате обновления"     },
        { value = "created_at",      label = "Дате добавления"     },
        { value = "releaseDate",     label = "Дате релиза"         },
        { value = "name",            label = "По названию (A-Z)"   },
        { value = "rus_name",        label = "По названию (А-Я)"   },
      }
    },
    {
      type         = "select",
      key          = "sort_type",
      label        = "Порядок",
      defaultValue = "desc",
      options = {
        { value = "desc", label = "По убыванию"   },
        { value = "asc",  label = "По возрастанию" },
      }
    },
    {
      type  = "select",
      key   = "require_chapters",
      label = "Только проекты с главами",
      defaultValue = "true",
      options = {
        { value = "true",  label = "Да" },
        { value = "false", label = "Все" },
      }
    },
    {
      type  = "checkbox",
      key   = "types",
      label = "Тип",
      options = {
        { value = "1", label = "Манга"      },
        { value = "5", label = "Манхва"     },
        { value = "6", label = "Маньхуа"    },
        { value = "8", label = "Руманга"    },
        { value = "9", label = "Комикс"     },
        { value = "4", label = "OEL-манга"  },
      }
    },
    {
      type  = "tristate",
      key   = "format",
      label = "Формат выпуска",
      options = {
        { value = "1", label = "4-кома (Ёнкома)" },
        { value = "2", label = "Сборник"         },
        { value = "3", label = "Додзинси"        },
        { value = "4", label = "В цвете"         },
        { value = "5", label = "Сингл"           },
        { value = "6", label = "Веб"             },
        { value = "7", label = "Вебтун"          },
      }
    },
    {
      type  = "checkbox",
      key   = "scanlateStatus",
      label = "Статус перевода",
      options = {
        { value = "1", label = "Продолжается" },
        { value = "2", label = "Завершён"     },
        { value = "3", label = "Заморожен"    },
        { value = "4", label = "Заброшен"     },
      }
    },
    {
      type  = "checkbox",
      key   = "manga_status",
      label = "Статус тайтла",
      options = {
        { value = "1", label = "Онгоинг"            },
        { value = "2", label = "Завершён"            },
        { value = "3", label = "Анонс"              },
        { value = "4", label = "Приостановлен"      },
        { value = "5", label = "Выпуск прекращён"   },
      }
    },
    {
      type  = "checkbox",
      key   = "ageRestriction",
      label = "Возрастное ограничение",
      options = {
        { value = "5", label = "18+ (RX)" },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Жанры",
      options = {
        { value = "32", label = "Арт"                    },
        { value = "91", label = "Безумие"                },
        { value = "34", label = "Боевик"                 },
        { value = "35", label = "Боевые искусства"       },
        { value = "36", label = "Вампиры"                },
        { value = "89", label = "Военное"                },
        { value = "37", label = "Гарем"                  },
        { value = "38", label = "Гендерная интрига"      },
        { value = "39", label = "Героическое фэнтези"    },
        { value = "81", label = "Демоны"                 },
        { value = "40", label = "Детектив"               },
        { value = "41", label = "Дзёсэй"                 },
        { value = "43", label = "Драма"                  },
        { value = "44", label = "Игра"                   },
        { value = "79", label = "Исекай"                 },
        { value = "45", label = "История"                },
        { value = "46", label = "Киберпанк"              },
        { value = "76", label = "Кодомо"                 },
        { value = "47", label = "Комедия"                },
        { value = "83", label = "Космос"                 },
        { value = "85", label = "Магия"                  },
        { value = "48", label = "Махо-сёдзё"             },
        { value = "90", label = "Машины"                 },
        { value = "49", label = "Меха"                   },
        { value = "50", label = "Мистика"                },
        { value = "80", label = "Музыка"                 },
        { value = "51", label = "Научная фантастика"     },
        { value = "77", label = "Омегаверс"              },
        { value = "86", label = "Пародия"                },
        { value = "52", label = "Повседневность"         },
        { value = "82", label = "Полиция"                },
        { value = "53", label = "Постапокалиптика"       },
        { value = "54", label = "Приключения"            },
        { value = "55", label = "Психология"             },
        { value = "56", label = "Романтика"              },
        { value = "57", label = "Самурайский боевик"     },
        { value = "58", label = "Сверхъестественное"     },
        { value = "59", label = "Сёдзё"                  },
        { value = "60", label = "Сёдзё-ай"               },
        { value = "61", label = "Сёнэн"                  },
        { value = "62", label = "Сёнэн-ай"              },
        { value = "63", label = "Спорт"                  },
        { value = "87", label = "Супер сила"             },
        { value = "64", label = "Сэйнэн"                 },
        { value = "65", label = "Трагедия"               },
        { value = "66", label = "Триллер"                },
        { value = "67", label = "Ужасы"                  },
        { value = "68", label = "Фантастика"             },
        { value = "69", label = "Фэнтези"                },
        { value = "70", label = "Школа"                  },
        { value = "72", label = "Этти"                   },
        { value = "73", label = "Юри"                    },
        { value = "74", label = "Яой"                    },
      }
    },
  }
end
