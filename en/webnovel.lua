-- ── Metadatos ─────────────────────────────────────────────────────────────────
id       = "webnovel"
name     = "WebNovel"
version  = "2.0.0"
baseUrl  = "https://www.webnovel.com/"
language = "en"
icon     = "https://cdn.jsdelivr.net/gh/HnDK0/external-sources@jsdelivr/icons/webnovel.png"

function getUserAgentPreset()
  return "Chrome Desktop"
end

-- v2.0.0: fusiona "webnovel" (novelas) y "webnovel_fanfic" en un solo source con dos MODOS:
--   novel  → novelas  (categoryType=1)
--   fanfic → fanfics  (categoryType=4)
--
-- El modo se puede cambiar desde FUERA y desde DENTRO. Los dos caminos escriben la misma
-- preferencia ("webnovel_mode"), así que siempre están sincronizados:
--   * Fuera : engranaje de este source en la lista de catálogos → ajuste "Mode"
--             (getSettingsSchema; con 2 opciones se dibuja como dos botones).
--   * Dentro: filtro "Mode" del panel de filtros del catálogo. Al aplicar, getCatalogFiltered
--             lo recibe, lo usa y lo guarda con set_preference.
-- El modo manda en el catálogo inicial, la búsqueda, los filtros y la API que se consulta.
-- El detalle del libro, la lista de capítulos y el texto son idénticos en ambos modos.
--
-- Por modo:
--   * Sin tags → go/pcm/category/categoryAjax   (respaldo: páginas HTML de listado)
--   * Con tags → go/pcm/search/get-search-list  (respaldo solo en novel: /tags/{tag}-novel)
--   * Los tags son los de go/pcm/search/get-tag-list: 336 de fandom + 324 de setting/plot/
--     character/tone (categoryType=4). Los de novelas (categoryType=1, 253 tags) son un
--     subconjunto de esos 324, más Isekai, Smut y Ecchi (que viven en la lista de fandom).
--
-- Búsqueda avanzada de novelas (m.webnovel.com/search/advancedTags?from=novel), según las
-- capturas de Network del usuario. La página /search/advancedResult es una app Next.js que
-- pinta todo por JS (el HTML solo trae una carcasa), por eso se usa la API JSON y no el HTML:
--   página: /search/advancedResult?sex=&categoryType=1&tagId=&negTagId=&t=&bookStatus=
--           &orderBy=&newChapterTime=0&pageIndex=&chapterNum=
--   API   : /go/pcm/search/get-search-list?_csrfToken=&sex=&categoryType=1&tagId=&negTagId=
--           &pageIndex=   (+ bookStatus / orderBy / chapterNum cuando se eligen)
--   sex        1 = "More Fantasy" (hombres) · 2 = "More Romance" (mujeres)
--   bookStatus 0 = All · 1 = Online (en curso) · 2 = Complete
--   orderBy    1 = Popular · 2 = Collection · 3 = Time updates
--   chapterNum (ausente = todos) 1 = menos de 300 · 2 = de 300 a 1000 · 3 = más de 1000
--   tagId / negTagId: ids de los tags incluidos / excluidos, separados por coma.
--
-- OJO al instalar: "Import Lua" reescribe la línea `id = "..."` con un id local generado.
-- Por eso la clave de la preferencia es un texto fijo y NO depende de `id`.

-- ── Constantes ────────────────────────────────────────────────────────────────

local WWW_BASE = "https://www.webnovel.com/"
-- La API de búsqueda avanzada (get-tag-list / get-search-list) y las páginas móviles viven
-- en el host m., igual que en el source de fanfic.
local M_BASE = "https://m.webnovel.com/"

-- Preferencia del modo (SharedPreferences "lua_preferences"): "novel" o "fanfic".
local PREF_MODE = "webnovel_mode"

-- categoryType del sitio en todas sus APIs: 1 = novelas, 4 = fanfics.
local CATEGORY_TYPE = { novel = "1", fanfic = "4" }

-- Modo actual. Lo escriben el ajuste del source (fuera) y el filtro "Mode" (dentro).
-- Sin valor guardado (o con uno desconocido) es "novel".
local function getMode()
  if get_preference(PREF_MODE) == "fanfic" then return "fanfic" end
  return "novel"
end

-- "orderBy": OJO, cada API tiene SU numeración (confirmadas en el source de fanfic).
--   categoryAjax    (sin tags): 1=Popular 2=Recommended 3=Most collections 4=Rating 5=Time updated
--   get-search-list (con tags): 1=Popular 2=Most collections 3=Time updated
-- El filtro "sort" guarda una clave neutra y cada API la traduce con su tabla.
local CATEGORY_ORDER = { popular = "1", recommended = "2", collections = "3", rating = "4", updated = "5" }
local SEARCH_ORDER   = { popular = "1", collections = "2", updated = "3" }
-- La v1.1 de novelas guardaba el orden como número ("1".."5", la numeración de categoryAjax).
local LEGACY_SORT = { ["1"] = "popular", ["2"] = "recommended", ["3"] = "collections", ["4"] = "rating", ["5"] = "updated" }

-- Una página completa trae 20 libros (algunas vistas HTML, 12). Con menos de FULL_PAGE
-- resultados se considera que es la última.
local FULL_PAGE = 10

-- El buscador avanzado del sitio parece admitir como máximo 5 tags incluidos y 5 excluidos
-- (en el ejemplo del usuario, 7 tags incluidos elegidos quedaron en 5 tagId en la URL).
-- Se envía todo lo elegido; solo si la API lo rechaza se reintenta con los primeros 5 de cada lista.
local MAX_TAGS = 5

-- Géneros de las páginas HTML /stories/novel-{género}-{audiencia} (modo novel, sin tags).
local MALE_GENRES = {
  { "action", "Action" }, { "acg", "ACG" }, { "eastern", "Eastern" }, { "fantasy", "Fantasy" },
  { "games", "Games" }, { "history", "History" }, { "horror", "Horror" }, { "realistic", "Realistic" },
  { "scifi", "Sci-fi" }, { "sports", "Sports" }, { "urban", "Urban" }, { "war", "War" },
}
local FEMALE_GENRES = {
  { "fantasy", "Fantasy" }, { "general", "General" }, { "history", "History" }, { "lgbt", "LGBT+" },
  { "scifi", "Sci-fi" }, { "teen", "Teen" }, { "urban", "Urban" },
}

-- Subcategorías de fanfic: categoryId de categoryAjax (modo fanfic, sin tags).
local FANFIC_CATEGORIES = {
  { "81006", "Anime & Comics" }, { "81005", "Video Games" }, { "81002", "Celebrities" },
  { "81003", "Music & Bands" }, { "81007", "Movies" }, { "81001", "Book & Literature" },
  { "81008", "TV" }, { "81004", "Theater" }, { "81009", "Others" },
}

local function valueSet(list)
  local s = { all = true }
  for _, g in ipairs(list) do s[g[1]] = true end
  return s
end
local MALE_SET, FEMALE_SET = valueSet(MALE_GENRES), valueSet(FEMALE_GENRES)

-- Lista de { valor, etiqueta } → opciones de un filtro select, con la opción "todos" primero.
local function listOptions(list, allValue)
  local opts = { { value = allValue, label = "All" } }
  for _, g in ipairs(list) do table.insert(opts, { value = g[1], label = g[2] }) end
  return opts
end

