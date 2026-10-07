-- WitAnime — видео-плагин NoveLA (content_type = "video")
-- Сайт: https://witanime.site — каталог аниме с плеером и списком хостов.

content_type = "video"
id           = "witanime"
name         = "WitAnime"
version      = "1.0.1"
baseUrl      = "https://witanime.site"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/witanime.png"

local EPISODE_MARK = "الحلقة" -- арабская метка «серия» в заголовках эпизодов

local string_lower = string.lower

-- ============ Каталог ============

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function headerValue(headers, name)
    local v = headers and (headers[name] or headers[string_lower(name)])
    if type(v) == "table" then return v[1] end
    if type(v) == "string" then return v end
    return nil
end

local function parseCards(body)
    local items = {}
    for _, card in ipairs(html_select(body, "a[data-preview]")) do
        local link = html_select_first(card.html, "h3")
        local url = absUrl(card.href)
        if link and url ~= "" then
            local title = string_clean(link.text)
            if title ~= "" then
                items[#items + 1] = {
                    title = title,
                    url   = url,
                    cover = absUrl(html_attr(card.html, "img", "src")),
                }
            end
        end
    end
    return items
end

local function fetchList(url)
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    return {
        items   = parseCards(r.body),
        hasNext = html_select_first(r.body, "a[rel='next']") ~= nil,
    }
end

-- /browse — первая страница, /browse/page/N (N >= 2) — остальные.
local function browseUrl(page, query)
    local path = page > 1 and ("/browse/page/" .. page) or "/browse"
    if query and query ~= "" then return baseUrl .. path .. "?" .. query end
    return baseUrl .. path
end

function getCatalogList(index)
    return fetchList(browseUrl(index + 1))
end

function getCatalogSearch(index, query)
    if not query or query == "" then return { items = {}, hasNext = false } end
    return fetchList(browseUrl(index + 1, "search=" .. url_encode(query)))
end

-- ============ Фильтры ============
-- Параметры и значения сверены с wire:effects компонента browse-anime.

local SORT_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "A-Z", label = "A-Z" },
    { value = "Z-A", label = "Z-A" },
    { value = "Top Rated", label = "الأعلى تقييمًا" },
    { value = "Most Viewed", label = "الأكثر مشاهدة" },
}

local STATUS_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "ongoing", label = "مستمر" },
    { value = "completed", label = "مكتمل" },
    { value = "upcoming", label = "قادم" },
}

local TYPE_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "TV", label = "TV" },
    { value = "TV Short", label = "TV Short" },
    { value = "OVA", label = "OVA" },
    { value = "ONA", label = "ONA" },
    { value = "Special", label = "Special" },
    { value = "Music", label = "Music" },
    { value = "PV", label = "PV" },
    { value = "CM", label = "CM" },
}

local YEAR_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "2026", label = "2026" },
    { value = "2025", label = "2025" },
    { value = "2024", label = "2024" },
    { value = "2023", label = "2023" },
    { value = "2022", label = "2022" },
    { value = "2021", label = "2021" },
    { value = "2020", label = "2020" },
    { value = "2019", label = "2019" },
    { value = "2018", label = "2018" },
    { value = "2017", label = "2017" },
    { value = "2016", label = "2016" },
    { value = "2015", label = "2015" },
    { value = "2014", label = "2014" },
    { value = "2013", label = "2013" },
    { value = "2012", label = "2012" },
    { value = "2011", label = "2011" },
    { value = "2010", label = "2010" },
    { value = "2009", label = "2009" },
    { value = "2008", label = "2008" },
    { value = "2007", label = "2007" },
    { value = "2006", label = "2006" },
    { value = "2005", label = "2005" },
    { value = "2004", label = "2004" },
    { value = "2003", label = "2003" },
    { value = "2002", label = "2002" },
    { value = "2000", label = "2000" },
    { value = "1999", label = "1999" },
    { value = "1998", label = "1998" },
    { value = "1997", label = "1997" },
    { value = "1996", label = "1996" },
    { value = "1995", label = "1995" },
    { value = "1994", label = "1994" },
    { value = "1993", label = "1993" },
    { value = "1992", label = "1992" },
    { value = "1989", label = "1989" },
    { value = "1986", label = "1986" },
    { value = "1985", label = "1985" },
    { value = "1978", label = "1978" },
}

local SEASON_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "spring", label = "الربيع" },
    { value = "summer", label = "الصيف" },
    { value = "fall", label = "الخريف" },
    { value = "winter", label = "الشتاء" },
}

