-- Loaded via require_lib("cdnlibs"): the shared engine for the LibGroup
-- CDN family (api.cdnlibs.org, "Site-Id" header, site_id[0] query) lives
-- in libs/family/cdnlibs.lua — this file only carries the site metadata,
-- the family config and the site-specific hooks. RanobeLib runs in
-- "novel" mode: chapters are TipTap/ProseMirror text, not page images.
id       = "ranobelib"
name     = "RanobeLib"
version  = "1.1.0"
baseUrl  = "https://ranobelib.me/"
language = "ru"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/ranobelib.png"

local function normalizeCover(raw)
  if not raw or raw == "" then return "" end
  if raw:sub(1, 2) == "//" then return "https:" .. raw end
  if raw:find("://") then return raw end
  return "https://" .. raw
end

-- ProseMirror node list -> HTML (chapter body rendering).
local function jsonToHtml(nodes, attachMap)
  if not nodes then return "" end
  local parts = {}

  for _, node in ipairs(nodes) do
    if type(node) ~= "table" then break end
    local ntype   = node.type or ""
    local content = node.content
    local inner   = jsonToHtml(content, attachMap)

    if ntype == "text" then
      local text = node.text or ""
      if node.marks then
        for _, mark in ipairs(node.marks) do
          local mt = mark.type or ""
          if mt == "bold"      then text = "<b>"  .. text .. "</b>"  end
          if mt == "italic"    then text = "<i>"  .. text .. "</i>"  end
          if mt == "underline" then text = "<u>"  .. text .. "</u>"  end
        end
      end
      table.insert(parts, text)

    elseif ntype == "paragraph"      then table.insert(parts, "<p>"           .. inner .. "</p>")
    elseif ntype == "heading"        then table.insert(parts, "<h2>"          .. inner .. "</h2>")
    elseif ntype == "listItem"       then table.insert(parts, "<li>"          .. inner .. "</li>")
    elseif ntype == "bulletList"     then table.insert(parts, "<ul>"          .. inner .. "</ul>")
    elseif ntype == "orderedList"    then table.insert(parts, "<ol>"          .. inner .. "</ol>")
    elseif ntype == "blockquote"     then table.insert(parts, "<blockquote>"  .. inner .. "</blockquote>")
    elseif ntype == "hardBreak"      then table.insert(parts, "<br>")
    elseif ntype == "horizontalRule" then table.insert(parts, "<hr>")

    elseif ntype == "image" then
      local attrs = node.attrs or {}
      -- The id sits either directly in attrs or in attrs.images[1].
      local imgId = attrs.id
      if not imgId and attrs.images and attrs.images[1] then
        imgId = attrs.images[1].id
      end
      local imgUrl = (imgId and attachMap[tostring(imgId)]) or attrs.src or ""
      if imgUrl ~= "" then
        table.insert(parts, "<img src=\"" .. normalizeCover(imgUrl) .. "\">")
      end

    else
      -- Unknown container node — just walk its children.
      if inner ~= "" then table.insert(parts, inner) end
    end
  end

  return table.concat(parts, "")
end

-- Raw HTML chapter (string content node): make image srcs absolute.
local function normalizeSrcs(html)
  return (html:gsub('src="([^"]+)"', function(src)
    return 'src="' .. normalizeCover(src) .. '"'
  end))
end

-- Plain-text walk used for the book summary: paragraphs and hard
-- breaks become newlines.
local function plainText(node)
  if not node then return "" end
  if type(node) == "string" then return node end
  if type(node) ~= "table" then return "" end
  local parts = {}
  if node.type == "text" then table.insert(parts, node.text or "") end
  if node.type == "hardBreak" then table.insert(parts, "\n") end
  if node.type == "paragraph" then
    if node.content and type(node.content) == "table" then
      for _, c in ipairs(node.content) do table.insert(parts, plainText(c)) end
    end
    table.insert(parts, "\n")
  elseif node.content and type(node.content) == "table" then
    for _, c in ipairs(node.content) do table.insert(parts, plainText(c)) end
  end
  return table.concat(parts, "")
end