-- ── Tags ──────────────────────────────────────────────────────────────────────
-- Listas de tags de go/pcm/search/get-tag-list (categoryType=4): las 5 categorías de la
-- búsqueda avanzada, 660 tags con su id numérico real. Entradas: { id, etiqueta }. El orden es
-- el de la API. Para actualizar: abrir la URL de arriba y reemplazar las entradas.
local TAG_GROUPS = {
  fandom = {
    { "41000057", "Isekai" },
    { "41000059", "Anime" },
    { "51065923", "Supernatural" },
    { "41000069", "Naruto" },
    { "41000499", "Smut" },
    { "41000197", "Marvel" },
    { "41001958", "One Piece" },
    { "41000091", "Yaoi" },
    { "41000413", "Harry Potter" },
    { "41001289", "Yuri" },
    { "41006270", "My Hero Academia" },
    { "41000868", "Ecchi" },
    { "51066138", "Crossover" },
    { "41000038", "DC" },
    { "51066036", "Fate Series" },
    { "51066152", "Original" },
    { "41000232", "Pokemon" },
    { "51066158", "High School DxD" },
    { "51066197", "Wattpad" },
    { "41003932", "Omegaverse" },
    { "51066151", "Game of Thrones" },
    { "51067046", "Jujutsu Kaisen" },
    { "41000595", "Bleach" },
    { "41000415", "BTS" },
    { "41000079", "Dragon Ball" },
    { "41001151", "K-Pop" },
    { "51066186", "Self Insert" },
    { "51066142", "Demon Slayer" },
    { "51066125", "A Song of Ice and Fire" },
    { "51066147", "Fairy Tail" },
    { "51066154", "Genshin Impact" },
    { "51066140", "DanMachi" },
    { "41001416", "RWBY" },
    { "41000065", "Starwars" },
    { "51066176", "Overlord" },
    { "41004287", "Douluo Dalu" },
    { "51066180", "Percy Jackson" },
    { "51066189", "Spider-Man" },
    { "51066134", "Classroom of the Elite" },
    { "51066195", "Twilight" },
    { "51066148", "Fate/Stay Night" },
    { "51067027", "Blood+" },
    { "51066968", "Hunter × Hunter" },
    { "51066126", "Attack on Titan" },
    { "51066129", "Ben 10" },
    { "51066130", "Black Clover" },
    { "51066196", "The Vampire Diaries" },
    { "51067030", "My Teen Romantic Comedy SNAFU" },
    { "51066174", "One Punch Man" },
    { "51066183", "General" },
    { "51067000", "Loveless" },
    { "41000816", "SMA" },
    { "51067023", "Re:Zero" },
    { "51066883", "The Tyrant Falls in Love" },
    { "51066132", "Castle" },
    { "51066192", "Supergirl" },
    { "51066934", "Yu-Gi-Oh!" },
    { "51066164", "Lucifer" },
    { "51066829", "Psycho-Pass" },
    { "51066181", "Personaseries" },
    { "51066153", "Gate" },
    { "51066123", "Archiveofourown" },
    { "51066191", "Strangerthings" },
    { "51066199", "Worm" },
    { "51066696", "Jojo'sbizarreadventure" },
    { "51066982", "Ghosthunt" },
    { "51066194", "Transformers" },
    { "51066198", "Thewitcher" },
    { "51066168", "Miraculousladybug" },
    { "51066918", "Chainsawman" },
    { "51066155", "Halo" },
    { "51066993", "Tokyoghoul" },
    { "51066156", "Hazbinhotel" },
    { "51067054", "Highschoolofthedead" },
    { "51067029", "Thesevendeadlysins" },
    { "51066979", "Swordartonline" },
    { "51066886", "Brothersconflict" },
    { "51066943", "Kuroko'sbasketball" },
    { "51066954", "Detectiveconan" },
    { "51066114", "Thelordoftherings" },
    { "51066938", "Deathnote" },
    { "51066166", "Masseffect" },
    { "51066157", "Helluvaboss" },
    { "51067110", "Dungeons&dragons" },
    { "51066190", "Spy×family" },
    { "51066958", "Haikyuu!!" },
    { "51066187", "Sonicthehedgehog" },
    { "51066159", "Howtotrainyourdragon" },
    { "51066815", "Oshinoko" },
    { "51066137", "Codegeass" },
    { "51066165", "Shadowhunters" },
    { "51066139", "Danganronpa" },
    { "41000158", "Bnha" },
    { "51066170", "Mylittlepony" },
    { "51066965", "Free!" },
    { "51066820", "Akamegakill!" },
    { "51066866", "Tolove-Ru" },
    { "51066871", "Datealive" },
    { "51066900", "Noir" },
    { "51066167", "Merlin" },
    { "51066869", "Futurediary" },
    { "51066849", "Dragonknights" },
    { "51066963", "Gundam" },
    { "51066193", "Tokyorevengers" },
    { "51066150", "Fivenightsatfreddy's" },
    { "51067021", "Acertainmagicalindex" },
    { "51067044", "Foodwars!shokugekinosoma" },
    { "51066936", "Digimon" },
    { "51066998", "Magi" },
    { "51066816", "Beyondtheboundary" },
    { "51066128", "Azurlane" },
    { "51066832", "Petshopofhorrors" },
    { "51066841", "Ohmygoddess!" },
    { "51066948", "Souleater" },
    { "51066877", "Berserk" },
    { "51066160", "Inuyasha" },
    { "51066902", "Monstermusume" },
    { "51067043", "Luckystar" },
    { "51066924", "Thedangersinmyheart" },
    { "51066141", "Dannyphantom" },
    { "51067006", "Xxxholic" },
    { "51067032", "Aceofdiamond" },
    { "51066177", "Theowlhouse" },
    { "51066974", "Slayers" },
    { "51066136", "Cobrakai" },
    { "51066989", "Slamdunk" },
    { "51066903", "Demondiary" },
    { "51067009", "Bungoustraydogs" },
    { "51067037", "07-Ghost" },
    { "51066988", "Junjōromantica" },
    { "51067010", "Lovehina" },
    { "51066149", "Fireemblem" },
    { "51066935", "Fullmetalalchemist" },
    { "51066928", "Mahoukakoukounorettousei" },
    { "51066950", "Saintseiya" },
    { "51066916", "Thequintessentialquintuplets" },
    { "51066163", "Theloudhouse" },
    { "51066956", "Vampireknight" },
    { "51066939", "Katekyohitmanreborn!" },
    { "51066947", "Beyblade" },
    { "51067052", "Blackcat" },
    { "51066474", "Thedisastrouslifeofsaikik." },
    { "51066985", "Assassinationclassroom" },
    { "51066999", "Magicalgirllyricalnanoha" },
    { "51066960", "Neongenesisevangelion" },
    { "51067001", "Spiritedaway" },
    { "51066135", "The100" },
    { "51066885", "Gunslingergirl" },
    { "51067026", "Diaboliklovers" },
    { "51066962", "Hellsing" },
    { "51067016", "Rosario+vampire" },
    { "51066857", "Strikewitches" },
    { "51066912", "Legaldrug" },
    { "51066927", "Madeinabyss" },
    { "51066133", "Cid" },
    { "51066161", "Killingeve" },
    { "51066225", "Dreamsmp" },
    { "51066997", "Puellamagimadokamagica" },
    { "51066131", "Bridgerton" },
    { "51066908", "Riddlestoryofdevil" },
    { "51066937", "Sailormoon" },
    { "51066944", "Princeoftennis" },
    { "51067045", "Chronocrusade" },
    { "51066830", "Killlakill" },
    { "51066845", "Infinitestratos" },
    { "51066863", "Vampirehunterd" },
    { "51066984", "Skipbeat!" },
    { "51067033", "Thefamiliarofzero" },
    { "51067049", "Prettycure" },
    { "51067002", "Roninwarriors" },
    { "51066122", "Amphibia" },
    { "51066698", "Wolf'srain" },
    { "51066860", "Thepromisedneverland" },
    { "51066146", "Encanto" },
    { "51066175", "Outlander" },
    { "51066980", "D.n.angel" },
    { "51066994", "Metalfightbeyblade" },
    { "51066200", "Zootopia" },
    { "51066837", "Gundamuc" },
    { "51066848", "Speciala" },
    { "51066887", "Magickaito" },
    { "51066906", "Thedevilisapart-Timer!" },
    { "51066987", "Blueexorcist" },
    { "51066838", "Blacklagoon" },
    { "51066162", "Onedirection" },
    { "51066823", "Dr.stone" },
    { "51066844", "Natsume'sbookoffriends" },
    { "51066901", "Samurai7" },
    { "51066819", "Angelsanctuary" },
    { "51066836", "Cyborg009" },
    { "51066851", "Spiral:thebondsofreasoning" },
    { "51066926", "Interspeciesreviewers" },
    { "51066969", "Inazumaeleven" },
    { "51067005", "Kproject" },
    { "51066827", "Angelbeats!" },
    { "51066840", "Girlsundpanzer" },
    { "51066853", "Beelzebub" },
    { "51066959", "Shamanking" },
    { "51067056", "Littlewitchacademia" },
    { "51066178", "Pawpatrol" },
    { "51066953", "Ranma½" },
    { "51066952", "Rurounikenshin" },
    { "51066945", "Ouranhighschoolhostclub" },
    { "51067035", "Finderseries" },
    { "51066870", "Thewallflower" },
    { "51066880", "Sekirei" },
    { "51067003", "Demashita!powerpuffgirlsz" },
    { "51066996", "Bakuganbattlebrawlers" },
    { "51067017", "Magicknightrayearth" },
    { "51066854", "Yuruyuri" },
    { "51066473", "Ancientmagus'bride" },
    { "51066921", "Bloodblockadebattlefront" },
    { "51066915", "Yourlieinapril" },
    { "51066991", "Cowboybebop" },
    { "51067007", "Maidsama!" },
    { "51067051", "Captaintsubasa" },
    { "51066839", "Nurarihyonnomago" },
    { "51066882", "Initiald" },
    { "51066941", "Cardcaptorsakura" },
    { "51066971", "Yuri!!!onice" },
    { "51067031", "Cardfight!!vanguard" },
    { "51066859", "Daa!daa!daa!" },
    { "51066973", "Gintama" },
    { "51067022", "Seraphoftheend" },
    { "51067053", "Trinityblood" },
    { "51066831", "Countcainseries" },
    { "51066834", "Fullmetalpanic!" },
    { "51066872", "Tengentoppagurrenlagann" },
    { "51066173", "Ncis" },
    { "51066904", "Citrus" },
    { "51066922", "Chuunibyoudemokoigashitai" },
    { "51066920", "Kiminonawa." },
    { "51066919", "Theheroiclegendofarslan" },
    { "51066942", "Yuyuhakusho" },
    { "51067034", "No.6" },
    { "51066856", "Fullmoonwosagashite" },
    { "51066881", "Peacemakerkurogane" },
    { "51066909", "Thebigo" },
    { "51066949", "D.gray-Man" },
    { "51067025", "Princesstutu" },
    { "51066700", "Howl'smovingcastle" },
    { "51066835", "Claymore" },
    { "51066894", "Itazuranakiss" },
    { "51066986", "Eyeshield21" },
    { "51066976", "Candycandy" },
    { "51066825", "Outlawstar" },
    { "51066817", "Witchhunterrobin" },
    { "51066846", "Matanteilokiragnarok" },
    { "51066951", "Fruitsbasket" },
    { "51066964", "Gravitation" },
    { "51066990", "Trigun" },
    { "51066981", "Pandorahearts" },
    { "51067014", "K-On!" },
    { "51067039", "Noragami" },
    { "51067050", "Sengokubasara" },
    { "51066828", "Elfenlied" },
    { "51066850", "Clannad" },
    { "51066855", "Clamp" },
    { "51066458", "Hetalia:axispowers" },
    { "51066457", "Gundamwing" },
    { "51066910", "Toradora!" },
    { "51067004", "X/1999" },
    { "51067036", "Mr.osomatsu" },
    { "51067028", "Akatsukinoyona" },
    { "51067047", "Tiger&bunny" },
    { "51066862", "Prétear" },
    { "51066873", "Princessmononoke" },
    { "51066865", "Thecatreturns" },
    { "51066325", "Station19" },
    { "51066895", "Baccano!" },
    { "51066896", "Sound!euphonium" },
    { "51066917", "Symphogear" },
    { "51066946", "Blackbutler" },
    { "51066961", "Durarara!!" },
    { "51066966", "Tsubasa:reservoirchronicle" },
    { "51066983", "Thevisionofescaflowne" },
    { "51066995", "Tenchimuyo!" },
    { "51067013", "Getbackers" },
    { "51067024", "Revolutionarygirlutena" },
    { "51067048", "Azumangadaioh" },
    { "51066695", "Toilet-Boundhanako-Kun" },
    { "51066842", "Airgear" },
    { "51066847", "009-1" },
    { "51066833", "Strawberrypanic!" },
    { "51066868", "Obanstar-Racers" },
    { "51066923", "Skipandloafer" },
    { "51066975", "Kyokaramaoh!" },
    { "51066972", "Tokyomewmew" },
    { "51066978", "Mai-Hime" },
    { "51067011", "Negima!magisternegimagi" },
    { "51067012", "Haruhisuzumiya" },
    { "51067038", "Hakuōki" },
    { "51067055", "Hanayoridango" },
    { "51067041", "Samuraideeperkyo" },
    { "51067040", "Samuraichamploo" },
    { "51066699", "Lacordad'oro" },
    { "51066826", "Zatchbell!" },
    { "51066824", "Kamichamakarin" },
    { "51066818", "Flameofrecca" },
    { "51066822", "Akagaminoshirayukihime" },
    { "51066843", "Ggundam" },
    { "51066861", "Fushigiboshinofutagohime" },
    { "51066852", "Theroseofversailles" },
    { "51066874", "Kamisamahajimemashita" },
    { "51066876", "Karneval" },
    { "51066867", "Kannazukinomiko" },
    { "51066864", "Rozenmaiden" },
    { "51066889", "Majintanteinōgamineuro" },
    { "51066888", "Saiunkokumonogatari" },
    { "51066893", "Aldnoah.zero" },
    { "51066892", "Eurekaseven" },
    { "51066884", "Yowamushipedal" },
    { "51066907", "Ayashinoceres" },
    { "51066905", "Megamikouhosei" },
    { "51066899", "Bananafish" },
    { "51066898", "Kodomonoomocha" },
    { "51066914", "Medabots" },
    { "51066955", "Gakuenalice" },
    { "51066957", "Shugochara!" },
    { "51066970", "Weisskreuz" },
    { "51066967", "Saiyuki" },
    { "51066977", "Fushigiyuugi" },
    { "51066992", "Yaminomatsuei" },
    { "51067019", "Utanoprince-Sama" },
    { "51067018", "Hikarunogo" },
    { "51067020", "Sekaiichihatsukoi" },
    { "51067008", "Kagerouproject" },
    { "51067042", "Hamtaro" },
    { "51066858", "Flcl" },
    { "51066879", "Lupiniii" },
    { "51066878", "Nabarinoou" },
    { "51067364", "Phantombladezero" },
    { "51066911", "Yumeiropâtissière" },
    { "51066913", "Bubblegumcrisis" },
    { "51067057", "Sgt.frog" },
    { "51066875", "Ōkikufurikabutte" },
  },
  setting = {
    { "41000016", "System" },
    { "41000884", "Magic" },
    { "41000147", "R18" },
    { "41001330", "Superpowers" },
    { "41000224", "Cultivation" },
    { "51006885", "Campus" },
    { "41002630", "Urban" },
    { "51001182", "Non-human" },
    { "41000329", "Apocalypse" },
    { "41000444", "Historical" },
    { "41000459", "Teen" },
    { "51003369", "Enemiestolovers" },
    { "41000331", "Family" },
    { "41000045", "Lovetriangle" },
    { "41004018", "Sweetlove" },
    { "51008739", "Royal Family" },
    { "51051471", "Fatedlove" },
    { "41001486", "Video Game" },
    { "41000096", "Bl" },
    { "51007341", "Richfamily" },
    { "41000352", "Firstlove" },
    { "51067222", "Hidden Identities" },
    { "41005437", "Advanced Technology" },
    { "41000274", "Mafia" },
    { "41000861", "Future" },
    { "41002695", "Forbiddenlove" },
    { "41000216", "Myth" },
    { "41000583", "Poor to Rich" },
    { "51065556", "Abusivelove" },
    { "41001400", "Arrangedmarriage" },
    { "51065921", "Horror" },
    { "41001805", "Wizards" },
    { "41004187", "Contractmarriage" },
    { "51065853", "Another World" },
    { "41000298", "Xianxia" },
    { "51066083", "Paranormal" },
    { "51035698", "Loveaftermarriage" },
    { "41006976", "Interstellar" },
    { "41001071", "Undead" },
    { "51008618", "Summons" },
    { "51067154", "Multiverse" },
    { "41001307", "Eastern" },
    { "51017528", "Friendstolovers" },
    { "51008740", "Beast Taming" },
    { "51065843", "Martial Arts" },
    { "51001460", "Childhoodsweethearts" },
    { "41001399", "Showbiz" },
    { "41003070", "Multiple Identities" },
    { "51067186", "Military" },
    { "51067064", "LitRPG" },
    { "41000437", "Entertainment" },
    { "41004339", "Noromance" },
    { "41002699", "Survival Game" },
    { "51065857", "Sword and Magic" },
    { "41001153", "Mecha" },
    { "51065555", "Humanandbeast" },
    { "51031547", "Hiddenmarriage" },
    { "41005971", "Flashmarriage" },
    { "51065976", "History" },
    { "41002301", "MMORPG" },
    { "51067137", "Clan" },
    { "51066005", "Alternate World" },
    { "51065946", "Space" },
    { "51065896", "Cheats" },
    { "51066233", "Technology" },
    { "51065893", "Zombie" },
    { "51047692", "Live Streaming" },
    { "51066272", "Cyberpunk" },
    { "41004299", "Genes" },
    { "51066275", "Football" },
    { "51065900", "Workplace" },
    { "51067181", "Doomsday" },
    { "41000956", "Esports" },
    { "51061183", "Womensworld" },
    { "51066277", "Sect" },
    { "51067187", "Global" },
    { "51066311", "Parallel World" },
    { "51067206", "Countryside" },
    { "51067253", "Mission" },
    { "51066230", "Virtual Reality" },
    { "51067145", "Beast Taming (2)" },
    { "51067150", "Qi" },
    { "51066310", "Steampunk" },
    { "51067149", "Add Point" },
    { "51066270", "Food" },
    { "51065911", "High Tech" },
    { "51048032", "Trialmarriage" },
    { "51065870", "Online Game" },
    { "51065871", "Abyss" },
    { "51067155", "Yakuza" },
    { "51067153", "Thug" },
    { "51067249", "Simulation Game" },
    { "51065999", "Card" },
    { "51065951", "Livestream" },
    { "51066070", "Cthulhu" },
    { "51066100", "Infinite" },
    { "51066033", "Dynasty" },
    { "51066397", "Spiritual Recovery" },
    { "51066117", "Infinity" },
    { "51067151", "Wukong" },
    { "51067085", "Overimaginative" },
    { "51067135", "Journey to the West" },
    { "51066328", "Gene" },
    { "51067152", "Journey to the West (2)" },
    { "51067167", "Kaidan" },
  },
  plot = {
    { "41000121", "Action" },
    { "41000120", "Adventure" },
    { "41000010", "Romance" },
    { "41000075", "Reincarnation" },
    { "41000074", "Weak to Strong" },
    { "41000052", "Survival" },
    { "41000799", "Overpowered" },
    { "41000132", "Transmigration" },
    { "41000019", "Revenge" },
    { "41000293", "Betrayal" },
    { "41001351", "Kingdom Building" },
    { "41000578", "Level Up" },
    { "41000228", "Academy" },
    { "41000125", "Rebirth" },
    { "41000033", "Evolution" },
    { "41001496", "Immortal" },
    { "51003788", "Powerfulcouple" },
    { "51003564", "Conquer" },
    { "51003589", "Face Slapping" },
    { "41005570", "Loveatfirstsight" },
    { "51063747", "The Strong Acting Weak" },
    { "41003638", "Pregnancy" },
    { "41003727", "Counterattack" },
    { "51066092", "Thriller" },
    { "41000403", "Crush" },
    { "51053152", "Rare Bloodline" },
    { "51067194", "Rejected" },
    { "51065939", "Suspense" },
    { "41005936", "Fake Identity" },
    { "51067193", "Grovellingex" },
    { "51005231", "Gettingbacktogether" },
    { "51066011", "Cheat" },
    { "51065877", "Marriage" },
    { "41004611", "Trauma" },
    { "51065917", "Golden Finger" },
    { "51066252", "1v1" },
    { "41003255", "Kidnap" },
    { "51006072", "Onenightstand" },
    { "51067122", "Secretbaby" },
    { "41003628", "Mutation" },
    { "51067136", "Reverseharem" },
    { "51065879", "Superpower" },
    { "51066024", "Forcedlove" },
    { "51065898", "Divorce" },
    { "51066416", "18+" },
    { "51067230", "Time Travel" },
    { "51067202", "Agegap" },
    { "51067166", "Warm" },
    { "41004250", "Shapeshifter" },
    { "51011059", "Substitute" },
    { "51066089", "Betrayed" },
    { "51067144", "Misunderstanding" },
    { "51065931", "Book Transmigration" },
    { "51066086", "Amnesia" },
    { "51065557", "Identityexchange" },
    { "51066451", "Zero to Hero" },
    { "41005410", "Cohabitation" },
    { "51067147", "No Harem" },
    { "41005130", "Crossdressing" },
    { "51067301", "Face Slapping (2)" },
    { "51065908", "Deception" },
    { "51067192", "Farming&business" },
    { "51067257", "Disaster" },
    { "51065949", "Transformation" },
    { "51067244", "Feeling Good" },
    { "51065863", "Grouppampering" },
    { "51067178", "Unstoppable" },
    { "51066071", "Farming" },
    { "51065992", "Super Rich" },
    { "51066334", "Happy Ending" },
    { "51067292", "Storage Space" },
    { "51067182", "Longevity" },
    { "51053709", "Sign-in" },
    { "51065895", "Strong Acting Weak" },
    { "51065979", "Cheating" },
    { "51065861", "Summon" },
    { "51067180", "Eternal" },
    { "51066426", "King Comeback" },
    { "51065986", "Rapid Development" },
    { "51067179", "Anti-Routine" },
    { "51065974", "Flirt" },
    { "51066091", "Betray" },
    { "51066030", "Simulator" },
    { "51065864", "Exposure" },
    { "51066265", "Pretend to Be a Fool" },
    { "51067300", "Accidentalmarriage" },
    { "51065889", "Esport" },
    { "51067278", "Fortune Telling" },
    { "51066340", "Fishing" },
  },
  character = {
    { "41000037", "Harem" },
    { "41001702", "Villain" },
    { "41001092", "Genius" },
    { "41000015", "Antihero" },
    { "41001868", "Possessive" },
    { "41000025", "Werewolf" },
    { "41004234", "Beauty" },
    { "41000316", "CEO" },
    { "41000024", "Vampire" },
    { "41000676", "Devil" },
    { "51067191", "Strongfl" },
    { "41002592", "Killer" },
    { "41001960", "Alpha" },
    { "41000683", "Abandoned" },
    { "51066439", "No Harem" },
    { "41000020", "Dragon" },
    { "51065862", "Strong Female Lead" },
    { "51063749", "High IQ" },
    { "51033398", "Ordinary" },
    { "51067190", "Abusedfl" },
    { "51067303", "CEO (2)" },
    { "51010291", "Seductive" },
    { "51007069", "Ex" },
    { "41002694", "Princess" },
    { "51063750", "Righteous" },
    { "51063748", "Egoist" },
    { "41002706", "Badboy" },
    { "51064558", "Unprincipled" },
    { "51023455", "Businesswoman" },
    { "51066085", "Billionaire" },
    { "51067328", "Fatedmate" },
    { "41001260", "Angel" },
    { "51016707", "Coolguy" },
    { "41003637", "Baby" },
    { "41001684", "Doctor" },
    { "41000988", "Elves" },
    { "51067184", "Calm" },
    { "41002788", "Superstar" },
    { "51067160", "Motivated" },
    { "51067188", "Heiress" },
    { "51048692", "Single Female Lead" },
    { "51067302", "Hidden Identity" },
    { "51067177", "Cold-Blooded" },
    { "51066084", "Luna" },
    { "51047674", "Big Shot" },
    { "51019894", "Heartthrob" },
    { "51067183", "Yandere" },
    { "51067168", "Heroic" },
    { "51067111", "Hero" },
    { "51064304", "Richdaughter" },
    { "41004094", "Side Character" },
    { "51067172", "Sexy" },
    { "51067297", "Powerfulcouple" },
    { "51067169", "Horny" },
    { "51066023", "Prince" },
    { "51065891", "Ancient Gods" },
    { "41004019", "NPC" },
    { "51067195", "Twins" },
    { "41000345", "Hentai" },
    { "51067159", "Humorous" },
    { "41001650", "Shonen" },
    { "51065938", "Detective" },
    { "51065858", "Warrior" },
    { "51067175", "Domineering" },
    { "51067171", "Arrogant" },
    { "51067076", "Scheming" },
    { "51022040", "Marysue" },
    { "51066088", "Witch" },
    { "51065966", "Goddess" },
    { "51067197", "Master" },
    { "51015810", "Stepmom" },
    { "41001075", "Ninja" },
    { "51066016", "Slave" },
    { "51028654", "Son-In-Law" },
    { "51067198", "Hot-Blooded" },
    { "51065868", "Legend" },
    { "51067174", "Sinister" },
    { "51066051", "Soldier" },
    { "51065860", "Demon King" },
    { "51067161", "Cynical" },
    { "51066331", "Immortals" },
    { "51065856", "Mage" },
    { "51067304", "Quick Transmigration" },
    { "51066396", "Wizard" },
    { "51067157", "Aloof" },
    { "51067196", "Disciples" },
    { "51067162", "Proud" },
    { "51065962", "Summoner" },
    { "51067170", "Tsundere" },
    { "51065970", "War God" },
    { "51067165", "Otaku" },
    { "51067158", "Pessimistic" },
    { "51065973", "Miracle Doctor" },
    { "51066356", "School Hero" },
    { "51067288", "Triplets" },
    { "51067173", "Elegant" },
    { "51066308", "Twin" },
    { "51067163", "Ethereal" },
    { "51067221", "Tycoon" },
    { "51067176", "Hypocritical" },
    { "51065874", "Gourmet" },
    { "51067164", "Chuunibyou" },
    { "51066321", "Mind Reading" },
    { "51065935", "Special Agent" },
    { "51065927", "Succubus" },
    { "51067185", "Eunuch" },
  },
  tone = {
    { "41000170", "Comedy" },
    { "41000165", "Dark" },
    { "41000066", "Mystery" },
    { "41001297", "Slice of Life" },
    { "41000051", "Tragedy" },
    { "51065559", "Dramatic" },
    { "51003261", "Fast-Paced" },
    { "41003852", "Scary" },
    { "41000629", "Angst" },
    { "41001626", "Sweet" },
    { "51005555", "Twisted" },
    { "41000776", "Light Novel" },
    { "51004627", "Healing" },
    { "51016596", "Multiple Leads" },
    { "51010858", "Invincible" },
    { "51046428", "Blood Pumping" },
    { "41006586", "Serious" },
    { "51012180", "Positive" },
    { "51065560", "Detailed" },
    { "51052957", "No Cheats" },
    { "51065873", "Humor" },
    { "51067156", "Hot-Blooded" },
    { "51067308", "Hot" },
    { "51067313", "Comic" },
  },
}

