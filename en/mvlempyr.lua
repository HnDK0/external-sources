id       = "mvlempyr.com"
name     = "MVLEMPYR"
version  = "1.0.12"
baseUrl  = "https://www.mvlempyr.io"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/mvlempyr.webp"

local chapSite = "https://chap.heliosarchive.online/"

local _pageCache = {}
local _allNovels = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(baseUrl, href)
end

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

local function checkCaptcha(body)
    local titleEl = html_select_first(body, "title")
    if titleEl then
        local title = string_trim(titleEl.text)
        if title == "Attention Required! | Cloudflare" or title == "Just a moment..." then
            return true
        end
    end
    return false
end

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
end

local function mulmod(a, b, m)
    local result = 0
    a = a % m
    b = b % m
    while b > 0 do
        if b % 2 == 1 then
            result = (result + a) % m
        end
        a = (a * 2) % m
        b = math.floor(b / 2)
    end
    return result
end

local function convertNovelId(e)
    local MOD = 1999999997
    local result = 1
    local base = 7 % MOD
    local exp = math.floor(e)
    while exp > 0 do
        if exp % 2 == 1 then
            result = mulmod(result, base, MOD)
        end
        base = mulmod(base, base, MOD)
        exp = math.floor(exp / 2)
    end
    return result
end

local function paginate(data, index)
    local startIdx = index * 20
    local result = {}
    for i = startIdx + 1, math.min(startIdx + 20, #data) do
        table.insert(result, data[i])
    end
    return result
end

local function parseDateTime(dateStr)
    if not dateStr or dateStr == "" then return 0 end
    local y, m, d, h, min, s = dateStr:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return 0 end
    local t = os.time({
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s)
    })
    return (t or 0) * 1000
end

local function novelToItem(novel)
    return {
        title = novel.name,
        url   = baseUrl .. "/" .. novel.path,
        cover = novel.cover
    }
end

-- ── Load all novels from WP REST API ────────────────────────────────────────

local function loadAll()
    local r = http_get(chapSite .. "wp-json/wp/v2/mvl-novels?per_page=10000")
    if not r.success then
        log_error("mvlempyr: failed to load novel list code=" .. tostring(r.code))
        return {}
    end
    local data = json_parse(r.body)
    if not data or type(data) ~= "table" then return {} end

    local novels = {}
    for _, novel in ipairs(data) do
        local novelCode = novel["novel-code"] or ""
        local genres = novel.genre
        if type(genres) == "string" then
            local arr = {}
            for g in genres:gmatch("[^,]+") do table.insert(arr, g) end
            genres = arr
        end
        local tags = novel.tags
        if type(tags) == "string" then
            local arr = {}
            for t in tags:gmatch("[^,]+") do table.insert(arr, t) end
            tags = arr
        end
        table.insert(novels, {
            name         = novel.name or "",
            path         = "novel/" .. (novel.slug or ""),
            cover        = "https://assets.mvlempyr.app/images/600/" .. novelCode .. ".webp",
            avgReview    = tonumber(novel["average-review"]) or 0,
            reviewCount  = tonumber(novel["total-reviews"]) or 0,
            chapterCount = tonumber(novel["total-chapters"]) or 0,
            created      = parseDateTime(novel["createdOn"] or ""),
            genres       = type(genres) == "table" and genres or {},
            tags         = type(tags) == "table" and tags or {},
        })
    end
    return novels
end

local function getAllNovels()
    if _allNovels then return _allNovels end
    _allNovels = loadAll()
    return _allNovels
end

-- ── Fetch chapters from WP REST API ─────────────────────────────────────────

local function fetchAllChapters(novelId)
    local allPosts = {}
    local page = 1
    while true do
        local url = chapSite .. "wp-json/wp/v2/posts?tags=" .. tostring(novelId) .. "&per_page=500&page=" .. page
        local r = http_get(url)
        if not r.success then break end
        local posts = json_parse(r.body)
        if not posts or type(posts) ~= "table" or #posts == 0 then break end
        for _, post in ipairs(posts) do
            table.insert(allPosts, post)
        end
        if #posts < 500 then break end
        page = page + 1
        sleep(200)
    end
    return allPosts
end

local function getNovelIdFromBody(body)
    local el = html_select_first(body, "#novel-code")
    if not el then return nil end
    local code = string_trim(el.text or "")
    if code == "" then return nil end
    local num = tonumber(code)
    if not num then return nil end
    return convertNovelId(num)
end

-- ── Filter and sort logic ───────────────────────────────────────────────────