local STUDIO_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "100studio", label = "100studio" },
    { value = "8bit", label = "8bit" },
    { value = "a-1-pictures", label = "A-1 Pictures" },
    { value = "a-real", label = "A-Real" },
    { value = "appp", label = "A.P.P.P." },
    { value = "acgt", label = "ACGT" },
    { value = "actas", label = "Actas" },
    { value = "adonero", label = "Adonero" },
    { value = "aic", label = "AIC" },
    { value = "aic-build", label = "AIC Build" },
    { value = "aic-plus", label = "AIC Plus+" },
    { value = "ajia-do", label = "Ajia-do" },
    { value = "akatsuki", label = "Akatsuki" },
    { value = "alfred-imageworks", label = "Alfred Imageworks" },
    { value = "animation-studio42", label = "animation studio42" },
    { value = "arect", label = "ARECT" },
    { value = "arms", label = "Arms" },
    { value = "artland", label = "Artland" },
    { value = "arvo-animation", label = "ARVO ANIMATION" },
    { value = "asahi-production", label = "Asahi Production" },
    { value = "ascension", label = "ascension" },
    { value = "ashi-productions", label = "Ashi Productions" },
    { value = "asread", label = "asread." },
    { value = "atelier-pontdarc", label = "Atelier Pontdarc" },
    { value = "aura-studio", label = "Aura Studio" },
    { value = "bcmay-pictures", label = "B.CMAY PICTURES" },
    { value = "bakken-record", label = "BAKKEN RECORD" },
    { value = "bandai-namco-pictures", label = "Bandai Namco Pictures" },
    { value = "bedream", label = "BeDream" },
    { value = "beemedia", label = "Bee・Media" },
    { value = "bellnox-films", label = "BELLNOX FILMS" },
    { value = "benten-film", label = "BENTEN Film" },
    { value = "bibury-animation-studios", label = "Bibury Animation Studios" },
    { value = "bigfirebird-animation", label = "BigFireBird Animation" },
    { value = "blade", label = "BLADE" },
    { value = "bones", label = "bones" },
    { value = "bones-film", label = "bones film" },
    { value = "bookong-culture", label = "BooKong Culture" },
    { value = "brains-base", label = "Brain&#039;s Base" },
    { value = "bridge", label = "Bridge" },
    { value = "bug-films", label = "BUG FILMS" },
    { value = "c-station", label = "C-Station" },
    { value = "c2c", label = "C2C" },
    { value = "cgcg", label = "CGCG" },
    { value = "childrens-playground-entertainment", label = "Children&#039;s Playground Entertainment" },
    { value = "clap", label = "CLAP" },
    { value = "climax-studio", label = "Climax Studio" },
    { value = "cloud-hearts", label = "CLOUD HEARTS" },
    { value = "cloverworks", label = "CloverWorks" },
    { value = "cmc-media", label = "CMC Media" },
    { value = "colored-pencil-animation", label = "Colored Pencil Animation" },
    { value = "colored-pencil-animation-japan", label = "Colored Pencil Animation Japan" },
    { value = "colored-pencil-animation-design", label = "Colored-Pencil Animation Design" },
    { value = "comix-wave-films", label = "CoMix Wave Films" },
    { value = "comptown", label = "CompTown" },
    { value = "connect", label = "CONNECT" },
    { value = "craftar", label = "CRAFTAR" },
    { value = "craftar-studios", label = "Craftar Studios" },
    { value = "crew-cell", label = "CREW-CELL" },
    { value = "cue", label = "CUE" },
    { value = "cypic", label = "Cypic" },
    { value = "daume", label = "Daume" },
    { value = "david-production", label = "david production" },
    { value = "digital-network-animation", label = "Digital Network Animation" },
    { value = "diomedea", label = "diomedéa" },
    { value = "dle", label = "DLE" },
    { value = "dmmfutureworks", label = "DMM.futureworks" },
    { value = "doga-kobo", label = "Doga Kobo" },
    { value = "domerica", label = "domerica" },
    { value = "drive", label = "Drive" },
    { value = "eh-production", label = "E&amp;H production" },
    { value = "east-fish-studio", label = "EAST FISH STUDIO" },
    { value = "egg-firm", label = "EGG FIRM" },
    { value = "eightbit", label = "eightbit" },
    { value = "ekachi-epilka", label = "EKACHI EPILKA" },
    { value = "emt-squared", label = "EMT Squared" },
    { value = "encourage-films", label = "Encourage Films" },
    { value = "engi", label = "ENGI" },
    { value = "enishiya", label = "ENISHIYA" },
    { value = "eota", label = "EOTA" },
    { value = "evg", label = "evg" },
    { value = "ezola", label = "Ezόla" },
    { value = "feel", label = "feel." },
    { value = "felixfilm", label = "FelixFilm" },
    { value = "flagship-line", label = "FLAGSHIP LINE" },
    { value = "flat-studio", label = "FLAT STUDIO" },
    { value = "gcmay-animation-film", label = "G.CMay Animation &amp; Film" },
    { value = "ga-crew", label = "GA-CREW" },
    { value = "gaina", label = "GAINA" },
    { value = "gainax", label = "Gainax" },
    { value = "gallop", label = "Gallop" },
    { value = "gambit", label = "Gambit" },
    { value = "garden", label = "GARDEN" },
    { value = "geek-toys", label = "Geek Toys" },
    { value = "geektoys", label = "GEEKTOYS" },
    { value = "gekkou", label = "GEKKOU" },
    { value = "gemba", label = "GEMBA" },
    { value = "geno-studio", label = "Geno Studio" },
    { value = "geyeg-pictures", label = "GeyeG Pictures" },
    { value = "gohands", label = "GoHands" },
    { value = "gonzo", label = "GONZO" },
    { value = "graphinica", label = "Graphinica" },
    { value = "haoliners-animation-league", label = "Haoliners Animation League" },
    { value = "hayabusa-film", label = "Hayabusa Film" },
    { value = "heart-soul-animation", label = "Heart &amp; Soul Animation" },
    { value = "hoods-drifters-studio", label = "Hoods Drifters Studio" },
    { value = "hoods-entertainment", label = "Hoods Entertainment" },
    { value = "hornets", label = "HORNETS" },
    { value = "hotline", label = "HOTLINE" },
    { value = "ilca", label = "ILCA" },
    { value = "imagica-infos", label = "IMAGICA Infos" },
    { value = "imagineer", label = "Imagineer" },
    { value = "jcstaff", label = "J.C.STAFF" },
    { value = "jumondou", label = "Jumondou" },
    { value = "juvenage", label = "JUVENAGE" },
    { value = "kachigarasu", label = "Kachigarasu" },
    { value = "kamikaze-douga", label = "Kamikaze Douga" },
    { value = "khara", label = "khara" },
    { value = "kigumi", label = "Kigumi" },
    { value = "kinema-citrus", label = "Kinema citrus" },
    { value = "kyoto-animation", label = "Kyoto Animation" },
    { value = "l-a-unchbox", label = "l-a-unch・BOX" },
    { value = "lan-studio", label = "LAN Studio" },
    { value = "landq-studios", label = "LandQ studios" },
    { value = "lapintrack", label = "Lapintrack" },
    { value = "lay-duce", label = "Lay-duce" },
    { value = "lerche", label = "Lerche" },
    { value = "lesprit", label = "Lesprit" },
    { value = "liber", label = "Liber" },
    { value = "lidenfilms", label = "LIDENFILMS" },
    { value = "lidenfilms-kyoto-studio", label = "LIDENFILMS KYOTO Studio" },
    { value = "ling-san-wu-donghua", label = "Ling San Wu Donghua" },
    { value = "liyu-culture", label = "LIYU CULTURE" },
    { value = "msc", label = "M.S.C" },
    { value = "madhouse", label = "MADHOUSE" },
    { value = "magic-bus", label = "Magic Bus" },
    { value = "maho-film", label = "MAHO FILM" },
    { value = "makaria", label = "Makaria" },
    { value = "manglobe", label = "Manglobe" },
    { value = "mappa", label = "MAPPA" },
    { value = "marvy-jack", label = "Marvy Jack" },
    { value = "millepensee", label = "Millepensee" },
    { value = "moe", label = "MOE" },
    { value = "nas", label = "NAS" },
    { value = "naz", label = "NAZ" },
    { value = "newon", label = "NEWON" },
    { value = "nexus", label = "Nexus" },
    { value = "nichicaline", label = "NICHICALINE" },
    { value = "nippon-animation", label = "Nippon Animation" },
    { value = "nomad", label = "NOMAD" },
    { value = "nut", label = "NUT" },
    { value = "okuruto-noboru", label = "Okuruto Noboru" },
    { value = "olm", label = "OLM" },
    { value = "olm-team-yoshioka", label = "OLM Team Yoshioka" },
    { value = "orange", label = "Orange" },
    { value = "outline", label = "OUTLINE" },
    { value = "oz", label = "OZ" },
    { value = "pa-works", label = "P.A. Works" },
    { value = "pics", label = "P.I.C.S." },
    { value = "passione", label = "Passione" },
    { value = "pastel", label = "Pastel" },
    { value = "pb-animation-co-ltd", label = "Pb Animation Co. Ltd." },
    { value = "pierrot-films", label = "PIERROT FILMS" },
    { value = "pine-jam", label = "PINE JAM" },
    { value = "platinumvision", label = "platinumvision" },
    { value = "polygon-pictures", label = "Polygon Pictures" },
    { value = "powerhouse-animation", label = "Powerhouse Animation" },
    { value = "pra", label = "PRA" },
    { value = "production-h", label = "Production +h." },
    { value = "production-ig", label = "Production I.G" },
    { value = "production-ims", label = "Production IMS" },
    { value = "production-reve", label = "Production Reve" },
    { value = "project-no9", label = "project No.9" },
    { value = "purple-cow", label = "Purple Cow" },
    { value = "quad", label = "Quad" },
    { value = "qualia-animation", label = "Qualia Animation" },
    { value = "quebico", label = "Quebico" },
    { value = "qzilla", label = "Qzil.la" },
    { value = "radix", label = "Radix" },
    { value = "red-dog-culture-house", label = "Red Dog Culture House" },
    { value = "revoroot", label = "REVOROOT" },
    { value = "rockn-roll-mountain", label = "ROCK&#039;N ROLL MOUNTAIN" },
    { value = "saetta", label = "Saetta" },
    { value = "sanzigen", label = "SANZIGEN" },
    { value = "sasayuri", label = "Sasayuri" },
    { value = "satelight", label = "Satelight" },
    { value = "science-saru", label = "Science SARU" },
    { value = "seven", label = "Seven" },
    { value = "seven-arcs", label = "Seven Arcs" },
    { value = "seven-arcs-pictures", label = "Seven Arcs Pictures" },
    { value = "shaft", label = "SHAFT" },
    { value = "shin-ei-animation", label = "Shin-Ei Animation" },
    { value = "shirogumi", label = "SHIROGUMI" },
    { value = "shogakukan-music-digital-entertainment", label = "Shogakukan Music &amp; Digital Entertainment" },
    { value = "shuka", label = "Shuka" },
    { value = "signalmd", label = "Signal.MD" },
    { value = "silver-link", label = "SILVER LINK." },
    { value = "soigne", label = "Soigne" },
    { value = "sola-digital-arts", label = "SOLA DIGITAL ARTS" },
    { value = "sola-entertainment", label = "Sola Entertainment" },
    { value = "sotsu", label = "SOTSU" },
    { value = "stsignpost", label = "St.Signpost" },
    { value = "stsilver", label = "st.Silver" },
    { value = "staple-entertainment", label = "Staple Entertainment" },
    { value = "studio-3hz", label = "Studio 3Hz" },
    { value = "studio-4c", label = "Studio 4°C" },
    { value = "studio-a-cat", label = "studio A-CAT" },
    { value = "studio-add", label = "Studio Add" },
    { value = "studio-bind", label = "Studio Bind" },
    { value = "studio-blanc", label = "Studio Blanc." },
    { value = "studio-candybox", label = "studio CANDYBOX" },
    { value = "studio-chizu", label = "Studio Chizu" },
    { value = "studio-colorido", label = "Studio Colorido" },
    { value = "studio-comet", label = "studio COMET" },
    { value = "studio-daisy", label = "studio daisy" },
    { value = "studio-deen", label = "Studio DEEN" },
    { value = "studio-durian", label = "Studio DURIAN" },
    { value = "studio-eek", label = "STUDIO EEK" },
    { value = "studio-elle", label = "Studio Elle" },
    { value = "studio-flad", label = "Studio flad" },
    { value = "studio-ghibli", label = "Studio Ghibli" },
    { value = "studio-gokumi", label = "Studio Gokumi" },
    { value = "studio-hibari", label = "Studio HIBARI" },
    { value = "studio-kafka", label = "Studio KAFKA" },
    { value = "studio-kai", label = "Studio KAI" },
    { value = "studio-lan", label = "Studio LAN" },
    { value = "studio-m2", label = "Studio M2" },
    { value = "studio-massket", label = "STUDIO MASSKET" },
    { value = "studio-mir", label = "Studio Mir" },
    { value = "studio-mother", label = "studio MOTHER" },
    { value = "studio-n", label = "Studio N" },
    { value = "studio-palette", label = "studio palette" },
    { value = "studio-pierrot", label = "studio Pierrot" },
    { value = "studio-polon", label = "STUDIO POLON" },
    { value = "studio-ponoc", label = "Studio Ponoc" },
    { value = "studio-puyukai", label = "Studio PuYUKAI" },
    { value = "studio-rikka", label = "Studio Rikka" },
    { value = "studio-voln", label = "studio VOLN" },
    { value = "studio4c", label = "STUDIO4°C" },
    { value = "sublimation", label = "Sublimation" },
    { value = "sunrise", label = "SUNRISE" },
    { value = "synergysp", label = "SynergySP" },
    { value = "tatsunoko-production", label = "Tatsunoko Production" },
    { value = "team-oneone", label = "Team OneOne" },
    { value = "team-yamahitsuji", label = "team Yamahitsuji" },
    { value = "tear-studio", label = "tear-studio" },
    { value = "teddy", label = "Teddy" },
    { value = "telecom-animation-film", label = "Telecom Animation Film" },
    { value = "tezuka-productions", label = "Tezuka Productions" },
    { value = "the-answer-studio", label = "The Answer Studio" },
    { value = "thundray", label = "Thundray" },
    { value = "tiger-animation", label = "Tiger Animation" },
    { value = "tms-entertainment", label = "TMS Entertainment" },
    { value = "tms-entertainment7studio", label = "TMS Entertainment/7studio" },
    { value = "tms-entertainmentstudio-6", label = "TMS Entertainment/Studio 6" },
    { value = "tmsstudio-1", label = "TMS/Studio 1" },
    { value = "tnk", label = "TNK" },
    { value = "toei-animation", label = "Toei Animation" },
    { value = "toho-animation-studio", label = "TOHO animation STUDIO" },
    { value = "tokyo-movie-shinsha", label = "Tokyo Movie Shinsha" },
    { value = "trif-studio", label = "TriF Studio" },
    { value = "trigger", label = "TRIGGER" },
    { value = "troyca", label = "TROYCA" },
    { value = "tsumugi-akita-animation-lab", label = "TSUMUGI AKITA ANIMATION LAB" },
    { value = "twilight-studio", label = "Twilight Studio" },
    { value = "tyo-animations", label = "TYO Animations" },
    { value = "typhoon-graphics", label = "Typhoon Graphics" },
    { value = "ufotable", label = "ufotable" },
    { value = "unend", label = "UNEND" },
    { value = "visual-flight", label = "Visual Flight" },
    { value = "voil", label = "Voil" },
    { value = "wao-world", label = "Wao World" },
    { value = "wawayu-animation", label = "Wawayu Animation" },
    { value = "white-fox", label = "WHITE FOX" },
    { value = "wit-studio", label = "WIT STUDIO" },
    { value = "wolfsbane", label = "Wolfsbane" },
    { value = "xebec", label = "XEBEC" },
    { value = "yokohama-animation-lab", label = "Yokohama Animation Lab" },
    { value = "yostar-pictures", label = "Yostar Pictures" },
    { value = "yumeta-company", label = "Yumeta Company" },
    { value = "zero-g", label = "ZERO-G" },
    { value = "zexcs", label = "ZEXCS" },
}

local SOURCE_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "Manga", label = "مانجا" },
    { value = "Web Manga", label = "مانجا ويب" },
    { value = "Light Novel", label = "رواية خفيفة" },
    { value = "Novel", label = "رواية" },
    { value = "Web Novel", label = "رواية ويب" },
    { value = "Visual Novel", label = "رواية مرئية" },
    { value = "Webtoon", label = "ويبتون" },
    { value = "Book", label = "كتاب" },
    { value = "Game", label = "لعبة" },
    { value = "Anime", label = "أنمي" },
    { value = "Original", label = "قصة أصلية" },
    { value = "Music", label = "أغنية" },
    { value = "Mixed Media", label = "وسائط متعددة" },
    { value = "Other", label = "أخرى" },
}

local COUNTRY_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "CN", label = "الصين" },
    { value = "US", label = "الولايات المتحدة" },
    { value = "JP", label = "اليابان" },
    { value = "KR", label = "كوريا الجنوبية" },
}

local VERSION_OPTIONS = {
    { value = "", label = "الكل" },
    { value = "sub", label = "مترجم" },
    { value = "dub", label = "مدبلج" },
    { value = "both", label = "مترجم ومدبلج" },
}