-- Tags que existen en la búsqueda avanzada de NOVELAS (go/pcm/search/get-tag-list?categoryType=1,
-- 253 tags) más Isekai, Smut y Ecchi, que el source de novelas ofrecía por página de tag. "id nombre":
-- el nombre es el que usa la página /tags/{nombre}-novel. Todos están dentro de TAG_GROUPS.
local NOVEL_TAG_RAW = [[
41000010 romance
41000015 antihero
41000016 system
41000019 revenge
41000020 dragon
41000024 vampire
41000025 werewolf
41000033 evolution
41000037 harem
41000051 tragedy
41000052 survival
41000057 isekai
41000066 mystery
41000074 weaktostrong
41000075 reincarnation
41000120 adventure
41000121 action
41000125 rebirth
41000132 transmigration
41000147 r18
41000165 dark
41000170 comedy
41000216 myth
41000224 cultivation
41000228 academy
41000274 mafia
41000293 betrayal
41000298 xianxia
41000316 ceo
41000329 apocalypse
41000345 hentai
41000437 entertainment
41000444 historical
41000499 smut
41000578 levelup
41000583 poortorich
41000676 devil
41000683 abandoned
41000776 lightnovel
41000799 overpowered
41000861 future
41000868 ecchi
41000884 magic
41000956 esports
41000988 elves
41001071 undead
41001075 ninja
41001092 genius
41001153 mecha
41001260 angel
41001297 sliceoflife
41001307 eastern
41001330 superpowers
41001351 kingdombuilding
41001399 showbiz
41001486 videogame
41001496 immortal
41001650 shonen
41001684 doctor
41001702 villain
41001805 wizards
41002301 mmorpg
41002592 killer
41002630 urban
41002699 survivalgame
41002788 superstar
41003070 multipleidentities
41003628 mutation
41003727 counterattack
41003852 scary
41004019 npc
41004094 sidecharacter
41004234 beauty
41004250 shapeshifter
41004299 genes
41004611 trauma
41005437 advancedtechnology
41005936 fakeidentity
41006976 interstellar
51001182 nonhuman
51003261 fastpaced
51003564 conquer
51003589 faceslapping
51006885 campus
51008618 summons
51008739 royalfamily
51008740 beasttaming
51010858 invincible
51012180 positive
51015810 stepmom
51016596 multipleleads
51019894 heartthrob
51028654 son-in-law
51033398 ordinary
51046428 bloodpumping
51047674 bigshot
51047692 livestreaming
51048692 singlefemalelead
51052957 nocheats
51053152 rarebloodline
51053709 signin
51063747 thestrongactingweak
51063748 egoist
51063749 highiq
51063750 righteous
51064558 unprincipled
51065843 martialarts
51065853 anotherworld
51065856 mage
51065857 swordandmagic
51065858 warrior
51065860 demonking
51065861 summon
51065862 strongfemalelead
51065864 exposure
51065868 legend
51065870 onlinegame
51065871 abyss
51065873 humor
51065874 gourmet
51065879 superpower
51065889 esport
51065891 ancientgods
51065893 zombie
51065895 strongactingweak
51065896 cheats
51065898 divorce
51065900 workplace
51065908 deception
51065911 hightech
51065917 goldenfinger
51065921 horror
51065927 succubus
51065931 booktransmigration
51065935 specialagent
51065938 detective
51065939 suspense
51065946 space
51065949 transformation
51065951 livestream
51065962 summoner
51065966 goddess
51065970 wargod
51065973 miracledoctor
51065974 flirt
51065976 history
51065979 cheating
51065986 rapiddevelopment
51065992 superrich
51065999 card
51066005 alternateworld
51066011 cheat
51066016 slave
51066023 prince
51066030 simulator
51066033 dynasty
51066051 soldier
51066070 cthulhu
51066071 farming
51066085 billionaire
51066086 amnesia
51066088 witch
51066089 betrayed
51066091 betray
51066092 thriller
51066100 infinite
51066117 infinity
51066230 virtualreality
51066233 technology
51066265 pretendtobeafool
51066270 food
51066272 cyberpunk
51066275 football
51066277 sect
51066308 twin
51066310 steampunk
51066311 parallelworld
51066321 mindreading
51066328 gene
51066331 immortals
51066334 happyending
51066340 fishing
51066356 schoolhero
51066396 wizard
51066397 spiritualrecovery
51066416 18
51066426 kingcomeback
51066439 no-harem
51066451 zerotohero
51067064 litrpg
51067076 scheming
51067085 overimaginative
51067111 hero
51067135 journeytothewest
51067137 clan
51067144 misunderstanding
51067145 beasttaming
51067147 noharem
51067149 addpoint
51067150 qi
51067151 wukong
51067152 journeytothewest
51067153 thug
51067154 multiverse
51067155 yakuza
51067156 hot-blooded
51067157 aloof
51067158 pessimistic
51067159 humorous
51067160 motivated
51067161 cynical
51067162 proud
51067163 ethereal
51067164 chuunibyou
51067165 otaku
51067166 warm
51067167 kaidan
51067168 heroic
51067169 horny
51067170 tsundere
51067171 arrogant
51067172 sexy
51067173 elegant
51067174 sinister
51067175 domineering
51067176 hypocritical
51067177 cold-blooded
51067178 unstoppable
51067179 anti-routine
51067180 eternal
51067181 doomsday
51067182 longevity
51067183 yandere
51067184 calm
51067185 eunuch
51067186 military
51067187 global
51067196 disciples
51067197 master
51067198 hotblooded
51067206 countryside
51067221 tycoon
51067222 hiddenidentities
51067230 timetravel
51067244 feelinggood
51067249 simulationgame
51067253 mission
51067257 disaster
51067278 fortunetelling
51067292 storagespace
51067301 faceslapping
51067302 hiddenidentity
51067303 ceo
51067304 quicktransmigration
51067308 hot
51067313 comic
]]

