-- ═══════════════════════════════════════════════════════════════════════════
-- Novel543 source plugin for NoveLA
-- Version 1.0.4 (2026-08-29)
--
-- VERSION NOTE: from this release on, the plugin follows the UPSTREAM version
-- line (external-sources zh/novel543.lua: 1.0.3 → 1.0.4). The internal dev
-- builds 1.1.0 / 1.2.0 / 1.2.1 / 1.2.2 (changelog below) shipped the same
-- feature set incrementally to a single tester and are all superseded by 1.0.4.
--
-- 1.0.4 (upstream PR release):
--   • PAGE-SCOPED FILTERS: every site page has its own filter sidebar, and
--     now the plugin's filter sheet mirrors exactly the page being browsed
--     (headed by a "Page" picker):
--       /bookstack/ → Type · Status · Category · Tags   (類型/作品狀態/分類/標籤)
--       /shudan/    → Type · Sort                       (類型 + 最新發佈/最多收藏/小編推薦)
--       /ranking.html → Ranking Type · Gender · Ranking Category
--                       (閱讀榜/潛力榜/風雲榜 + 女生/男生 + per-type categories)
--     Previously ALL filters of ALL pages were stacked into one 8-section
--     sheet ("Category — Bookstack only"…), which did not match any single
--     page. getFilterList() now returns ONLY the current page's filters.
--     Switching Page inside the sheet applies immediately; the reduced
--     filter set appears the next time the source screen is opened (the app
--     fetches the filter list once per catalog-screen session).
--   • TAG FILTER NOW IN ENGLISH: all 100 site tags have curated English names
--     — "Transmigration (穿越)", "Wealthy CEO (豪門總裁)", "Face-Slapping (打臉)"…
--     Previously the tag dropdown listed raw Chinese only, which was unusable
--     for non-Chinese readers. The tag VALUES stay the raw site tags (they are
--     URL-encoded into /tags/ URLs — only the labels changed).
--   • FILTERS GO FULL ENGLISH IN TRANSLATOR MODE: with Mode = Translator every
--     filter label (each section header AND every option, all 100 tags
--     included) shows English ONLY — "Bookstack", "Male", "Transmigration" —
--     no Chinese counterparts. Raw mode keeps bilingual "English (中文)"
--     labels. Labels rebuild when the source screen is (re)opened — the app
--     fetches the filter list once per screen session, so toggling Mode (or
--     switching Page) takes effect the next time the source is opened; leave
--     the catalog and come back to see them switch.
--   • Version realigned to the upstream line (1.0.3 → 1.0.4) for the PR to
--     HnDK0/external-sources. The display name stays "Novel543 Full" so the
--     file can be imported and run side-by-side with the repository's v1.0.3
--     (see the 1.2.2 note below); when merging upstream, `name` may be
--     reverted to "Novel543".
--
-- 1.2.2 hotfix ("Filters don't show up / no filters button" reports):
--   • RENAMED to "Novel543 Full". WHY: the app's built-in extension repository
--     ships novel543.lua v1.0.3, which has NO getFilterList and NO
--     getSettingsSchema. The source catalog resolves a source BY BASE URL
--     (Scraper.getCompatibleSourceCatalog finds the FIRST match), so when the
--     old repo "Novel543" and this plugin are both installed they collide —
--     the app can open the old v1.0.3 no matter which entry you tapped, and
--     two identically-named "Novel543" entries are impossible to tell apart.
--     The new name makes the right source unmistakable in the source list
--     AND lets the file import cleanly (re-importing under the same name is
--     rejected with "Extension Novel543 already exists locally").
--     → After importing, DISABLE/UNINSTALL the old repo "Novel543".
--   • Self-test banner: the report's first line now shows the plugin name +
--     version, so you can instantly confirm you are browsing THIS plugin
--     (v1.0.3 shows no filters at all, so no self-test either).
--
-- 1.2.1 hotfix ("Translator doesn't work" reports):
--   • NEVER-BREAK ARMOR: every translator entry point is pcall-wrapped. A Lua
--     error inside the translator (old app build missing a helper, an API
--     shape change, anything) now degrades to untranslated text instead of
--     failing the whole catalog/book call.
--   • os_time() BUG FIXED: NoveLA's os_time() returns MILLISECONDS
--     (System.currentTimeMillis — verified in LuaSourceLoader.kt), but the
--     circuit breaker compared it against seconds: the breaker re-armed
--     after 0.6s instead of 10min, and if the app build lacks os_time the
--     breaker-trip line crashed the page with "attempt to call a nil
--     value". Now: ms-aware clock, pcall-guarded, with a probe-counter
--     fallback when no clock exists at all.
--   • GET fallback for Google: the dict endpoint also answers GET (q params
--     in the URL), so a network/middlebox that breaks POST bodies still
--     gets translations (POST googleapis → POST clients5 → GET googleapis →
--     GET clients5 → MyMemory → per-item gtx single as the last resort).
--   • Empty-string results no longer poison a whole batch: Google returns
--     "" for an empty q, and the old parser rejected the entire chunk on the
--     first empty string — one empty title used to fail all 18 items on a
--     page (and, three pages in, trip the breaker).
--   • Book pages are fetched ONCE per open: the app calls getBookTitle /
--     Cover / Description / Genres / Status / LastUpdate / ChapterListHash
--     separately and each used to re-download the same page (6-8 round
--     trips per book, multiplied by translation latency). A 60s/12-page
--     session cache now serves the burst from one fetch. Chapter text is
--     never cached.
--   • NEW: ⚡ Translator Self-Test — pick it under Browse filters and the
--     catalog becomes a live diagnostics report (mode, target language,
--     os_time/http_post/json_parse availability, each translation engine
--     with latency and a sample, end-to-end batch, verdict + what to do).
--     Works in raw mode too, so a broken setup can be diagnosed without
--     logs: every step that can fail on-device is shown as its own line.
--
-- 1.2.0 additions (on top of 1.1.0):
--   • Full site filters — mirrors the site's own navigation:
--     - Browse surface picker: Bookstack (書庫) / Rankings (排行榜) / Booklists (書單)
--     - Bookstack: 13 categories (分類), 100 tags (標籤, tag overrides category),
--       gender (男生/女生) and end status (連載/完結) — all combine:
--       /bookstack/<cat>/?page=N&gender=boy|girl&end=1|2  and
--       /tags/[boy|girl/]<tag>/?page=N  (tags accept gender paths, verified live).
--     - Rankings: /ranking/<g>-<t>-<cid>.html — g: 0=女生 1=男生, t: 2=閱讀榜
--       1=潛力榜; the 風雲榜 special ranks instead use t=8 with cid 8001..8005
--       (40 entries): /ranking/<g>-8-<rankId>.html. 34 gender-specific category
--       ids; some (category, type) combos are legitimately EMPTY on the site.
--       30/40 titles, no pagination, items prefixed "#N" with their rank.
--     - Booklists: /shudan/[boy|girl/][new|fav|commend/]?page=N (order matters:
--       gender BEFORE sort — /shudan/fav/boy/ is a 404, verified live).
--   • Booklist pages open like a book: title/cover/description come from the
--     booklist header (h1.title / .cover img / div.intro — same selectors as
--     book pages), and the chapter list is the booklist's novels (title + score).
--     Opening a novel "chapter" fetches that novel's FIRST chapter (a sampler)
--     and appends a footer telling the reader which original title to search
--     to continue the full book.
--   • Translator mode (getSettingsSchema, mirrors WTR-Lab's mode picker):
--     mode = "translate" machine-translates everything EXCEPT chapter text
--     (NoveLA's built-in reader translator handles novel content):
--     catalog/search/ranking/booklist item titles, book title (+ original in
--     parentheses), description, genres, status, chapter titles (toggle),
--     and search queries typed in a non-Chinese language (translated to
--     zh-TW first, zh-CN retry if nothing found). Engine: Google's free
--     "dict-chrome-ex" endpoint (POST, batched q params, no API key) with a
--     MyMemory per-item fallback, a translation cache, a failure circuit
--     breaker (3 strikes → pass-through for 10 minutes), and pass-through to
--     the original text on ANY error — browsing never breaks.
--   • httpGetFollow: NoveLA's http_get does NOT follow redirects
--     (NetworkClient.call default followRedirects=false — verified in Kotlin
--     source), and /ranking.html + mismatched ranking combos 301-redirect;
--     this helper follows Location headers manually (max 4 hops).
--
-- 1.1.0 additions (on top of upstream 1.0.3):
--   • Filters: getFilterList + getCatalogFiltered — gender (全部/男生/女生)
--     and end status (全部/連載/完結) via the site's own /bookstack/
--     query params (gender=boy|girl, end=1|2 — verified live).
--   • getBookGenres: from the og:novel:category meta tag.
--   • Exact hasNext: derived from the pagination widget's next link
--     (li.next.pagination-link:not(.disabled)) — the old `#items > 0`
--     heuristic over-fetched one clamped duplicate page at the end of
--     every list. NOTE: the site clamps out-of-range pages to the last
--     page (page=9999 serves 第20頁 content with HTTP 200), so an
--     items-only heuristic can never detect the end.
--   • getChapterListHash: now og:novel:update_time + "|" +
--     og:novel:latest_chapter_name — catches new chapters AND same-day
--     retranslations (the old p.meta span.iconf:last-child selector
--     returned only the date-granularity 更新 label).
--   • Chapter text: strips the site's trailing "溫馨提示..." reader
--     notice that gets appended inside div.content on every chapter.
--
-- Site facts (verified live 2026-08-28, site now brands as 稷下書院):
--   • Catalog:      GET /bookstack/[<category>/]?page=N[&gender=boy|girl][&end=1|2]
--                   18 items/page, HTML only (no JSON API).
--   • Tags:         GET /tags/[boy|girl/]<urlencoded tag>/?page=N — 18 items/page;
--                   the 100-tag cloud shown in the sidebar is identical on
--                   /bookstack/ and every /tags/ page.
--   • Rankings:     GET /ranking/<g>-<t>-<cid>.html — 30 items, li.media (same
--                   card markup as bookstack), no pagination. cid=0 or a
--                   cross-gender cid 301-redirects to that gender's default.
--   • Booklists:    GET /shudan/[boy|girl/][new|fav|commend/]?page=N — 20
--                   booklists/page; detail page GET /shudan/<id>/ lists its
--                   books as the same li.media cards (h3 a + span.score +
--                   p.desc + span.author).
--   • Search:       GET /search/<url-encoded query>  (site's own JS does
--                   window.location.href = "/search/" + kw). This path is
--                   behind Cloudflare — from datacenter IPs it 403s with a
--                   challenge; NoveLA's CloudFareVerificationInterceptor
--                   auto-solves it on real devices (do NOT add
--                   cf_options = { whitelist = true } — it would disable
--                   that recovery path for this host).
--   • Book page:    h1.title, .cover img, div.intro (has extra modifier
--                   classes — jsoup class selector still matches),
--                   og:novel:{category,author,book_name,status,update_time,
--                   latest_chapter_name} meta tags.
--   • Chapter list: GET <bookUrl>/dir → ul.all li a (all chapters, one page).
--   • Chapter text: div.content (+ nested div.gadBlock/div.adBlock/script/
--                   ins to remove). Long chapters are paginated as
--                   <file>_2.html, <file>_3.html… linked from the current
--                   page (cap 20 sub-pages).
--
-- IMPORTANT — do NOT add `cf_options = { whitelist = true }`:
--   NoveLA's CloudfareVerificationInterceptor auto-detects Cloudflare
--   challenges (the /search/ path sits behind CF) and solves them via the
--   integrated WebView. whitelist = true would DISABLE that recovery path.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
-- NOTE: "Novel543 Full" is intentional (v1.2.2). Do NOT rename it back to
-- "Novel543" — it must stay visually distinct from the old repository
-- extension of the same name, whose v1.0.3 has no filters/settings and
-- collides with this one because sources resolve by baseUrl.
local VERSION = "1.0.4" -- upstream line: 1.0.3 → 1.0.4 (dev builds 1.1.0–1.2.2 superseded)
id       = "novel543"
name     = "Novel543 Full"
version  = VERSION
baseUrl  = "https://www.novel543.com/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/novel543.png"

-- ── Settings preference keys ─────────────────────────────────────────────────
local PREF_MODE    = "novel543_mode"     -- "raw" | "translate"
local PREF_TLANG   = "novel543_tlang"    -- target language code, default "en"
local PREF_TR_CH   = "novel543_tr_chapters" -- "1" | "0" (translate chapter titles)

local SITE = "https://www.novel543.com"

-- ── Site taxonomy (all verified live 2026-08-28) ────────────────────────────

-- /bookstack/<value>/ path segments. en/zh feed flLabel(): filter options
-- render "English (中文)" in raw mode and English only in Translator mode.
local CATEGORIES = {
  { value = "xuanhuan", en = "Xuanhuan / Eastern Fantasy", zh = "玄幻" },
  { value = "xiuzhen",  en = "Xiuzhen / Cultivation",      zh = "修真" },
  { value = "dushi",    en = "Urban",                      zh = "都市" },
  { value = "lishi",    en = "Historical",                 zh = "歷史" },
  { value = "wangyou",  en = "VRMMO / LitRPG",             zh = "網遊" },
  { value = "kehuan",   en = "Sci-Fi",                     zh = "科幻" },
  { value = "nvpin",    en = "Female-Oriented",            zh = "女頻" },
  { value = "lingyi",   en = "Supernatural",               zh = "靈異" },
  { value = "tongren",  en = "Fanfiction",                 zh = "同人" },
  { value = "junshi",   en = "Military",                   zh = "軍事" },
  { value = "xuanyi",   en = "Mystery",                    zh = "懸疑" },
  { value = "chuanyue", en = "Transmigration",             zh = "穿越" },
  { value = "other",    en = "Other",                      zh = "其它" }
}

-- The 100-tag cloud from the site sidebar (identical on /bookstack/ + /tags/).
-- zh is the raw site tag AND the filter VALUE (URL-encoded when building
-- /tags/ URLs — never change it); en is a curated English name for the
-- dropdown. Labels render "English (中文)" in raw mode, English only in
-- Translator mode (flLabel).
local TAGS = {
  { zh = "穿越",     en = "Transmigration" },
  { zh = "現代言情", en = "Modern Romance" },
  { zh = "系統",     en = "System" },
  { zh = "都市",     en = "Urban" },
  { zh = "重生",     en = "Rebirth" },
  { zh = "古代言情", en = "Historical Romance" },
  { zh = "豪門總裁", en = "Wealthy CEO" },
  { zh = "輕鬆",     en = "Lighthearted" },
  { zh = "種田",     en = "Farming" },
  { zh = "玄幻",     en = "Xuanhuan (Eastern Fantasy)" },
  { zh = "寵妻",     en = "Doting Husband" },
  { zh = "系統流",   en = "System Genre" },
  { zh = "歷史",     en = "Historical" },
  { zh = "1V1",      en = "1V1 (Monogamy)" },
  { zh = "幻想言情", en = "Fantasy Romance" },
  { zh = "甜寵",     en = "Sweet & Doting" },
  { zh = "女強",     en = "Strong Female Lead" },
  { zh = "無敵流",   en = "Invincible MC" },
  { zh = "豪門",     en = "Wealthy Family" },
  { zh = "爽文",     en = "Feel-Good Power Fantasy" },
  { zh = "熱血",     en = "Hot-Blooded" },
  { zh = "校園",     en = "School Life" },
  { zh = "空間",     en = "Pocket Dimension" },
  { zh = "娛樂圈",   en = "Showbiz" },
  { zh = "日久生情", en = "Slow-Burn Romance" },
  { zh = "萌寶",     en = "Cute Baby" },
  { zh = "殺伐果斷", en = "Ruthless & Decisive" },
  { zh = "腹黑",     en = "Scheming" },
  { zh = "扮豬吃虎", en = "Playing Pig to Eat Tiger" },
  { zh = "HE",       en = "HE (Happy Ending)" },
  { zh = "懸疑",     en = "Mystery" },
  { zh = "快節奏",   en = "Fast-Paced" },
  { zh = "科幻",     en = "Sci-Fi" },
  { zh = "寵文",     en = "Doting Romance" },
  { zh = "日常文",   en = "Slice of Life" },
  { zh = "腦洞大",   en = "Wild Imagination" },
  { zh = "智商在線", en = "Smart Protagonist" },
  { zh = "推理",     en = "Detective" },
  { zh = "專情",     en = "Devoted Love" },
  { zh = "都市生活", en = "City Life" },
  { zh = "強強",     en = "Power Couple" },
  { zh = "總裁",     en = "CEO" },
  { zh = "賺錢",     en = "Making Money" },
  { zh = "懸疑靈異", en = "Mystery & Supernatural" },
  { zh = "歡喜冤家", en = "Bickering Lovers" },
  { zh = "先婚後愛", en = "Marriage Before Love" },
  { zh = "權謀",     en = "Political Intrigue" },
  { zh = "冷靜",     en = "Level-Headed" },
  { zh = "戰神贅婿", en = "War God Son-in-Law" },
  { zh = "神豪",     en = "Filthy Rich" },
  { zh = "獨寵",     en = "Exclusive Devotion" },
  { zh = "護短",     en = "Fiercely Protective" },
  { zh = "懸疑戀愛", en = "Mystery Romance" },
  { zh = "打臉",     en = "Face-Slapping" },
  { zh = "靈異",     en = "Supernatural" },
  { zh = "養成",     en = "Nurturing" },
  { zh = "宅斗",     en = "Household Intrigue" },
  { zh = "經營",     en = "Business Management" },
  { zh = "異能",     en = "Superpowers" },
  { zh = "神醫",     en = "Miraculous Doctor" },
  { zh = "搞笑",     en = "Comedy" },
  { zh = "家長里短", en = "Domestic Drama" },
  { zh = "都市日常", en = "Urban Slice of Life" },
  { zh = "穿書",     en = "Book Transmigration" },
  { zh = "快穿",     en = "Quick Transmigration" },
  { zh = "架空",     en = "Alternate World" },
  { zh = "科幻末世", en = "Sci-Fi Apocalypse" },
  { zh = "強者歸來", en = "Return of the Strong" },
  { zh = "斗羅大陸", en = "Douluo Continent (Soul Land)" },
  { zh = "甜文",     en = "Sweet Story" },
  { zh = "逆襲",     en = "Counterattack" },
  { zh = "草根崛起", en = "Underdog Rising" },
  { zh = "相愛相殺", en = "Love-Hate Relationship" },
  { zh = "王妃",     en = "Princess Consort" },
  { zh = "武俠",     en = "Wuxia (Martial Heroes)" },
  { zh = "明星",     en = "Celebrity" },
  { zh = "無限流",   en = "Infinite Stream" },
  { zh = "復仇",     en = "Revenge" },
  { zh = "勵志",     en = "Inspirational" },
  { zh = "婚戀",     en = "Marriage & Romance" },
  { zh = "學生",     en = "Student" },
  { zh = "二次元",   en = "Anime & Manga" },
  { zh = "懸疑腦洞", en = "Mystery Twist" },
  { zh = "衍生同人", en = "Derivative Fanfiction" },
  { zh = "破鏡重圓", en = "Rekindled Love" },
  { zh = "爆笑",     en = "Hilarious" },
  { zh = "末世",     en = "Apocalypse" },
  { zh = "青梅竹馬", en = "Childhood Sweethearts" },
  { zh = "護花高手", en = "Guardian of Beauties" },
  { zh = "才女",     en = "Talented Woman" },
  { zh = "家庭",     en = "Family" },
  { zh = "體育",     en = "Sports" },
  { zh = "開局流",   en = "Distinct Opening Scenario" },
  { zh = "智斗",     en = "Battle of Wits" },
  { zh = "王爺",     en = "Prince" },
  { zh = "文娛",     en = "Arts & Entertainment" },
  { zh = "雙潔",     en = "Double Purity" },
  { zh = "現實生活", en = "Realistic Life" },
  { zh = "同居",     en = "Cohabitation" },
  { zh = "諸天流",   en = "Myriad Worlds (Multiverse)" }
}

-- Rank types (URL segment t of /ranking/<g>-<t>-<cid>.html) — mirrors the
-- ranking page's three sidebar sections exactly:
--   閱讀榜 (t=2) and 潛力榜 (t=1) rank the per-gender categories below,
--   風雲榜 (t=8) holds the five special sub-ranks (cid 8001..8005) which
--   are listed at the bottom of RANK_CATEGORIES as "Trending · …" entries.
local RANK_TYPES = {
  { value = "2", en = "Reading Rank",   zh = "閱讀榜" },
  { value = "1", en = "Potential Rank", zh = "潛力榜" },
  { value = "8", en = "Trending Rank",  zh = "風雲榜" }
}

-- Rank categories — value is "<gender>-<cid>" (gender 0=女生 1=男生) so the
-- plugin always builds a gender-matched URL and never triggers the 301.
-- "default" (site landing category per gender) and the five 風雲榜 sub-ranks
-- (value "8-800x") are mixed in: they apply when the Ranking Type is
-- 閱讀榜/潛力榜 (default) or 風雲榜 (sub-ranks) respectively; mismatched
-- combos fall back safely in getCatalogFiltered.
local RANK_CATEGORIES = {
  { value = "default", en = "Default (per gender)",        zh = "預設" },
  { value = "0-1015", en = "(F) Fan Derivative",          zh = "女頻衍生" },
  { value = "0-248",  en = "(F) Fantasy Romance",         zh = "玄幻言情" },
  { value = "0-23",   en = "(F) Farming",                 zh = "種田" },
  { value = "0-79",   en = "(F) Period / Era",            zh = "年代" },
  { value = "0-267",  en = "(F) Modern Romance Twist",    zh = "現言腦洞" },
  { value = "0-246",  en = "(F) Palace Intrigue",         zh = "宮斗宅斗" },
  { value = "0-539",  en = "(F) Mystery Twist",           zh = "懸疑腦洞" },
  { value = "0-253",  en = "(F) Ancient Romance Twist",   zh = "古言腦洞" },
  { value = "0-247",  en = "(F) Medical",                 zh = "醫術" },
  { value = "0-24",   en = "(F) Quick Transmigration",    zh = "快穿" },
  { value = "0-749",  en = "(F) Youth Sweet Romance",     zh = "青春甜寵" },
  { value = "0-745",  en = "(F) Starlight Showbiz",       zh = "星光璀璨" },
  { value = "0-747",  en = "(F) Mystery Romance",         zh = "懸疑戀愛" },
  { value = "0-750",  en = "(F) Career & Marriage",       zh = "職場婚戀" },
  { value = "0-748",  en = "(F) Wealthy CEO",             zh = "豪門總裁" },
  { value = "0-1017", en = "(F) Republican Era Romance",  zh = "民國言情" },
  { value = "1-8",    en = "(M) Sci-Fi Apocalypse",       zh = "科幻末世" },
  { value = "1-261",  en = "(M) Urban Daily Life",         zh = "都市日常" },
  { value = "1-124",  en = "(M) Urban Cultivation",        zh = "都市修真" },
  { value = "1-1014", en = "(M) Urban High-Martial",       zh = "都市高武" },
  { value = "1-259",  en = "(M) Xianxia Fantasy",         zh = "奇幻仙俠" },
  { value = "1-273",  en = "(M) Historical",              zh = "歷史古代" },
  { value = "1-27",   en = "(M) War God Son-in-Law",      zh = "戰神贅婿" },
  { value = "1-263",  en = "(M) Urban Farming",           zh = "都市種田" },
  { value = "1-258",  en = "(M) Traditional Xuanhuan",    zh = "傳統玄幻" },
  { value = "1-272",  en = "(M) Alt-History Twist",       zh = "歷史腦洞" },
  { value = "1-539",  en = "(M) Mystery Twist",           zh = "懸疑腦洞" },
  { value = "1-262",  en = "(M) Urban Twist",             zh = "都市腦洞" },
  { value = "1-257",  en = "(M) Xuanhuan Twist",          zh = "玄幻腦洞" },
  { value = "1-751",  en = "(M) Mystery Supernatural",     zh = "懸疑靈異" },
  { value = "1-504",  en = "(M) War & Espionage",          zh = "抗戰諜戰" },
  { value = "1-746",  en = "(M) Gaming & Sports",          zh = "遊戲體育" },
  { value = "1-718",  en = "(M) Anime Derivative",        zh = "動漫衍生" },
  { value = "1-1016", en = "(M) Male-Oriented Derivative", zh = "男頻衍生" },
  -- 風雲榜 sub-ranks (cid 8001..8005 — same ids for both genders):
  { value = "8-8001", en = "Trending · Hot",              zh = "風雲·大熱榜" },
  { value = "8-8002", en = "Trending · New Books",        zh = "風雲·新書榜" },
  { value = "8-8003", en = "Trending · Completed",        zh = "風雲·完結榜" },
  { value = "8-8004", en = "Trending · Most Collected",   zh = "風雲·收藏榜" },
  { value = "8-8005", en = "Trending · Recently Updated", zh = "風雲·更新榜" }
}

-- Static English lookups for tiny fixed vocabulary (used only when the target
-- language is English; other languages go through the API and get cached).
local STATIC_EN = {
  ["連載"] = "Ongoing",   ["完結"] = "Completed",
  ["玄幻"] = "Xuanhuan (Fantasy)", ["修真"] = "Xiuzhen (Cultivation)",
  ["都市"] = "Urban",     ["歷史"] = "Historical",
  ["網遊"] = "VRMMO",     ["科幻"] = "Sci-Fi",
  ["女頻"] = "Female-Oriented", ["靈異"] = "Supernatural",
  ["同人"] = "Fanfiction",["軍事"] = "Military",
  ["懸疑"] = "Mystery",   ["穿越"] = "Transmigration",
  ["其它"] = "Other",     ["其他"] = "Other"
}

-- ── Generic helpers ──────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- True when the string contains CJK ideographs (UTF-8 lead bytes E4-E9 cover
-- U+3000–U+9FFF). Used to decide whether a search query needs translating.
local function hasCJK(s)
  return type(s) == "string" and string.find(s, "[\228-\233]") ~= nil
end

local function isShudanUrl(url)
  return type(url) == "string" and string.find(url, "/shudan/%d+/?") ~= nil
end

-- A booklist "chapter" URL is a book page: https://host/<digits>/ with no .html
local function isBookPageUrl(url)
  return type(url) == "string" and string.find(url, "^https?://[^/]+/%d+/?$") ~= nil
end

-- ── HTTP with manual redirect following ─────────────────────────────────────
-- NoveLA's http_get does NOT follow redirects (NetworkClient default), and
-- /ranking.html or a gender/cid mismatch answers 301. Follow Location by hand.
local function httpGetFollow(url)
  local r = http_get(url)
  for _ = 1, 4 do
    if not r then return r end
    if r.success then return r end
    local code = tonumber(r.code) or 0
    if code ~= 301 and code ~= 302 and code ~= 303 and code ~= 307 and code ~= 308 then
      return r
    end
    local loc = nil
    if type(r.headers) == "table" and type(r.headers["location"]) == "table" then
      loc = r.headers["location"][1]
    end
    if type(loc) ~= "string" or loc == "" then return r end
    r = http_get(absUrl(loc))
  end
  return r
end

-- ── Short-lived page cache ──────────────────────────────────────────────
-- Opening a book makes the app call getBookTitle / getBookCoverImageUrl /
-- getBookDescription / getBookGenres / getBookStatus / getBookLastUpdate /
-- getChapterListHash separately — without this cache each of them re-downloads
-- the SAME page (6-8 network round-trips per book open, multiplied by
-- translation latency in Translator mode). 60s TTL, 12 pages, self-disables
-- when no clock is available. Chapter text is NEVER served from here.

-- NoveLA's os_time() returns MILLISECONDS (System.currentTimeMillis —
-- LuaSourceLoader.kt OsTimeFunction). Be robust anyway: scale seconds up,
-- and survive builds where the function does not exist at all.
-- Returns a ms clock, or nil when no clock is available.
local function nowMs()
  local ok, v = pcall(os_time)
  if ok and type(v) == "number" and v > 0 then
    if v < 100000000000 then v = v * 1000 end -- seconds → ms
    return v
  end
  return nil
end

local pageCache, pageCacheOrder = {}, {}
local PAGE_TTL_MS    = 60000
local PAGE_CACHE_MAX = 12

local function fetchPageCached(url)
  local now = nowMs()
  if not now then return httpGetFollow(url) end -- no clock → bypass cache
  local e = pageCache[url]
  if e and (now - e.t) < PAGE_TTL_MS then return e.r end
  local r = httpGetFollow(url)
  if r and r.success then
    if pageCache[url] == nil then
      pageCacheOrder[#pageCacheOrder + 1] = url
      if #pageCacheOrder > PAGE_CACHE_MAX then
        pageCache[table.remove(pageCacheOrder, 1)] = nil
      end
    end
    pageCache[url] = { r = r, t = now }
  end
  return r
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Translator core
-- ═══════════════════════════════════════════════════════════════════════════
-- Engine: Google's free dict endpoint (client=dict-chrome-ex) — POST with
-- repeated q params returns one translation per q, e.g. body "q=玄幻&q=都市"
-- → ["fantasy","city"]. With sl=auto the shape nests the detected source:
-- [["fantasy","zh-CN"]] — both shapes are parsed. No API key, no OAuth.
-- Request chain, each step only on the previous step's failure:
--   1. POST translate.googleapis.com/translate_a/t
--   2. POST clients5.google.com/translate_a/t
--   3. GET  translate.googleapis.com/translate_a/t (q in the URL — same shape;
--      survives middleboxes that mangle POST bodies; skipped for long chunks)
--   4. GET  clients5.google.com/translate_a/t
--   5. MyMemory (api.mymemory.translated.net, anonymous, ~5k chars/day)
--   6. Google gtx single — per item, only the first 6 of a failed chunk
--      (blocked on some datacenter IPs but works from residential/mobile
--      networks, i.e. real devices)
-- EVERY failure path returns the original text, and every public entry point
-- is pcall-armored — browsing must never break because of the translator.

local TR_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
local TR_HOSTS = {
  "https://translate.googleapis.com",
  "https://clients5.google.com"
}
local TR_FAIL_LIMIT     = 3       -- consecutive failed batches before pass-through
local TR_RETRY_AFTER_MS = 600000  -- breaker half-opens after 10 minutes

local trCache      = {}       -- original → translated (session-lifetime)
local trCacheCount = 0
local trFailStreak = 0
local trDisabledAt = 0
local trProbeCount = 0        -- breaker tick when no clock is available

local function getMode()
  local ok, v = pcall(get_preference, PREF_MODE)
  if ok and v == "translate" then return "translate" end
  return "raw"
end

local function getTl()
  local ok, v = pcall(get_preference, PREF_TLANG)
  if ok and type(v) == "string" and v ~= "" then return v end
  return "en"
end

local function trChaptersEnabled()
  local ok, v = pcall(get_preference, PREF_TR_CH)
  if ok and v == "0" then return false end
  return true -- default on
end

-- Filter label builder. Labels follow the Mode setting — they rebuild when
-- the source screen is (re)opened (the ViewModel fetches getFilterList() once
-- per catalog-screen session; the adapter itself has no cache):
--   raw mode       → "English (中文)"   (bilingual — keeps the site flavor)
--   translate mode → "English"          (English only, no Chinese counterpart)
-- Latin-only zh values ("HE", "1V1") add nothing and collapse to the English
-- name in both modes. Applies to every filter: section headers AND options,
-- the 100 tags included. Tag VALUES are never touched — only labels.
local function flLabel(en, zh)
  if getMode() == "translate" then return en end
  if zh and zh ~= "" and hasCJK(zh) then return en .. " (" .. zh .. ")" end
  return en
end

local function trActive()
  if getMode() ~= "translate" then return false end
  if trFailStreak < TR_FAIL_LIMIT then return true end
  local now = nowMs()
  if now then
    return (now - trDisabledAt) >= TR_RETRY_AFTER_MS -- half-open after 10 min
  end
  return (trProbeCount % 16) == 0 -- no clock: probe once every 16 batches
end

local function trCachePut(k, v)
  if trCacheCount > 4000 then return end -- hard cap; a session never gets near it
  if trCache[k] == nil then trCacheCount = trCacheCount + 1 end
  trCache[k] = v
end

-- Parse the /t endpoint response. Accepted shapes (Lua 1-based):
--   {"t1","t2"}                (explicit sl)
--   {{"t1","src"},{"t2","src"}} (sl=auto)
--   {"t1"}                     (single q, either sl)
-- Empty strings are VALID (Google returns "" for an empty q) — the caller
-- maps them back to the original text. Returns an array of exactly `want`
-- strings, or nil when the response is too short / malformed.
local function parseTrArray(j, want)
  if type(j) ~= "table" then return nil end
  local out = {}
  for i = 1, want do
    local e = j[i]
    local t = nil
    if type(e) == "string" then
      t = e
    elseif type(e) == "table" then
      if type(e[1]) == "string" then t = e[1]
      elseif type(e[1]) == "table" and type(e[1][1]) == "string" then t = e[1][1] end
    end
    if t == nil then return nil end
    out[i] = t
  end
  return out
end

-- GET variant of the /t endpoint with q params in the URL — same response
-- shape as POST. Splits the chunk into groups that keep the URL under
-- ~1400 chars (an 18-title Chinese page encodes to ~2k chars, over both
-- conservative URL limits and the old hard cap — splitting keeps the GET
-- fallback usable for real pages instead of silently skipping it).
-- Returns a full-length array (originals for empty slots), or nil on failure.
local function trGetChunk(host, texts, sl, tl)
  local out = {}
  local i = 1
  while i <= #texts do
    local group, encLen = {}, 0
    while i <= #texts do
      local enc = "q=" .. url_encode(texts[i])
      if encLen + #enc + 1 > 1400 and #group > 0 then break end
      group[#group + 1] = texts[i]
      encLen = encLen + #enc + 1
      i = i + 1
    end
    local qs = {}
    for _, t in ipairs(group) do qs[#qs + 1] = "q=" .. url_encode(t) end
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl
      .. "&tl=" .. url_encode(tl) .. "&" .. table.concat(qs, "&")
    local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
    if not (r and r.success and type(r.body) == "string"
            and string.sub(r.body, 1, 1) == "[") then return nil end
    local res = parseTrArray(json_parse(r.body), #group)
    if not res then return nil end
    for k = 1, #group do
      local v = res[k]
      if v == nil or v == "" then v = group[k] end
      out[#out + 1] = v
    end
  end
  return out
end

-- Steps 1-4 of the request chain: Google dict endpoint, POST then GET, on
-- both hosts. Returns an array of #texts strings, or nil.
local function trRequestGoogle(texts, sl, tl)
  local qs = {}
  for _, t in ipairs(texts) do qs[#qs + 1] = "q=" .. url_encode(t) end
  local qstr = table.concat(qs, "&")
  for _, host in ipairs(TR_HOSTS) do
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl .. "&tl=" .. url_encode(tl)
    -- POST (q params in the body)
    local r = http_post(url, qstr, {
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["User-Agent"]   = TR_UA
      }
    })
    if r and r.success and type(r.body) == "string"
       and string.sub(r.body, 1, 1) == "[" then
      local res = parseTrArray(json_parse(r.body), #texts)
      if res then return res end
    end
    -- GET (q params in the URL, auto-split for length)
    local res = trGetChunk(host, texts, sl, tl)
    if res then return res end
  end
  return nil
end

-- Step 6: classic gtx single endpoint — one text per request. Blocked from
-- some datacenter IPs but works from residential/mobile networks (i.e. real
-- devices), so it is the last Google resort before giving up on an item.
-- Response: [[["translation","original",...],...],...] — take j[1][1][1].
local function trGtxSingle(text, tl)
  local url = "https://translate.googleapis.com/translate_a/single"
    .. "?client=gtx&sl=auto&tl=" .. url_encode(tl)
    .. "&dt=t&q=" .. url_encode(text)
  local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
  if r and r.success and type(r.body) == "string"
     and string.sub(r.body, 1, 1) == "[" then
    local j = json_parse(r.body)
    if type(j) == "table" and type(j[1]) == "table" and type(j[1][1]) == "table"
       and type(j[1][1][1]) == "string" then
      return j[1][1][1]
    end
  end
  return nil
end

-- MyMemory fallback — per-item GET, short texts only (anonymous daily quota).
-- Returns an array of #texts entries (originals where an item failed), or
-- NIL when nothing at all was translated — the caller treats nil as a real
-- failure (circuit-breaker tick + gtx rescue). Returning a full array of
-- originals here would make every batch look "successful" and the breaker
-- would never trip.
local function trChunkMyMemory(texts, tl)
  local out = {}
  local any = false
  for i, t in ipairs(texts) do
    out[i] = t
    if #t <= 300 then
      local url = "https://api.mymemory.translated.net/get?q=" .. url_encode(t)
                   .. "&langpair=zh|" .. url_encode(tl)
      local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
      if r and r.success and type(r.body) == "string"
         and string.sub(r.body, 1, 1) == "{" then
        local j = json_parse(r.body)
        if type(j) == "table" and type(j.responseData) == "table"
           and type(j.responseData.translatedText) == "string" then
          local tr = j.responseData.translatedText
          if tr ~= "" and tr ~= t and string.find(tr, "MYMEMORY WARNING") == nil then
            out[i] = tr
            any = true
          end
        end
      end
    end
  end
  if not any then return nil end
  return out
end

-- Translate an array of strings; ALWAYS returns an array of the same length
-- (failed/uncached items pass through unchanged). pcall-armored: a Lua error
-- anywhere inside (old app build, changed API shape, anything) degrades to
-- the original texts instead of failing the page.
local function translateBatchImpl(texts)
  local n = #texts
  if n == 0 then return texts end
  if not trActive() then
    trProbeCount = trProbeCount + 1 -- breaker tick (also the no-clock probe)
    return texts
  end

  -- cache pass
  local out, pending, pIdx = {}, {}, {}
  for i = 1, n do
    local c = trCache[texts[i]]
    if c ~= nil then out[i] = c
    else pending[#pending + 1] = texts[i]; pIdx[#pIdx + 1] = i end
  end
  if #pending == 0 then return out end

  -- chunked requests: ≤40 items and ≤3000 chars per chunk
  local CHUNK_MAX = 40
  local s = 1
  while s <= #pending do
    local chunk, chars = {}, 0
    while s + #chunk <= #pending and #chunk < CHUNK_MAX do
      local t = pending[s + #chunk]
      if chars + #t > 3000 and #chunk > 0 then break end
      chunk[#chunk + 1] = t
      chars = chars + #t
    end
    local base = s
    s = s + #chunk

    local tl = getTl()
    local res = trRequestGoogle(chunk, "zh-CN", tl)
    local usedFallback = false
    if not res then
      res = trChunkMyMemory(chunk, tl)
      usedFallback = true
    end
    if res and #res == #chunk then
      if not usedFallback then trFailStreak = 0 end -- full success resets the breaker
      for k = 1, #chunk do
        local v = res[k]
        if v == nil or v == "" then v = chunk[k] end -- empty result → original
        out[pIdx[base + k - 1]] = v
        trCachePut(chunk[k], v)
      end
    else
      -- Last resort: per-item gtx single for the first items of the chunk
      -- (covers 1-item calls fully; caps the worst-case latency for pages).
      local anyOk = false
      local cap = #chunk
      if cap > 6 then cap = 6 end
      for k = 1, cap do
        local v = nil
        if #chunk[k] <= 400 then v = trGtxSingle(chunk[k], tl) end
        if v and v ~= "" then
          out[pIdx[base + k - 1]] = v
          trCachePut(chunk[k], v)
          anyOk = true
        else
          out[pIdx[base + k - 1]] = chunk[k] -- pass-through on failure
        end
      end
      for k = cap + 1, #chunk do
        out[pIdx[base + k - 1]] = chunk[k]
      end
      if not anyOk then
        trFailStreak = trFailStreak + 1
        if trFailStreak >= TR_FAIL_LIMIT then
          trDisabledAt = nowMs() or 0
          log_info("novel543: translator disabled for 10 min (3 failed batches)")
        end
      end
    end
  end
  return out
end

local function translateBatch(texts)
  if type(texts) ~= "table" then return texts end
  local ok, res = pcall(translateBatchImpl, texts)
  if ok and type(res) == "table" and #res == #texts then return res end
  if not ok then log_info("novel543: translator error: " .. tostring(res)) end
  return texts
end

-- Translate a single string (cached; original on failure).
local function translateOne(text)
  if type(text) ~= "string" or text == "" or not trActive() then return text end
  local c = trCache[text]
  if c ~= nil then return c end
  local r = translateBatch({ text })
  return r[1] or text
end

-- Fixed site vocabulary: free for English, API (cached) for other languages.
local function translateVocab(text)
  if type(text) ~= "string" or text == "" then return text end
  if not trActive() then return text end
  if getTl() == "en" and STATIC_EN[text] then return STATIC_EN[text] end
  return translateOne(text)
end

-- Reverse direction for search: user-language query → Chinese.
-- sl=auto → response nests detected source, parseTrArray handles it.
local function translateQueryToZh(query, tl)
  if not trActive() then return nil end
  local ok, res = pcall(trRequestGoogle, { query }, "auto", tl)
  if ok and type(res) == "table" and res[1] and res[1] ~= query then return res[1] end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing (shared by bookstack / tags / ranking / shudan / search)
-- ═══════════════════════════════════════════════════════════════════════════

-- Parse one list page into { items, hasNext }. Every site list surface uses
-- the same ul.list li.media cards. hasNext comes from the pagination widget's
-- next link (exact) — the site clamps out-of-range pages to the last page, so
-- item-count heuristics fail. Items get an optional `count` field when the
-- card shows a booklist's book count (共N本書 — shudan listing pages).
local function parseListPage(r)
  local items = {}
  if not r or not r.success then return { items = items, hasNext = false } end
  for _, li in ipairs(html_select(r.body, "ul.list li.media")) do
    local titleEl = html_select_first(li.html, "div.media-content h3 a")
    local bookUrl = absUrl(html_attr(li.html, "div.media-left a", "href"))
    local cover   = absUrl(html_attr(li.html, "div.media-left img", "src"))
    if titleEl and bookUrl ~= "" then
      local item = {
        title = string_clean(titleEl.text),
        url   = bookUrl,
        cover = cover
      }
      -- booklist cards: "共4本書" in one of the p.desc lines
      for _, p in ipairs(html_select(li.html, "p.desc")) do
        local c = string.match(p.text or "", "(%d+)本書")
        if c then item.count = tonumber(c) end
      end
      table.insert(items, item)
    end
  end
  local hasNext = #html_select(r.body, "li.next.pagination-link:not(.disabled)") > 0
  return { items = items, hasNext = hasNext }
end

-- Batch-translate catalog item titles in place (after decorations are applied
-- by the caller — rank prefixes and book counts are added post-translation).
local function translateCatalogItems(items)
  if not trActive() or #items == 0 then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Translator self-test (Browse filter → "⚡ Translator Self-Test")
-- ═══════════════════════════════════════════════════════════════════════════
-- Turns the catalog into a live diagnostics report: settings, environment
-- helpers, every translation engine with latency + a sample translation, the
-- end-to-end batch, and a verdict with the next step. Runs in ANY mode — if
-- the mode is raw the engines are still probed, so a broken on-device setup
-- can be diagnosed without logcat. Tapping a line just opens the bookstack.
local function runSelfTest()
  local items = {}
  local function line(mark, label, detail)
    local d = ""
    if detail ~= nil and detail ~= "" then d = " — " .. detail end
    items[#items + 1] = {
      title = mark .. " " .. label .. d,
      url   = SITE .. "/bookstack/",
      cover = ""
    }
  end
  local function elapsed(t0)
    local n = nowMs()
    if t0 and n and n >= t0 then return tostring(math.floor(n - t0)) .. "ms" end
    return ""
  end

  -- 0. banner — proves which plugin this catalog is running (v1.0.3 from the
  -- old repository has no filters at all, so it can never show this report)
  line("⚡", "Plugin", "Novel543 Full v" .. VERSION ..
       " — if you can see this line, you are on the RIGHT source")

  -- 1. settings
  local mode = getMode()
  local tl   = getTl()
  if mode == "translate" then
    line("✓", "Mode", "translate (target language: " .. tl .. ")")
  else
    line("!", "Mode", "raw — open this source's Settings, set Mode = Translator, then REFRESH the catalog")
  end

  -- 2. environment helpers (the things older app builds can lack)
  local clock = nowMs()
  line(clock and "✓" or "!", "os_time",
       clock and "available (milliseconds)" or
       "MISSING on this app build — translation still works, breaker degrades")

  local hasPost = (type(http_post) == "function")
  line(hasPost and "✓" or "!", "http_post",
       hasPost and "available" or
       "MISSING on this app build — old version; the GET fallback covers translation")

  local j = json_parse('["a","b"]')
  local jOk = type(j) == "table" and j[1] == "a" and j[2] == "b"
  line(jOk and "✓" or "✗", "json_parse",
       jOk and "array → Lua table OK" or ("unexpected result type: " .. type(j)))

  -- 3. engines (probed directly, regardless of mode)
  local probe = { "玄幻", "都市" }

  local t1 = nowMs()
  local r1 = trRequestGoogle(probe, "zh-CN", tl)
  line(r1 and "✓" or "✗", "Google batch (POST/GET, 2 hosts)",
       r1 and ((elapsed(t1) .. " → ") .. table.concat(r1, " / ")) or
       (elapsed(t1) .. " unreachable"))

  local t2 = nowMs()
  local r2 = trChunkMyMemory(probe, tl)
  local mmOk = r2 ~= nil and r2[1] ~= probe[1]
  line(mmOk and "✓" or "✗", "MyMemory fallback",
       mmOk and (elapsed(t2) .. " → " .. table.concat(r2, " / ")) or
       (elapsed(t2) .. " unreachable"))

  local t3 = nowMs()
  local r3 = trGtxSingle("玄幻", tl)
  line(r3 and "✓" or "✗", "Google gtx single",
       r3 and (elapsed(t3) .. " → " .. r3) or
       (elapsed(t3) .. " unreachable (fine when the batch engine works)"))

  -- 4. end-to-end through the real pipeline (mode + breaker respected)
  if mode == "translate" then
    local e2e = translateBatch({ "釋放那個女巫" })
    local e2eOk = e2e ~= nil and e2e[1] ~= nil and e2e[1] ~= "釋放那個女巫"
    line(e2eOk and "✓" or "!", "End-to-end batch",
         e2eOk and ("「釋放那個女巫」 → " .. e2e[1]) or
         "returned the original text — see the failing step above")
  end

  -- 5. verdict
  if mode ~= "translate" then
    line("→", "Verdict", "engines probed above — switch Mode to Translator in this source's settings, then pull-to-refresh the catalog")
  elseif r1 or (mmOk) or r3 then
    line("→", "Verdict", "translator pipeline OK — if titles still show Chinese: pull-to-refresh the catalog (already-loaded pages are not retranslated)")
  else
    line("→", "Verdict", "ALL engines unreachable — your network/region is blocking Google & MyMemory (VPN, DNS filter, firewall). Try another network or disable the VPN")
  end

  return { items = items, hasNext = false }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Catalog, search and filtered browse
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Page-scoped filters (1.0.4) ─────────────────────────────────────────
-- Each site page has its OWN filter sidebar, and the filter sheet must mirror
-- the page being browsed (NOT stack every page's filters together). The app's
-- filter UI cannot show/hide sections dynamically — SourceCatalogViewModel
-- fetches getFilterList() once per catalog-screen session and the sheet renders
-- whatever it receives — so the plugin adapts its LIST to the page instead:
--   bookstack → Type · Status · Category · Tags   (類型/作品狀態/分類/標籤)
--   shudan    → Type · Sort                       (類型 + 最新發佈/最多收藏/小編推薦)
--   ranking   → Ranking Type · Gender · Ranking Category
--               (閱讀榜/潛力榜/風雲榜 + 女生/男生 + per-type categories)
-- getCatalogFiltered records the applied page here; getCatalogList resets it
-- to bookstack (a fresh unfiltered session shows the bookstack page). After
-- switching Page inside the sheet the catalog updates instantly; the reduced
-- filter set appears the next time the source screen is opened (back out of
-- the catalog and re-enter — the app re-fetches the filter list then).
local currentSurface = "bookstack"

function getCatalogList(index)
  -- Fresh unfiltered session → the sheet must mirror the bookstack page it
  -- is about to show (page-scoped filters).
  currentSurface = "bookstack"
  local url = SITE .. "/bookstack/?page=" .. tostring(index + 1)
  local res = parseListPage(httpGetFollow(url))
  translateCatalogItems(res.items)
  return res
end

-- ── Search (first page only; /search/ is CF-protected — NoveLA solves it) ───
-- In Translator mode a non-Chinese query is first translated to zh-TW (the
-- site indexes Traditional titles); if nothing is found the zh-CN variant is
-- tried once. Result titles are translated like any other catalog page.
function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end

  local q = query
  if trActive() and not hasCJK(query) and query ~= "" then
    local tw = translateQueryToZh(query, "zh-TW")
    if tw then q = tw end
  end

  local res = parseListPage(httpGetFollow(SITE .. "/search/" .. url_encode(q)))

  if q ~= query and #res.items == 0 then
    -- retry with the Simplified variant (user-generated titles may be either)
    local cn = translateQueryToZh(query, "zh-CN")
    if cn and cn ~= q then
      res = parseListPage(httpGetFollow(SITE .. "/search/" .. url_encode(cn)))
    end
  end

  translateCatalogItems(res.items)
  return res
end

-- ── Filtered browse ──────────────────────────────────────────────────────────
-- URL shapes (all verified live):
--   bookstack: /bookstack/[<cat>/]?page=N[&gender=boy|girl][&end=1|2]
--   tag:       /tags/[boy|girl/]<tag>/?page=N          (tag overrides category)
--   ranking:   /ranking/<g>-<t>-<cid>.html             (30 items, no pages)
--   shudan:    /shudan/[boy|girl/][new|fav|commend/]?page=N
function getCatalogFiltered(index, filters)
  filters = filters or {}
  local page   = index + 1
  local browse = filters["browse"] or "bookstack"
  if browse ~= "bookstack" and browse ~= "ranking" and browse ~= "shudan" and browse ~= "selftest" then
    browse = "bookstack"
  end
  currentSurface = browse -- page-scoped filters: remember the page being browsed
  local gender = filters["gender"]

  -- ── Translator self-test (diagnostics as catalog items) ──────────────
  if browse == "selftest" then
    if index > 0 then return { items = {}, hasNext = false } end
    local ok, res = pcall(runSelfTest)
    if ok and type(res) == "table" then return res end
    return {
      items = {
        {
          title = "✗ Self-test crashed: " .. tostring(res),
          url   = SITE .. "/bookstack/",
          cover = ""
        }
      },
      hasNext = false
    }
  end

  -- ── Rankings ──────────────────────────────────────────────────────────────
  -- Mirrors /ranking.html: three sidebar sections (閱讀榜 t=2 / 潛力榜 t=1 /
  -- 風雲榜 t=8) + the 女生(g=0)/男生(g=1) tabs + per-type categories.
  if browse == "ranking" then
    if index > 0 then return { items = {}, hasNext = false } end
    -- rank_type: 2/1/8; legacy saved values (8001..8005 from old-style state)
    -- fold into the 風雲榜 type.
    local rt = filters["rank_type"]
    if rt == "8001" or rt == "8002" or rt == "8003" or rt == "8004" or rt == "8005" then
      rt = "8"
    end
    if rt ~= "1" and rt ~= "2" and rt ~= "8" then rt = "2" end
    -- Gender tabs: 0=女生 (site default) 1=男生
    local g = filters["rank_gender"]
    if g ~= "0" and g ~= "1" then g = "0" end
    local cg, cid = string.match(filters["rank_category"] or "", "^(%d)-(%d+)$")
    local url
    if rt == "8" then
      -- 風雲榜: the category picker supplies the sub-rank (cid 8001..8005);
      -- anything else (default / a plain category / nothing) → Hot (大熱榜).
      local sub = cid
      if cg ~= "8" or (sub ~= "8001" and sub ~= "8002" and sub ~= "8003" and sub ~= "8004" and sub ~= "8005") then
        sub = "8001"
      end
      url = SITE .. "/ranking/" .. g .. "-8-" .. sub .. ".html"
    else
      -- 閱讀榜/潛力榜: an explicitly picked (F)/(M) category carries its own
      -- gender (cids are gender-specific, exactly like the site sidebar);
      -- "default" / a trending sub-rank / nothing → the Gender picker with
      -- the site's per-gender landing category (F 1015 女頻衍生, M 8 科幻末世).
      if cg ~= "0" and cg ~= "1" then cg = nil end
      if not cg or (cid == "8001" or cid == "8002" or cid == "8003" or cid == "8004" or cid == "8005") then
        cg  = g
        cid = (g == "1") and "8" or "1015"
      end
      url = SITE .. "/ranking/" .. cg .. "-" .. rt .. "-" .. cid .. ".html"
    end
    local res = parseListPage(httpGetFollow(url))
    translateCatalogItems(res.items)
    for i, it in ipairs(res.items) do
      it.title = "#" .. i .. " " .. it.title
    end
    res.hasNext = false -- ranking pages hold every entry (30, or 40 for 風雲榜)
    return res
  end

  -- ── Booklists (書單) ──────────────────────────────────────────────────────
  if browse == "shudan" then
    local path = SITE .. "/shudan/"
    if gender == "boy" or gender == "girl" then path = path .. gender .. "/" end
    local sort = filters["shudan_sort"]
    if sort == "new" or sort == "fav" or sort == "commend" then
      path = path .. sort .. "/"
    end
    local res = parseListPage(httpGetFollow(path .. "?page=" .. page))
    translateCatalogItems(res.items)
    for _, it in ipairs(res.items) do
      if it.count then
        if getMode() == "translate" then
          it.title = it.title .. " (" .. it.count .. " books)"
        else
          it.title = it.title .. " (共" .. it.count .. "本書)"
        end
      end
    end
    return res
  end

  -- ── Bookstack (書庫): tag browse or category browse ───────────────────────
  local tag = filters["tag"]
  if tag and tag ~= "" and tag ~= "none" then
    local path = SITE .. "/tags/"
    if gender == "boy" or gender == "girl" then path = path .. gender .. "/" end
    local res = parseListPage(httpGetFollow(path .. url_encode(tag) .. "/?page=" .. page))
    translateCatalogItems(res.items)
    return res
  end

  local cat = filters["category"]
  local path = SITE .. "/bookstack/"
  if cat and cat ~= "" and cat ~= "all" then path = path .. cat .. "/" end
  local params = { "page=" .. page }
  if gender == "boy" or gender == "girl" then
    params[#params + 1] = "gender=" .. gender
  end
  local endStatus = filters["end_status"]
  if endStatus == "1" or endStatus == "2" then
    params[#params + 1] = "end=" .. endStatus
  end
  local res = parseListPage(httpGetFollow(path .. "?" .. table.concat(params, "&")))
  translateCatalogItems(res.items)
  return res
end

-- PAGE-SCOPED (1.0.4): the sheet mirrors the page being browsed — the Page
-- picker first, then ONLY that page's filters (see currentSurface above for
-- how the app's once-per-session fetch interacts with page switching).
-- Labels are mode-aware (flLabel): bilingual "English (中文)" in raw mode,
-- English only in Translator mode. Tag VALUES stay the raw site tags in both
-- modes — they are URL-encoded into /tags/ URLs and saved in filter state.
function getFilterList()
  local surface = currentSurface
  if surface ~= "bookstack" and surface ~= "ranking" and surface ~= "shudan" and surface ~= "selftest" then
    surface = "bookstack"
  end

  local function opt(en, zh, value)
    return { value = value, label = flLabel(en, zh) }
  end

  local filters = {
    {
      type = "select", key = "browse",
      label = flLabel("Page", "頁面"),
      defaultValue = surface, -- follows the page being browsed
      options = {
        { value = "bookstack", label = flLabel("Bookstack", "書庫") },
        { value = "ranking",   label = flLabel("Rankings", "排行榜") },
        { value = "shudan",    label = flLabel("Booklists", "書單") },
        { value = "selftest",  label = flLabel("⚡ Translator Self-Test", "診斷") }
      }
    }
  }

  if surface == "bookstack" then
    -- Mirrors the /bookstack/ sidebar, same order: 類型 · 作品狀態 · 分類 · 標籤
    local catOptions = { opt("All", "全部", "all") }
    for _, c in ipairs(CATEGORIES) do
      catOptions[#catOptions + 1] = { value = c.value, label = flLabel(c.en, c.zh) }
    end
    local tagOptions = { opt("None", "無", "none") }
    for _, t in ipairs(TAGS) do
      tagOptions[#tagOptions + 1] = { value = t.zh, label = flLabel(t.en, t.zh) }
    end
    filters[#filters + 1] = {
      type = "select", key = "gender",
      label = flLabel("Type", "類型"),
      defaultValue = "all",
      options = { opt("All", "全部", "all"), opt("Male", "男生", "boy"), opt("Female", "女生", "girl") }
    }
    filters[#filters + 1] = {
      type = "select", key = "end_status",
      label = flLabel("Status", "作品狀態"),
      defaultValue = "all",
      options = { opt("All", "全部", "all"), opt("Ongoing", "連載", "1"), opt("Completed", "完結", "2") }
    }
    filters[#filters + 1] = {
      type = "select", key = "category",
      label = flLabel("Category", "分類"),
      defaultValue = "all",
      options = catOptions
    }
    filters[#filters + 1] = {
      type = "select", key = "tag",
      label = flLabel("Tags", "標籤"),
      defaultValue = "none",
      options = tagOptions
    }

  elseif surface == "shudan" then
    -- Mirrors the /shudan/ sidebar: 類型 row + the sort row
    filters[#filters + 1] = {
      type = "select", key = "gender",
      label = flLabel("Type", "類型"),
      defaultValue = "all",
      options = { opt("All", "全部", "all"), opt("Male", "男生", "boy"), opt("Female", "女生", "girl") }
    }
    filters[#filters + 1] = {
      type = "select", key = "shudan_sort",
      label = flLabel("Sort", "排序"),
      defaultValue = "new",
      options = {
        opt("Latest", "最新發佈", "new"),
        opt("Most Favorited", "最多收藏", "fav"),
        opt("Editor's Picks", "小編推薦", "commend")
      }
    }

  elseif surface == "ranking" then
    -- Mirrors /ranking.html: the three sidebar sections 閱讀榜/潛力榜/風雲榜,
    -- the 女生/男生 tabs, and the per-type categories (the "Trending · …"
    -- entries apply when Ranking Type = 風雲榜).
    local rankTypeOptions = {}
    for _, r in ipairs(RANK_TYPES) do
      rankTypeOptions[#rankTypeOptions + 1] = { value = r.value, label = flLabel(r.en, r.zh) }
    end
    local rankCatOptions = {}
    for _, r in ipairs(RANK_CATEGORIES) do
      rankCatOptions[#rankCatOptions + 1] = { value = r.value, label = flLabel(r.en, r.zh) }
    end
    filters[#filters + 1] = {
      type = "select", key = "rank_type",
      label = flLabel("Ranking Type", "榜單類型"),
      defaultValue = "2",
      options = rankTypeOptions
    }
    filters[#filters + 1] = {
      type = "select", key = "rank_gender",
      label = flLabel("Gender", "性別"),
      defaultValue = "0",
      options = { opt("Female", "女生", "0"), opt("Male", "男生", "1") }
    }
    filters[#filters + 1] = {
      type = "select", key = "rank_category",
      label = flLabel("Ranking Category", "榜單分類"),
      defaultValue = "default",
      options = rankCatOptions
    }
  end

  -- surface == "selftest": the Page picker alone — the diagnostics page has
  -- no filters of its own.
  return filters
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Book details
-- ═══════════════════════════════════════════════════════════════════════════

function getBookTitle(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return nil end
  local el = html_select_first(r.body, "h1.title")
  if not el then return nil end
  local title = string_clean(el.text)
  if trActive() then
    local tr = translateOne(title)
    if tr and tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return nil end
  local el = html_select_first(r.body, ".cover img")
  if el then return absUrl(el.src) end
  return nil
end

-- Books: div.intro. Booklists: div.intro (often empty) — enrich with the
-- creator line and book count from the header meta.
function getBookDescription(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return nil end

  if isShudanUrl(bookUrl) then
    local intro = ""
    local el = html_select_first(r.body, "div.intro")
    if el then intro = string_clean(el.text) end
    local meta = html_select_first(r.body, "p.meta")
    local creator = ""
    if meta then creator = string_clean(meta.text) end
    local count = #html_select(r.body, "ul.list li.media")
    local header = "Booklist · " .. count .. " books"
    if creator ~= "" then header = header .. " · " .. creator end
    if trActive() and intro ~= "" then
      intro = translateOne(intro)
    end
    if intro ~= "" then
      return header .. "\n\n" .. intro
    end
    return header
  end

  local el = html_select_first(r.body, "div.intro")
  if not el then return nil end
  local desc = string_clean(el.text)
  if desc ~= "" and trActive() then
    if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
    desc = translateOne(desc)
  end
  return desc
end

-- Genre from the og:novel:category meta tag (e.g. 「其他」). Booklists have none.
function getBookGenres(bookUrl)
  if isShudanUrl(bookUrl) then return {} end
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return {} end
  local cat = html_attr(r.body, "meta[name='og:novel:category']", "content")
  if cat and cat ~= "" then
    return { translateVocab(string_clean(cat)) }
  end
  return {}
end

-- ── Status and last update ──────────────────────────────────────────────────

-- Status — og:novel:status meta (「連載」/「完結」). Booklists: no status.
function getBookStatus(bookUrl)
  if isShudanUrl(bookUrl) then return nil end
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return nil end
  local s = html_attr(r.body, "meta[name='og:novel:status']", "content")
  if s and s ~= "" then return translateVocab(string_clean(s)) end
  return nil
end

-- Last update — books: og:novel:update_time meta (date part). Booklists: the
-- 更新 timestamp from the header meta line.
function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return nil end

  if isShudanUrl(bookUrl) then
    local meta = html_select_first(r.body, "p.meta")
    if meta then
      local dt = string.match(meta.text or "", "(%d%d%d%d%-%d%d%-%d%d)")
      if dt then return dt end
    end
    return nil
  end

  local dt = html_attr(r.body, "meta[name='og:novel:update_time']", "content")
  if dt and dt ~= "" then
    local d = string.match(dt, "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
  end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list (books: GET <bookUrl>/dir; booklists: the list's novels)
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterList(bookUrl)
  -- ── Booklist: each novel in the list becomes a "chapter" ─────────────────
  if isShudanUrl(bookUrl) then
    local r = fetchPageCached(bookUrl)
    if not r or not r.success then return {} end
    local chapters = {}
    for _, li in ipairs(html_select(r.body, "ul.list li.media")) do
      local titleEl = html_select_first(li.html, "div.media-content h3 a")
      local href    = html_attr(li.html, "div.media-left a", "href")
      if titleEl and href and href ~= "" then
        local title = string_clean(titleEl.text)
        local scoreEl = html_select_first(li.html, "span.score")
        if scoreEl then
          local s = string.match(scoreEl.text or "", "(%d+%.?%d*)")
          if s then title = title .. " (" .. s .. "/10)" end
        end
        table.insert(chapters, { title = title, url = absUrl(href) })
      end
    end
    if trActive() and trChaptersEnabled() then
      local titles = {}
      for i = 1, #chapters do titles[i] = chapters[i].title end
      local tr = translateBatch(titles)
      for i = 1, #chapters do chapters[i].title = tr[i] end
    end
    return chapters
  end

  -- ── Regular book: GET <bookUrl>/dir ──────────────────────────────────────
  local dirUrl = bookUrl:gsub("/$", "") .. "/dir"
  local r = http_get(dirUrl)
  if not r or not r.success then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, "ul.all li a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      table.insert(chapters, {
        title = string_clean(a.text),
        url   = chUrl
      })
    end
  end

  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    for i = 1, #chapters do chapters[i].title = tr[i] end
  end

  return chapters
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Update hash
-- ═══════════════════════════════════════════════════════════════════════════

-- Books: og:novel:update_time (full "YYYY-MM-DD HH:MM:SS" — second
-- granularity, so same-day retranslations are caught) + og:novel:
-- latest_chapter_name. Booklists: the 更新 timestamp + book count (lists
-- change when their creator edits them).
function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not r or not r.success then return nil end

  if isShudanUrl(bookUrl) then
    local meta = html_select_first(r.body, "p.meta")
    local ts = ""
    if meta then
      ts = string.match(meta.text or "", "(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d)") or ""
    end
    local count = #html_select(r.body, "ul.list li.media")
    if ts ~= "" or count > 0 then
      return tostring(count) .. "|" .. ts
    end
    return nil
  end

  local updated  = html_attr(r.body, "meta[name='og:novel:update_time']", "content")
  local lastChap = html_attr(r.body, "meta[name='og:novel:latest_chapter_name']", "content")
  if (updated and updated ~= "") or (lastChap and lastChap ~= "") then
    return (updated or "") .. "|" .. (lastChap or "")
  end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text (multi-page) + booklist sampler
-- ═══════════════════════════════════════════════════════════════════════════

-- Strip the site's trailing reader notice, e.g.
-- 「溫馨提示: iphone手機下某些版本的Safari瀏覽器會卡死的問題...改善!」
-- Primary removal is structural (div:has(p:contains(溫馨提示)) in extractPage);
-- this text-level pass is a safety net for when the wrapper markup changes
-- but the notice wording stays. Runs to the notice's closing "!".
local function stripSiteNotice(text)
  return regex_replace(text, "溫馨提示[:：]?\\s*iphone[^!]{0,400}!\\s*", "")
end

local function extractChapterText(pageHtml, chapterFile)
  local function extractPage(htmlIn)
    local el = html_select_first(htmlIn, "div.content")
    if not el then return "" end
    -- Story paragraphs are bare <p> children; the site's trailing reader notice
    -- (「溫馨提示: iphone手機...Safari瀏覽器...」) is injected as a nested
    -- <div><p><span style="color:#ff6666">…</span>…</p></div> at the end of
    -- div.content — remove that wrapper element wholesale.
    local cleaned = html_remove(el.html, "div.gadBlock", "div.adBlock", "script", "ins",
                                 "div:has(p:contains(溫馨提示))")
    return html_text("<div>" .. cleaned .. "</div>")
  end

  local parts = {}
  local first = extractPage(pageHtml)
  if first ~= "" then table.insert(parts, first) end

  local currentHtml = pageHtml
  for _ = 1, 20 do
    local subUrl = nil
    for _, a in ipairs(html_select(currentHtml, "a[href]")) do
      local href = a.href
      local fname = string.match(href, "/([^/]+)$") or ""
      if string.match(fname, "^" .. chapterFile:gsub("%-", "%%-") .. "_%d+%.html$") then
        subUrl = absUrl(href)
        break
      end
    end

    if not subUrl then break end

    local pr = http_get(subUrl)
    if not pr.success then break end

    local sub = extractPage(pr.body)
    if sub ~= "" then table.insert(parts, sub) end

    currentHtml = pr.body
  end

  local text = string_trim(table.concat(parts, "\n\n"))
  text = string_trim(stripSiteNotice(text))
  return text
end

-- Footer appended to booklist sampler chapters so the reader knows how to
-- reach the full novel (the original title is what the site's search indexes).
local function samplerFooter(bookTitle)
  local title = bookTitle or "?"
  if getMode() == "translate" then
    return "\n\n—— Booklist sampler: this is chapter 1 of 「" .. title ..
           "」. To keep reading the full novel, search this exact title " ..
           "in this source's search bar."
  end
  return "\n\n—— 書單試讀：這是《" .. title .. "》的第一章。要閱讀全書，請以這個書名在本書源的搜索欄搜索。"
end

function getChapterText(html, url)
  -- ── Booklist sampler: url is a book page (/<bookId>/), html is that page.
  -- Fetch the novel's chapter list and deliver its FIRST chapter.
  if isBookPageUrl(url) then
    local titleEl = html_select_first(html, "h1.title")
    local bookTitle = titleEl and string_clean(titleEl.text) or nil

    local dirUrl = url:gsub("/$", "") .. "/dir"
    local dr = http_get(dirUrl)
    if dr and dr.success then
      local first = html_select_first(dr.body, "ul.all li a")
      if first and first.href and first.href ~= "" then
        local chUrl = absUrl(first.href)
        local cr = http_get(chUrl)
        if cr and cr.success then
          local chFile = string.match(chUrl, "/([^/]+)%.html$") or ""
          local text = extractChapterText(cr.body, chFile)
          if text ~= "" then
            return text .. samplerFooter(bookTitle)
          end
        end
      end
    end

    -- Fall back to the book's introduction if chapter 1 is unavailable.
    local el = html_select_first(html, "div.intro")
    if el then
      local intro = string_clean(el.text)
      if intro ~= "" then
        return intro .. samplerFooter(bookTitle)
      end
    end
    return samplerFooter(bookTitle)
  end

  -- ── Regular chapter ───────────────────────────────────────────────────────
  local chapterFile = string.match(url, "/([^/]+)%.html$") or ""
  return extractChapterText(html, chapterFile)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Settings schema (Translator mode)
-- ═══════════════════════════════════════════════════════════════════════════

function getSettingsSchema()
  return {
    {
      key = PREF_MODE,
      type = "select",
      label = "Mode (模式)",
      current = getMode(),
      options = {
        { value = "raw",       label = "Raw (原文) — Chinese UI, no translation" },
        { value = "translate", label = "Translator (翻譯模式) — translate everything except chapter text" }
      }
    },
    {
      key = PREF_TLANG,
      type = "select",
      label = "Translate To (目標語言)",
      current = getTl(),
      options = {
        { value = "en", label = "English" },
        { value = "es", label = "Español" },
        { value = "pt", label = "Português" },
        { value = "ru", label = "Русский" },
        { value = "fr", label = "Français" },
        { value = "de", label = "Deutsch" },
        { value = "tr", label = "Türkçe" },
        { value = "ar", label = "العربية" },
        { value = "id", label = "Bahasa Indonesia" },
        { value = "th", label = "ไทย" },
        { value = "vi", label = "Tiếng Việt" },
        { value = "ja", label = "日本語" },
        { value = "ko", label = "한국어" },
        { value = "hi", label = "हिन्दी" },
        { value = "ur", label = "اردو" }
      }
    },
    {
      key = PREF_TR_CH,
      type = "select",
      label = "Translate Chapter Titles (章節標題)",
      current = trChaptersEnabled() and "1" or "0",
      options = {
        { value = "1", label = "On (開)" },
        { value = "0", label = "Off (關)" }
      }
    }
  }
end