local GENRE_OPTIONS = {
    { value = "mythology", label = "أساطير" },
    { value = "kids", label = "أطفال" },
    { value = "action", label = "أكشن" },
    { value = "ecchi", label = "إيتشي" },
    { value = "isekai", label = "إيسكاي" },
    { value = "strategy-game", label = "استراتيجي" },
    { value = "avant-garde", label = "الخارج عن المألوف" },
    { value = "time-travel", label = "السفر عبر الزمن" },
    { value = "survival", label = "بقاء" },
    { value = "baseball", label = "بيسبول" },
    { value = "historical", label = "تاريخي" },
    { value = "detective", label = "تحري" },
    { value = "suspense", label = "تشويق" },
    { value = "educational", label = "تعليمي" },
    { value = "reincarnation", label = "تناسخ" },
    { value = "tennis", label = "تنس" },
    { value = "josei", label = "جوسيه" },
    { value = "harem", label = "حريم" },
    { value = "reverse-harem", label = "حريم عكسي" },
    { value = "pets", label = "حيوانات أليفة" },
    { value = "supernatural", label = "خارق للطبيعة" },
    { value = "fantasy", label = "خيال" },
    { value = "sci-fi", label = "خيال علمي" },
    { value = "drama", label = "دراما" },
    { value = "gore", label = "دموي" },
    { value = "horror", label = "رعب" },
    { value = "archery", label = "رماية بالقوس" },
    { value = "romance", label = "رومانسي" },
    { value = "combat-sports", label = "رياضات قتالية" },
    { value = "motorsport", label = "رياضة السيارات" },
    { value = "sports", label = "رياضي" },
    { value = "zombies", label = "زومبي" },
    { value = "parody", label = "ساخر" },
    { value = "samurai", label = "ساموراي" },
    { value = "magic", label = "سحر" },
    { value = "seinen", label = "سينين" },
    { value = "slice-of-life", label = "شريحة من الحياة" },
    { value = "shoujo", label = "شوجو" },
    { value = "shounen", label = "شونين" },
    { value = "medical", label = "طبي" },
    { value = "gourmet", label = "طعام راقي" },
    { value = "military", label = "عسكري" },
    { value = "mystery", label = "غموض" },
    { value = "mahou-shoujo", label = "فتيات سحرية" },
    { value = "space", label = "فضاء" },
    { value = "performing-arts", label = "فنون الأداء" },
    { value = "visual-arts", label = "فنون بصرية" },
    { value = "martial-arts", label = "فنون قتالية" },
    { value = "cats", label = "قطط" },
    { value = "super-power", label = "قوى خارقة" },
    { value = "badminton", label = "كرة الريشة" },
    { value = "basketball", label = "كرة السلة" },
    { value = "volleyball", label = "كرة الطائرة" },
    { value = "soccer", label = "كرة قدم" },
    { value = "comedy", label = "كوميديا" },
    { value = "video-game", label = "لعبة فيديو" },
    { value = "post-apocalyptic", label = "ما بعد نهاية العالم" },
    { value = "school", label = "مدرسي" },
    { value = "vampire", label = "مصاصي الدماء" },
    { value = "adventure", label = "مغامرة" },
    { value = "workplace", label = "مهني" },
    { value = "music", label = "موسيقى" },
    { value = "mecha", label = "ميكا" },
    { value = "psychological", label = "نفسي" },
}

function getFilterList()
    return {
        { label = "ترتيب حسب", type = "select", key = "sort", options = SORT_OPTIONS },
        { label = "الحالة", type = "select", key = "status", options = STATUS_OPTIONS },
        { label = "النوع", type = "select", key = "type", options = TYPE_OPTIONS },
        { label = "سنة الإصدار", type = "select", key = "year", options = YEAR_OPTIONS },
        { label = "الموسم", type = "select", key = "season", options = SEASON_OPTIONS },
        { label = "الاستوديو", type = "select", key = "studio", options = STUDIO_OPTIONS },
        { label = "المصدر", type = "select", key = "source", options = SOURCE_OPTIONS },
        { label = "البلد", type = "select", key = "country", options = COUNTRY_OPTIONS },
        { label = "النسخة", type = "select", key = "version", options = VERSION_OPTIONS },
        { label = "التصنيف", type = "checkbox", key = "genres_included", options = GENRE_OPTIONS },
    }
end

local FILTER_KEYS = {
    "status", "type", "year", "season", "studio",
    "source", "country", "version", "sort",
}