local TAG_ORDER_FANFIC = { "fandom", "setting", "plot", "character", "tone" }
-- En modo novel el grupo de fandom (casi todo fanfic) va al final.
local TAG_ORDER_NOVEL  = { "setting", "plot", "character", "tone", "fandom" }
local TAG_TITLES = { fandom = "Fandom", setting = "Setting", plot = "Plot", character = "Character/Role", tone = "Tone" }

-- id numérico → nombre interno de los tags que existen para novelas. Sirve para (a) saber
-- qué tags son válidos en modo novel y (b) el respaldo por página /tags/{nombre}-novel.
local NOVEL_TAG = {}
for tid, tname in NOVEL_TAG_RAW:gmatch("(%d+)%s+([%w%-]+)") do NOVEL_TAG[tid] = tname end

-- Opciones de un grupo de tags. En modo novel, los tags que NO existen en la lista de novelas
-- llevan " (F)" (solo Fanfic) para que no se elijan creyendo que filtran novelas. El grupo
-- de fandom no se marca: se avisa en su título.
local function tagOptions(group, novelMode)
  local opts = {}
  for _, t in ipairs(TAG_GROUPS[group]) do
    local label = t[2]
    if novelMode and group ~= "fandom" and not NOVEL_TAG[t[1]] then label = label .. " (F)" end
    table.insert(opts, { value = t[1], label = label })
  end
  return opts