-- TipTap/ProseMirror -> string. opts == nil: plain text (summary);
-- opts.html: chapter HTML (doc node rendered, string content passed
-- through with absolute image srcs).
local function novelTextExtractor(node, opts)
  if type(node) == "string" then
    if opts and opts.html then return normalizeSrcs(node) end
    return node
  end
  if type(node) ~= "table" then return "" end
  if opts and opts.html then
    if node.type == "doc" then
      return jsonToHtml(node.content, opts.attachMap or {})
    end
    return ""
  end
  return plainText(node)
end

local CONFIG = {
    id                = "ranobelib",
    baseUrl           = baseUrl,
    siteId            = "3",
    mode              = "novel",
    descriptionFields = "fields[]=summary",
    textExtractor     = novelTextExtractor,
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
        { value = "10", label = "Япония"     },
        { value = "11", label = "Корея"      },
        { value = "12", label = "Китай"      },
        { value = "13", label = "Английский" },
        { value = "14", label = "Авторский"  },
        { value = "15", label = "Фанфик"     },
      }
    },
    {
      type  = "checkbox",
      key   = "scanlateStatus",
      label = "Статус перевода",
      options = {
        { value = "1", label = "Продолжается" },
        { value = "2", label = "Завершен"     },
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
        { value = "1", label = "6+"  },
        { value = "2", label = "12+" },
        { value = "3", label = "16+" },
        { value = "4", label = "18+" },
      }
    },
    {
      type  = "tristate",
      key   = "genres",
      label = "Жанры",
      options = {
        { value = "32",  label = "Арт"                    },
        { value = "91",  label = "Безумие"                },
        { value = "34",  label = "Боевик"                 },
        { value = "35",  label = "Боевые искусства"       },
        { value = "36",  label = "Вампиры"                },
        { value = "89",  label = "Военное"                },
        { value = "37",  label = "Гарем"                  },
        { value = "38",  label = "Гендерная интрига"      },
        { value = "39",  label = "Героическое фэнтези"    },
        { value = "81",  label = "Демоны"                 },
        { value = "40",  label = "Детектив"               },
        { value = "88",  label = "Детское"                },
        { value = "41",  label = "Дзёсэй"                 },
        { value = "43",  label = "Драма"                  },
        { value = "44",  label = "Игра"                   },
        { value = "79",  label = "Исекай"                 },
        { value = "45",  label = "История"                },
        { value = "46",  label = "Киберпанк"              },
        { value = "76",  label = "Кодомо"                 },
        { value = "47",  label = "Комедия"                },
        { value = "83",  label = "Космос"                 },
        { value = "85",  label = "Магия"                  },
        { value = "48",  label = "Махо-сёдзё"             },
        { value = "90",  label = "Машины"                 },
        { value = "49",  label = "Меха"                   },
        { value = "50",  label = "Мистика"                },
        { value = "80",  label = "Музыка"                 },
        { value = "51",  label = "Научная фантастика"     },
        { value = "77",  label = "Омегаверс"              },
        { value = "86",  label = "Пародия"                },
        { value = "52",  label = "Повседневность"         },
        { value = "82",  label = "Полиция"                },
        { value = "53",  label = "Постапокалиптика"       },
        { value = "54",  label = "Приключения"            },
        { value = "55",  label = "Психология"             },
        { value = "56",  label = "Романтика"              },
        { value = "57",  label = "Самурайский боевик"     },
        { value = "58",  label = "Сверхъестественное"     },
        { value = "59",  label = "Сёдзё"                  },
        { value = "60",  label = "Сёдзё-ай"               },
        { value = "61",  label = "Сёнэн"                  },
        { value = "62",  label = "Сёнэн-ай"               },
        { value = "63",  label = "Спорт"                  },
        { value = "87",  label = "Супер сила"             },
        { value = "64",  label = "Сэйнэн"                 },
        { value = "65",  label = "Трагедия"               },
        { value = "66",  label = "Триллер"                },
        { value = "67",  label = "Ужасы"                  },
        { value = "68",  label = "Фантастика"             },
        { value = "69",  label = "Фэнтези"                },
        { value = "84",  label = "Хентай"                 },
        { value = "70",  label = "Школа"                  },
        { value = "71",  label = "Эротика"                },
        { value = "72",  label = "Этти"                   },
        { value = "73",  label = "Юри"                    },
        { value = "74",  label = "Яой"                    },
      }
    },
  }
end
