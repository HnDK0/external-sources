-- ── Метаданные ───────────────────────────────────────────────────────────────
id        = "NovelPing"
name      = "Novel Ping"
version   = "1.0.0"
baseUrl   = "https://novelping.com/"
language  = "en"
icon      = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novelping.png"

-- ── Кэш страниц (1 запрос вместо 4–5) ────────────────────────────────────────

local _pageCache = {}

local function fetchPage(url)
  if _pageCache[url] then return _pageCache[url] end
  local r = http_get(url)
  if r.success then
    _pageCache[url] = r.body
    return r.body
  end
  return nil
end

-- ── Хелперы ───────────────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  local domain = baseUrl:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
  text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  text = regex_replace(text, "(?i)Remove\\s+Ads\\s+From\\s+\\$\\d+", "")
  text = string_trim(text)
  return text
end

-- Карточка каталога: div.row → h3.novel-title > a[href][title] + img.cover
-- (src лежит в div.col-xs-3, обложки уже абсолютные, трансформация не нужна).
local function parseCatalogItems(body, useDataSrc)
  local items = {}
  for _, row in ipairs(html_select(body, "div.row")) do
    local titleEl = html_select_first(row.html, ".novel-title a")
    if titleEl then
      local cover = ""
      if useDataSrc then
        cover = html_attr(row.html, "img[data-src]", "data-src")
      end
      if cover == "" then
        cover = html_attr(row.html, "img[src]", "src")
      end
      -- ponytail: полный размер обложки вместо миниатюры novel_200_89/novel_80_113
      cover = cover:gsub("novel_%d+_%d+/", "novel/")
      table.insert(items, {
        title = string_trim(titleEl.text),
        url   = absUrl(titleEl.href),
        cover = cover
      })
    end
  end
  return items
end

-- ── Извлечение novelId из URL книги (slug) ──────────────────────────────────

local function extractNovelId(bookUrl)
  return bookUrl:match("/book/([^/?#]+)")
end

-- ── AJAX-запрос архива глав ───────────────────────────────────────────────────

local function fetchChapterArchive(novelId, bookUrl)
  local ajaxUrl = baseUrl:gsub("/$", "") .. "/ajax/chapter-archive?novelId=" .. novelId
  local ar = http_get(ajaxUrl, {
    headers = {
      ["Referer"]          = bookUrl,
      ["X-Requested-With"] = "XMLHttpRequest",
    }
  })
  if not ar.success then
    log_error("fetchChapterArchive: AJAX failed code=" .. tostring(ar.code))
    return nil
  end
  return ar.body
end