end

local function tagTitle(group, novelMode)
  local title = TAG_TITLES[group]
  if novelMode and group == "fandom" then
    title = title .. " (Fanfic tags; Isekai, Smut and Ecchi also work for Novels)"
  end
  return title .. " — tap once to include, twice to exclude"
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function absUrl(href, base)
  base = base or baseUrl
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(base, href)
end

-- Primeros n elementos de una lista.
local function firstN(list, n)
  local out = {}
  for i = 1, math.min(#list, n) do out[i] = list[i] end
  return out
end

-- Las tarjetas HTML traen /book/{slug}_{id}; las APIs JSON solo traen el id. Todo se
-- unifica en /book/{id} en www (el sitio lo resuelve igual sin slug, confirmado en el source
-- de fanfic) para que un mismo libro no quede con dos URLs según de dónde salió, ni con la
-- URL del host móvil (la app asocia cada URL al source cuyo baseUrl la contiene).
--
-- OJO: aquí se usan patrones de Lua (string.match) y NO regex_match: el regex_match del
-- motor devuelve las coincidencias COMPLETAS, no los grupos de captura (y una tabla vacía
-- si no hay ninguna), así que m[1] sería "/book/slug_123…" y no el id.
local function bookUrlFromHref(href)
  href = tostring(href or "")
  if href == "" then return "" end
  local path = (href:gsub("[?#].*$", ""))   -- sin query ni fragmento
  local id = path:match("/book/[^/]*_(%d%d%d%d%d%d%d%d+)/?$")   -- /book/{slug}_{id}
          or path:match("/book/(%d%d%d%d%d%d%d%d+)/?$")         -- /book/{id}
  if id then return WWW_BASE .. "book/" .. id end
  return absUrl(href, WWW_BASE)
end

-- "4.57" a partir de un texto que puede traer más cosas (estrellas, espacios…).
local function ratingFromText(t)
  t = tostring(t or "")
  return t:match("%d+%.%d+") or t:match("%d+") or ""
end

-- La portada real va en data-original; src suele ser un placeholder genérico igual en
-- todas las tarjetas. Se descartan los data: URI.
local function pickCover(scopeHtml, selector)
  for _, attr in ipairs({ "data-original", "data-src", "src" }) do
    local v = html_attr(scopeHtml, selector, attr)
    if v ~= "" and not string_starts_with(v, "data:") then return absUrl(v, WWW_BASE) end
  end
  return ""
end

-- Acumula libros sin repetir (por URL). Devuelve la lista y la función para agregar.
local function newCollector()
  local items, seen = {}, {}
  local function add(title, href, cover, rating)
    title = string_clean(title or "")
    local url = bookUrlFromHref(href)
    if title == "" or url == "" or seen[url] then return end
    seen[url] = true
    local item = { title = title, url = url, cover = cover or "" }
    if rating and rating ~= "" then item.rating = rating end
    table.insert(items, item)
  end
  return items, add
end

-- Cache de la página de detalle del libro: el motor llama a getBookTitle/Cover/
-- Description/Genres/Rating en paralelo con la misma URL; el cache evita pedidos repetidos.
local _bookCache = {}

local function fetchBookPage(bookUrl)
  if _bookCache[bookUrl] then return _bookCache[bookUrl] end
  local r = http_get(bookUrl)
  if not r.success then return nil end
  _bookCache[bookUrl] = r.body
  return r.body
end

-- Deja la URL del libro limpia para armar "<url>/catalog": sin query, sin
-- fragmento, sin "/" final y sin un "/catalog" ya puesto.
local function cleanBookUrl(u)
  u = tostring(u or "")
  u = regex_replace(u, "[?#].*$", "")
  u = regex_replace(u, "/+$", "")
  u = regex_replace(u, "/catalog$", "")
  return u
end

-- Token CSRF del MISMO host que recibe la petición. Si no hay cookie no se manda nada:
-- categoryAjax responde bien sin token.
local function cookieToken(base)
  local cookies = get_cookies(base)
  local token = cookies and cookies["_csrfToken"]
  if token and token ~= "" then return token end
  return ""
end

-- get-search-list pide _csrfToken como query param ("double submit cookie": el servidor
-- lo entrega como cookie a cualquier visitante y espera recibirlo igual en la URL).
-- Si todavía no hay cookie (primer uso) se hace un pedido liviano para conseguirla; la
-- cookie es del host, así que sirve para los dos modos. La primera página es la que ya
-- se confirmó en el source de fanfic.
-- No se usa ningún token fijo: el del navegador es de sesión y caduca.
local function ensureCsrfToken()
  local cookies = get_cookies(M_BASE)
  local token = cookies and cookies["_csrfToken"]
  if token and token ~= "" then return token end
  for _, warm in ipairs({ M_BASE .. "stories/fanfic-anime-comics", M_BASE .. "stories/novel", M_BASE }) do
    http_get(warm)
    cookies = get_cookies(M_BASE)
    token = cookies and cookies["_csrfToken"]
    if token and token ~= "" then return token end
  end
  return ""
end

local function applyStandardContentTransforms(text)
  if not text or text == "" then return "" end
  text = string_normalize(text)
  text = regex_replace(text, "(?i)webnovel\\.com.*?\\n", "")
  text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+[^\\n\\r]*)[\\n\\r\\s]*)+", "")
  text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
  -- Solo líneas que SON un marcador de fin: [End], [THE END], [Chapter End],
  -- [End of Chapter 12 ...]. La versión anterior borraba cualquier línea entre
  -- corchetes que contuviera "end" en cualquier parte: "[Endurance +2]",
  -- "[Defend]" o "[Legend]" (ventanas de sistema típicas en fanfics) se perdían.
  text = regex_replace(text, "(?im)^\\s*\\[\\s*(?:the\\s+|chapter\\s+)?end(?:\\s+of\\b[^\\]\\n]*)?\\s*\\]\\s*(\\r?\\n|$)", "")
  text = string_trim(text)
  text = regex_replace(text, "\\n{3,}", "\n\n")
  return text
end

