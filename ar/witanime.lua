-- WitAnime — видео-плагин NoveLA (content_type = "video")
-- Сайт: https://witanime.site — каталог аниме с плеером и списком хостов.

content_type = "video"
id           = "witanime"
name         = "WitAnime"
version      = "1.1.0"
baseUrl      = "https://witanime.site"
language     = "ar"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/witanime.png"

local EPISODE_MARK = "الحلقة" -- арабская метка «серия» в заголовках эпизодов

local string_lower = string.lower

-- ============ Guard: engine-API + общие либы (новые сборки NoveLA) ============
-- Top-level обязан загрузиться без require_lib (иначе плагин молча исчезает из
-- списка источников) — pcall-tryLib-паттерн latanime (M9): ошибка сохраняется
-- в libErr и докладывается в ensureEngine.
local libErr = nil
local HAS_LIBS = type(require_lib) == "function"

local function tryLib(name)
    if not HAS_LIBS then return nil end
    local ok, res = pcall(require_lib, name)
    if not ok then libErr = tostring(res) return nil end
    return res
end

local URLS = tryLib("urls")
local HLS = tryLib("hls")
local OKRU = tryLib("okru")
local DM = tryLib("dailymotion")
local DOOD = tryLib("dood")
local VIDEA = tryLib("videa")
local VIDBOM = tryLib("vidbom")
local MAILRU = tryLib("mailru")
local HGCLOUD = tryLib("hgcloud")
local SORAPLAY = tryLib("soraplay")
local DOTPLAY = tryLib("dotplay")
local DROPBOX = tryLib("dropbox")
local VIDEAS = tryLib("videas")