-- ── Парсинг глав из HTML шаблона ─────────────────────────────────────────────
-- href уже абсолютные (https://novelping.com/book/{slug}/{chapter-id}),
-- chapter-id бывает любым — берём href как есть.

local function parseChaptersFromArchive(archiveHtml)
  local tmpl = html_select_first(archiveHtml, "template[data-chapter-item-template]")
  if not tmpl then
    log_error("parseChaptersFromArchive: template element not found")
    return {}
  end

  local chapters = {}
  for _, a in ipairs(html_select(tmpl.html, "a[href]")) do
    local span  = html_select_first(a.html, "span.nchr-text")
    local title = span and string_trim(span.text) or ""
    if title == "" then title = string_trim(a.title or "") end
    if title == "" then title = string_trim(a.text) end
    if title == "" then title = a.href end
    table.insert(chapters, { title = title, url = a.href })
  end
  return chapters
end

-- ── Каталог ───────────────────────────────────────────────────────────────────

function getCatalogList(index)
  local page = index + 1
  local url = baseUrl .. "sort/updates"
  if page > 1 then url = url .. "?page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body, true)
  return { items = items, hasNext = #items > 0 }
end

-- ── Поиск ─────────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
  local page = index + 1
  local url = baseUrl .. "search?keyword=" .. url_encode(query)
  if page > 1 then url = url .. "&page=" .. page end

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body, false)
  return { items = items, hasNext = #items > 0 }
end

-- ── Детали книги (все через кэш — 1 запрос) ──────────────────────────────────

function getBookTitle(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "h3.title")
  return el and string_clean(el.text) or nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local url = html_attr(body, "meta[property='og:image']", "content")
  return url ~= "" and absUrl(url) or nil
end

function getBookDescription(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "#novel-description-content")
  return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, li in ipairs(html_select(body, "ul.info.info-meta li, ul.info-meta li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Genre:" then
      for _, a in ipairs(html_select(li.html, "a")) do
        local g = string_trim(a.text)
        if g ~= "" then table.insert(genres, g) end
      end
      break
    end
  end
  return genres
end

function getBookRating(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  local el = html_select_first(body, "span[itemprop='ratingValue']")
  return el and string_trim(el.text) or nil
end

function getBookStatus(bookUrl)
  local body = fetchPage(bookUrl)
  if not body then return nil end
  for _, li in ipairs(html_select(body, "ul.info.info-meta li, ul.info-meta li")) do
    local h3 = html_select_first(li.html, "h3")
    if h3 and string_trim(h3.text) == "Status:" then
      local a = html_select_first(li.html, "a")
      if a then return string_trim(a.text) end
    end
  end
  return nil
end

-- getBookLastUpdate не реализован: надёжного источника даты в HTML нет.

-- ── Список глав ───────────────────────────────────────────────────────────────
-- NovelPing отдаёт все главы одним AJAX-запросом (chapter-archive).
-- totalPages = 1, движок при обновлении перечитывает только эту страницу.

function parsePage(bookUrl, page)
  if page > 1 then
    return { chapters = {}, totalPages = 1 }
  end

  local novelId = extractNovelId(bookUrl)
  if not novelId then
    log_error("parsePage: cannot extract novelId from " .. bookUrl)
    return { chapters = {}, totalPages = 1 }
  end

  local archiveHtml = fetchChapterArchive(novelId, bookUrl)
  if not archiveHtml then
    return { chapters = {}, totalPages = 1 }
  end

  local chapters = parseChaptersFromArchive(archiveHtml)
  log_error("parsePage: found " .. tostring(#chapters) .. " chapters")
  return { chapters = chapters, totalPages = 1 }
end

-- ── Текст главы ───────────────────────────────────────────────────────────────

function getChapterText(html)
  local el = html_select_first(html, "#chr-content")
  if not el then return "" end
  local cleaned = html_remove(el.html, "script", "style", ".ads", "h3", "h4", ".js-ad-slot", ".ad-insert", "[id^=pf-]", "[class*='app-promo']")
  return applyStandardContentTransforms(html_text(cleaned))
end

-- ── Список фильтров ───────────────────────────────────────────────────────────
-- Advanced search: /search?advanced=1 с параметрами формы сайта.
-- Значения жанров — верхним регистром, как в форме продвинутого поиска.

function getFilterList()
  return {
    {
      type         = "select",
      key          = "sort",
      label        = "Sort By",
      defaultValue = "",
      options = {
        { value = "LASTEST",  label = "Newest update"    },
        { value = "NEW",      label = "Recently added"   },
        { value = "ALL_TIME", label = "Top (most viewed)" },
        { value = "",         label = "Popular this week" },
        { value = "RATING",   label = "Top rated"        },
        { value = "CHAPTERS", label = "Most chapters"    },
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
      }
    },
    {
      type         = "select",
      key          = "language",
      label        = "Language",
      defaultValue = "ALL",
      options = {
        { value = "ALL", label = "All"      },
        { value = "EN",  label = "English"  },
        { value = "CN",  label = "Chinese"  },
        { value = "JP",  label = "Japanese" },
        { value = "KR",  label = "Korean"   },
      }
    },
    {
      type         = "select",
      key          = "genre_mode",
      label        = "Genre Mode",
      defaultValue = "AND",
      options = {
        { value = "AND", label = "Match all" },
        { value = "OR",  label = "Match any" },
      }
    },
    {
      type        = "checkbox",
      key         = "genres",
      label       = "Genres",
      multiselect = true,
      options = {
        { value = "ACTION",          label = "Action"          },
        { value = "ADULT",           label = "Adult"           },
        { value = "ADVENTURE",       label = "Adventure"       },
        { value = "ANIME & COMICS",  label = "Anime & Comics"  },
        { value = "COMEDY",          label = "Comedy"          },
        { value = "DRAMA",           label = "Drama"           },
        { value = "EASTERN",         label = "Eastern"         },
        { value = "ECCHI",           label = "Ecchi"           },
        { value = "FAN-FICTION",     label = "Fan-fiction"     },
        { value = "FANTASY",         label = "Fantasy"         },
        { value = "GAME",            label = "Game"            },
        { value = "GENDER BENDER",   label = "Gender Bender"   },
        { value = "HAREM",           label = "Harem"           },
        { value = "HISTORICAL",      label = "Historical"      },
        { value = "HORROR",          label = "Horror"          },
        { value = "ISEKAI",          label = "Isekai"          },
        { value = "JOSEI",           label = "Josei"           },
        { value = "LGBT+",           label = "LGBT+"           },
        { value = "LITRPG",          label = "LitRPG"          },
        { value = "MAGIC",           label = "Magic"           },
        { value = "MAGICAL REALISM", label = "Magical Realism" },
        { value = "MARTIAL ARTS",    label = "Martial Arts"    },
        { value = "MATURE",          label = "Mature"          },
        { value = "MECHA",           label = "Mecha"           },
        { value = "MILITARY",        label = "Military"        },
        { value = "MODERN LIFE",     label = "Modern Life"     },
        { value = "MYSTERY",         label = "Mystery"         },
        { value = "PSYCHOLOGICAL",   label = "Psychological"   },
        { value = "REALISTIC",       label = "Realistic"       },
        { value = "REINCARNATION",   label = "Reincarnation"   },
        { value = "ROMANCE",         label = "Romance"         },
        { value = "SCHOOL LIFE",     label = "School Life"     },
        { value = "SCI-FI",          label = "Sci-Fi"          },
        { value = "SEINEN",          label = "Seinen"          },
        { value = "SHOUJO",          label = "Shoujo"          },
        { value = "SHOUJO AI",       label = "Shoujo Ai"       },
        { value = "SHOUNEN",         label = "Shounen"         },
        { value = "SHOUNEN AI",      label = "Shounen Ai"      },
        { value = "SLICE OF LIFE",   label = "Slice of Life"   },
        { value = "SMUT",            label = "Smut"            },
        { value = "SPORTS",          label = "Sports"          },
        { value = "SUPERNATURAL",    label = "Supernatural"    },
        { value = "SYSTEM",          label = "System"          },
        { value = "THRILLER",        label = "Thriller"        },
        { value = "TRAGEDY",         label = "Tragedy"         },
        { value = "URBAN",           label = "Urban"           },
        { value = "VIDEO GAMES",     label = "Video Games"     },
        { value = "WAR",             label = "War"             },
        { value = "WUXIA",           label = "Wuxia"           },
        { value = "XIANXIA",         label = "Xianxia"         },
        { value = "XUANHUAN",        label = "Xuanhuan"        },
        { value = "YAOI",            label = "Yaoi"            },
        { value = "YURI",            label = "Yuri"            },
      }
    },
    {
      type         = "select",
      key          = "tag_mode",
      label        = "Tag Mode",
      defaultValue = "AND",
      options = {
        { value = "AND", label = "Match all" },
        { value = "OR",  label = "Match any" },
      }
    },
    {
      type        = "checkbox",
      key         = "tags",
      label       = "Tags",
      multiselect = true,
      options = {
        { value = "MALE PROTAGONIST",             label = "Male Protagonist"             },
        { value = "SYSTEM",                        label = "System"                        },
        { value = "WEAK TO STRONG",                label = "Weak to Strong"                },
        { value = "OVERPOWERED PROTAGONIST",       label = "Overpowered Protagonist"       },
        { value = "GAME ELEMENTS",                 label = "Game Elements"                 },
        { value = "TRANSMIGRATION",                label = "Transmigration"                },
        { value = "CULTIVATION",                   label = "Cultivation"                   },
        { value = "SURVIVAL",                      label = "Survival"                      },
        { value = "LEVEL SYSTEM",                  label = "Level System"                  },
        { value = "R-18",                          label = "R-18"                          },
        { value = "MODERN DAY",                    label = "Modern Day"                    },
        { value = "REINCARNATION",                 label = "Reincarnation"                 },
        { value = "SPECIAL ABILITIES",             label = "Special Abilities"             },
        { value = "MAGIC",                         label = "Magic"                         },
        { value = "ALTERNATE WORLD",               label = "Alternate World"               },
        { value = "MONSTERS",                      label = "Monsters"                      },
        { value = "DRAGONS",                       label = "Dragons"                       },
        { value = "ANTIHERO PROTAGONIST",          label = "Antihero Protagonist"          },
        { value = "POOR TO RICH",                  label = "Poor to Rich"                  },
        { value = "WARS",                          label = "Wars"                          },
        { value = "DEMONS",                        label = "Demons"                        },
        { value = "GENIUS PROTAGONIST",            label = "Genius Protagonist"            },
        { value = "HANDSOME MALE LEAD",            label = "Handsome Male Lead"            },
        { value = "BLOODLINES",                    label = "Bloodlines"                    },
        { value = "REVENGE",                       label = "Revenge"                       },
        { value = "HARD-WORKING PROTAGONIST",      label = "Hard-Working Protagonist"      },
        { value = "IMMORTALS",                     label = "Immortals"                     },
        { value = "HAREM-SEEKING PROTAGONIST",     label = "Harem-Seeking Protagonist"     },
        { value = "FAMILY",                        label = "Family"                        },
        { value = "FEMALE PROTAGONIST",            label = "Female Protagonist"            },
        { value = "SCHEMES AND CONSPIRACIES",      label = "Schemes and Conspiracies"      },
        { value = "APOCALYPSE",                    label = "Apocalypse"                    },
        { value = "HIDING TRUE ABILITIES",         label = "Hiding True Abilities"         },
        { value = "GODS",                          label = "Gods"                          },
        { value = "ARTIFACTS",                     label = "Artifacts"                     },
        { value = "CAUTIOUS PROTAGONIST",          label = "Cautious Protagonist"          },
        { value = "ALCHEMY",                       label = "Alchemy"                       },
        { value = "KINGDOM BUILDING",              label = "Kingdom Building"              },
        { value = "BUSINESS MANAGEMENT",           label = "Business Management"           },
        { value = "NOBLES",                        label = "Nobles"                        },
        { value = "POOR PROTAGONIST",              label = "Poor Protagonist"              },
        { value = "POST-APOCALYPTIC",              label = "Post-Apocalyptic"              },
        { value = "RUTHLESS PROTAGONIST",          label = "Ruthless Protagonist"          },
        { value = "COLD PROTAGONIST",              label = "Cold Protagonist"              },
        { value = "EVOLUTION",                     label = "Evolution"                     },
        { value = "ROMANTIC SUBPLOT",              label = "Romantic Subplot"              },
        { value = "ACADEMY",                       label = "Academy"                       },
        { value = "UNDERESTIMATED PROTAGONIST",    label = "Underestimated Protagonist"    },
        { value = "CALM PROTAGONIST",              label = "Calm Protagonist"              },
        { value = "LUCKY PROTAGONIST",             label = "Lucky Protagonist"             },
        { value = "GRINDING",                      label = "Grinding"                      },
        { value = "POLYGAMY",                      label = "Polygamy"                      },
        { value = "DOCTORS",                       label = "Doctors"                       },
        { value = "FARMING",                       label = "Farming"                       },
        { value = "HEARTWARMING",                  label = "Heartwarming"                  },
        { value = "MARRIAGE",                      label = "Marriage"                      },
        { value = "MEDICAL KNOWLEDGE",             label = "Medical Knowledge"             },
        { value = "CUNNING PROTAGONIST",           label = "Cunning Protagonist"           },
        { value = "BEAST COMPANIONS",              label = "Beast Companions"              },
        { value = "BEAUTIFUL FEMALE LEAD",         label = "Beautiful Female Lead"         },
        { value = "SYSTEM ADMINISTRATOR",          label = "System Administrator"          },
        { value = "HIDING TRUE IDENTITY",          label = "Hiding True Identity"          },
        { value = "ARRANGED MARRIAGE",             label = "Arranged Marriage"             },
        { value = "HIDDEN ABILITIES",              label = "Hidden Abilities"              },
        { value = "BETRAYAL",                      label = "Betrayal"                      },
        { value = "ABILITY STEAL",                 label = "Ability Steal"                 },
        { value = "FANTASY WORLD",                 label = "Fantasy World"                 },
        { value = "UNIQUE CULTIVATION TECHNIQUE",  label = "Unique Cultivation Technique"  },
        { value = "SURVIVAL GAME",                 label = "Survival Game"                 },
        { value = "NOT-HAREM",                     label = "Not-Harem"                     },
        { value = "ARROGANT CHARACTERS",           label = "Arrogant Characters"           },
        { value = "SECT DEVELOPMENT",              label = "Sect Development"              },
        { value = "SLOW GROWTH AT START",          label = "Slow Growth at Start"          },
        { value = "MULTIPLE REALMS",               label = "Multiple Realms"               },
        { value = "MODERN KNOWLEDGE",              label = "Modern Knowledge"              },
        { value = "ARTIFICIAL INTELLIGENCE",       label = "Artificial Intelligence"       },
        { value = "VIRTUAL REALITY",               label = "Virtual Reality"               },
        { value = "WEALTHY CHARACTERS",            label = "Wealthy Characters"            },
        { value = "FACE SLAPPING",                 label = "Face Slapping"                 },
        { value = "COOKING",                       label = "Cooking"                       },
        { value = "SUDDEN STRENGTH GAIN",          label = "Sudden Strength Gain"          },
        { value = "COMEDIC UNDERTONE",             label = "Comedic Undertone"             },
        { value = "REINCARNATED IN A GAME WORLD",  label = "Reincarnated in a Game World"  },
        { value = "VILLAIN",                       label = "Villain"                       },
        { value = "CLEVER PROTAGONIST",            label = "Clever Protagonist"            },
        { value = "UNLIMITED FLOW",                label = "Unlimited Flow"                },
        { value = "DAOISM",                        label = "Daoism"                        },
        { value = "HEAVENLY TRIBULATION",          label = "Heavenly Tribulation"          },
        { value = "MAGIC BEASTS",                  label = "Magic Beasts"                  },
        { value = "REINCARNATED IN ANOTHER WORLD", label = "Reincarnated in Another World" },
        { value = "DESTINY",                       label = "Destiny"                       },
        { value = "GODDESSES",                     label = "Goddesses"                     },
        { value = "SWORD WIELDER",                 label = "Sword Wielder"                 },
        { value = "CRAFTING",                      label = "Crafting"                      },
        { value = "TRANSPORTED TO ANOTHER WORLD",  label = "Transported to Another World"  },
        { value = "GHOSTS",                        label = "Ghosts"                        },
        { value = "CHEATS",                        label = "Cheats"                        },
        { value = "GORE",                          label = "Gore"                          },
        { value = "BODY TEMPERING",                label = "Body Tempering"                },
        { value = "COLLEGE/UNIVERSITY",            label = "College/University"            },
      }
    },
    {
      type         = "text",
      key          = "min_chapters",
      label        = "Min Chapters",
      defaultValue = ""
    },
    {
      type         = "text",
      key          = "max_chapters",
      label        = "Max Chapters",
      defaultValue = ""
    },
  }
end

-- ── Каталог с фильтрами (advanced search) ─────────────────────────────────────

function getCatalogFiltered(index, filters)
  local page       = index + 1
  local sort       = filters["sort"]       or ""
  local status     = filters["status"]     or "all"
  local language   = filters["language"]   or "ALL"
  local genre_mode = filters["genre_mode"] or "AND"
  local genres_inc = filters["genres_included"] or {}
  local genres_exc = filters["genres_excluded"] or {}

  local tag_mode   = filters["tag_mode"]   or "AND"
  local tags_inc   = filters["tags_included"] or {}
  local tags_exc   = filters["tags_excluded"] or {}

  local url = baseUrl .. "search?advanced=1"
  -- Значения жанров/тегов содержат пробелы и спецсимволы
  -- ("ANIME & COMICS", "ANTIHERO PROTAGONIST") — всё кодируем через url_encode.
  if sort ~= ""       then url = url .. "&sort="       .. url_encode(sort)       end
  if status ~= "all"  then url = url .. "&status="     .. url_encode(status)     end
  if language ~= "ALL" then url = url .. "&language="  .. url_encode(language)   end
  if genre_mode ~= "AND" then url = url .. "&genre_mode=" .. url_encode(genre_mode) end
  if tag_mode ~= "AND" then url = url .. "&tag_mode=" .. url_encode(tag_mode)   end

  for _, g in ipairs(genres_inc) do
    url = url .. "&genres=" .. url_encode(g)
  end
  for _, g in ipairs(genres_exc) do
    url = url .. "&genres_exclude=" .. url_encode(g)
  end
  for _, t in ipairs(tags_inc) do
    url = url .. "&tags=" .. url_encode(t)
  end
  for _, t in ipairs(tags_exc) do
    url = url .. "&tags_exclude=" .. url_encode(t)
  end

  -- Числовые ограничения по числу глав (пусто = фильтр не применяется)
  if filters["min_chapters"] and filters["min_chapters"] ~= "" then
    url = url .. "&min_chapters=" .. url_encode(filters["min_chapters"])
  end
  if filters["max_chapters"] and filters["max_chapters"] ~= "" then
    url = url .. "&max_chapters=" .. url_encode(filters["max_chapters"])
  end

  url = url .. "&page=" .. page

  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items = parseCatalogItems(r.body, false)
  return { items = items, hasNext = #items > 0 }
end