-- ── Parsers ───────────────────────────────────────────────────────────────────

-- Tarjetas de las páginas de listado (/stories/novel*, /stories/fanfic-*): li dentro de
-- .j_category_wrapper → .g_thumb[title][href], rating en el primer strong de p.df.aic
-- (estructura que ya usaban los dos sources). Si el sitio cambia el contenedor, respaldo
-- genérico: cualquier li con un a.g_thumb (misma tarjeta que usan la búsqueda y los tags).
local function parseStoriesPage(html)
  local items, add = newCollector()
  for _, li in ipairs(html_select(html, ".j_category_wrapper li")) do
    local gt = html_select_first(li.html, ".g_thumb")
    if gt then
      local rs = html_select_first(li.html, "p.df.aic strong span")
      add(gt.title, gt.href, pickCover(li.html, ".g_thumb img"), rs and ratingFromText(rs.text))
    end
  end
  if #items > 0 then return items end

  for _, li in ipairs(html_select(html, "li")) do
    local gt = html_select_first(li.html, "a.g_thumb[href]")
    if gt then
      local rs = html_select_first(li.html, ".g_star_num")
      add(gt.title, gt.href, pickCover(li.html, ".g_thumb img"), rs and ratingFromText(rs.text))
    end
  end
  return items
end

-- Página de tag (/tags/{tag}-novel en www.webnovel.com): tarjetas .g_book_item →
-- a.c_000[href][title], portada en .g_thumb img[data-original], rating en .g_star_num small
-- (estructura confirmada en el source de fanfic; las novelas usan la misma plantilla).
-- Si no calza, se prueba con la tarjeta genérica de parseStoriesPage.
local function parseTagPage(html)
  local items, add = newCollector()
  for _, item in ipairs(html_select(html, ".g_book_item")) do
    local a = html_select_first(item.html, "a.c_000[href]")
    if a then
      local rs = html_select_first(item.html, ".g_star_num small")
      add(a.title, a.href, pickCover(item.html, ".g_thumb img"), rs and ratingFromText(rs.text))
    end
  end
  if #items > 0 then return items end
  return parseStoriesPage(html)
end

-- Respuesta de go/pcm/search/get-search-list: data.bookInfos[] trae bookId/bookName/
-- totalScore/coverUpdateTime pero NO un slug ni una URL de portada armada; ambas se
-- construyen a mano. data.last=false indica que hay más páginas.
local function parseSearchListJson(body)
  local data = json_parse(body)
  if not data then return {}, false, "la respuesta no es JSON" end
  if data.code ~= 0 or not data.data then
    return {}, false, "code=" .. tostring(data.code) .. " msg=" .. tostring(data.msg)
  end
  local d = data.data
  local items = {}
  for _, b in ipairs(d.bookInfos or {}) do
    local bookId = tostring(b.bookId or "")
    if bookId ~= "" then
      local item = {
        title = string_clean(b.bookName or ""),
        url   = WWW_BASE .. "book/" .. bookId,
        cover = absUrl("//book-pic.webnovel.com/bookcover/" .. bookId
                .. "?imageMogr2/thumbnail/150x&imageId=" .. tostring(b.coverUpdateTime or ""), WWW_BASE),
      }
      if b.totalScore and b.totalScore ~= 0 then
        item.rating = tostring(b.totalScore)
      end
      table.insert(items, item)
    end
  end
  -- una página vacía nunca tiene "siguiente" (evita paginar en bucle si falta "last")
  local hasNext = #items > 0 and d.last ~= true
  return items, hasNext, nil
end