-- Канон (гайд «Паттерн guard»): проверяем только реально используемые API.
-- На старых сборках show_error + error рвут вызов и просят обновить приложение;
-- show_error в проде асинхронный, поэтому после него идёт error(..., 0).
local function ensureEngine()
    local missing = {}
    if rawget(_G, "sha256") == nil then missing[#missing + 1] = "sha256" end
    if rawget(_G, "aes_gcm_decrypt") == nil then missing[#missing + 1] = "aes_gcm_decrypt" end
    if rawget(_G, "rc4") == nil then missing[#missing + 1] = "rc4" end
    if rawget(_G, "base64_decode_bytes") == nil then missing[#missing + 1] = "base64_decode_bytes" end
    if rawget(_G, "unpack_packed") == nil then missing[#missing + 1] = "unpack_packed" end
    if #missing > 0 then
        show_error("NoveLA update required",
            "This plugin needs new functions (" .. table.concat(missing, ", ") ..
            "). Update the app to the latest version.")
        error("A newer version of the app is required: " .. table.concat(missing, ","), 0)
    end
    if not HAS_LIBS then
        show_error("NoveLA update required",
            "This plugin needs shared libraries (require_lib). Update the app to the latest version.")
        error("A newer version of the app is required: require_lib", 0)
    end
    if not URLS or not HLS or not OKRU or not DM or not DOOD
        or not VIDEA or not VIDBOM or not MAILRU or not HGCLOUD
        or not SORAPLAY or not DOTPLAY or not DROPBOX or not VIDEAS then
        show_error("Libraries not loaded",
            "Open the extensions screen and tap update, then restart the app. " .. (libErr or ""))
        error("Shared libraries not loaded", 0)
    end
end

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
    ensureEngine()
    return fetchList(browseUrl(index + 1))
end

function getCatalogSearch(index, query)
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
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
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local j = jsonLd(d)
    local title = j and string_clean(j.name or "") or ""
    if title == "" then return nil end
    return title
end

function getBookCoverImageUrl(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local img = html_select_first(d.body, "img[src*='/posters/']")
    local cover = img and absUrl(img.src) or ""
    if cover == "" then return nil end
    return cover
end

function getBookDescription(bookUrl)
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local j = jsonLd(d)
    local text = j and string_trim(j.description or "") or ""
    if text == "" then return nil end
    return text
end

function getBookGenres(bookUrl)
    ensureEngine()
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
    ensureEngine()
    local d = fetchDetail(bookUrl)
    if not d then return nil end
    local r = ratingValue(d.body)
    if not r then return nil end
    return r .. "/10"
end

-- ============ Серии ============

function getChapterList(bookUrl)
    ensureEngine()
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
-- Схема (референс DoodExtractor; код docs/hoster-implementations.md):
-- разбор /pass_md5 и http_get тела — общая либа dood (см. комментарий в
-- resolveDood ниже). Referer финального потока = origin embed (без него CDN
-- отвечает 302). Капча-вариант embed отдаёт без /pass_md5 — тогда ветка
-- отдаёт отказ.

local function resolveDood(episodeUrl, link, entry)
    local page = http_get(link, {
        headers = { ["Referer"] = episodeUrl }, timeout = 8000,
    })
    if not page.success or type(page.body) ~= "string" then
        log_error("WitAnime: " .. entry.label .. " — dood: embed HTTP " .. tostring(page.code))
        return nil
    end
    -- Разбор pass_md5 и http_get /pass_md5 — общая либа dood; embed грузим сами
    -- (Referer = серия), капча-вариант без /pass_md5 отдаёт nil.
    local url, mime, origin = DOOD.resolveDood(link, page.body)
    if not url then
        log_error("WitAnime: " .. entry.label .. " — dood: не удалось получить ссылку")
        return nil
    end
    return { sourceOf(episodeUrl, url, qualityOf(entry), origin) }
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
-- Разбор ответа api.php и оба GETа — общая либа dotplay.

local function dotplaySources(episodeUrl, link, quality)
    local list, err = DOTPLAY.resolve(link)
    if not list then
        log_error("WitAnime: dotplay — " .. err)
        return nil
    end
    local out = {}
    for _, s in ipairs(list) do
        out[#out + 1] = sourceOf(episodeUrl, s.url, quality, link)
    end
    return out
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
-- расшифрованную ссылку, а определение — ниже, после dropboxSource
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
    local payload = resp and resp.d and base64_decode_bytes(resp.d)
    if type(payload) ~= "string" or #payload < 28 then
        log_error("WitAnime: yonaplay — пустой ответ api.php")
        return nil
    end

    -- 5) AES-256-GCM c ключом SHA-256(k) → ссылка хостера.
    -- raw-формат ответа: iv(12) ‖ tag(16) ‖ ciphertext — разбираем на Lua-стороне,
    -- сам engine API получает 4 сырых аргумента (key, iv, ct, tag).
    -- Хост НЕ заранее известен: помимо dotplay встречается 4shared и другие,
    -- поэтому дальше общий диспетчер по хосту, а не жёсткий dotplay.
    local iv  = payload:sub(1, 12)
    local tag = payload:sub(13, 28)
    local ct  = payload:sub(29)
    local plain = aes_gcm_decrypt(sha256(key), iv, ct, tag)
    if type(plain) ~= "string" or plain == "" then
        log_error("WitAnime: yonaplay — расшифровка не удалась")
        return nil
    end
    return resolveHostedLink(episodeUrl, plain, entry)
end

-- ---- videa: обфускация _xt → XML (часто RC4 + base64) → ссылки с md5 ----

-- ---- videa.hu: обфускация _xt → XML (RC4 + base64) → ссылки с md5 ----
-- Токен/разбор XML — общая либа videa; HTTP остаётся здесь (страница эмбеда
-- с Referer episodeUrl, XML — с Referer'ом самой ссылки, как в прежней
-- реализации).
local function videaSources(episodeUrl, link, entry)
    local page = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not page.success then
        log_error("WitAnime: videa — HTTP " .. tostring(page.code))
        return nil
    end
    local req, err = VIDEA.request(link, page.body)
    if not req then
        log_error("WitAnime: videa — " .. err)
        return nil
    end
    local r = http_get(req.url, { headers = { ["Referer"] = link } })
    if not r.success then
        log_error("WitAnime: videa — XML HTTP " .. tostring(r.code))
        return nil
    end
    local list, perr = VIDEA.parse(req, r)
    if not list then
        log_error("WitAnime: videa — " .. perr)
        return nil
    end
    local out = {}
    for _, s in ipairs(list) do
        out[#out + 1] = sourceOf(episodeUrl,
            s.url, s.name, "https://videa.hu/")
    end
    if #out == 0 then log_error("WitAnime: videa — в XML нет источников") end
    return #out > 0 and out or nil
end

-- ---- videas: эмбед app.videas.fr → прямой HLS (не путать с videa.hu) ----
-- videa.hu (выше) живёт на своём домене и раскрывается через RC4/XML,
-- у videas гейт отдаёт app.videas.fr/embed/media/<uuid>/: разметка листинга
-- чужая, в ней сразу лежит CDN-плейлист — в preload-теге и в JSON data-embed.
-- Разбор preload/JSON — общая либа videas; эмбед и запасной скан
-- directLinks остаются здесь.

local function videasSources(episodeUrl, link, entry)
    local page = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not page.success then
        log_error("WitAnime: videas — эмбед HTTP " .. tostring(page.code))
        return nil
    end
    local urls = VIDEAS.parse(page.body)
    if #urls == 0 then
        -- запасной путь: общий скан на прямые .mp4/.m3u8 в разметке
        urls = directLinks(page.body)
        if #urls == 0 then
            log_error("WitAnime: videas — в эмбеде нет прямой ссылки")
            return nil
        end
    end
    local out = {}
    for _, u in ipairs(urls) do
        out[#out + 1] = sourceOf(episodeUrl, u, qualityOf(entry), link)
    end
    return out
end

-- ---- ok.ru: data-options → flashvars.metadata ----

local function resolveOkRu(episodeUrl, link, entry)
    local r = http_get(link, { headers = { ["Referer"] = "https://ok.ru/" } })
    if not r.success then
        log_error("WitAnime: ok.ru — HTTP " .. tostring(r.code))
        return nil
    end
    -- Разбор data-options/metadata — общая либа okru; body грузим сами.
    local list = OKRU.resolveOkRu(r.body)
    if #list == 0 then
        log_error("WitAnime: ok.ru — нет источников в ответе")
        return nil
    end
    local out = {}
    for _, s in ipairs(list) do
        local q = s.name or qualityOf(entry)
        out[#out + 1] = sourceOf(episodeUrl, s.url, q, s.referer)
    end
    return out
end

-- ---- dropbox: прямая ссылка редиректами до файлового CDN ----
-- Обход редиректов — общая либа dropbox.

local function dropboxSource(episodeUrl, link, entry)
    local res, err = DROPBOX.resolve(link, episodeUrl)
    if not res then
        log_error("WitAnime: dropbox — " .. err)
        return nil
    end
    return { sourceOf(episodeUrl, res.url, qualityOf(entry)) }
end

-- ---- soraplay: эмбед → sources:[{"file":…,"label":…}] (SoraPlayExtractor.kt) ----
-- Разбор sources[] и списка go_to_player — общая либа soraplay; HTTP
-- и рекурсивный диспетчер (go_to_player → resolveHostedLink) остаются здесь.

local function soraplaySources(episodeUrl, link, entry)
    local r = http_get(link, { headers = { ["Referer"] = "https://yonaplay.org/" } })
    if not r.success then
        log_error("WitAnime: soraplay — HTTP " .. tostring(r.code))
        return nil
    end
    -- Список плееров разбираем одинаково для soraplay-/mirror и для страниц
    -- yonaplay — обе в референсе уходят в extractFromMulti (.OD li →
    -- go_to_player → снова диспетчер).
    if SORAPLAY.isMulti(link) then
        local out = {}
        for _, target in ipairs(SORAPLAY.parsePlayers(r.body)) do
            local res = resolveHostedLink(episodeUrl, target, entry)
            if type(res) == "table" then
                for _, s in ipairs(res) do out[#out + 1] = s end
            end
        end
        if #out == 0 then log_error("WitAnime: список плееров — нет go_to_player") end
        return #out > 0 and out or nil
    end
    local list = SORAPLAY.parseSources(r.body)
    if #list == 0 then
        log_error("WitAnime: soraplay — в embed нет sources[]")
        return nil
    end
    local out = {}
    -- Референс режет по `"file":"` (у vidbom ключ без кавычек — см. ниже).
    for _, s in ipairs(list) do
        out[#out + 1] = sourceOf(episodeUrl, s.url, "Soraplay: " .. s.label,
            "https://yonaplay.org/")
    end
    if #out == 0 then log_error("WitAnime: soraplay — в sources[] нет файлов") end
    return #out > 0 and out or nil
end

-- ---- vidbom: embed → sources:[{file:"…",label:"…"}] (VidBomExtractor.kt) ----
-- Разбор sources[] и проверка хоста (isLink, union-паттернов) — общая либа
-- vidbom; HTTP остаётся здесь.

local function vidbomSources(episodeUrl, link)
    local r = http_get(link, { headers = { ["Referer"] = episodeUrl } })
    if not r.success then
        log_error("WitAnime: vidbom — HTTP " .. tostring(r.code))
        return nil
    end
    local list, err = VIDBOM.parseSources(r.body)
    if not list then
        log_error("WitAnime: vidbom — " .. err)
        return nil
    end
    local out = {}
    for _, s in ipairs(list) do
        -- Референс: "Vidbom: " + label, длиннее 15 символов → "Vidshare: 480p".
        local quality = "Vidbom: " .. (s.quality or "")
        if #quality > 15 then quality = "Vidshare: 480p" end
        out[#out + 1] = sourceOf(episodeUrl, s.url, quality, link)
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

    -- 2) metadata → master m3u8 + субтитры. Разбор metadata на URL — общая
    -- либа dailymotion (parseMetadata); лог password_protected и субтитры —
    -- логика плагина (либа их не возвращает).
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
    local streams = mr.success and DM.parseMetadata(mr.body) or {}
    local master = type(streams[1]) == "table" and streams[1].url or nil
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

-- ---- drive.google: usercontent/download (либа urls: driveDirectUrl) ----
-- Живьём 2026-10-03: usercontent с confirm=t отдаёт 206 без единого заголовка,
-- для файлов >100 МБ хватает confirm=t. Раньше хост был в skip-листе как
-- «JS-превью», хотя прямую ссылку движок отдаёт без JS.
-- ponytail: playback-API-фоллбэк для «download disabled» (403 + UA-биндинг)
-- не делаем — ставим, если на сайте реально встретятся залоченные ссылки.

-- ---- mail.ru: embed → metadataUrl → /+/video/meta/<id> → mp4 ----
-- Живьём 2026-10-05: embed отдаёт "metadataUrl":"//my.mail.ru/+/video/meta/<id>",
-- meta-JSON — videos[].url, mp4 отвечает 206 на Range с Referer'ом эмбеда
-- (cookie video_key из ответа meta для воспроизведения не требуется).
-- Разбор и meta-запрос — общая либа mailru (embed загружает вызывающий).
local function mailRuSources(episodeUrl, link, entry)
    local r = http_get(link, {
        headers = { ["Referer"] = "https://my.mail.ru/" },
        timeout = 10000,
    })
    if not r.success then
        log_error("WitAnime: " .. entry.label .. " — mail.ru: HTTP " .. tostring(r.code))
        return nil
    end
    local list, err = MAILRU.resolve(r.body, link, qualityOf(entry))
    if not list then
        log_error("WitAnime: " .. entry.label .. " — mail.ru: " .. err)
        return nil
    end
    local out = {}
    for _, s in ipairs(list) do
        out[#out + 1] = sourceOf(episodeUrl, s.url, s.quality, link)
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
    -- Сайт (Livewire v3) отдаёт на stream-gate 302 только навигационным
    -- запросам БЕЗ Referer (iframe плеера висит на referrerpolicy=no-referrer)
    -- и с Sec-Fetch-Mode: navigate; с Referer и в fetch-режиме — 404.
    local r = http_get(baseUrl .. "/watch/stream-gate/" .. token, {
        binary          = true,
        followRedirects = false,
        headers         = {
            ["Accept"]         = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Sec-Fetch-Mode"] = "navigate",
            ["Sec-Fetch-Dest"] = "iframe",
            ["Sec-Fetch-Site"] = "same-origin",
        },
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
-- Распаковка — engine API unpack_packed (паритет с прежним локальному
-- unpackPacked, портом unpack.py из mediaflow-proxy): возвращает "",
-- если упаковщика нет. Проверено на uqload/hgcloud живьём 2026-10-05/06.

-- Есть ли медиа-расширение в пути URL (до "?" / "#"): без него media3 гадает
-- по последнему сегменту и ломается на HLS-плейлисте без расширения (.txt).
-- Общая либа hls (union копий: +.mkv из animephoenix — progressive тоже).
-- Обёртка, не алиас: top-level обращение к полю nil-либы упало бы до
-- ensureEngine (плагин молча исчезает — инцидент фазы 1).
local function hasMediaExt(u)
    return HLS.hasMediaExt(u)
end

-- ---- hgcloud: страница /e/<id> → зеркало с packed-конфигом ----
-- Живьём 2026-10-06: HTTP-редиректа на зеркало НЕТ — hgcloud.to/e/<id>
-- отдаёт 452 байта заглушки с <script src="/main.js?v=1.1.9">, и переход на
-- случайное зеркало делает клиентский main.js (домен собирается в рантайме,
-- статически не извлекается) → зеркала перебираем сами, путь эмбеда берём
-- из gate-ссылки. Разбор packed-конфига и обход зеркал — общая либа
-- hgcloud; HTTP (таймаут 8 с, максимум оригинал + 3 зеркала) отдаём колбэком.
-- Вход — gate-ссылка, тянем её здесь же (её код первым попадает в tried).

local function hgcloudSources(episodeUrl, link, entry)
    local function attempt(url, referer)
        local r = http_get(url, {
            headers = { ["Referer"] = referer },
            timeout = 8000,
        })
        local code = (r and r.code) or -1
        local body = (r and type(r.body) == "string") and r.body or ""
        return body, code
    end
    local gateBody, gateCode = attempt(link, episodeUrl)
    local urls, finalRef, tried = HGCLOUD.resolve(gateBody, link,
        function(url, ref)
            local b, c = attempt(url, ref)
            return b, c
        end)
    if #urls == 0 then
        -- finalRef = страница, с которой взят конфиг: без неё master.txt и
        -- сегменты отдают 404 (живьём 2026-10-06).
        local parts = { tostring(gateCode) .. " " .. link }
        for _, t in ipairs(tried) do parts[#parts + 1] = t end
        log_error("WitAnime: " .. entry.label .. " — hgcloud: нет packed-конфига; ответы: "
            .. table.concat(parts, ", "))
        return nil
    end
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
-- Определение ниже dropboxSource: функция ссылается на все резолверы.
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
    -- в soraplaySources (общая логика extractFromMulti).
    if low:find("yonaplay", 1, true) then
        return soraplaySources(episodeUrl, link, entry)
    end
    if low:find("dotplay.net", 1, true) then
        return dotplaySources(episodeUrl, link, qualityOf(entry))
    end
    if low:find("soraplay", 1, true) then
        return soraplaySources(episodeUrl, link, entry)
    end
    if low:find("videa.hu", 1, true) then
        return videaSources(episodeUrl, link, entry)
    end
    if low:find("videas.fr", 1, true) then
        return videasSources(episodeUrl, link, entry)
    end
    if low:find("ok.ru", 1, true) then
        return resolveOkRu(episodeUrl, link, entry)
    end
    if low:find("dropbox.com", 1, true) then
        return dropboxSource(episodeUrl, link, entry)
    end
    if low:find("dailymotion", 1, true) then
        return resolveDailymotion(link)
    end
    -- Google Drive: прямая ссылка собирается из id в URL, сеть не нужна.
    if low:find("drive.google", 1, true) then
        local drive = URLS.driveDirectUrl(link)
        if not drive then
            log_error("WitAnime: " .. entry.label .. " — drive.google: не найден id файла")
            return nil
        end
        return { sourceOf(episodeUrl, drive, qualityOf(entry), "https://drive.google.com/") }
    end
    if low:find("mail.ru", 1, true) then
        return mailRuSources(episodeUrl, link, entry)
    end
    -- hgcloud: страница /e/<id> сама по себе не поток (452-заглушка или
    -- packed-конфиг зеркала) — свой разбор, generic в нём не поможет.
    if low:find("hgcloud", 1, true) then
        return hgcloudSources(episodeUrl, link, entry)
    end
    -- dood/playmogo: /e/<id> сам по себе не поток — резолвер (embed грузим
    -- сами, разбор pass_md5 — либа dood; в капча-варианте ссылок в HTML нет).
    if low:find("dood", 1, true) or low:find("playmogo", 1, true)
        or low:find("dsvplay", 1, true) then
        return resolveDood(episodeUrl, link, entry)
    end
    -- VIDBOM_REGEX референса ("//v[aie]d[bp][aoe]?m") — проверка хоста в
    -- либе vidbom (isLink, union-паттернов из Anime4Up и Witanime).
    if VIDBOM.isLink(link) then
        return vidbomSources(episodeUrl, link)
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
    ensureEngine()
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