local function buildQuery(filters)
    if type(filters) ~= "table" then return "" end
    local parts = {}
    for _, key in ipairs(FILTER_KEYS) do
        local v = filters[key]
        if type(v) == "string" and v ~= "" then
            parts[#parts + 1] = key .. "=" .. url_encode(v)
        end
    end
    local genres = filters["genres_included"]
    if type(genres) == "table" then
        for _, v in ipairs(genres) do
            if type(v) == "string" and v ~= "" then
                -- сайт читает именно genres[]=value
                parts[#parts + 1] = "genres%5B%5D=" .. url_encode(v)
            end
        end
    end
    return table.concat(parts, "&")
end

function getCatalogFiltered(index, filters)
    return fetchList(browseUrl(index + 1, buildQuery(filters)))
end

-- ============ Карточка тайтла ============

local _detailCache = {}

local function fetchDetail(bookUrl)
    local cached = _detailCache[bookUrl]
    if cached then return cached end
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local detail = { body = r.body }
    _detailCache[bookUrl] = detail
    return detail
end

-- Первый блок JSON-LD — TVSeries, второй — BreadcrumbList (его не берём).
local function jsonLd(detail)
    if detail.jsonld == nil then
        local raw = detail.body:match(
            '<script[^>]-application/ld%+json[^>]*>(.-)</script>')
        local data = raw and json_parse(raw) or nil
        if type(data) ~= "table" or data["@type"] ~= "TVSeries" then data = nil end
        detail.jsonld = data or false
    end
    return detail.jsonld or nil
end

local function badgeRow(body)
    return html_select_first(body, "div.mb-4.flex.flex-wrap.items-center.gap-2")
end

-- Рейтинг живёт в третьем бейдже рядом с рейтинговой звёздочкой: "6.80".
local function ratingValue(body)
    local row = badgeRow(body)
    if not row then return nil end
    for _, span in ipairs(html_select(row.html, "span")) do
        local t = string_clean(span.text)
        if t:match("^%d+%.%d+$") then return t end
    end
    return nil
end

function getBookTitle(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local j = jsonLd(d)
    local title = j and string_clean(j.name or "") or ""
    if title == "" then return nil end
    return title
end

function getBookCoverImageUrl(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local img = html_select_first(d.body, "img[src*='/posters/']")
    local cover = img and absUrl(img.src) or ""
    if cover == "" then return nil end
    return cover
end

function getBookDescription(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local j = jsonLd(d)
    local text = j and string_trim(j.description or "") or ""
    if text == "" then return nil end
    return text
end

function getBookGenres(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return {} end
    local j = jsonLd(d)
    local genres = {}
    local list = j and j.genre
    if type(list) == "table" then
        for _, g in ipairs(list) do
            local t = string_clean(g)
            if t ~= "" then genres[#genres + 1] = t end
        end
    end
    return genres
end

-- Рейтинг на сайте дан по шкале 10 — отдаём в формате "6.80/10".
function getBookRating(bookUrl)
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local r = ratingValue(d.body)
    if not r then return nil end
    return r .. "/10"
end

-- ============ Серии ============

function getChapterList(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return {} end
    local items, index = {}, {}
    for _, el in ipairs(html_select(r.body, "a[href*='/watch/']")) do
        local url = absUrl(el.href)
        if url ~= "" then
            local title = string_clean(el.text)
            local i = index[url]
            if not i then
                index[url] = #items + 1
                items[#items + 1] = { title = title, url = url }
            else
                -- «شاهد الآن» и плоский номер серии идут первыми — заменяем
                -- на нормальный заголовок, когда он появляется.
                local stored = items[i].title
                local better = title ~= "" and (stored == ""
                    or (title:find(EPISODE_MARK, 1, true)
                        and not stored:find(EPISODE_MARK, 1, true)))
                if better then items[i].title = title end
            end
        end
    end
    return items
end

-- ============ Байтовые помощники ============

local function bytesToString(t)
    local parts = {}
    for i = 1, #t do parts[i] = string.char(t[i]) end
    return table.concat(parts)
end

-- Крипто-хелперы для резолверов (чистый Lua, без библиотеки bit).
-- Цель — LuaJ (семантика Lua 5.1): только math.floor, string.*, table.*.

local floor = math.floor

-- 32-битные операции над беззнаковыми (0 .. 2^32-1), только арифметика ──

local function xb(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local x, y = a % 16, b % 16
        local n, q = 0, 1
        for _ = 1, 4 do
            local xa, ya = x % 2, y % 2
            if xa ~= ya then n = n + q end
            x, y, q = (x - xa) / 2, (y - ya) / 2, q * 2
        end
        r = r + n * p
        a, b, p = (a - a % 16) / 16, (b - b % 16) / 16, p * 16
    end
    return r
end

local function band(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local x, y = a % 16, b % 16
        local n, q = 0, 1
        for _ = 1, 4 do
            local xa, ya = x % 2, y % 2
            if xa == 1 and ya == 1 then n = n + q end
            x, y, q = (x - xa) / 2, (y - ya) / 2, q * 2
        end
        r = r + n * p
        a, b, p = (a - a % 16) / 16, (b - b % 16) / 16, p * 16
    end
    return r
end

local MOD32 = 4294967296
local MAX32 = 4294967295

local function bnot(a) return MAX32 - a end
local function rshift(a, n) return floor(a / 2 ^ n) end
local function ror(a, n)
    n = n % 32
    if n == 0 then return a end
    return floor(a / 2 ^ n) + (a % 2 ^ n) * 2 ^ (32 - n)
end

-- SHA-256 (FIPS 180-4) ──

local K256 = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function u32be(v)
    return string.char(floor(v / 16777216) % 256, floor(v / 65536) % 256,
                       floor(v / 256) % 256, v % 256)
end

local function sha256(msg)
    local ml = #msg
    local bits = ml * 8
    local padz = (55 - ml) % 64
    local hi = floor(bits / MOD32)
    local lo = bits % MOD32
    local raw = msg .. "\128" .. string.rep("\0", padz) .. u32be(hi) .. u32be(lo)

    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

    local w = {}
    for off = 1, #raw, 64 do
        for i = 0, 15 do
            local p = off + i * 4
            w[i + 1] = floor(raw:byte(p) * 16777216) + raw:byte(p + 1) * 65536
                     + raw:byte(p + 2) * 256 + raw:byte(p + 3)
        end
        for i = 17, 64 do
            local a15, a2 = w[i - 15], w[i - 2]
            local s0 = xb(xb(ror(a15, 7), ror(a15, 18)), rshift(a15, 3))
            local s1 = xb(xb(ror(a2, 17), ror(a2, 19)), rshift(a2, 10))
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD32
        end

        local a, b, c, d, e, f, g, hh = h0, h1, h2, h3, h4, h5, h6, h7
        for t = 1, 64 do
            local S1 = xb(xb(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = xb(band(e, f), band(bnot(e), g))
            local temp1 = (hh + S1 + ch + K256[t] + w[t]) % MOD32
            local S0 = xb(xb(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = xb(xb(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) % MOD32
            hh, g, f = g, f, e
            e = (d + temp1) % MOD32
            d, c, b = c, b, a
            a = (temp1 + temp2) % MOD32
        end
        h0 = (h0 + a) % MOD32
        h1 = (h1 + b) % MOD32
        h2 = (h2 + c) % MOD32
        h3 = (h3 + d) % MOD32
        h4 = (h4 + e) % MOD32
        h5 = (h5 + f) % MOD32
        h6 = (h6 + g) % MOD32
        h7 = (h7 + hh) % MOD32
    end

    return u32be(h0) .. u32be(h1) .. u32be(h2) .. u32be(h3)
        .. u32be(h4) .. u32be(h5) .. u32be(h6) .. u32be(h7)
end

-- AES-256 (FIPS 197): S-box по определению, только шифрование ──

local function gmul(a, b)
    local p = 0
    for _ = 1, 8 do
        if b % 2 == 1 then p = xb(p, a) end
        if a >= 128 then a = xb((a * 2) % 256, 0x1b)
        else a = (a * 2) % 256 end
        b = floor(b / 2)
    end
    return p
end

local EXP, LOG = {}, {}
do
    local x = 1
    for i = 0, 254 do
        EXP[i] = x
        LOG[x] = i
        x = gmul(x, 3)
    end
end

local function rol8(v, n)
    return (v * 2 ^ n) % 256 + floor(v / 2 ^ (8 - n))
end

local SBOX = {}
do
    for i = 0, 255 do
        local inv = 0
        if i ~= 0 then inv = EXP[(255 - LOG[i]) % 255] end
        local s = xb(xb(xb(xb(inv, rol8(inv, 1)), rol8(inv, 2)),
                        rol8(inv, 3)), rol8(inv, 4))
        SBOX[i] = xb(s, 0x63)
    end
end

-- слово — массив из 4 байт, w[1] — старший
local function expandKey(key)
    local w = {}
    for i = 1, 8 do
        local p = (i - 1) * 4
        w[i] = { key:byte(p + 1), key:byte(p + 2), key:byte(p + 3), key:byte(p + 4) }
    end
    local rcon = 1
    for i = 9, 60 do
        local temp = { w[i - 1][1], w[i - 1][2], w[i - 1][3], w[i - 1][4] }
        if i % 8 == 1 then
            temp = { temp[2], temp[3], temp[4], temp[1] }
            for j = 1, 4 do temp[j] = SBOX[temp[j]] end
            temp[1] = xb(temp[1], rcon)
            rcon = gmul(rcon, 2)
        elseif i % 8 == 5 then
            for j = 1, 4 do temp[j] = SBOX[temp[j]] end
        end
        local prev = w[i - 8]
        w[i] = {
            xb(prev[1], temp[1]), xb(prev[2], temp[2]),
            xb(prev[3], temp[3]), xb(prev[4], temp[4]),
        }
    end
    return w
end

local function addRoundKey(state, w, round)
    for c = 1, 4 do
        local word = w[(round - 1) * 4 + c]
        for r = 1, 4 do
            state[r][c] = xb(state[r][c], word[r])
        end
    end
end

local function subBytes(state)
    for r = 1, 4 do
        for c = 1, 4 do state[r][c] = SBOX[state[r][c]] end
    end
end

local function shiftRows(state)
    local s = state
    local t = { s[2][1], s[2][2], s[2][3], s[2][4] }
    for c = 1, 4 do s[2][c] = t[(c % 4) + 1] end
    t = { s[3][1], s[3][2], s[3][3], s[3][4] }
    for c = 1, 4 do s[3][c] = t[((c + 1) % 4) + 1] end
    t = { s[4][1], s[4][2], s[4][3], s[4][4] }
    for c = 1, 4 do s[4][c] = t[((c + 2) % 4) + 1] end
end

local function mixColumns(state)
    for c = 1, 4 do
        local a1, a2, a3, a4 = state[1][c], state[2][c], state[3][c], state[4][c]
        state[1][c] = xb(xb(gmul(a1, 2), gmul(a2, 3)), xb(a3, a4))
        state[2][c] = xb(xb(a1, gmul(a2, 2)), xb(gmul(a3, 3), a4))
        state[3][c] = xb(xb(a1, a2), xb(gmul(a3, 2), gmul(a4, 3)))
        state[4][c] = xb(xb(gmul(a1, 3), a2), xb(a3, gmul(a4, 2)))
    end
end

local function aes256EncryptBlock(w, block)
    local state = { {}, {}, {}, {} }
    for c = 1, 4 do
        for r = 1, 4 do state[r][c] = block[(c - 1) * 4 + r] end
    end
    addRoundKey(state, w, 1)
    for round = 2, 14 do
        subBytes(state)
        shiftRows(state)
        mixColumns(state)
        addRoundKey(state, w, round)
    end
    subBytes(state)
    shiftRows(state)
    addRoundKey(state, w, 15)
    local out = {}
    for c = 1, 4 do
        for r = 1, 4 do out[(c - 1) * 4 + r] = state[r][c] end
    end
    return out
end

-- AES-GCM (NIST SP 800-38D), IV 96 бит, тег 128 бит ──

local RPOLY = { 0xE1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

local function b16zero() return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } end

local function b16xor(a, b)
    local r = {}
    for i = 1, 16 do r[i] = xb(a[i], b[i]) end
    return r
end

local function b16copy(a)
    local r = {}
    for i = 1, 16 do r[i] = a[i] end
    return r
end

local function getBit(bytes, i)           -- i = 0 .. 127, порядок бит — от старшего
    local byte = bytes[floor(i / 8) + 1]
    return floor(byte / 2 ^ (7 - (i % 8))) % 2
end

local function ghashMul(x, y)
    local z = b16zero()
    local v = b16copy(y)
    for i = 0, 127 do
        if getBit(x, i) == 1 then z = b16xor(z, v) end
        local lsb = v[16] % 2
        for j = 16, 2, -1 do
            v[j] = floor(v[j] / 2) + (v[j - 1] % 2) * 128
        end
        v[1] = floor(v[1] / 2)
        if lsb == 1 then v = b16xor(v, RPOLY) end
    end
    return z
end

local function ctrStep(w, counter)
    local e = aes256EncryptBlock(w, counter)
    -- инкремент счётчика (последние 4 байта, big-endian, mod 2^32)
    local n = 16
    counter[n] = counter[n] + 1
    while n > 12 and counter[n] > 255 do
        counter[n] = 0
        n = n - 1
        counter[n] = counter[n] + 1
    end
    return e
end

-- raw = iv(12) || tag(16) || шифротекст; key — 32 сырых байта.
-- Возвращает расшифрованный текст либо nil, если проверка тега не прошла.
local function aesGcmDecrypt(key, raw)
    if type(key) ~= "string" or #key ~= 32 then return nil end
    if type(raw) == "table" then raw = bytesToString(raw) end
    if type(raw) ~= "string" or #raw < 28 then return nil end
    local iv = { raw:byte(1, 12) }
    local tag = { raw:byte(13, 28) }
    local ct = { raw:byte(29, #raw) }

    local w = expandKey(key)
    local h = aes256EncryptBlock(w, b16zero())

    -- J0 = iv || 0^31 || 1
    local j0 = { iv[1], iv[2], iv[3], iv[4], iv[5], iv[6], iv[7], iv[8],
                 iv[9], iv[10], iv[11], iv[12], 0, 0, 0, 1 }

    -- счётчик стартует с inc32(J0)
    local counter = b16copy(j0)
    counter[16] = 2

    local out = {}
    local e = nil
    for i = 1, #ct do
        local pos = (i - 1) % 16
        if pos == 0 then e = ctrStep(w, counter) end
        out[i] = xb(ct[i], e[pos + 1])
    end
    local parts = {}
    for i = 1, #out do parts[i] = string.char(out[i]) end
    local pt = table.concat(parts)

    -- GHASH по шифротексту и двум 64-битным длинам
    local y = b16zero()
    local full = math.floor(#ct / 16)
    for b = 1, full do
        local blk = {}
        for i = 1, 16 do blk[i] = ct[(b - 1) * 16 + i] end
        y = ghashMul(b16xor(y, blk), h)
    end
    local rest = #ct % 16
    if rest > 0 then
        local blk = b16zero()
        for i = 1, rest do blk[i] = ct[full * 16 + i] end
        y = ghashMul(b16xor(y, blk), h)
    end
    local lens = {}
    local alen, clen = 0, #ct * 8  -- длины в GCM задаются в битах
    for i = 8, 1, -1 do
        lens[i] = alen % 256
        alen = floor(alen / 256)
    end
    for i = 16, 9, -1 do
        lens[i] = clen % 256
        clen = floor(clen / 256)
    end
    y = ghashMul(b16xor(y, lens), h)

    local s = aes256EncryptBlock(w, j0)
    local calc = {}
    for i = 1, 16 do calc[i] = xb(y[i], s[i]) end
    for i = 1, 16 do
        if calc[i] ~= tag[i] then return nil end
    end
    return pt
end

-- Экспорт ──

local cryptoSha256 = sha256
local cryptoAesGcmDecrypt = aesGcmDecrypt


-- base64 → таблица байтов: стандартный base64_decode движка отдаёт строку,
-- декодированную как UTF-8, а AES-GCM и RC4 требуют сырые байты.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function base64Bytes(s)
    s = (s or ""):gsub("%s+", "")
    local out, buf, bits = {}, 0, 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch == "=" then break end
        local v = B64_INDEX[ch]
        if v ~= nil then
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = math.floor(buf / 2 ^ bits) % 256
                buf = buf % 2 ^ bits
            end
        end
    end
    return out
end

local function rc4(key, data)
    local S, j = {}, 0
    for i = 0, 255 do S[i] = i end
    for i = 0, 255 do
        j = (j + S[i] + key:byte((i % #key) + 1)) % 256
        S[i], S[j] = S[j], S[i]
    end
    local a, b = 0, 0
    local out = {}
    for n = 1, #data do
        a = (a + 1) % 256
        b = (b + S[a]) % 256
        S[a], S[b] = S[b], S[a]
        out[n] = xb(data[n], S[(S[a] + S[b]) % 256])
    end
    return out
end

-- ============ Резолверы ============

-- Хосты, где чистый HTTP не даёт прямую ссылку (перемерено 2026-10-05).
-- drive.google, mail.ru, hgcloud и dood/playmogo из списка убраны: для них
-- есть резолверы ниже (usercontent-ссылка Drive, embed → metadataUrl → mp4 у
-- Mail.ru, ручной разбор packed-конфига hgcloud, /pass_md5-схема dood).
local SKIP_HOSTS = {
    { sub = "mega.nz",      reason = "поток зашифрован AES-CTR и отдаётся чанками с Range — в движке нет крипто и частичных запросов" },
    { sub = "docs.google",  reason = "Google Docs: превью на JS" },
    -- dsvplay — зеркало DoodStream: dood/playmogo раскрыты resolveDood ниже
    -- (CF обходит движок), но у этого домена не поднимается TLS.
    { sub = "dsvplay",      reason = "TLS-хендшейк не проходит (curl rc=35) — проверено и с браузерным UA (живьём 2026-10-07)" },
}

-- Причина пропуска хоста либо nil. Общая для resolveEntry и для
-- resolveHostedLink: хост может прийти и после расшифровки yonaplay, и из
-- списка /mirror — в обеих ветках сеть должна остановиться до похода в неё.
local function skipReason(link)
    local low = string_lower(link)
    for _, skip in ipairs(SKIP_HOSTS) do
        if low:find(skip.sub, 1, true) then return skip.reason end
    end
    return nil
end

local function qualityOf(entry)
    if entry.label == "" then return entry.tier end
    if entry.tier == "" then return entry.label end
    return entry.tier .. " · " .. entry.label
end

-- Явные .mp4/.m3u8 в разметке плеера (mp4upload, 4shared, soraplay и прочие).
local function directLinks(body)
    local out, seen = {}, {}
    for u0 in body:gmatch([[https?://[^"'%s<>]+]]) do
        local u = u0:gsub("&amp;", "&"):gsub("[,%);%]]+$", ""):gsub("\\+$", "")
        local base = u:match("^[^%?#]*") or u
        if not seen[u] and (base:match("%.mp4$") or base:match("%.m3u8$")) then
            seen[u] = true
            out[#out + 1] = u
        end
    end
    return out
end

local function sourceOf(episodeUrl, url, quality, referer)
    return { url = url, quality = quality, headers = { ["Referer"] = referer or episodeUrl } }
end

-- ---- dood / playmogo: embed → /pass_md5 → префикс + 10 random + token/expiry ----
-- Схема (референс DoodExtractor; код docs/hoster-implementations.md): в embed
-- есть путь /pass_md5/<...>, его тело — начало финального URL; к нему
-- дописываются 10 случайных символов и "?token=<последний сегмент>&expiry=".
-- expiry = Date.now() в МИЛЛИСЕКУНДАХ — проверено по inline-коду плеера
-- playmogo.com/e/yx3yl4w4y9br (живьём 2026-10-07), os_time() в NoveLA тоже
-- возвращает миллисекунды. Финал — mp4 на cloudatacdn.com; Referer финального
-- потока = origin embed (без него CDN отвечает 302). Капча-вариант embed
-- отдаёт без /pass_md5 — тогда ветка отдаёт отказ.
local RANDOM_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function resolveDood(episodeUrl, link, entry)
    local page = http_get(link, {
        headers = { ["Referer"] = episodeUrl }, timeout = 8000,
    })
    if not page.success or type(page.body) ~= "string" then
        log_error("WitAnime: " .. entry.label .. " — dood: embed HTTP " .. tostring(page.code))
        return nil
    end
    local md5 = page.body:match("(/pass_md5/[^'\"]+)")
    local origin = link:match("^(https?://[^/]+)")
    if not md5 or not origin then
        log_error("WitAnime: " .. entry.label .. " — dood: в embed нет /pass_md5")
        return nil
    end
    local token = md5:match("([^/]+)$")
    local r = http_get(origin .. md5, {
        headers = { ["Referer"] = link }, timeout = 8000,
    })
    local start = r.success and type(r.body) == "string"
        and r.body:match("^%s*(https?://.-)%s*$") or nil
    if not start then
        local b = type(r.body) == "string" and r.body or ""
        log_error("WitAnime: " .. entry.label .. " — dood: /pass_md5 — "
            .. (b:find("RELOAD", 1, true) and "RELOAD"
                or ("HTTP " .. tostring(r.code))))
        return nil
    end
    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd)
        .. "?token=" .. token .. "&expiry=" .. tostring(os_time())
    return { sourceOf(episodeUrl, url, qualityOf(entry), origin .. "/") }
end

local function resolveGeneric(episodeUrl, link, entry)
    local r = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not r.success then
        log_error("WitAnime: " .. entry.label .. " — HTTP " .. tostring(r.code))
        return nil
    end
    local urls = directLinks(r.body)
    if #urls == 0 then
        log_error("WitAnime: " .. entry.label .. " — нет прямой ссылки (нужен JS)")
        return nil
    end
    local out = {}
    for _, u in ipairs(urls) do
        out[#out + 1] = sourceOf(episodeUrl, u, qualityOf(entry), link)
    end
    return out
end

-- ---- dotplay: эмбед → /api.php?code= → base64-поле video_url ----

local function resolveDotplay(episodeUrl, link, quality)
    local code = link:match("/embed/([^/?#]+)")
    local origin = link:match("^(https?://[^/]+)") or ""
    -- api.php?code= — это API именно dotplay. Чужой хост (в ответе yonaplay
    -- бывает 4shared) отдаёт HTML вместо JSON: запрос заведомо мёртвый,
    -- поэтому не выходим в сеть, а просто логируем и пропускаем.
    if not code or not string_lower(origin):find("dotplay.net", 1, true) then
        log_error("WitAnime: dotplay — не dotplay-ссылка, пропущена: " .. tostring(link))
        return nil
    end
    -- эмбед поднимает куку; сам api.php отвечает и без неё, поэтому
    -- неудача здесь не считается фатальной
    http_get(link, { headers = { ["Referer"] = "https://mid.yonaplay.net/" } })

    local api = origin .. "/api.php?code=" .. url_encode(code)
    local r = http_get(api, {
        headers = {
            ["Accept"]  = "application/json",
            ["Referer"] = link,
        },
    })
    if not r.success then
        log_error("WitAnime: dotplay — HTTP " .. tostring(r.code))
        return nil
    end
    local data = json_parse(r.body)
    local url = data and data.video_url and base64Bytes(data.video_url)
    if not url or #url == 0 then
        log_error("WitAnime: dotplay — пустой video_url")
        return nil
    end
    -- значимая часть до '|' (там подпись-время)
    local raw = bytesToString(url):match("^([^|]+)") or ""
    if raw == "" then return nil end
    return { sourceOf(episodeUrl, raw, quality, link) }
end

-- ---- yonaplay: эмбед → init-session → sources → api.php → AES-256-GCM ----

local function yonaplayPost(origin, path, referer, payload)
    return http_post(origin .. path, payload, {
        headers = {
            ["Content-Type"]      = "application/json",
            ["Accept"]            = "application/json",
            ["X-Requested-With"]  = "XMLHttpRequest",
            ["Referer"]           = referer,
            ["Origin"]            = origin,
        },
    })
end

local YTIER_RANK = { fhd = 1, hd = 2, sd = 3 }

local function pickServerToken(qualities, wantTier)
    if type(qualities) ~= "table" then return nil end
    local best, bestRank = nil, 100
    local prefer = wantTier ~= "" and string_lower(wantTier) or nil
    for name, tier in pairs(qualities) do
        -- Регистр ключей ответа не нормализован: /sources отдаёт ярусы как
        -- TIER_ORDER (FHD/HD/SD), а YTIER_RANK и prefer — строчные, поэтому
        -- сравниваем всё в нижнем регистре (иначе ранг никогда не совпадёт).
        local key = type(name) == "string" and string_lower(name) or ""
        local rank = YTIER_RANK[key] or 4
        if prefer and key == prefer then rank = 0 end
        local servers = type(tier) == "table" and tier.servers or nil
        local first = type(servers) == "table" and servers[1] or nil
        local token = type(first) == "table" and first.token or nil
        if type(token) == "string" and token ~= "" and rank < bestRank then
            best, bestRank = token, rank
        end
    end
    return best
end

-- объявление раньше всех резолверов: resolveYonaplay отдаёт сюда
-- расшифрованную ссылку, а определение — ниже, после resolveDropbox
local resolveHostedLink

local function resolveYonaplay(episodeUrl, link, entry)
    local origin = link:match("^(https?://[^/]+)") or link

    -- 1) эмбед: кука em_embed и база API (window._E={a:"/api"})
    local page = http_get(link, { headers = { ["Referer"] = baseUrl } })
    if not page.success then
        log_error("WitAnime: yonaplay — эмбед HTTP " .. tostring(page.code))
        return nil
    end
    local apiPath = page.body:match('window%._E%s*=%s*{%s*a%s*:%s*"([^"]+)"')
        or page.body:match("window%._E%s*=%s*{%s*a%s*:%s*'([^']+)'")
        or "/api"
    local api = origin .. apiPath

    -- 2) init-session → {success, c, t, k}; k — ключ шифрования
    local init = json_parse(yonaplayPost(api, "/init-session.php", link, "{}").body)
    local code = init and init.c
    local key = init and init.k
    if type(code) ~= "string" or type(key) ~= "string" then
        log_error("WitAnime: yonaplay — init-session не вернул ключ")
        return nil
    end

    -- 3) sources → токен конкретного сервера (именно его ждёт api.php)
    local src = json_parse(yonaplayPost(api, "/sources.php", link,
        json_stringify({ code = code })).body)
    local token = src and pickServerToken(src.qualities, entry.tier)
    if not token then
        log_error("WitAnime: yonaplay — нет токена сервера")
        return nil
    end

    -- 4) api.php → {d: base64(iv || tag || ciphertext)}
    local resp = json_parse(yonaplayPost(api, "/api.php", link, json_stringify({
        code = code, token = token, key = key,
    })).body)
    local payload = resp and resp.d and base64Bytes(resp.d)
    if not payload or #payload < 28 then
        log_error("WitAnime: yonaplay — пустой ответ api.php")
        return nil
    end

    -- 5) AES-256-GCM c ключом SHA-256(k) → ссылка хостера
    -- Хост НЕ заранее известен: помимо dotplay встречается 4shared и другие,
    -- поэтому дальше общий диспетчер по хосту, а не жёсткий resolveDotplay.
    local plain = cryptoAesGcmDecrypt(cryptoSha256(key), payload)
    if type(plain) ~= "string" or plain == "" then
        log_error("WitAnime: yonaplay — расшифровка не удалась")
        return nil
    end
    return resolveHostedLink(episodeUrl, plain, entry)
end

-- ---- videa: обфускация _xt → XML (часто RC4 + base64) → ссылки с md5 ----

local VIDEA_O = "xHb0ZvME5q8CBcoQi6AngerDu3FGO9fkUlwPmLVY_RTzj2hJIS4NasXWKy1td7p"
local VIDEA_R = { "e", "a", "g", "j", "d", "c", "h", "i", "b", "f" }
local VIDEA_RR = { "f", "h", "c", "b", "i" }

local function videaToken(xt)
    local c = {}
    for i = 1, #xt do
        local i0 = i - 1
        local k = VIDEA_R[math.floor(i0 / 8) + 2]
        if not k then return nil end
        if i0 % 8 == 0 then c[k] = "" end
        c[k] = (c[k] or "") .. xt:sub(i, i)
    end
    local d = (c.a or "") .. (c.g or "") .. (c.j or "") .. (c.d or "")
    local u = (c.c or "") .. (c.h or "") .. (c.i or "") .. (c.b or "")
    -- обе половинки обязаны быть собраны целиком, иначе токен неверный
    if d == "" or u == "" then return nil end
    local m = {}
    for i = 1, #d do
        local oi = VIDEA_O:find(d:sub(i, i), 1, true)
        if not oi then return nil end
        -- oi — 1-based, а в эталонной формуле индексация с 0: i - (oi0 - 31) + 1
        local at = i - (oi - 32)
        if at < 1 or at > #u then return nil end
        m[i] = u:sub(at, at)
    end
    local mm = table.concat(m)
    c = {}
    for i = 1, #mm do
        local i0 = i - 1
        local k = VIDEA_RR[math.floor(i0 / 8) + 2]
        if k then
            if i0 % 8 == 0 then c[k] = "" end
            c[k] = (c[k] or "") .. mm:sub(i, i)
        end
    end
    c.f = ""
    return {
        t = (c.h or "") .. (c.c or ""),
        k = (c.b or "") .. (c.i or ""),
    }
end

local function videaRandom8()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local out = {}
    for i = 1, 8 do
        local n = math.random(#chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

local function resolveVidea(episodeUrl, link, entry)
    local vcode = link:match("[?&]v=([%w]+)")
    if not vcode then return nil end

    local page = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not page.success then
        log_error("WitAnime: videa — HTTP " .. tostring(page.code))
        return nil
    end
    local xt = page.body:match('_xt%s*=%s*"([^"]+)"')
        or page.body:match("_xt%s*=%s*'([^']+)'")
    if not xt then
        log_error("WitAnime: videa — не найден _xt")
        return nil
    end

    local parts = videaToken(xt)
    if not parts then
        log_error("WitAnime: videa — не удалось разобрать _xt")
        return nil
    end

    local rnd = videaRandom8()
    local xmlUrl = "https://videa.hu/player/xml"
        .. "?v=" .. url_encode(vcode)
        .. "&_t=" .. url_encode(parts.t)
        .. "&_s=" .. url_encode(rnd)
        .. "&platform=desktop&lang=en&start=0"
    local r = http_get(xmlUrl, { headers = { ["Referer"] = link } })
    if not r.success then
        log_error("WitAnime: videa — XML HTTP " .. tostring(r.code))
        return nil
    end

    local contentType = headerValue(r.headers, "content-type") or ""
    local xml
    if string_starts_with(contentType, "text/xml") then
        xml = r.body
    else
        local xs = headerValue(r.headers, "x-videa-xs") or ""
        xml = bytesToString(rc4(parts.k .. rnd .. xs, base64Bytes(r.body)))
    end

    local err = xml:match("<error[^>]*>([^<]*)</error>")
    if err then
        log_error("WitAnime: videa — " .. err)
        return nil
    end

    local exp = xml:match('<video_sources[^>]*exp="(%d+)"')
        or xml:match('<video_source[^>]*exp="(%d+)"')
    if not exp then
        log_error("WitAnime: videa — в XML нет exp")
        return nil
    end

    local hashes = {}
    for name, h in xml:gmatch("<hash_value_([^>]+)>([^<]+)</hash_value_") do
        hashes[name] = h
    end

    local out = {}
    for name, path in xml:gmatch('<video_source name="([^"]+)"[^>]*>([^<]+)</video_source>') do
        local md5 = hashes[name]
        if md5 then
            out[#out + 1] = sourceOf(episodeUrl,
                "https:" .. path .. "?md5=" .. md5 .. "&expires=" .. exp,
                name, "https://videa.hu/")
        end
    end
    if #out == 0 then log_error("WitAnime: videa — в XML нет источников") end
    return #out > 0 and out or nil
end

-- ---- videas: эмбед app.videas.fr → прямой HLS (не путать с videa.hu) ----
-- videa.hu (выше) живёт на своём домене и раскрывается через RC4/XML,
-- у videas гейт отдаёт app.videas.fr/embed/media/<uuid>/: разметка листинга
-- чужая, в ней сразу лежит CDN-плейлист — в preload-теге и в JSON data-embed.
local function resolveVideas(episodeUrl, link, entry)
    local page = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not page.success then
        log_error("WitAnime: videas — эмбед HTTP " .. tostring(page.code))
        return nil
    end
    -- <link rel="preload" href="…/playlist.m3u8" as="fetch"> — надёжнее всего
    local url = page.body:match('<link[^>]+rel="preload"[^>]+href="([^"]+)"')
        or page.body:match('"src"%s*:%s*"(https?://[^"]+%.m3u8[^"]*)"')
    if not url then
        -- запасной путь: общий скан на прямые .mp4/.m3u8 в разметке
        local urls = directLinks(page.body)
        if #urls == 0 then
            log_error("WitAnime: videas — в эмбеде нет прямой ссылки")
            return nil
        end
        local out = {}
        for _, u in ipairs(urls) do
            out[#out + 1] = sourceOf(episodeUrl, u, qualityOf(entry), link)
        end
        return out
    end
    return { sourceOf(episodeUrl, url, qualityOf(entry), link) }
end

-- ---- ok.ru: data-options → flashvars.metadata ----

local function resolveOkRu(episodeUrl, link, entry)
    local r = http_get(link, { headers = { ["Referer"] = "https://ok.ru/" } })
    if not r.success then
        log_error("WitAnime: ok.ru — HTTP " .. tostring(r.code))
        return nil
    end
    local opts = r.body:match('data%-options="([^"]+)"')
    if not opts then
        log_error("WitAnime: ok.ru — нет data-options")
        return nil
    end
    opts = opts:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<")
        :gsub("&gt;", ">"):gsub("&amp;", "&")
    local data = json_parse(opts)
    local meta = data and data.flashvars and data.flashvars.metadata
    if type(meta) == "string" then meta = json_parse(meta) end
    if type(meta) ~= "table" then
        log_error("WitAnime: ok.ru — нет metadata")
        return nil
    end

    local out = {}
    if type(meta.hlsManifestUrl) == "string" and meta.hlsManifestUrl ~= "" then
        out[#out + 1] = sourceOf(episodeUrl, meta.hlsManifestUrl, "HLS", "https://ok.ru/")
    end
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            if type(u) == "string" and u ~= "" then
                local q = type(v.name) == "string" and v.name or qualityOf(entry)
                out[#out + 1] = sourceOf(episodeUrl, u, q, "https://ok.ru/")
            end
        end
    end
    if #out == 0 then log_error("WitAnime: ok.ru — пустая metadata") end
    return #out > 0 and out or nil
end

-- ---- dropbox: прямая ссылка редиректами до файлового CDN ----

local function resolveDropbox(episodeUrl, link, entry)
    local current = link
    for _ = 1, 5 do
        local r = http_get(current, {
            binary          = true,
            followRedirects = false,
            headers         = { ["Referer"] = episodeUrl },
        })
        -- 3xx у binary-ответа приходит с success = false, смотрим на код
        if r.code >= 400 then
            log_error("WitAnime: dropbox — HTTP " .. tostring(r.code))
            return nil
        end
        local loc = headerValue(r.headers, "location")
        if not loc then break end
        current = absUrl(loc)
    end
    return { sourceOf(episodeUrl, current, qualityOf(entry)) }
end

-- ---- soraplay: эмбед → sources:[{"file":…,"label":…}] (SoraPlayExtractor.kt) ----

local function resolveSoraplay(episodeUrl, link, entry)
    local r = http_get(link, { headers = { ["Referer"] = "https://yonaplay.org/" } })
    if not r.success then
        log_error("WitAnime: soraplay — HTTP " .. tostring(r.code))
        return nil
    end
    -- Список плееров разбираем одинаково для soraplay-/mirror и для страниц
    -- yonaplay — обе в референсе уходят в extractFromMulti (.OD li →
    -- go_to_player → снова диспетчер).
    local low = string_lower(link)
    if low:find("/mirror", 1, true) or low:find("yonaplay", 1, true) then
        local out = {}
        for u in r.body:gmatch("go_to_player%('([^']*)'%)") do
            local target = u
            if target ~= "" then
                if not string_starts_with(target, "https:") then
                    target = "https:" .. target
                end
                local res = resolveHostedLink(episodeUrl, target, entry)
                if type(res) == "table" then
                    for _, s in ipairs(res) do out[#out + 1] = s end
                end
            end
        end
        if #out == 0 then log_error("WitAnime: список плееров — нет go_to_player") end
        return #out > 0 and out or nil
    end
    local p = r.body:find("sources: [", 1, true)
    local rest = p and r.body:sub(p + 10) or nil
    local data = rest and (rest:match("^(.-)%],") or rest) or nil
    if not data then
        log_error("WitAnime: soraplay — в embed нет sources[]")
        return nil
    end
    local out = {}
    -- Референс режет по `"file":"` (у vidbom ключ без кавычек — см. ниже).
    for src, label in data:gmatch('"file":"([^"]+)".-"label":"([^"]*)"') do
        out[#out + 1] = sourceOf(episodeUrl, src, "Soraplay: " .. label,
            "https://yonaplay.org/")
    end
    if #out == 0 then log_error("WitAnime: soraplay — в sources[] нет файлов") end
    return #out > 0 and out or nil
end

-- ---- vidbom: embed → sources:[{file:"…",label:"…"}] (VidBomExtractor.kt) ----

local function resolveVidbom(episodeUrl, link)
    local r = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not r.success then
        log_error("WitAnime: vidbom — HTTP " .. tostring(r.code))
        return nil
    end
    local p = r.body:find("sources: [", 1, true)
    local rest = p and r.body:sub(p + 10) or nil
    local data = rest and (rest:match("^(.-)%],") or rest) or nil
    if not data then
        log_error("WitAnime: vidbom — в embed нет sources[]")
        return nil
    end
    local out = {}
    for src, label in data:gmatch('file:"([^"]+)".-label:"([^"]*)"') do
        -- Референс: "Vidbom: " + label, длиннее 15 символов → "Vidshare: 480p".
        local quality = "Vidbom: " .. label
        if #quality > 15 then quality = "Vidshare: 480p" end
        out[#out + 1] = sourceOf(episodeUrl, src, quality, link)
    end
    if #out == 0 then log_error("WitAnime: vidbom — в sources[] нет файлов") end
    return #out > 0 and out or nil
end

-- ---- dailymotion: страница → metadata → master m3u8 → варианты ----
-- Порт DailymotionExtractor.kt. Ветка password_protected (GraphQL-токен из
-- client_id/secret эмбеда) не портирована — она логируется и пропускается.

local DAILYMOTION_URL = "https://www.dailymotion.com"

-- headersBuilder() референса: Accept */*, Referer и Origin на dailymotion.
local function dmHeaders()
    return {
        ["Accept"]  = "*/*",
        ["Referer"] = DAILYMOTION_URL .. "/",
        ["Origin"]  = DAILYMOTION_URL,
    }
end

-- Имя варианта: референс даёт "<высота>p (<разрешение>)" (stnQuality —
-- округление высоты до стандартных — косметика, опущена), иначе само
-- разрешение, иначе "Video".
local function dailymotionLabel(res)
    if not res then return "Video" end
    local h = res:match("[xX](%d+)")
    if h then return h .. "p (" .. res .. ")" end
    return res
end

local function resolveDailymotion(link)
    -- 1) страница видео → dmInternalData {ts, v1st}
    local page = http_get(link)
    if not page.success then
        log_error("WitAnime: dailymotion — HTTP " .. tostring(page.code))
        return nil
    end
    local internal = page.body:match('"dmInternalData":(.-)</script>')
    local ts = internal and internal:match('"ts":([^,]+)') or nil
    local v1st = internal and internal:match('"v1st":"([^"]+)"') or nil
    -- id: query-параметр ?video=, иначе последний сегмент пути
    local path = (link:match("^[^?#]*") or ""):gsub("/+$", "")
    local videoId = link:match("[?&]video=([^&#]+)") or path:match("([^/]+)$")
    if not ts or not v1st or not videoId then
        log_error("WitAnime: dailymotion — не найден dmInternalData или id видео")
        return nil
    end

    -- 2) metadata → qualities.auto[0].url (master m3u8) + субтитры
    local metaUrl = DAILYMOTION_URL .. "/player/metadata/video/" .. videoId
        .. "?locale=en-US&dmV1st=" .. v1st .. "&dmTs=" .. ts .. "&is_native_app=0"
    local mr = http_get(metaUrl)
    local meta = mr.success and json_parse(mr.body) or nil
    if type(meta) ~= "table" then
        log_error("WitAnime: dailymotion — metadata HTTP " .. tostring(mr.code))
        return nil
    end
    if type(meta.error) == "table" then
        local kind = type(meta.error.type) == "string" and meta.error.type or "?"
        if kind == "password_protected" then
            log_error("WitAnime: dailymotion — видео под паролем (GraphQL-ветка референса не портирована)")
        else
            log_error("WitAnime: dailymotion — metadata: " .. kind)
        end
        return nil
    end
    local auto = meta.qualities and meta.qualities.auto
    local master = type(auto) == "table" and type(auto[1]) == "table"
        and auto[1].url or nil
    if type(master) ~= "string" or master == "" then
        log_error("WitAnime: dailymotion — в metadata нет qualities.auto")
        return nil
    end

    -- субтитры metadata: data — объект или массив [{label, urls:[…]}]
    local subs = {}
    local subData = meta.subtitles and meta.subtitles.data
    if type(subData) == "table" then
        for _, s in pairs(subData) do
            if type(s) == "table" and type(s.label) == "string"
                and type(s.urls) == "table" and type(s.urls[1]) == "string" then
                subs[#subs + 1] = { url = s.urls[1], label = s.label }
            end
        end
    end

    -- 3) master m3u8 → варианты (порт extractFromHls из PlaylistUtils.kt):
    -- без #EXT-X-STREAM-INF отдаём сам master, аудио-только дорок (все codecs
    -- из mp4a.*) не берём, сортировка по BANDWIDTH как в референсе.
    local pr = http_get(master, { headers = dmHeaders() })
    if not pr.success then
        log_error("WitAnime: dailymotion — master m3u8 HTTP " .. tostring(pr.code))
        return nil
    end
    if not pr.body:find("#EXT-X-STREAM-INF:", 1, true) then
        return { {
            url = master, quality = "Dailymotion - Video",
            headers = dmHeaders(), subtitles = subs,
        } }
    end

    local variants = {}
    for attrs, raw in pr.body:gmatch("#EXT%-%-X%-%-STREAM%-%-INF:([^\n]*)\n([^\n]+)") do
        local audioOnly = false
        local codecs = attrs:match('CODECS="([^"]+)"')
        if codecs and codecs ~= "" then
            audioOnly = true
            for part in codecs:gmatch("[^,]+") do
                if not string_starts_with(part, "mp4a") then
                    audioOnly = false
                    break
                end
            end
        end
        local res = attrs:match("RESOLUTION=([xX%d]+)")
        local bw = tonumber(attrs:match("BANDWIDTH=(%d+)")) or 0
        local u = raw:match("^%s*(.-)%s*$")
        if not audioOnly and u ~= "" then
            -- относительный адрес плейлиста — относительно самого master
            if not string_starts_with(u, "http") then
                if string_starts_with(u, "//") then
                    u = "https:" .. u
                else
                    u = url_resolve(master, u)
                end
            end
            variants[#variants + 1] = { bw = bw, url = u, label = dailymotionLabel(res) }
        end
    end
    if #variants == 0 then
        log_error("WitAnime: dailymotion — в master нет вариантов")
        return nil
    end
    table.sort(variants, function(a, b) return a.bw > b.bw end)

    local out = {}
    for _, v in ipairs(variants) do
        out[#out + 1] = {
            url = v.url, quality = "Dailymotion - " .. v.label,
            headers = dmHeaders(), subtitles = subs,
        }
    end
    return out
end

-- ---- drive.google: usercontent/download (порт из ar/animephoenix.lua) ----
-- Живьём 2026-10-03: usercontent с confirm=t отдаёт 206 без единого заголовка,
-- для файлов >100 МБ хватает confirm=t. Раньше хост был в skip-листе как
-- «JS-превью», хотя прямую ссылку движок отдаёт без JS.
-- ponytail: playback-API-фоллбэк для «download disabled» (403 + UA-биндинг)
-- не делаем — ставим, если на сайте реально встретятся залоченные ссылки.
local function driveDirectUrl(link)
    local host = (link:match("^https?://([^/]+)") or ""):lower()
    host = host:gsub("^www%.", "")
    if host ~= "drive.google.com" and host ~= "drive.usercontent.google.com" then
        return nil
    end
    local id = link:match("/file/d/([%w_-]+)") or link:match("[?&]id=([%w_-]+)")
    if not id then return nil end
    local u = "https://drive.usercontent.google.com/download?id=" .. id
        .. "&export=download&confirm=t"
    local rk = link:match("[?&]resourcekey=([%w_-]+)")
    if rk then u = u .. "&resourcekey=" .. rk end
    return u
end

-- ---- mail.ru: embed → metadataUrl → /+/video/meta/<id> → mp4 ----
-- Живьём 2026-10-05: embed отдаёт "metadataUrl":"//my.mail.ru/+/video/meta/<id>",
-- meta-JSON — videos[].url, mp4 отвечает 206 на Range с Referer'ом эмбеда
-- (cookie video_key из ответа meta для воспроизведения не требуется).
local function resolveMailRu(episodeUrl, link, entry)
    local r = http_get(link, {
        headers = { ["Referer"] = "https://my.mail.ru/" },
        timeout = 10000,
    })
    if not r.success then
        log_error("WitAnime: " .. entry.label .. " — mail.ru: HTTP " .. tostring(r.code))
        return nil
    end
    local metaUrl = r.body:match('metadataUrl":"([^"]+)')
    if not metaUrl then
        log_error("WitAnime: " .. entry.label .. " — mail.ru: в embed нет metadataUrl")
        return nil
    end
    local mr = http_get((metaUrl:gsub("^//", "https://")), {
        headers = {
            ["Referer"] = link,
            ["X-Requested-With"] = "XMLHttpRequest",
        },
        timeout = 10000,
    })
    if not mr.success then
        log_error("WitAnime: " .. entry.label .. " — mail.ru: meta HTTP " .. tostring(mr.code))
        return nil
    end
    local data = json_parse(mr.body)
    local videos = type(data) == "table" and data.videos or nil
    if type(videos) ~= "table" then
        log_error("WitAnime: " .. entry.label .. " — mail.ru: в meta нет videos[]")
        return nil
    end
    local out = {}
    for _, v in ipairs(videos) do
        local u = type(v) == "table" and v.url or nil
        local key = type(v) == "table" and type(v.key) == "string" and v.key or nil
        if type(u) == "string" and u ~= "" then
            local quality = key and ("Mail.ru · " .. key) or qualityOf(entry)
            out[#out + 1] = sourceOf(episodeUrl, u:gsub("^//", "https://"), quality, link)
        end
    end
    if #out == 0 then log_error("WitAnime: " .. entry.label .. " — mail.ru: в videos[] нет ссылок") end
    return #out > 0 and out or nil
end

-- ============ Список потоков серии ============

local function pushSource(list, seen, src)
    if type(src) ~= "table" then return end
    local url = src.url
    if type(url) ~= "string" or url == "" or seen[url] then return end
    seen[url] = true
    list[#list + 1] = src
end

local function gateUrl(token, episodeUrl)
    -- followRedirects=false: гейт отвечает 302 + Location; движок по умолчанию
    -- переходит по редиректу, и хостер-страница приходит вместо Location.
    local r = http_get(baseUrl .. "/watch/stream-gate/" .. token, {
        binary          = true,
        followRedirects = false,
        headers         = { ["Referer"] = episodeUrl },
    })
    -- 302 — это успех: у binary-ответа success считается по 2xx, не глядим на него
    if r.code >= 400 then
        log_error("WitAnime: stream-gate — HTTP " .. tostring(r.code))
        return nil
    end
    local loc = headerValue(r.headers, "location")
    if loc and loc ~= "" then return absUrl(loc) end
    -- Location не пришёл — в теле 302 иногда остаётся строка url='...'
    local body = type(r.body) == "table" and bytesToString(r.body) or r.body
    return (type(body) == "string" and body:match("url='([^']+)'")) or nil
end

-- ---- packed-JS: eval(function(p,a,c,k,e,d){…}('…',62,N,'a|b|c'.split('|'))) ----
-- Словарь символов разворачивается обратно в строку payload. Порт unpack.py
-- из mediaflow-proxy; те же функции в anime4up (проверено живьём 2026-10-05).

local function baseN(tok, radix)
    local v = 0
    for i = 1, #tok do
        local c = tok:byte(i)
        local d
        if c >= 48 and c <= 57 then d = c - 48
        elseif c >= 97 and c <= 122 then d = c - 87
        elseif c >= 65 and c <= 90 then d = c - 29
        else return nil end
        if d >= radix then return nil end
        v = v * radix + d
    end
    return v
end

local function unpackPacked(body)
    if not body:find("p,a,c,k,e,d", 1, true) then return "" end
    local payload, radix, _, syms = body:match("}%('(.-)',(%d+),(%d+),'([^']*)'%.split%('|'%)")
    if not payload then
        payload, radix, _, syms = body:match("%('(.-)',(%d+),(%d+),'([^']*)'%.split%('|'%)")
    end
    if not payload then return "" end
    local b = tonumber(radix)
    if not b or b < 2 then return "" end
    local dict, i = {}, 1
    for tok in (syms .. "|"):gmatch("(.-)|") do
        dict[i] = tok
        i = i + 1
    end
    return (payload:gsub("%w+", function(tok)
        local v = baseN(tok, b)
        local s = v and dict[v + 1] or nil
        if type(s) == "string" and s ~= "" then return s end
        return tok
    end))
end

-- Есть ли медиа-расширение в пути URL (до "?" / "#"): без него media3 гадает
-- по последнему сегменту и ломается на HLS-плейлисте без расширения (.txt).
local function hasMediaExt(u)
    local base = u:match("^[^%?#]*") or u
    return base:match("%.m3u8$") ~= nil or base:match("%.mp4$") ~= nil
end

-- ---- hgcloud: страница /e/<id> → зеркало с packed-конфигом ----
-- Живьём 2026-10-06: HTTP-редиректа на зеркало НЕТ — hgcloud.to/e/<id>
-- отдаёт 452 байта заглушки с <script src="/main.js?v=1.1.9">, и переход на
-- случайное зеркало делает клиентский main.js (домен собирается в рантайме,
-- статически не извлекается) → зеркала перебираем сами, путь эмбеда берём
-- из gate-ссылки. На зеркале лежит packed-конфиг: ссылки в links =
-- {hls2:…, hls3:…}, setup берёт file: links.hls4||links.hls3||links.hls2 —
-- голый file:"…" не матчит, поэтому свой сбор URL.
-- Зеркала ротатора hgcloud.to (main.js, наблюдение 2026-10-06); если
-- перестанут отдавать конфиг — обновить по main.js ротатора.
local HGCLOUD_MIRRORS = { "hanerix.com", "vibuxer.com", "audinifer.com" }

local function hgcloudMediaUrls(body)
    local text = body
    local un = unpackPacked(body)
    if un ~= "" then text = un .. "\n" .. body end
    local out, seen = {}, {}
    local function add(u)
        if seen[u] then return end
        seen[u] = true
        out[#out + 1] = u:gsub("\\/", "/"):gsub("&amp;", "&")
    end
    -- Порядок = приоритет: первый кандидат — master.txt (hls3 из hls4||hls3).
    for u in text:gmatch([[https?://[^"'%s<>\\]+master%.txt[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+master%.m3u8[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.m3u8[^"'%s<>\\]*]]) do add(u) end
    return out
end

local function resolveHgcloud(episodeUrl, link, entry)
    -- Тело, медиа-ссылки из него и код ответа. Таймаут 8 с: запрос идёт
    -- по очереди, максимум оригинал + 3 зеркала.
    local function attempt(url, referer)
        local r = http_get(url, {
            headers = { ["Referer"] = referer },
            timeout = 8000,
        })
        local code = (r and r.code) or -1
        local body = (r and type(r.body) == "string") and r.body or ""
        return hgcloudMediaUrls(body), code, body
    end

    local tried = {}
    local finalRef = link
    local urls, code, body = attempt(link, episodeUrl)
    tried[#tried + 1] = tostring(code) .. " " .. link
    if #urls == 0 then
        -- Вход — заглушка: main.js редиректит на случайное зеркало. Путь
        -- эмбеда (/e/<id>) сохраняем из gate-ссылки, не выдумываем.
        local path = body:find("/main.js", 1, true)
            and link:match("^https?://[^/]+(/[^?#]*)") or nil
        for i = 1, #HGCLOUD_MIRRORS do
            if not path then break end
            local mirror = HGCLOUD_MIRRORS[i]
            local ref = "https://" .. mirror .. "/"
            local murl = "https://" .. mirror .. path
            local mu, mc = attempt(murl, ref)
            tried[#tried + 1] = tostring(mc) .. " " .. murl
            if #mu > 0 then
                urls, finalRef = mu, ref
                break
            end
        end
    end
    if #urls == 0 then
        log_error("WitAnime: " .. entry.label .. " — hgcloud: нет packed-конфига; ответы: "
            .. table.concat(tried, ", "))
        return nil
    end
    -- finalRef = страница, с которой взят конфиг: без неё master.txt и
    -- сегменты отдают 404 (живьём 2026-10-06).
    local out, seen = {}, {}
    for _, u in ipairs(urls) do
        local src = sourceOf(episodeUrl, u, qualityOf(entry), finalRef)
        if not hasMediaExt(u) then src.mime = "hls" end
        pushSource(out, seen, src)
    end
    return out
end

-- Диспетчер по хосту — единая точка для gate-ссылки и для расшифрованного
-- ответа yonaplay-api, где хост заранее неизвестен (dotplay, 4shared, …).
-- Определение ниже resolveDropbox: функция ссылается на все резолверы.
-- Без `local` — это присваивание в ранее объявленную локальную, иначе
-- resolveYonaplay (выше) работал бы с nil.
resolveHostedLink = function(episodeUrl, link, entry)
    -- Пропуск здесь, а не только в resolveEntry: сюда приходят и
    -- расшифрованные yonaplay ссылки, и плееры из /mirror-списка.
    local reason = skipReason(link)
    if reason then
        log_error("WitAnime: " .. entry.label .. " — пропущен: " .. reason)
        return nil
    end
    local base = link:match("^[^%?#]*") or link
    if base:match("%.mp4$") or base:match("%.m3u8$") then
        return { sourceOf(episodeUrl, link, qualityOf(entry)) }
    end
    local low = string_lower(link)
    -- yonaplay первым — как в when-референса; ветка отдаёт список плееров
    -- в resolveSoraplay (общая логика extractFromMulti).
    if low:find("yonaplay", 1, true) then
        return resolveSoraplay(episodeUrl, link, entry)
    end
    if low:find("dotplay.net", 1, true) then
        return resolveDotplay(episodeUrl, link, qualityOf(entry))
    end
    if low:find("soraplay", 1, true) then
        return resolveSoraplay(episodeUrl, link, entry)
    end
    if low:find("videa.hu", 1, true) then
        return resolveVidea(episodeUrl, link, entry)
    end
    if low:find("videas.fr", 1, true) then
        return resolveVideas(episodeUrl, link, entry)
    end
    if low:find("ok.ru", 1, true) then
        return resolveOkRu(episodeUrl, link, entry)
    end
    if low:find("dropbox.com", 1, true) then
        return resolveDropbox(episodeUrl, link, entry)
    end
    if low:find("dailymotion", 1, true) then
        return resolveDailymotion(link)
    end
    -- Google Drive: прямая ссылка собирается из id в URL, сеть не нужна.
    if low:find("drive.google", 1, true) then
        local drive = driveDirectUrl(link)
        if not drive then
            log_error("WitAnime: " .. entry.label .. " — drive.google: не найден id файла")
            return nil
        end
        return { sourceOf(episodeUrl, drive, qualityOf(entry), "https://drive.google.com/") }
    end
    if low:find("mail.ru", 1, true) then
        return resolveMailRu(episodeUrl, link, entry)
    end
    -- hgcloud: страница /e/<id> сама по себе не поток (452-заглушка или
    -- packed-конфиг зеркала) — свой разбор, generic в нём не поможет.
    if low:find("hgcloud", 1, true) then
        return resolveHgcloud(episodeUrl, link, entry)
    end
    -- dood/playmogo: /e/<id> сам по себе не поток — свой разбор pass_md5,
    -- generic в нём бесполезен (в капча-варианте ссылок в HTML нет).
    if low:find("dood", 1, true) or low:find("playmogo", 1, true)
        or low:find("dsvplay", 1, true) then
        return resolveDood(episodeUrl, link, entry)
    end
    -- VIDBOM_REGEX референса ("//v[aie]d[bp][aoe]?m") — в Lua-паттернах
    -- пишется тем же текстом.
    if low:find("//v[aie]d[bp][aoe]?m") then
        return resolveVidbom(episodeUrl, link)
    end
    return resolveGeneric(episodeUrl, link, entry)
end

-- Цепочка на вход батчить нельзя: stream-source — POST (его обязан пройти
-- каждый токен до гейта, иначе 404), а gate требует followRedirects=false
-- ради headers.location — в http_get_batch есть только binary/headers;
-- ответы резолверов вдобавок зависят от результата гейта.
local function resolveEntry(episodeUrl, entry, apiHeaders)
    -- stream-source «выпускает» токен: без него gate отвечает 404
    http_post(baseUrl .. "/watch/stream-source/" .. entry.token, "{}",
        { headers = apiHeaders })

    local link = gateUrl(entry.token, episodeUrl)
    if not link then
        log_error("WitAnime: " .. entry.label .. " — нет ссылки хостера")
        return nil
    end

    local reason = skipReason(link)
    if reason then
        log_error("WitAnime: " .. entry.label .. " — пропущен: " .. reason)
        return nil
    end

    local label = string_lower(entry.label)
    local low = string_lower(link)
    if label == "yonaplay" or low:find("yonaplay", 1, true) then
        return resolveYonaplay(episodeUrl, link, entry)
    end
    return resolveHostedLink(episodeUrl, link, entry)
end

local TIER_ORDER = { "FHD", "HD", "SD" }

function getVideoList(episodeUrl)
    local page = http_get(episodeUrl)
    if not page.success then
        log_error("WitAnime: страница серии — HTTP " .. tostring(page.code))
        return nil
    end
    local csrf = page.body:match('<meta[^>]*name="csrf%-token"[^>]*content="([^"]+)"')
    if not csrf then
        log_error("WitAnime: на странице серии нет csrf-token")
        return nil
    end

    local apiHeaders = {
        ["Content-Type"]     = "application/json",
        ["Accept"]           = "application/json",
        ["X-CSRF-TOKEN"]     = csrf,
        ["X-Requested-With"] = "XMLHttpRequest",
        ["Referer"]          = episodeUrl,
        ["Origin"]           = baseUrl,
    }

    local resp = http_post(episodeUrl .. "/sources", "{}", { headers = apiHeaders })
    local data = resp.success and json_parse(resp.body) or nil
    local players = data and data.players
    if type(players) ~= "table" then
        log_error("WitAnime: /sources не вернул players")
        return nil
    end

    local entries, byLabel = {}, {}
    for _, tier in ipairs(TIER_ORDER) do
        local list = players[tier]
        if type(list) == "table" then
            for _, p in ipairs(list) do
                local label = type(p.label) == "string" and p.label or tier
                local token = type(p.token) == "string" and p.token or ""
                -- один и тот же хостер встречается в нескольких ярусах:
                -- оставляем первый (FHD), он и есть самый качественный
                if token ~= "" and not byLabel[label] then
                    byLabel[label] = true
                    entries[#entries + 1] = { label = label, tier = tier, token = token }
                end
            end
        end
    end

    if #entries == 0 then
        log_error("WitAnime: на странице серии нет ни одного плеера")
        return nil
    end

    local sources, seen = {}, {}
    for _, entry in ipairs(entries) do
        local ok, result = pcall(resolveEntry, episodeUrl, entry, apiHeaders)
        if not ok then
            log_error("WitAnime: " .. entry.label .. ": " .. tostring(result))
        elseif type(result) == "table" then
            for _, s in ipairs(result) do pushSource(sources, seen, s) end
        end
    end
    if #sources == 0 then return nil end
    return sources
end