-- Respuesta de go/pcm/category/categoryAjax: data.items[] trae bookId (string), bookName,
-- totalScore, coverUpdateTime…; data.isLast es 0/1. El bloque data.categoryItems es ruido
-- y se ignora. La URL del libro es /book/{id} y la portada se arma con bookId + coverUpdateTime.
local function parseCategoryJson(body)
  local data = json_parse(body)
  if not data then return {}, false, "la respuesta no es JSON" end
  if data.code ~= 0 or not data.data then
    return {}, false, "code=" .. tostring(data.code) .. " msg=" .. tostring(data.msg)
  end
  local d = data.data
  local items = {}
  for _, b in ipairs(d.items or {}) do
    local bookId = tostring(b.bookId or "")
    local title  = string_clean(b.bookName or "")
    if bookId ~= "" and title ~= "" then
      local item = {
        title = title,
        url   = WWW_BASE .. "book/" .. bookId,
        cover = absUrl("//book-pic.webnovel.com/bookcover/" .. bookId
                .. "?imageMogr2/thumbnail/150x&imageId=" .. tostring(b.coverUpdateTime or ""), WWW_BASE),
      }
      if b.totalScore and b.totalScore ~= 0 then
        item.rating = tostring(b.totalScore)
      end
      table.insert(items, item)
    end
  end
  local isLast = (d.isLast == 1 or d.isLast == true)
  return items, (#items > 0 and not isLast), nil
end

-- ── Peticiones ────────────────────────────────────────────────────────────────

-- GET a categoryAjax. Devuelve { items, hasNext } o nil si la petición/JSON falló
-- (una lista vacía pero válida NO es un fallo: es "sin resultados").
-- Parámetros: categoryId (0 = todo el modo; en fanfic también 81001–81009), categoryType
-- (1 novelas / 4 fanfics), bookStatus (0 todos, 2 completado, 1 en curso) y orderBy
-- (ver CATEGORY_ORDER).
local function fetchCategoryApi(mode, page, categoryId, status, orderBy)
  local url = WWW_BASE .. "go/pcm/category/categoryAjax?"
  local token = cookieToken(WWW_BASE)
  if token ~= "" then url = url .. "_csrfToken=" .. url_encode(token) .. "&" end
  url = url .. "pageIndex=" .. tostring(page)
             .. "&categoryId=" .. url_encode(categoryId)
             .. "&categoryType=" .. CATEGORY_TYPE[mode]
             .. "&bookStatus=" .. url_encode(status)
             .. "&orderBy=" .. url_encode(orderBy)

  local r = http_get(url, {
    headers = {
      ["Accept"]           = "application/json",
      ["X-Requested-With"] = "XMLHttpRequest",
    }
  })
  if not r.success then
    log_error("webnovel[" .. mode .. "]: categoryAjax HTTP " .. tostring(r.code) .. " (página " .. tostring(page) .. ")")
    return nil
  end
  local items, hasNext, err = parseCategoryJson(r.body)
  if err then
    log_error("webnovel[" .. mode .. "]: categoryAjax " .. err .. " (página " .. tostring(page) .. ")")
    return nil
  end
  return { items = items, hasNext = hasNext }
end

-- GET a get-search-list (buscador avanzado, el único que respeta tags incluidos/excluidos).
-- chapterNum "0" = sin filtro; "1" / "2" / "3" = menos de 300 / 300–1000 / más de 1000
-- (solo se manda en modo novel).
local function fetchFilteredApi(mode, page, sex, tagsInc, tagsExc, status, order, chapterNum)
  local token = ensureCsrfToken()
  local url = M_BASE .. "go/pcm/search/get-search-list"
             .. "?_csrfToken=" .. url_encode(token)
             .. "&sex=" .. url_encode(sex)
             .. "&categoryType=" .. CATEGORY_TYPE[mode]
  if #tagsInc > 0 then
    url = url .. "&tagId=" .. url_encode(table.concat(tagsInc, ","))
  end
  if #tagsExc > 0 then
    url = url .. "&negTagId=" .. url_encode(table.concat(tagsExc, ","))
  end
  url = url .. "&bookStatus=" .. url_encode(status)
  -- Popular es el default: orderBy solo se manda al elegir otra pestaña.
  if order ~= "1" then
    url = url .. "&orderBy=" .. url_encode(order)
  end
  url = url .. "&newChapterTime=0&pageIndex=" .. tostring(page)
  if chapterNum and chapterNum ~= "0" then
    url = url .. "&chapterNum=" .. url_encode(chapterNum)
  end

  local r = http_get(url, {
    headers = {
      ["Accept"]           = "application/json",
      ["X-Requested-With"] = "XMLHttpRequest",
    }
  })
  if not r.success then
    log_error("webnovel[" .. mode .. "]: get-search-list HTTP " .. tostring(r.code) .. " (página " .. tostring(page) .. ")")
    return nil
  end
  local items, hasNext, err = parseSearchListJson(r.body)
  if err then
    log_error("webnovel[" .. mode .. "]: get-search-list " .. err .. " (página " .. tostring(page) .. ")")
    return nil
  end
  return { items = items, hasNext = hasNext }
end

-- Página HTML de listado de novelas: /stories/novel o /stories/novel-{género}-{audiencia}.
-- sourceType: 0 todos, 1 traducidas, 2 originales; MTL (3) pide translateMode=3&sourceType=1.
local function fetchStoriesHtml(genrePath, page, orderBy, status, ctype)
  local url = WWW_BASE .. "stories/" .. genrePath
             .. "?orderBy=" .. url_encode(orderBy)
             .. "&bookStatus=" .. url_encode(status)
             .. "&pageIndex=" .. tostring(page)
  if ctype == "3" then
    url = url .. "&translateMode=3&sourceType=1"
  else
    url = url .. "&sourceType=" .. url_encode(ctype)
  end

  local r = http_get(url)
  if not r.success then
    log_error("webnovel[novel]: HTML HTTP " .. tostring(r.code) .. " en " .. url)
    return { items = {}, hasNext = false }
  end
  local items = parseStoriesPage(r.body)
  return { items = items, hasNext = #items >= FULL_PAGE }
end

-- Respaldo HTML de fanfic: m.webnovel.com/stories/fanfic-anime-comics (confirmada en el source
-- de fanfic). Ignora el orden (sus pestañas Popular/New son widgets de JS), así que siempre
-- es Popular, y solo cubre la sección Anime & Comics.
local function fetchFanficHtml(page, status)
  local url = M_BASE .. "stories/fanfic-anime-comics?orderBy=1"
             .. "&bookStatus=" .. url_encode(status)
             .. "&pageIndex=" .. tostring(page)
  local r = http_get(url)
  if not r.success then
    log_error("webnovel[fanfic]: HTML HTTP " .. tostring(r.code) .. " en " .. url)
    return { items = {}, hasNext = false }
  end
  local items = parseStoriesPage(r.body)
  return { items = items, hasNext = #items >= FULL_PAGE }
end

-- ── Catálogo ──────────────────────────────────────────────────────────────────
-- Al abrir el source: categoryAjax con "Popular" para el modo guardado (la API que alimenta
-- las pestañas de www.webnovel.com/stories/novel y /stories/fanfic), 20 libros por página.
-- Si falla, o si la primera página llega vacía (algo anómalo en "todo el modo"), se usa la
-- página HTML de listado.

function getCatalogList(index)
  local page = index + 1
  local mode = getMode()

  local res = fetchCategoryApi(mode, page, "0", "0", CATEGORY_ORDER.popular)
  if res and (#res.items > 0 or page > 1) then return res end
  log_info("webnovel[" .. mode .. "]: categoryAjax sin datos; se usa la página HTML de respaldo")

  if mode == "fanfic" then return fetchFanficHtml(page, "0") end
  return fetchStoriesHtml("novel", page, CATEGORY_ORDER.popular, "0", "0")
end

-- ── Búsqueda ──────────────────────────────────────────────────────────────────
-- "keywords" (plural) es lo que funciona en peticiones HTTP crudas. En modo fanfic se agrega
-- type=fanfic y se consulta el host móvil, como hacía el source de fanfic. Las dos
-- páginas usan la misma tarjeta; las URLs de libro se normalizan a www en ambos casos.

function getCatalogSearch(index, query)
  local page = index + 1
  local url
  if getMode() == "fanfic" then
    url = M_BASE .. "search?keywords=" .. url_encode(query) .. "&type=fanfic&pageIndex=" .. tostring(page)
  else
    url = WWW_BASE .. "search?keywords=" .. url_encode(query) .. "&pageIndex=" .. tostring(page)
  end
  local r = http_get(url)
  if not r.success then return { items = {}, hasNext = false } end

  local items, add = newCollector()
  for _, li in ipairs(html_select(r.body, ".j_list_container li")) do
    local h3a = html_select_first(li.html, "h3 a")
    if h3a then
      local rs = html_select_first(li.html, ".g_star_num")
      add(h3a.text, h3a.href, pickCover(li.html, "a.g_thumb img"), rs and ratingFromText(rs.text))
    end
  end

  return { items = items, hasNext = #items >= FULL_PAGE }
end

-- ── Ajustes (FUERA del catálogo) ──────────────────────────────────────────────
-- Aparece como engranaje junto a este source en la lista de catálogos. Con dos opciones la
-- app lo dibuja como dos botones. Escribe la preferencia directamente (mismo almacén que
-- get_preference / set_preference), por eso el filtro "Mode" de dentro y este ajuste
-- siempre muestran lo mismo.

function getSettingsSchema()
  return {
    {
      key     = PREF_MODE,
      type    = "select",
      label   = "Mode",
      current = getMode(),
      options = {
        { value = "novel",  label = "Novels" },
        { value = "fanfic", label = "Fanfic" },
      },
    },
  }
end

-- ── Filtros (DENTRO del catálogo) ─────────────────────────────────────────────
-- La app carga esta lista una vez al abrir el catálogo, así que los filtros incluyen las
-- cinco categorías de tags para cualquier modo: cambiar "Mode" dentro del panel funciona de
-- inmediato, sin volver a abrir el source. Lo único que depende del modo guardado AL ABRIR es
-- el orden (lo relevante primero) y las marcas "(F)" de modo novel.
-- Cada categoría de tags es un filtro "tristate": una vez incluye el tag, dos lo excluye.
-- getCatalogFiltered junta los include/exclude de las categorías en una sola lista antes de
-- pegarle a la API, porque a la API no le importa de qué categoría vino cada tag.

function getFilterList()
  local mode = getMode()
  local novelMode = (mode == "novel")

  local list = {
    {
      type         = "select",
      key          = "mode",
      label        = novelMode and "Mode (in Novel mode, tags marked (F) are Fanfic-only)" or "Mode",
      defaultValue = mode,
      options = {
        { value = "novel",  label = "Novels" },
        { value = "fanfic", label = "Fanfic" },
      }
    },
    {
      type         = "select",
      key          = "sort",
      label        = "Sort by (Recommended and Rating: without tags only)",
      defaultValue = "popular",
      options = {
        { value = "popular",     label = "Popular"          },
        { value = "recommended", label = "Recommended"      },
        { value = "collections", label = "Most Collections" },
        { value = "rating",      label = "Rating"           },
        { value = "updated",     label = "Time Updated"     },
      }
    },
    {
      type         = "select",
      key          = "status",
      label        = "Status",
      defaultValue = "0",
      options = {
        { value = "0", label = "All"       },
        { value = "2", label = "Completed" },
        { value = "1", label = "Ongoing"   },
      }
    },
    {
      type         = "select",
      key          = "sex",
      label        = "Audience (with tags, only this audience is searched; Novel genres use it too)",
      defaultValue = "1",
      options = {
        { value = "1", label = "Male — More Fantasy"   },
        { value = "2", label = "Female — More Romance" },
      }
    },
  }

  local novelOnly = {
    {
      type         = "select",
      key          = "chapters",
      label        = "Chapters (Novel mode, advanced search)",
      defaultValue = "0",
      options = {
        { value = "0", label = "Any"        },
        { value = "1", label = "Under 300"  },
        { value = "2", label = "300 – 1000" },
        { value = "3", label = "Over 1000"  },
      }
    },
    {
      type         = "select",
      key          = "genres_male",
      label        = "Male genres (Novel mode, without tags)",
      defaultValue = "all",
      options      = listOptions(MALE_GENRES, "all"),
    },
    {
      type         = "select",
      key          = "genres_female",
      label        = "Female genres (Novel mode, without tags)",
      defaultValue = "all",
      options      = listOptions(FEMALE_GENRES, "all"),
    },
    {
      type         = "select",
      key          = "type",
      label        = "Content type (Novel mode, without tags)",
      defaultValue = "0",
      options = {
        { value = "0", label = "All"                       },
        { value = "1", label = "Translate"                 },
        { value = "2", label = "Original"                  },
        { value = "3", label = "MTL (Machine Translation)" },
      }
    },
  }

  local fanficOnly = {
    {
      type         = "select",
      key          = "category",
      label        = "Fanfic category (Fanfic mode, without tags)",
      defaultValue = "0",
      options      = listOptions(FANFIC_CATEGORIES, "0"),
    },
  }

  -- lo del modo guardado primero
  local first, second = fanficOnly, novelOnly
  if novelMode then first, second = novelOnly, fanficOnly end
  for _, f in ipairs(first) do table.insert(list, f) end
  for _, f in ipairs(second) do table.insert(list, f) end

  for _, g in ipairs(novelMode and TAG_ORDER_NOVEL or TAG_ORDER_FANFIC) do
    table.insert(list, {
      type    = "tristate",
      key     = "tags_" .. g,
      label   = tagTitle(g, novelMode),
      options = tagOptions(g, novelMode),
    })
  end

  return list
end

-- ── Catálogo con filtros ──────────────────────────────────────────────────────
-- El modo sale del filtro "Mode" (si falta o es desconocido, del guardado). Si es distinto del
-- guardado se guarda con set_preference: así el catálogo inicial, la búsqueda y la próxima
-- apertura del panel siguen el cambio hecho desde dentro.
--
-- Caminos, según lo que se haya elegido (cada API numera "orderBy" a su manera):
--   * CON tags incluidos/excluidos → get-search-list (categoryType 1 o 4). Solo ofrece
--     Popular / Most collections / Time updated; "Recommended" y "Rating" no existen ahí y
--     se cambian a Popular. Usa audiencia (sex), estado y —solo en novel— número de capítulos;
--     ignora género, tipo y categoría. En novel, si la API falla y hay al menos un tag
--     incluido, respaldo: la página del primer tag incluido (/tags/{tag}-novel), que no
--     admite varios tags, exclusiones ni capítulos.
--   * Modo novel, SIN tags pero con filtro de capítulos → se intenta get-search-list sin tags
--     (la página de búsqueda avanzada es el único lugar del sitio con ese filtro). Si la API no
--     admite una lista vacía de tags (falla o la 1ª página llega vacía), se sigue con los
--     caminos de abajo y el filtro de capítulos se ignora.
--   * Modo fanfic, SIN tags → categoryAjax con la subcategoría elegida (respaldo: HTML).
--   * Modo novel, SIN tags → categoryAjax (todas) o, con género o tipo, la página HTML
--     /stories/novel[-{género}-{audiencia}].
-- El estado (bookStatus: 0 todos, 2 completado, 1 en curso) funciona en todos.

function getCatalogFiltered(index, filters)
  local page = index + 1

  -- modo (cambio desde dentro)
  local mode = tostring(filters["mode"] or "")
  if mode ~= "novel" and mode ~= "fanfic" then mode = getMode() end
  if mode ~= getMode() then
    set_preference(PREF_MODE, mode)
    log_info("webnovel: modo cambiado a '" .. mode .. "' desde el filtro")
  end

  -- audiencia: 1 = hombres, 2 = mujeres (en get-search-list se llama "sex")
  local sex = tostring(filters["sex"] or "1")
  if sex ~= "2" then sex = "1" end

  local function mergeAll(suffix)
    local out = {}
    for _, cat in ipairs(TAG_ORDER_FANFIC) do
      local arr = filters["tags_" .. cat .. suffix] or {}
      for _, v in ipairs(arr) do
        v = tostring(v)
        if v:match("^%d+$") then table.insert(out, v) end
      end
    end
    return out
  end
  local tagsInc = mergeAll("_included")
  local tagsExc = mergeAll("_excluded")

  -- valores numéricos / conocidos (van directo a la URL)
  local status = tostring(filters["status"] or "0")
  if not status:match("^%d+$") then status = "0" end

  -- clave neutra del orden; un valor viejo/desconocido cae a Popular
  local sortKey = tostring(filters["sort"] or "popular")
  sortKey = LEGACY_SORT[sortKey] or sortKey
  if not CATEGORY_ORDER[sortKey] then sortKey = "popular" end

  -- número de capítulos: solo existe en la búsqueda avanzada de novelas
  local chapterNum = "0"
  if mode == "novel" then
    chapterNum = tostring(filters["chapters"] or "0")
    if not chapterNum:match("^[1-3]$") then chapterNum = "0" end
  end

  -- 1) Búsqueda avanzada: con tags, o (solo novel) sin tags pero con filtro de capítulos
  local hasTags = (#tagsInc > 0 or #tagsExc > 0)
  if hasTags or chapterNum ~= "0" then
    local order = SEARCH_ORDER[sortKey]
    if not order then
      order = SEARCH_ORDER.popular
      log_info("webnovel[" .. mode .. "]: '" .. sortKey .. "' no existe en la búsqueda avanzada; se usa Popular")
    end
    local res = fetchFilteredApi(mode, page, sex, tagsInc, tagsExc, status, order, chapterNum)

    if not res and (#tagsInc > MAX_TAGS or #tagsExc > MAX_TAGS) then
      log_info("webnovel[" .. mode .. "]: la API rechazó " .. #tagsInc .. " tags incluidos / " .. #tagsExc
               .. " excluidos; se reintenta con los primeros " .. MAX_TAGS .. " de cada lista")
      tagsInc, tagsExc = firstN(tagsInc, MAX_TAGS), firstN(tagsExc, MAX_TAGS)
      res = fetchFilteredApi(mode, page, sex, tagsInc, tagsExc, status, order, chapterNum)
    end

    if hasTags then
      -- con tags, get-search-list es la única fuente que los respeta; una lista vacía es
      -- "sin resultados" y se devuelve tal cual
      if res then return res end

      -- respaldo solo en novel: los nombres de página /tags/ solo se conocen para sus tags
      local slug = (mode == "novel" and #tagsInc > 0) and NOVEL_TAG[tagsInc[1]] or nil
      if slug then
        log_info("webnovel[novel]: get-search-list falló; respaldo con /tags/" .. slug .. "-novel (un solo tag, sin exclusiones ni capítulos)")
        local r = http_get(WWW_BASE .. "tags/" .. slug .. "-novel?pageIndex=" .. tostring(page))
        if r.success then
          local items = parseTagPage(r.body)
          return { items = items, hasNext = #items >= FULL_PAGE }
        end
      end
      return { items = {}, hasNext = false }
    end

    -- solo capítulos: si la API no admite "sin tags" (falla o 1ª página vacía) se ignora el filtro
    if res and (#res.items > 0 or page > 1) then return res end
    log_info("webnovel[novel]: get-search-list sin tags no devolvió datos; se ignora el filtro de capítulos")
  end

  -- 2) Fanfic sin tags: categoryAjax con la subcategoría. Una lista vacía pero válida es
  -- "sin resultados" (se devuelve tal cual); solo un fallo real cae a la página HTML.
  if mode == "fanfic" then
    local category = tostring(filters["category"] or "0")
    if not category:match("^%d+$") then category = "0" end
    local res = fetchCategoryApi("fanfic", page, category, status, CATEGORY_ORDER[sortKey])
    if res then return res end
    log_info("webnovel[fanfic]: categoryAjax falló; se usa la página HTML (orden y categoría no aplican)")
    return fetchFanficHtml(page, status)
  end

  -- 3) Novel sin tags: género y tipo de contenido
  local genre = tostring(filters[sex == "1" and "genres_male" or "genres_female"] or "all")
  if not (sex == "1" and MALE_SET or FEMALE_SET)[genre] then genre = "all" end
  local ctype = tostring(filters["type"] or "0")
  if not ctype:match("^[0-3]$") then ctype = "0" end

  if genre == "all" and ctype == "0" then
    local res = fetchCategoryApi("novel", page, "0", status, CATEGORY_ORDER[sortKey])
    if res and (#res.items > 0 or page > 1) then return res end
    log_info("webnovel[novel]: categoryAjax sin datos; se usa la página HTML (respaldo)")
  end

  local genrePath = "novel"
  if genre ~= "all" then
    genrePath = "novel-" .. genre .. "-" .. (sex == "1" and "male" or "female")
  end
  return fetchStoriesHtml(genrePath, page, CATEGORY_ORDER[sortKey], status, ctype)
end

-- ── Detalle del libro, capítulos y texto ──────────────────────────────────────
-- Iguales en los dos modos: la página de un libro en /book/{slug}_{id} usa la misma
-- plantilla para una novela y para un fanfic. Copiado tal cual del source de fanfic.

function getBookTitle(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local og = html_attr(body, "meta[property='og:title']", "content")
  if og ~= "" then return string_clean(og) end
  local h1 = html_select_first(body, "h1")
  if h1 then return string_clean(h1.text) end
  return nil
end

function getBookCoverImageUrl(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local og = html_attr(body, "meta[property='og:image']", "content")
  if og ~= "" then return absUrl(og) end
  return nil
end

function getBookDescription(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local meta = html_attr(body, "meta[name='description']", "content")
  if meta ~= "" then
    meta = regex_replace(meta, "(?i)^Read\\s+['\"]?.+?['\"]?\\s+Online\\s+for\\s+Free,\\s+written\\s+by\\s+the\\s+author\\s+.+?,\\s+This\\s+book\\s+is\\s+a\\s+\\w+\\s+Novel,\\s+covering\\s+.+?\\s+and\\s+the\\s+synopsis\\s+is:\\s*", "")
    -- respaldo: si la regex exacta no calzó (p.ej. "Sci-Fi Novel", géneros de dos
    -- palabras), cortar todo hasta "the synopsis is:" solo cuando el texto empieza
    -- con "Read" y esa frase aparece en los primeros 300 caracteres
    meta = regex_replace(meta, "(?is)^Read\\s.{0,300}?synopsis\\s+is:\\s*", "")
    meta = string_trim(meta)
    if meta == "" then return nil end
    return meta
  end
  return nil
end

function getBookGenres(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return {} end
  local genres = {}
  for _, a in ipairs(html_select(body, ".m-tags a, .book-info a[href*='/tags/']")) do
    local g = string_trim(a.text)
    if g ~= "" then table.insert(genres, g) end
  end
  return genres
end

-- ── Rating ────────────────────────────────────────────────────────────────────

function getBookRating(bookUrl)
  local body = fetchBookPage(bookUrl)
  if not body then return nil end
  local strong = html_select_first(body, "._score strong")
  if strong then
    local v = string_clean(strong.text)
    if v ~= "" then return v end
    return nil
  end
  -- JSON-LD AggregateRating. Patrón de Lua: el regex_match del motor devuelve la coincidencia
  -- completa, no el grupo de captura.
  local v = body:match('"aggregateRating"%s*:%s*{[^}]-"ratingValue"%s*:%s*"?([%d%.]+)')
  if v and v ~= "" then return v end
  return nil
end

-- ── Lista de capítulos ────────────────────────────────────────────────────────

function getChapterList(bookUrl)
  local catalogUrl = cleanBookUrl(bookUrl) .. "/catalog"
  local r = http_get(catalogUrl)
  if not r.success then
    log_error("webnovel: getChapterList HTTP " .. tostring(r.code) .. " en " .. catalogUrl)
    return {}
  end

  local chapters, seen = {}, {}
  for _, li in ipairs(html_select(r.body, ".content-list li")) do
    local a = html_select_first(li.html, "a[href]")
    if a then
      local href = a.href or ""
      local title = a.title or ""
      if href ~= "" and title ~= "" then
        local url = absUrl(href)
        if not seen[url] then
          seen[url] = true
          local isLocked = html_select_first(li.html, "svg") ~= nil
          if isLocked then
            title = title .. " 🔒"
          end
          table.insert(chapters, {
            title = string_clean(title),
            url   = url,
          })
        end
      end
    end
  end

  if #chapters == 0 then
    log_error("webnovel: 0 capítulos en " .. catalogUrl .. " (body=" .. #r.body .. " bytes)")
  end
  return chapters
end

-- Huella = cantidad de capítulos + URL del último. Va directo con http_get (nunca
-- con caché) para que una actualización se note.
function getChapterListHash(bookUrl)
  local r = http_get(cleanBookUrl(bookUrl) .. "/catalog")
  if not r.success then return nil end
  local lis = html_select(r.body, ".content-list li")
  if #lis == 0 then return nil end
  local lastA = html_select_first(lis[#lis].html, "a[href]")
  if not lastA then return nil end
  return tostring(#lis) .. "|" .. absUrl(lastA.href)
end

-- ── Texto del capítulo ────────────────────────────────────────────────────────

function getChapterText(html, url)
  if not html or html == "" then return "" end
  local cleaned = html_remove(html, "script", "style", ".para-comment", "nav", "header", "footer")
  local el = html_select_first(cleaned, ".cha-words")
  if not el then return "" end
  return applyStandardContentTransforms(html_text(el.html))
end