local function filterAndSort(novels, filters)
    local filtered = {}
    for _, novel in ipairs(novels) do
        local include = true

        if filters then
            local genresExc = filters["genres_excluded"] or {}
            for _, g in ipairs(genresExc) do
                for _, ng in ipairs(novel.genres) do
                    if ng == g then include = false; break end
                end
                if not include then break end
            end

            if include then
                local genresInc = filters["genres_included"] or {}
                for _, g in ipairs(genresInc) do
                    local found = false
                    for _, ng in ipairs(novel.genres) do
                        if ng == g then found = true; break end
                    end
                    if not found then include = false; break end
                end
            end

            if include then
                local tagsExc = filters["tags_excluded"] or {}
                for _, t in ipairs(tagsExc) do
                    for _, nt in ipairs(novel.tags) do
                        if nt == t then include = false; break end
                    end
                    if not include then break end
                end
            end

            if include then
                local tagsInc = filters["tags_included"] or {}
                for _, t in ipairs(tagsInc) do
                    local found = false
                    for _, nt in ipairs(novel.tags) do
                        if nt == t then found = true; break end
                    end
                    if not found then include = false; break end
                end
            end
        end

        if include then
            table.insert(filtered, novel)
        end
    end

    local sortKey = "reviewCount"
    if filters and filters["order"] then
        sortKey = filters["order"]
    end
    table.sort(filtered, function(a, b)
        return (a[sortKey] or 0) > (b[sortKey] or 0)
    end)

    return filtered
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local allNovels = getAllNovels()
    local sorted = filterAndSort(allNovels, nil)
    local items = {}
    for _, n in ipairs(paginate(sorted, index)) do
        table.insert(items, novelToItem(n))
    end
    return { items = items, hasNext = #sorted > (index + 1) * 20 }
end

function getCatalogSearch(index, query)
    local allNovels = getAllNovels()
    local queryLower = query:lower()
    local results = {}
    for _, novel in ipairs(allNovels) do
        if novel.name:lower():find(queryLower, 1, true) then
            table.insert(results, novel)
        end
    end
    local items = {}
    for _, n in ipairs(paginate(results, index)) do
        table.insert(items, novelToItem(n))
    end
    return { items = items, hasNext = #results > (index + 1) * 20 }
end

function getCatalogFiltered(index, filters)
    local allNovels = getAllNovels()
    local sorted = filterAndSort(allNovels, filters)
    local items = {}
    for _, n in ipairs(paginate(sorted, index)) do
        table.insert(items, novelToItem(n))
    end
    return { items = items, hasNext = #sorted > (index + 1) * 20 }
end

-- ── Filters ─────────────────────────────────────────────────────────────────

function getFilterList()
    return {
        {
            type         = "select",
            key          = "order",
            label        = "Order by",
            defaultValue = "reviewCount",
            options = {
                { value = "created",      label = "Latest Added" },
                { value = "avgReview",    label = "Best Rated" },
                { value = "reviewCount",  label = "Most Reviewed" },
                { value = "chapterCount", label = "Chapter Count" },
            }
        },
        {
            type  = "tristate",
            key   = "genres",
            label = "Genres",
            options = {
                { value = "action",         label = "Action" },
                { value = "adult",          label = "Adult" },
                { value = "adventure",      label = "Adventure" },
                { value = "comedy",         label = "Comedy" },
                { value = "drama",          label = "Drama" },
                { value = "ecchi",          label = "Ecchi" },
                { value = "fan-fiction",    label = "Fan-Fiction" },
                { value = "fantasy",        label = "Fantasy" },
                { value = "gender-bender",  label = "Gender Bender" },
                { value = "harem",          label = "Harem" },
                { value = "historical",     label = "Historical" },
                { value = "horror",         label = "Horror" },
                { value = "josei",          label = "Josei" },
                { value = "martial-arts",   label = "Martial Arts" },
                { value = "mature",         label = "Mature" },
                { value = "mecha",          label = "Mecha" },
                { value = "mystery",        label = "Mystery" },
                { value = "psychological",  label = "Psychological" },
                { value = "romance",        label = "Romance" },
                { value = "school-life",    label = "School Life" },
                { value = "sci-fi",         label = "Sci-fi" },
                { value = "seinen",         label = "Seinen" },
                { value = "shoujo",         label = "Shoujo" },
                { value = "shoujo-ai",      label = "Shoujo Ai" },
                { value = "shounen",        label = "Shounen" },
                { value = "shounen-ai",     label = "Shounen Ai" },
                { value = "slice-of-life",  label = "Slice of Life" },
                { value = "smut",           label = "Smut" },
                { value = "sports",         label = "Sports" },
                { value = "supernatural",   label = "Supernatural" },
                { value = "tragedy",        label = "Tragedy" },
                { value = "wuxia",          label = "Wuxia" },
                { value = "xianxia",        label = "Xianxia" },
                { value = "xuanhuan",       label = "Xuanhuan" },
                { value = "yaoi",           label = "Yaoi" },
                { value = "yuri",           label = "Yuri" },
            }
        },
        {
            type  = "tristate",
            key   = "tags",
            label = "Tags",
            options = {
                { value = "abandoned-children", label = "Abandoned Children" },
                { value = "ability-steal", label = "Ability Steal" },
                { value = "absent-parents", label = "Absent Parents" },
                { value = "abusive-characters", label = "Abusive Characters" },
                { value = "academy", label = "Academy" },
                { value = "accelerated-growth", label = "Accelerated Growth" },
                { value = "acting", label = "Acting" },
                { value = "adapted-from-manga", label = "Adapted from Manga" },
                { value = "adapted-from-manhua", label = "Adapted from Manhua" },
                { value = "adapted-to-anime", label = "Adapted to Anime" },
                { value = "adapted-to-drama", label = "Adapted to Drama" },
                { value = "adapted-to-drama-cd", label = "Adapted to Drama CD" },
                { value = "adapted-to-game", label = "Adapted to Game" },
                { value = "adapted-to-manga", label = "Adapted to Manga" },
                { value = "adapted-to-manhua", label = "Adapted to Manhua" },
                { value = "adapted-to-manhwa", label = "Adapted to Manhwa" },
                { value = "adapted-to-movie", label = "Adapted to Movie" },
                { value = "adapted-to-visual-novel", label = "Adapted to Visual Novel" },
                { value = "adopted-children", label = "Adopted Children" },
                { value = "adopted-protagonist", label = "Adopted Protagonist" },
                { value = "adultery", label = "Adultery" },
                { value = "advanced-technology", label = "Advanced technology" },
                { value = "adventurers", label = "Adventurers" },
                { value = "affair", label = "Affair" },
                { value = "age-progression", label = "Age Progression" },
                { value = "age-regression", label = "Age Regression" },
                { value = "aggressive-characters", label = "Aggressive Characters" },
                { value = "alchemy", label = "Alchemy" },
                { value = "aliens", label = "Aliens" },
                { value = "all-girls-school", label = "All-Girls School" },
                { value = "alternate-world", label = "Alternate World" },
                { value = "american-comics", label = "American Comics" },
                { value = "amnesia", label = "Amnesia" },
                { value = "amusement-park", label = "Amusement Park" },
                { value = "an-l", label = "An*l" },
                { value = "ancient-china", label = "Ancient China" },
                { value = "ancient-times", label = "Ancient Times" },
                { value = "androgynous-characters", label = "Androgynous Characters" },
                { value = "androids", label = "Androids" },
                { value = "angels", label = "Angels" },
                { value = "animal-characteristics", label = "Animal Characteristics" },
                { value = "animal-rearing", label = "Animal Rearing" },
                { value = "anti-heo", label = "Anti-Heo" },
                { value = "anti-magic", label = "Anti-Magic" },
                { value = "anti-social-protagonist", label = "Anti-social Protagonist" },
                { value = "antihero-protagonist", label = "Antihero Protagonist" },
                { value = "antique-shop", label = "Antique Shop" },
                { value = "apartment-life", label = "Apartment Life" },
                { value = "apathetic-protagonist", label = "Apathetic Protagonist" },
                { value = "apocalypse", label = "Apocalypse" },
                { value = "appearance-changes", label = "Appearance Changes" },
                { value = "appearance-different-from-actual-age", label = "Appearance Different from Actual Age" },
                { value = "archery", label = "Archery" },
                { value = "aristocracy", label = "Aristocracy" },
                { value = "arms-dealers", label = "Arms Dealers" },
                { value = "army", label = "Army" },
                { value = "army-building", label = "Army Building" },
                { value = "arranged-marriage", label = "Arranged Marriage" },
                { value = "arrogant-characters", label = "Arrogant Characters" },
                { value = "artifact-crafting", label = "Artifact Crafting" },
                { value = "artifacts", label = "Artifacts" },
                { value = "artificial-intelligence", label = "Artificial Intelligence" },
                { value = "artists", label = "Artists" },
                { value = "assassins", label = "Assassins" },
                { value = "astrologers", label = "Astrologers" },
                { value = "autism", label = "Autism" },
                { value = "automatons", label = "Automatons" },
                { value = "average-looking-protagonist", label = "Average-looking Protagonist" },
                { value = "award-winning-work", label = "Award-winning Work" },
                { value = "awkward-protagonist", label = "Awkward Protagonist" },
                { value = "bdsm", label = "BDSM" },
                { value = "bands", label = "Bands" },
                { value = "based-on-a-movie", label = "Based on a Movie" },
                { value = "based-on-a-song", label = "Based on a Song" },
                { value = "based-on-a-tv-show", label = "Based on a TV Show" },
                { value = "based-on-a-video-game", label = "Based on a Video Game" },
                { value = "based-on-a-visual-novel", label = "Based on a Visual Novel" },
                { value = "based-on-an-anime", label = "Based on an Anime" },
                { value = "battle-academy", label = "Battle Academy" },
                { value = "battle-competition", label = "Battle Competition" },
                { value = "beast-companions", label = "Beast Companions" },
                { value = "beastkin", label = "Beastkin" },
                { value = "beasts", label = "Beasts" },
                { value = "beautiful-female-lead", label = "Beautiful Female Lead" },
                { value = "bestiality", label = "Bestiality" },
                { value = "betrayal", label = "Betrayal" },
                { value = "bickering-couple", label = "Bickering Couple" },
                { value = "biochip", label = "Biochip" },
                { value = "bisexual-protagonist", label = "Bisexual Protagonist" },
                { value = "black-belly", label = "Black Belly" },
                { value = "blackmail", label = "Blackmail" },
                { value = "blacksmith", label = "Blacksmith" },
                { value = "blind-dates", label = "Blind Dates" },
                { value = "blind-protagonist", label = "Blind Protagonist" },
                { value = "blood-manipulation", label = "Blood Manipulation" },
                { value = "bloodlines", label = "Bloodlines" },
                { value = "body-swap", label = "Body Swap" },
                { value = "body-tempering", label = "Body Tempering" },
                { value = "body-double", label = "Body-double" },
                { value = "bodyguards", label = "Bodyguards" },
                { value = "books", label = "Books" },
                { value = "bookworm", label = "Bookworm" },
                { value = "boss-subordinate-relationship", label = "Boss-Subordinate Relationship" },
                { value = "brainwashing", label = "Brainwashing" },
                { value = "breast-fetish", label = "Breast Fetish" },
                { value = "broken-engagement", label = "Broken Engagement" },
                { value = "brother-complex", label = "Brother Complex" },
                { value = "brotherhood", label = "Brotherhood" },
                { value = "buddhism", label = "Buddhism" },
                { value = "bullying", label = "Bullying" },
                { value = "business-management", label = "Business Management" },
                { value = "businessmen", label = "Businessmen" },
                { value = "butlers", label = "Butlers" },
                { value = "c-nnilingus", label = "C*nnilingus" },
                { value = "calm-protagonist", label = "Calm Protagonist" },
                { value = "cannibalism", label = "Cannibalism" },
                { value = "card-games", label = "Card Games" },
                { value = "carefree-protagonist", label = "Carefree Protagonist" },
                { value = "caring-protagonist", label = "Caring Protagonist" },
                { value = "cautious-protagonist", label = "Cautious Protagonist" },
                { value = "celebrities", label = "Celebrities" },
                { value = "character-growth", label = "Character Growth" },
                { value = "charismatic-protagonist", label = "Charismatic Protagonist" },
                { value = "charming-protagonist", label = "Charming Protagonist" },
                { value = "chat-rooms", label = "Chat Rooms" },
                { value = "cheats", label = "Cheats" },
                { value = "chefs", label = "Chefs" },
                { value = "child-abuse", label = "Child Abuse" },
                { value = "child-protagonist", label = "Child Protagonist" },
                { value = "childcare", label = "Childcare" },
                { value = "childhood-friends", label = "Childhood Friends" },
                { value = "childhood-love", label = "Childhood Love" },
                { value = "childhood-promise", label = "Childhood Promise" },
                { value = "childish-protagonist", label = "Childish Protagonist" },
                { value = "chuunibyou", label = "Chuunibyou" },
                { value = "clan-building", label = "Clan Building" },
                { value = "classic", label = "Classic" },
                { value = "clever-protagonist", label = "Clever Protagonist" },
                { value = "clingy-lover", label = "Clingy Lover" },
                { value = "clones", label = "Clones" },
                { value = "clubs", label = "Clubs" },
                { value = "clumsy-love-interests", label = "Clumsy Love Interests" },
                { value = "co-workers", label = "Co-Workers" },
                { value = "cohabitation", label = "Cohabitation" },
                { value = "cold-love-interests", label = "Cold Love Interests" },
                { value = "cold-protagonist", label = "Cold Protagonist" },
                { value = "collection-of-short-stories", label = "Collection of Short Stories" },
                { value = "college-university", label = "College/University" },
                { value = "coma", label = "Coma" },
                { value = "comedic-undertone", label = "Comedic Undertone" },
                { value = "coming-of-age", label = "Coming of Age" },
                { value = "complex-family-relationships", label = "Complex Family Relationships" },
                { value = "conditional-power", label = "Conditional Power" },
                { value = "confident-protagonist", label = "Confident Protagonist" },
                { value = "confinement", label = "Confinement" },
                { value = "conflicting-loyalties", label = "Conflicting Loyalties" },
                { value = "contracts", label = "Contracts" },
                { value = "cooking", label = "Cooking" },
                { value = "corruption", label = "Corruption" },
                { value = "cosmic-wars", label = "Cosmic Wars" },
                { value = "cosplay", label = "Cosplay" },
                { value = "couple-growth", label = "Couple Growth" },
                { value = "court-official", label = "Court Official" },
                { value = "cousins", label = "Cousins" },
                { value = "cowardly-protagonist", label = "Cowardly Protagonist" },
                { value = "crafting", label = "Crafting" },
                { value = "crime", label = "Crime" },
                { value = "criminals", label = "Criminals" },
                { value = "cross-dressing", label = "Cross-dressing" },
                { value = "crossover", label = "Crossover" },
                { value = "cruel-characters", label = "Cruel Characters" },
                { value = "cryostasis", label = "Cryostasis" },
                { value = "cultivation", label = "Cultivation" },
                { value = "cunning-protagonist", label = "Cunning Protagonist" },
                { value = "curious-protagonist", label = "Curious Protagonist" },
                { value = "curses", label = "Curses" },
                { value = "cute-children", label = "Cute Children" },
                { value = "cute-protagonist", label = "Cute Protagonist" },
                { value = "cute-story", label = "Cute Story" },
                { value = "dc", label = "DC" },
                { value = "dancers", label = "Dancers" },
                { value = "dao-companion", label = "Dao Companion" },
                { value = "dao-comprehension", label = "Dao Comprehension" },
                { value = "daoism", label = "Daoism" },
                { value = "dark", label = "Dark" },
                { value = "dead-protagonist", label = "Dead Protagonist" },
                { value = "death", label = "Death" },
                { value = "death-of-loved-ones", label = "Death of Loved Ones" },
                { value = "debts", label = "Debts" },
                { value = "delinquents", label = "Delinquents" },
                { value = "delusions", label = "Delusions" },
                { value = "demi-humans", label = "Demi-Humans" },
                { value = "demon-lord", label = "Demon Lord" },
                { value = "demonic-cultivation-technique", label = "Demonic Cultivation Technique" },
                { value = "demons", label = "Demons" },
                { value = "dense-protagonist", label = "Dense Protagonist" },
                { value = "depictions-of-cruelty", label = "Depictions of Cruelty" },
                { value = "depression", label = "Depression" },
                { value = "destiny", label = "Destiny" },
                { value = "detectives", label = "Detectives" },
                { value = "determined-protagonist", label = "Determined Protagonist" },
                { value = "devoted-love-interests", label = "Devoted Love Interests" },
                { value = "different-social-status", label = "Different Social Status" },
                { value = "disabilities", label = "Disabilities" },
                { value = "discrimination", label = "Discrimination" },
                { value = "disfigurement", label = "Disfigurement" },
                { value = "dishonest-protagonist", label = "Dishonest Protagonist" },
                { value = "distrustful-protagonist", label = "Distrustful Protagonist" },
                { value = "divination", label = "Divination" },
                { value = "divine-protection", label = "Divine Protection" },
                { value = "divorce", label = "Divorce" },
                { value = "doctors", label = "Doctors" },
                { value = "dolls-puppets", label = "Dolls/Puppets" },
                { value = "domestic-affairs", label = "Domestic Affairs" },
                { value = "doting-love-interests", label = "Doting Love Interests" },
                { value = "doting-older-siblings", label = "Doting Older Siblings" },
                { value = "doting-parents", label = "Doting Parents" },
                { value = "dragon-ball", label = "Dragon Ball" },
                { value = "dragon-riders", label = "Dragon Riders" },
                { value = "dragon-slayers", label = "Dragon Slayers" },
                { value = "dragons", label = "Dragons" },
                { value = "dreams", label = "Dreams" },
                { value = "drugs", label = "Drugs" },
                { value = "druids", label = "Druids" },
                { value = "dungeon-master", label = "Dungeon Master" },
                { value = "dungeons", label = "Dungeons" },
                { value = "dwarfs", label = "Dwarfs" },
                { value = "dystopia", label = "Dystopia" },
                { value = "early-romance", label = "Early Romance" },
                { value = "earth-invasion", label = "Earth Invasion" },
                { value = "easy-going-life", label = "Easy Going Life" },
                { value = "economics", label = "Economics" },
                { value = "editors", label = "Editors" },
                { value = "eidetic-memory", label = "Eidetic Memory" },
                { value = "elderly-protagonist", label = "Elderly Protagonist" },
                { value = "elemental-magic", label = "Elemental Magic" },
                { value = "elves", label = "Elves" },
                { value = "emotionally-weak-protagonist", label = "Emotionally Weak Protagonist" },
                { value = "empires", label = "Empires" },
                { value = "enemies-become-allies", label = "Enemies Become Allies" },
                { value = "enemies-become-lovers", label = "Enemies Become Lovers" },
                { value = "engagement", label = "Engagement" },
                { value = "engineer", label = "Engineer" },
                { value = "enlightenment", label = "Enlightenment" },
                { value = "episodic", label = "Episodic" },
                { value = "eunuch", label = "Eunuch" },
                { value = "european-ambience", label = "European Ambience" },
                { value = "evil-gods", label = "Evil Gods" },
                { value = "evil-organizations", label = "Evil Organizations" },
                { value = "evil-protagonist", label = "Evil Protagonist" },
                { value = "evil-religions", label = "Evil Religions" },
                { value = "evolution", label = "Evolution" },
                { value = "exhibitionism", label = "Exhibitionism" },
                { value = "exorcism", label = "Exorcism" },
                { value = "eye-powers", label = "Eye Powers" },
                { value = "f-llatio", label = "F*llatio" },
                { value = "face-slapping", label = "Face slapping" },
                { value = "fairies", label = "Fairies" },
                { value = "fallen-angels", label = "Fallen Angels" },
                { value = "fallen-nobility", label = "Fallen Nobility" },
                { value = "familial-love", label = "Familial Love" },
                { value = "familiars", label = "Familiars" },
                { value = "family", label = "Family" },
                { value = "family-business", label = "Family Business" },
                { value = "family-conflict", label = "Family Conflict" },
                { value = "famous-parents", label = "Famous Parents" },
                { value = "famous-protagonist", label = "Famous Protagonist" },
                { value = "fanaticism", label = "Fanaticism" },
                { value = "fanfiction", label = "Fanfiction" },
                { value = "fantasy-creatures", label = "Fantasy Creatures" },
                { value = "fantasy-world", label = "Fantasy World" },
                { value = "farming", label = "Farming" },
                { value = "fast-cultivation", label = "Fast Cultivation" },
                { value = "fast-learner", label = "Fast Learner" },
                { value = "fat-protagonist", label = "Fat Protagonist" },
                { value = "fat-to-fit", label = "Fat to Fit" },
                { value = "fated-lovers", label = "Fated Lovers" },
                { value = "fearless-protagonist", label = "Fearless Protagonist" },
                { value = "female-master", label = "Female Master" },
                { value = "female-protagonist", label = "Female Protagonist" },
                { value = "female-to-male", label = "Female to Male" },
                { value = "feng-shui", label = "Feng Shui" },
                { value = "firearms", label = "Firearms" },
                { value = "first-love", label = "First Love" },
                { value = "first-time-interc-rse", label = "First-time Interc**rse" },
                { value = "flashbacks", label = "Flashbacks" },
                { value = "fleet-battles", label = "Fleet Battles" },
                { value = "folklore", label = "Folklore" },
                { value = "forced-living-arrangements", label = "Forced Living Arrangements" },
                { value = "forced-marriage", label = "Forced Marriage" },
                { value = "forced-into-a-relationship", label = "Forced into a Relationship" },
                { value = "forgetful-protagonist", label = "Forgetful Protagonist" },
                { value = "former-hero", label = "Former Hero" },
                { value = "fox-spirits", label = "Fox Spirits" },
                { value = "friends-become-enemies", label = "Friends Become Enemies" },
                { value = "friendship", label = "Friendship" },
                { value = "fujoshi", label = "Fujoshi" },
                { value = "futanari", label = "Futanari" },
                { value = "futuristic-setting", label = "Futuristic Setting" },
                { value = "galge", label = "Galge" },
                { value = "gambling", label = "Gambling" },
                { value = "game-elements", label = "Game Elements" },
                { value = "game-ranking-system", label = "Game Ranking System" },
                { value = "gamers", label = "Gamers" },
                { value = "gangs", label = "Gangs" },
                { value = "gate-to-another-world", label = "Gate to Another World" },
                { value = "genderless-protagonist", label = "Genderless Protagonist" },
                { value = "generals", label = "Generals" },
                { value = "genetic-modifications", label = "Genetic Modifications" },
                { value = "genies", label = "Genies" },
                { value = "genius-protagonist", label = "Genius Protagonist" },
                { value = "ghosts", label = "Ghosts" },
                { value = "gladiators", label = "Gladiators" },
                { value = "glasses-wearing-love-interests", label = "Glasses-wearing Love Interests" },
                { value = "glasses-wearing-protagonist", label = "Glasses-wearing Protagonist" },
                { value = "goblins", label = "Goblins" },
                { value = "god-protagonist", label = "God Protagonist" },
                { value = "god-human-relationship", label = "God-human Relationship" },
                { value = "goddesses", label = "Goddesses" },
                { value = "godly-powers", label = "Godly Powers" },
                { value = "gods", label = "Gods" },
                { value = "golems", label = "Golems" },
                { value = "gore", label = "Gore" },
                { value = "grave-keepers", label = "Grave Keepers" },
                { value = "grinding", label = "Grinding" },
                { value = "guardian-relationship", label = "Guardian Relationship" },
                { value = "guilds", label = "Guilds" },
                { value = "gunfighters", label = "Gunfighters" },
                { value = "h-ndjob", label = "H*ndjob" },
                { value = "hackers", label = "Hackers" },
                { value = "half-human-protagonist", label = "Half-human Protagonist" },
                { value = "handsome-male-lead", label = "Handsome Male Lead" },
                { value = "hard-working-protagonist", label = "Hard-Working Protagonist" },
                { value = "harem-seeking-protagonist", label = "Harem-seeking Protagonist" },
                { value = "harry-potter", label = "Harry Potter" },
                { value = "harsh-training", label = "Harsh Training" },
                { value = "hated-protagonist", label = "Hated Protagonist" },
                { value = "healers", label = "Healers" },
                { value = "heartwarming", label = "Heartwarming" },
                { value = "heaven", label = "Heaven" },
                { value = "heavenly-tribulation", label = "Heavenly Tribulation" },
                { value = "hell", label = "Hell" },
                { value = "helpful-protagonist", label = "Helpful Protagonist" },
                { value = "herbalist", label = "Herbalist" },
                { value = "heroes", label = "Heroes" },
                { value = "heterochromia", label = "Heterochromia" },
                { value = "hidden-abilities", label = "Hidden Abilities" },
                { value = "hiding-true-abilities", label = "Hiding True Abilities" },
                { value = "hiding-true-identity", label = "Hiding True Identity" },
                { value = "hikikomori", label = "Hikikomori" },
                { value = "hollywood", label = "Hollywood" },
                { value = "homunculus", label = "Homunculus" },
                { value = "honest-protagonist", label = "Honest Protagonist" },
                { value = "hospital", label = "Hospital" },
                { value = "hot-blooded-protagonist", label = "Hot-blooded Protagonist" },
                { value = "human-experimentation", label = "Human Experimentation" },
                { value = "human-weapon", label = "Human Weapon" },
                { value = "human-nonhuman-relationship", label = "Human-Nonhuman Relationship" },
                { value = "humanoid-protagonist", label = "Humanoid Protagonist" },
                { value = "hunter-x-hunter", label = "Hunter x Hunter" },
                { value = "hunters", label = "Hunters" },
                { value = "hypnotism", label = "Hypnotism" },
                { value = "identity-crisis", label = "Identity Crisis" },
                { value = "imaginary-friend", label = "Imaginary Friend" },
                { value = "immortals", label = "Immortals" },
                { value = "imperial-harem", label = "Imperial Harem" },
                { value = "incest", label = "Incest" },
                { value = "incubus", label = "Incubus" },
                { value = "indecisive-protagonist", label = "Indecisive Protagonist" },
                { value = "industrialization", label = "Industrialization" },
                { value = "inferiority-complex", label = "Inferiority Complex" },
                { value = "inheritance", label = "Inheritance" },
                { value = "inscriptions", label = "Inscriptions" },
                { value = "insects", label = "Insects" },
                { value = "interconnected-storylines", label = "Interconnected Storylines" },
                { value = "interdimensional-travel", label = "Interdimensional Travel" },
                { value = "introverted-protagonist", label = "Introverted Protagonist" },
                { value = "investigations", label = "Investigations" },
                { value = "invisibility", label = "Invisibility" },
                { value = "jsdf", label = "JSDF" },
                { value = "jack-of-all-trades", label = "Jack of All Trades" },
                { value = "jealousy", label = "Jealousy" },
                { value = "jiangshi", label = "Jiangshi" },
                { value = "jobless-class", label = "Jobless Class" },
                { value = "jujutsu-kaisen", label = "Jujutsu Kaisen" },
                { value = "kidnappings", label = "Kidnappings" },
                { value = "kind-love-interests", label = "Kind Love Interests" },
                { value = "kingdom-building", label = "Kingdom Building" },
                { value = "kingdoms", label = "Kingdoms" },
                { value = "knights", label = "Knights" },
                { value = "kuudere", label = "Kuudere" },
                { value = "lack-of-common-sense", label = "Lack of Common Sense" },
                { value = "language-barrier", label = "Language Barrier" },
                { value = "late-romance", label = "Late Romance" },
                { value = "lawyers", label = "Lawyers" },
                { value = "lazy-protagonist", label = "Lazy Protagonist" },
                { value = "leadership", label = "Leadership" },
                { value = "legends", label = "Legends" },
                { value = "level-system", label = "Level System" },
                { value = "library", label = "Library" },
                { value = "limited-lifespan", label = "Limited Lifespan" },
                { value = "living-abroad", label = "Living Abroad" },
                { value = "living-alone", label = "Living Alone" },
                { value = "loli", label = "Loli" },
                { value = "loneliness", label = "Loneliness" },
                { value = "loner-protagonist", label = "Loner Protagonist" },
                { value = "long-separations", label = "Long Separations" },
                { value = "long-distance-relationship", label = "Long-distance Relationship" },
                { value = "lost-civilizations", label = "Lost Civilizations" },
                { value = "lottery", label = "Lottery" },
                { value = "love-interest-falls-in-love-first", label = "Love Interest Falls in Love First" },
                { value = "love-rivals", label = "Love Rivals" },
                { value = "love-triangles", label = "Love Triangles" },
                { value = "love-at-first-sight", label = "Love at First Sight" },
                { value = "lovers-reunited", label = "Lovers Reunited" },
                { value = "low-key-protagonist", label = "Low-key Protagonist" },
                { value = "loyal-subordinates", label = "Loyal Subordinates" },
                { value = "lucky-protagonist", label = "Lucky Protagonist" },
                { value = "m-sturbation", label = "M*sturbation" },
                { value = "mmorpg", label = "MMORPG" },
                { value = "mafia", label = "Mafia" },
                { value = "magic", label = "Magic" },
                { value = "magic-beasts", label = "Magic Beasts" },
                { value = "magic-formations", label = "Magic Formations" },
                { value = "magical-girls", label = "Magical Girls" },
                { value = "magical-space", label = "Magical Space" },
                { value = "magical-technology", label = "Magical Technology" },
                { value = "maids", label = "Maids" },
                { value = "male-protagonist", label = "Male Protagonist" },
                { value = "male-yandere", label = "Male Yandere" },
                { value = "male-to-female", label = "Male to Female" },
                { value = "management", label = "Management" },
                { value = "mangaka", label = "Mangaka" },
                { value = "manipulative-characters", label = "Manipulative Characters" },
                { value = "manly-gay-couple", label = "Manly Gay Couple" },
                { value = "marriage", label = "Marriage" },
                { value = "marriage-of-convenience", label = "Marriage of Convenience" },
                { value = "martial-spirits", label = "Martial Spirits" },
                { value = "marvel", label = "Marvel" },
                { value = "masochistic-characters", label = "Masochistic Characters" },
                { value = "master-disciple-relationship", label = "Master-Disciple Relationship" },
                { value = "master-servant-relationship", label = "Master-Servant Relationship" },
                { value = "matriarchy", label = "Matriarchy" },
                { value = "mature-protagonist", label = "Mature Protagonist" },
                { value = "medical-knowledge", label = "Medical Knowledge" },
                { value = "medieval", label = "Medieval" },
                { value = "mercenaries", label = "Mercenaries" },
                { value = "merchants", label = "Merchants" },
                { value = "military", label = "Military" },
                { value = "mind-break", label = "Mind Break" },
                { value = "mind-control", label = "Mind Control" },
                { value = "misandry", label = "Misandry" },
                { value = "mismatched-couple", label = "Mismatched Couple" },
                { value = "misunderstandings", label = "Misunderstandings" },
                { value = "mob-protagonist", label = "Mob Protagonist" },
                { value = "models", label = "Models" },
                { value = "modern-day", label = "Modern Day" },
                { value = "modern-knowledge", label = "Modern Knowledge" },
                { value = "money-grubber", label = "Money Grubber" },
                { value = "monster-girls", label = "Monster Girls" },
                { value = "monster-society", label = "Monster Society" },
                { value = "monster-tamer", label = "Monster Tamer" },
                { value = "monsters", label = "Monsters" },
                { value = "movies", label = "Movies" },
                { value = "mpreg", label = "Mpreg" },
                { value = "multiple-identities", label = "Multiple Identities" },
                { value = "multiple-pov", label = "Multiple POV" },
                { value = "multiple-personalities", label = "Multiple Personalities" },
                { value = "multiple-protagonists", label = "Multiple Protagonists" },
                { value = "multiple-realms", label = "Multiple Realms" },
                { value = "multiple-reincarnated-individuals", label = "Multiple Reincarnated Individuals" },
                { value = "multiple-timelines", label = "Multiple Timelines" },
                { value = "multiple-transported-individuals", label = "Multiple Transported Individuals" },
                { value = "murders", label = "Murders" },
                { value = "music", label = "Music" },
                { value = "mutated-creatures", label = "Mutated Creatures" },
                { value = "mutations", label = "Mutations" },
                { value = "mute-character", label = "Mute Character" },
                { value = "mysterious-family-background", label = "Mysterious Family Background" },
                { value = "mysterious-illness", label = "Mysterious Illness" },
                { value = "mysterious-past", label = "Mysterious Past" },
                { value = "mystery-solving", label = "Mystery Solving" },
                { value = "mythical-beasts", label = "Mythical Beasts" },
                { value = "mythology", label = "Mythology" },
                { value = "naive-protagonist", label = "Naive Protagonist" },
                { value = "narcissistic-protagonist", label = "Narcissistic Protagonist" },
                { value = "naruto", label = "Naruto" },
                { value = "nationalism", label = "Nationalism" },
                { value = "near-death-experience", label = "Near-Death Experience" },
                { value = "necromancer", label = "Necromancer" },
                { value = "neet", label = "Neet" },
                { value = "netorare", label = "Netorare" },
                { value = "netorase", label = "Netorase" },
                { value = "netori", label = "Netori" },
                { value = "nightmares", label = "Nightmares" },
                { value = "ninjas", label = "Ninjas" },
                { value = "nobles", label = "Nobles" },
                { value = "non-humanoid-protagonist", label = "Non-humanoid Protagonist" },
                { value = "non-linear-storytelling", label = "Non-linear Storytelling" },
                { value = "not-harem", label = "Not-harem" },
                { value = "nudity", label = "Nudity" },
                { value = "nurses", label = "Nurses" },
                { value = "obsessive-love", label = "Obsessive Love" },
                { value = "office-romance", label = "Office Romance" },
                { value = "older-love-interests", label = "Older Love Interests" },
                { value = "omegaverse", label = "Omegaverse" },
                { value = "one-piece", label = "One Piece" },
                { value = "oneshot", label = "Oneshot" },
                { value = "online-romance", label = "Online Romance" },
                { value = "onmyouji", label = "Onmyouji" },
                { value = "or-y", label = "Or*y" },
                { value = "orcs", label = "Orcs" },
                { value = "organized-crime", label = "Organized Crime" },
                { value = "orphans", label = "Orphans" },
                { value = "otaku", label = "Otaku" },
                { value = "otome-game", label = "Otome Game" },
                { value = "outcasts", label = "Outcasts" },
                { value = "outdoor-interc-rse", label = "Outdoor Interc**rse" },
                { value = "outer-space", label = "Outer Space" },
                { value = "overpowered-protagonist", label = "Overpowered Protagonist" },
                { value = "overprotective-siblings", label = "Overprotective Siblings" },
                { value = "pacifist-protagonist", label = "Pacifist Protagonist" },
                { value = "paizuri", label = "Paizuri" },
                { value = "parallel-worlds", label = "Parallel Worlds" },
                { value = "parasites", label = "Parasites" },
                { value = "parent-complex", label = "Parent Complex" },
                { value = "parody", label = "Parody" },
                { value = "part-time-job", label = "Part-Time Job" },
                { value = "past-plays-a-big-role", label = "Past Plays a Big Role" },
                { value = "past-trauma", label = "Past Trauma" },
                { value = "pe-verted-protagonist", label = "Pe*verted Protagonist" },
                { value = "persistent-love-interests", label = "Persistent Love Interests" },
                { value = "personality-changes", label = "Personality Changes" },
                { value = "pets", label = "Pets" },
                { value = "pharmacist", label = "Pharmacist" },
                { value = "philosophical", label = "Philosophical" },
                { value = "phobias", label = "Phobias" },
                { value = "phoenixes", label = "Phoenixes" },
                { value = "photography", label = "Photography" },
                { value = "pill-based-cultivation", label = "Pill Based Cultivation" },
                { value = "pill-concocting", label = "Pill Concocting" },
                { value = "pilots", label = "Pilots" },
                { value = "pirates", label = "Pirates" },
                { value = "playboys", label = "Playboys" },
                { value = "playful-protagonist", label = "Playful Protagonist" },
                { value = "poetry", label = "Poetry" },
                { value = "poisons", label = "Poisons" },
                { value = "police", label = "Police" },
                { value = "polite-protagonist", label = "Polite Protagonist" },
                { value = "politics", label = "Politics" },
                { value = "polyandry", label = "Polyandry" },
                { value = "polygamy", label = "Polygamy" },
                { value = "poor-protagonist", label = "Poor Protagonist" },
                { value = "poor-to-rich", label = "Poor to Rich" },
                { value = "popular-love-interests", label = "Popular Love Interests" },
                { value = "possession", label = "Possession" },
                { value = "possessive-characters", label = "Possessive Characters" },
                { value = "post-apocalyptic", label = "Post-apocalyptic" },
                { value = "power-couple", label = "Power Couple" },
                { value = "power-struggle", label = "Power Struggle" },
                { value = "pragmatic-protagonist", label = "Pragmatic Protagonist" },
                { value = "precognition", label = "Precognition" },
                { value = "pregnancy", label = "Pregnancy" },
                { value = "pretend-lovers", label = "Pretend Lovers" },
                { value = "previous-life-talent", label = "Previous Life Talent" },
                { value = "priestesses", label = "Priestesses" },
                { value = "priests", label = "Priests" },
                { value = "prison", label = "Prison" },
                { value = "proactive-protagonist", label = "Proactive Protagonist" },
                { value = "programmer", label = "Programmer" },
                { value = "prophecies", label = "Prophecies" },
                { value = "prostit-es", label = "Prostit**es" },
                { value = "protagonist-falls-in-love-first", label = "Protagonist Falls in Love First" },
                { value = "protagonist-strong-from-the-start", label = "Protagonist Strong from the Start" },
                { value = "protagonist-with-multiple-bodies", label = "Protagonist with Multiple Bodies" },
                { value = "psychic-powers", label = "Psychic Powers" },
                { value = "psychopaths", label = "Psychopaths" },
                { value = "puppeteers", label = "Puppeteers" },
                { value = "quiet-characters", label = "Quiet Characters" },
                { value = "quirky-characters", label = "Quirky Characters" },
                { value = "r-pe", label = "R*pe" },
                { value = "r-pe-victim-becomes-lover", label = "R*pe Victim Becomes Lover" },
                { value = "r-15", label = "R-15" },
                { value = "r-18", label = "R-18" },
                { value = "race-change", label = "Race Change" },
                { value = "racism", label = "Racism" },
                { value = "rebellion", label = "Rebellion" },
                { value = "reincarnated-as-a-monster", label = "Reincarnated as a Monster" },
                { value = "reincarnated-as-an-object", label = "Reincarnated as an Object" },
                { value = "reincarnated-in-another-world", label = "Reincarnated in Another World" },
                { value = "reincarnated-in-a-game-world", label = "Reincarnated in a Game World" },
                { value = "reincarnation", label = "Reincarnation" },
                { value = "religions", label = "Religions" },
                { value = "reluctant-protagonist", label = "Reluctant Protagonist" },
                { value = "reporters", label = "Reporters" },
                { value = "restaurant", label = "Restaurant" },
                { value = "resurrection", label = "Resurrection" },
                { value = "returning-from-another-world", label = "Returning from Another World" },
                { value = "revenge", label = "Revenge" },
                { value = "reverse-harem", label = "Reverse Harem" },
                { value = "reverse-r-pe", label = "Reverse R*pe" },
                { value = "reversible-couple", label = "Reversible Couple" },
                { value = "rich-to-poor", label = "Rich to Poor" },
                { value = "righteous-protagonist", label = "Righteous Protagonist" },
                { value = "rivalry", label = "Rivalry" },
                { value = "romantic-subplot", label = "Romantic Subplot" },
                { value = "roommates", label = "Roommates" },
                { value = "royalty", label = "Royalty" },
                { value = "ruthless-protagonist", label = "Ruthless Protagonist" },
                { value = "s-ave-harem", label = "S*ave Harem" },
                { value = "s-ave-protagonist", label = "S*ave Protagonist" },
                { value = "s-aves", label = "S*aves" },
                { value = "s-x-friends", label = "S*x Friends" },
                { value = "s-x-s-aves", label = "S*x S*aves" },
                { value = "s-xual-abuse", label = "S*xual Abuse" },
                { value = "s-xual-cultivation-technique", label = "S*xual Cultivation Technique" },
                { value = "sadistic-characters", label = "Sadistic Characters" },
                { value = "saints", label = "Saints" },
                { value = "salaryman", label = "Salaryman" },
                { value = "samurai", label = "Samurai" },
                { value = "saving-the-world", label = "Saving the World" },
                { value = "schemes-and-conspiracies", label = "Schemes And Conspiracies" },
                { value = "schizophrenia", label = "Schizophrenia" },
                { value = "scientists", label = "Scientists" },
                { value = "sculptors", label = "Sculptors" },
                { value = "sealed-power", label = "Sealed Power" },
                { value = "second-chance", label = "Second Chance" },
                { value = "secret-crush", label = "Secret Crush" },
                { value = "secret-identity", label = "Secret Identity" },
                { value = "secret-organizations", label = "Secret Organizations" },
                { value = "secret-relationship", label = "Secret Relationship" },
                { value = "secretive-protagonist", label = "Secretive Protagonist" },
                { value = "secrets", label = "Secrets" },
                { value = "sect-development", label = "Sect Development" },
                { value = "seduction", label = "Seduction" },
                { value = "seeing-things-other-humans-cant", label = "Seeing Things Other Humans Can't" },
                { value = "selfish-protagonist", label = "Selfish Protagonist" },
                { value = "selfless-protagonist", label = "Selfless Protagonist" },
                { value = "seme-protagonist", label = "Seme Protagonist" },
                { value = "senpai-kouhai-relationship", label = "Senpai-Kouhai Relationship" },
                { value = "sentient-objects", label = "Sentient Objects" },
                { value = "sentimental-protagonist", label = "Sentimental Protagonist" },
                { value = "serial-killers", label = "Serial Killers" },
                { value = "servants", label = "Servants" },
                { value = "seven-deadly-sins", label = "Seven Deadly Sins" },
                { value = "seven-virtues", label = "Seven Virtues" },
                { value = "shameless-protagonist", label = "Shameless Protagonist" },
                { value = "shapeshifters", label = "Shapeshifters" },
                { value = "sharing-a-body", label = "Sharing A Body" },
                { value = "sharp-tongued-characters", label = "Sharp-tongued Characters" },
                { value = "shield-user", label = "Shield User" },
                { value = "shikigami", label = "Shikigami" },
                { value = "short-story", label = "Short Story" },
                { value = "shota", label = "Shota" },
                { value = "shoujo-ai-subplot", label = "Shoujo-Ai Subplot" },
                { value = "shounen-ai-subplot", label = "Shounen-Ai Subplot" },
                { value = "showbiz", label = "Showbiz" },
                { value = "shy-characters", label = "Shy Characters" },
                { value = "sibling-rivalry", label = "Sibling Rivalry" },
                { value = "siblings-care", label = "Sibling's Care" },
                { value = "siblings", label = "Siblings" },
                { value = "siblings-not-related-by-blood", label = "Siblings Not Related by Blood" },
                { value = "sickly-characters", label = "Sickly Characters" },
                { value = "sign-language", label = "Sign Language" },
                { value = "singers", label = "Singers" },
                { value = "single-parent", label = "Single Parent" },
                { value = "sister-complex", label = "Sister Complex" },
                { value = "skill-assimilation", label = "Skill Assimilation" },
                { value = "skill-books", label = "Skill Books" },
                { value = "skill-creation", label = "Skill Creation" },
                { value = "sleeping", label = "Sleeping" },
                { value = "slow-growth-at-start", label = "Slow Growth at Start" },
                { value = "slow-romance", label = "Slow Romance" },
                { value = "smart-couple", label = "Smart Couple" },
                { value = "social-outcasts", label = "Social Outcasts" },
                { value = "soldiers", label = "Soldiers" },
                { value = "soul-power", label = "Soul Power" },
                { value = "souls", label = "Souls" },
                { value = "spatial-manipulation", label = "Spatial Manipulation" },
                { value = "spear-wielder", label = "Spear Wielder" },
                { value = "special-abilities", label = "Special Abilities" },
                { value = "spies", label = "Spies" },
                { value = "spirit-advisor", label = "Spirit Advisor" },
                { value = "spirit-users", label = "Spirit Users" },
                { value = "spirits", label = "Spirits" },
                { value = "stalkers", label = "Stalkers" },
                { value = "stockholm-syndrome", label = "Stockholm Syndrome" },
                { value = "stoic-characters", label = "Stoic Characters" },
                { value = "store-owner", label = "Store Owner" },
                { value = "straight-seme", label = "Straight Seme" },
                { value = "straight-uke", label = "Straight Uke" },
                { value = "strategic-battles", label = "Strategic Battles" },
                { value = "strategist", label = "Strategist" },
                { value = "strength-based-social-hierarchy", label = "Strength-based Social Hierarchy" },
                { value = "strong-background", label = "Strong Background" },
                { value = "strong-love-interests", label = "Strong Love Interests" },
                { value = "strong-to-stronger", label = "Strong to Stronger" },
                { value = "stubborn-protagonist", label = "Stubborn Protagonist" },
                { value = "student-council", label = "Student Council" },
                { value = "student-teacher-relationship", label = "Student-Teacher Relationship" },
                { value = "succubus", label = "Succubus" },
                { value = "sudden-strength-gain", label = "Sudden Strength Gain" },
                { value = "sudden-wealth", label = "Sudden Wealth" },
                { value = "suicides", label = "Suicides" },
                { value = "summoned-hero", label = "Summoned Hero" },
                { value = "summoning-magic", label = "Summoning Magic" },
                { value = "survival", label = "Survival" },
                { value = "survival-game", label = "Survival Game" },
                { value = "sword-and-magic", label = "Sword And Magic" },
                { value = "sword-wielder", label = "Sword Wielder" },
                { value = "system", label = "System" },
                { value = "system-administrator", label = "System Administrator" },
                { value = "teachers", label = "Teachers" },
                { value = "teamwork", label = "Teamwork" },
                { value = "technological-gap", label = "Technological Gap" },
                { value = "tentacles", label = "Tentacles" },
                { value = "terminal-illness", label = "Terminal Illness" },
                { value = "territory-management", label = "Territory Management" },
                { value = "terrorists", label = "Terrorists" },
                { value = "thieves", label = "Thieves" },
                { value = "threesome", label = "Threesome" },
                { value = "thriller", label = "Thriller" },
                { value = "time-loop", label = "Time Loop" },
                { value = "time-manipulation", label = "Time Manipulation" },
                { value = "time-paradox", label = "Time Paradox" },
                { value = "time-skip", label = "Time Skip" },
                { value = "time-travel", label = "Time Travel" },
                { value = "timid-protagonist", label = "Timid Protagonist" },
                { value = "tomboyish-female-lead", label = "Tomboyish Female Lead" },
                { value = "torture", label = "Torture" },
                { value = "toys", label = "Toys" },
                { value = "tragic-past", label = "Tragic Past" },
                { value = "transformation-ability", label = "Transformation Ability" },
                { value = "transmigration", label = "Transmigration" },
                { value = "transplanted-memories", label = "Transplanted Memories" },
                { value = "transported-modern-structure", label = "Transported Modern Structure" },
                { value = "transported-into-a-game-world", label = "Transported into a Game World" },
                { value = "transported-to-another-world", label = "Transported to Another World" },
                { value = "trap", label = "Trap" },
                { value = "tribal-society", label = "Tribal Society" },
                { value = "trickster", label = "Trickster" },
                { value = "tsundere", label = "Tsundere" },
                { value = "twins", label = "Twins" },
                { value = "twisted-personality", label = "Twisted Personality" },
                { value = "ugly-protagonist", label = "Ugly Protagonist" },
                { value = "ugly-to-beautiful", label = "Ugly to Beautiful" },
                { value = "unconditional-love", label = "Unconditional Love" },
                { value = "underestimated-protagonist", label = "Underestimated Protagonist" },
                { value = "unique-cultivation-technique", label = "Unique Cultivation Technique" },
                { value = "unique-weapon-user", label = "Unique Weapon User" },
                { value = "unique-weapons", label = "Unique Weapons" },
                { value = "unlimited-flow", label = "Unlimited Flow" },
                { value = "unlucky-protagonist", label = "Unlucky Protagonist" },
                { value = "unreliable-narrator", label = "Unreliable Narrator" },
                { value = "unrequited-love", label = "Unrequited Love" },
                { value = "valkyries", label = "Valkyries" },
                { value = "vampires", label = "Vampires" },
                { value = "villain", label = "Villain" },
                { value = "villainess-noble-girls", label = "Villainess Noble Girls" },
                { value = "virtual-reality", label = "Virtual Reality" },
                { value = "vocaloid", label = "Vocaloid" },
                { value = "voice-actors", label = "Voice Actors" },
                { value = "voyeurism", label = "Voyeurism" },
                { value = "waiters", label = "Waiters" },
                { value = "war-records", label = "War Records" },
                { value = "wars", label = "Wars" },
                { value = "weak-protagonist", label = "Weak Protagonist" },
                { value = "weak-to-strong", label = "Weak to Strong" },
                { value = "wealthy-characters", label = "Wealthy Characters" },
                { value = "werebeasts", label = "Werebeasts" },
                { value = "wishes", label = "Wishes" },
                { value = "witches", label = "Witches" },
                { value = "wizards", label = "Wizards" },
                { value = "world-hopping", label = "World Hopping" },
                { value = "world-travel", label = "World Travel" },
                { value = "world-tree", label = "World Tree" },
                { value = "writers", label = "Writers" },
                { value = "yandere", label = "Yandere" },
                { value = "youkai", label = "Youkai" },
                { value = "younger-brothers", label = "Younger Brothers" },
                { value = "younger-love-interests", label = "Younger Love Interests" },
                { value = "younger-sisters", label = "Younger Sisters" },
                { value = "zombies", label = "Zombies" },
                { value = "e-sports", label = "e-Sports" },
            }
        },
    }
end

-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    if checkCaptcha(body) then return nil end
    local el = html_select_first(body, "h1.novel-title")
    return el and string_clean(el.text) or "Untitled"
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local cover = html_attr(body, "img.novel-image", "src")
    return cover ~= "" and absUrl(cover) or nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    if checkCaptcha(body) then return nil end
    local el = html_select_first(body, "div.synopsis.w-richtext")
    return el and string_trim(el.text) or nil
end

function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    if checkCaptcha(body) then return {} end
    local genres = {}
    for _, el in ipairs(html_select(body, ".genre-tags")) do
        local label = string_trim(el.text)
        if label ~= "" then table.insert(genres, label) end
    end
    return genres
end

-- ── Chapter list ────────────────────────────────────────────────────────────

function getChapterList(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then
        log_error("mvlempyr: getChapterList failed to fetch " .. bookUrl)
        return {}
    end
    if checkCaptcha(body) then return {} end

    local novelId = getNovelIdFromBody(body)
    if not novelId then
        log_error("mvlempyr: cannot extract novel code from " .. bookUrl)
        return {}
    end

    local posts = fetchAllChapters(novelId)

    local chapters = {}
    for _, chap in ipairs(posts) do
        local acf = chap.acf or {}
        local chName = acf.ch_name or ""
        local novelCode = acf.novel_code or ""
        local chapterNumber = acf.chapter_number or 0
        local path = "chapter/" .. novelCode .. "-" .. tostring(chapterNumber)
        table.insert(chapters, {
            title         = string_clean(chName),
            url           = baseUrl .. "/" .. path,
            releaseTime   = chap.date or "",
            chapterNumber = chapterNumber,
        })
    end

    local reversed = {}
    for i = #chapters, 1, -1 do
        table.insert(reversed, chapters[i])
    end
    return reversed
end

function getChapterListHash(bookUrl)
    local r = http_get(bookUrl)
    if not r.success then return nil end
    local novelId = getNovelIdFromBody(r.body)
    if not novelId then return nil end
    local cr = http_get(chapSite .. "wp-json/wp/v2/posts?tags=" .. tostring(novelId) .. "&orderby=date&order=desc&per_page=1")
    if not cr.success then return nil end
    local posts = json_parse(cr.body)
    if not posts or type(posts) ~= "table" or #posts == 0 then return "0" end
    return posts[1].date or "0"
end

-- ── Chapter text ────────────────────────────────────────────────────────────

function getChapterText(html, url)
    if not html or html == "" then return "" end
    local cleaned = html_remove(html, "script", "style")
    local el = html_select_first(cleaned, "#chapter > span")
    if not el then
        el = html_select_first(cleaned, "#chapter")
    end
    if not el then return "" end
    return applyStandardContentTransforms(html_text(el.html))
end
