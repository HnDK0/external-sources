# Video hosters: реализации и несделанное

Справочник по видео-хостерам: для каждого — либо схема раскрытия до потока и
рабочий Lua-код, либо честная причина, почему он не раскрыт. Хостеры в скобках
после имени в содержании — те, на которых хостер встречается.

Используются функции движка: `http_get`, `http_post`, `http_get_batch`,
`json_parse`/`json_stringify`, `html_select`/`html_attr`, `base64_decode`,
`log_error`/`log_info`. Проверки 2026-10-02…2026-10-05 — по живым ответам.

## Содержание

- 4shared / shared
- abyssplayer (anichin.moe)
- aksor
- alloha
- cdnvideohub (CVH)
- D.Tube
- dailymotion (+ geo.dailymotion)
- direct-scan (прямые m3u8/mp4, cdn-token)
- docs.google (witanime.site, anime-phoenix.com)
- dood / dsvplay / playmogo
- dotplay
- dropbox
- file-upload.org (w1.anime4up.rest)
- gdriveplayer (w1.anime4up.rest)
- google drive
- hentaila CDN (cdn.hvidserv)
- hgcloud
- kodik
- larhu (w1.anime4up.rest)
- listeamed / strwish (anichin.moe)
- Lua-unpacker (packed-JS)
- mail.ru
- mediafire / gofile / terabox / mirrored.to (latanime.org, animexin.dev)
- mega.nz / mega.io (witanime.site, w1.anime4up.rest, anime-phoenix.com, animexin.dev, anichin.moe, latanime.org)
- mixdrop
- mp4upload
- odysee (animexin.dev, anichin.moe)
- ok.ru
- pixeldrain
- racaty.my.id (anichin.moe)
- rpmvid (anichin.moe)
- rubyvidhub / streamruby / rubystm / turbovidhls (anichin.moe, w1.anime4up.rest)
- Rumble
- seekplayer.vip (animexin.dev, w1.anime4up.rest)
- sendvid
- share4max
- short.icu / short.ink (anichin.moe)
- sibnet
- soraplay
- uqload
- uptostream (anime-phoenix.com, w1.anime4up.rest)
- vadbam (w1.anime4up.rest)
- veohentai (hentaiplayer)
- videa.hu
- videas.fr
- vidbom-семейство
- video.vid3rb
- vidhide
- vidmoly
- vidyard
- vkvideo / vk.com
- voe
- window.__P (otaku-embed)
- yonaplay

---

## 4shared / shared

Эмбед `4shared.com` отдаёт прямую ссылку первым тегом `<source src>`.
Protocol-relative дописывается до `https:`, относительный — к базовому URL
эмбеда; Referer источника = эмбед. Заголовки при разборе не нужны.

```lua
-- Эмбед уже загружен: первый <source src> — и есть прямая ссылка.
local function resolveShared(body, entry, candidates)
    local src = html_attr(body, "source", "src")
    if type(src) ~= "string" or src == "" then
        log_error(entry.quality .. " — 4shared: в embed нет <source>")
        return 0
    end
    -- абсолютным делаем только protocol-relative/относительные значения —
    -- иначе плеер их не откроет.
    if not string_starts_with(src, "http") then
        if string_starts_with(src, "//") then
            src = "https:" .. src
        else
            src = url_resolve(entry.link, src)
        end
    end
    candidates[#candidates + 1] = {
        url = src, quality = "4Shared: mirror", referer = entry.link,
    }
    return 1
end
```

## abyssplayer

Домен: `abyssplayer.com`. Что известно: ссылка на медиа в странице шифруется
в `lite.bundle.js` — в HTML прямой ссылки нет. Живьём не проверялся
(проверялось 2026-10-03 при снятии skip-листа).

Сайты: anichin.moe.

Причина: ключ и алгоритм шифрования лежат в бандле плеера; порт не сделан.

## aksor

Домен: `player.aksor.tv`. id = последний сегмент iframe (md5) →
`GET https://player.aksor.tv/api/video/<md5>` с `Accept: application/json` →
`qualities.q1080/q720/q480` → `.mpd`-ссылки; пробелы в путях («SHIZA Project»)
заменяются на `%20`, иначе URL не проходит. Свой GET не делается — тело приходит
общим батчем по API-URL.

```lua
-- Один запрос к api/video/<md5 из iframe_url>; страница заполняет только
-- q1080, остальные качества приходят null.
local AKSOR_QUALITIES = {
    { key = "q1080", label = "1080" },
    { key = "q720",  label = "720" },
    { key = "q480",  label = "480" },
}

local function aksorApiUrl(iframeUrl)
    local md5 = iframeUrl:gsub("[?#].*$", ""):match("([^/]+)$")
    if not md5 or md5 == "" then return nil end
    return "https://player.aksor.tv/api/video/" .. md5
end

local function resolveAksor(iframeUrl, dubbing, page)
    if not aksorApiUrl(iframeUrl) then return nil end
    if type(page) ~= "table" or not page.success then
        log_error("Aksor api " .. tostring(page and page.code))
        return nil
    end
    local data = json_parse(page.body)
    local quals = type(data) == "table" and data.qualities or nil
    if type(quals) ~= "table" then return nil end
    local out = {}
    for _, q in ipairs(AKSOR_QUALITIES) do
        local u = quals[q.key]
        if type(u) == "string" and u ~= "" then
            -- без %20 путь с пробелом не проходит, а .mpd проигрывается
            -- и без заголовков
            local enc = (u:gsub(" ", "%%20"))
            out[#out + 1] = {
                url     = enc,
                quality = "Aksor · " .. dubbing .. " · " .. q.label .. "p",
            }
        end
    end
    return out
end
```

## alloha

Домен: `alloha.yani.tv`. `GET iframe` → `<meta name="viewporti">`, `token`,
`"active":{"id":N}` → заголовок `Borth` = 64 нуля + `|` + перестановки
`borthQ(borthX(borthU(viewporti)))` → `POST https://alloha.yani.tv/bnsi/movies/<id>`
формой `token=…&av1=true&autoplay=0&audio=&subtitle=` → JSON `hlsSource[].quality`.
Хеш-отпечаток `fp` не сверяется (на живом нули и настоящий sha256 дают одинаковый
200). Источникам обязательны `Referer` = iframe и `Origin` — CDN vkvideo без них 403.

```lua
local function borthBits(len)
    local bits = 0
    while 2 ^ bits < len do bits = bits + 1 end
    return bits
end

local function borthGroupU(v)
    local n = 0
    while v > 0 do
        n = n + 1
        v = math.floor(v / 2)
    end
    return n
end

local function borthGroupX(v, bits)
    if v == 0 then return bits end
    local n = 0
    while v % 2 == 0 do
        n = n + 1
        v = math.floor(v / 2)
    end
    return n
end

local function borthU(s)
    local len = #s
    if len <= 1 then return s end
    local bits = borthBits(len)
    local counts = {}
    for g = 0, bits do counts[g] = 0 end
    for i = 0, len - 1 do
        local g = borthGroupU(i)
        counts[g] = counts[g] + 1
    end
    local chunks, pos = {}, 0
    for g = bits, 0, -1 do              -- нарезка входа по группам сверху вниз
        local n = counts[g]
        chunks[g] = s:sub(pos + 1, pos + n)
        pos = pos + n
    end
    local used = {}
    for g = 0, bits do used[g] = 0 end
    local out = {}
    for i = 0, len - 1 do
        local g = borthGroupU(i)
        local o = used[g]
        used[g] = o + 1
        out[i + 1] = chunks[g]:sub(o + 1, o + 1)
    end
    return table.concat(out)
end

local function borthX(s)
    local len = #s
    if len <= 1 then return s end
    local bits = borthBits(len)
    local counts = {}
    for g = 0, bits do counts[g] = 0 end
    for i = 0, len - 1 do
        local g = borthGroupX(i, bits)
        counts[g] = counts[g] + 1
    end
    local chunks, pos = {}, 0
    for g = 0, bits do                  -- нарезка входа по группам снизу вверх
        local n = counts[g]
        chunks[g] = s:sub(pos + 1, pos + n)
        pos = pos + n
    end
    local used = {}
    for g = 0, bits do used[g] = 0 end
    local out = {}
    for i = 0, len - 1 do
        local g = borthGroupX(i, bits)
        local o = used[g]
        used[g] = o + 1
        out[i + 1] = chunks[g]:sub(o + 1, o + 1)
    end
    return table.concat(out)
end

local function isPrime(n)
    if n < 2 then return false end
    if n % 2 == 0 then return n == 2 end
    local d = 3
    while d * d <= n do
        if n % d == 0 then return false end
        d = d + 2
    end
    return true
end

local function borthQ(s)
    local len = #s
    if len <= 1 then return s end
    local p = len + 1
    while not isPrime(p) do p = p + 1 end
    local taken, order, cur = {}, {}, 0
    while #order < len do
        cur = (cur + 2) % p
        if cur < len and not taken[cur + 1] then
            taken[cur + 1] = true
            order[#order + 1] = cur
        end
    end
    local out = {}
    for m = 0, len - 1 do
        out[order[m + 1] + 1] = s:sub(m + 1, m + 1)
    end
    return table.concat(out)
end

local function borthPayload(viewporti)
    return borthQ(borthX(borthU(viewporti)))
end

-- Качества в порядке убывания: ключи JSON приходят в произвольном порядке.
local function sortedQualityKeys(quals)
    local keys = {}
    for k in pairs(quals) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb and na ~= nb then return na > nb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local ALLOHA_ORIGIN = "https://alloha.yani.tv"

local function resolveAlloha(iframeUrl, dubbing, page)
    if type(page) ~= "table" or not page.success then
        log_error("Alloha iframe " .. tostring(page and page.code))
        return nil
    end
    local html = page.body
    local viewporti = html:match('<meta name="viewporti" content="([^"]+)"')
    local token     = html:match("token:%s*'([0-9a-f]+)'")
    local activeId  = html:match('"active"%s*:%s*{%s*"id"%s*:%s*(%d+)')
    if not viewporti or not token or not activeId then
        log_error("Alloha — не удалось разобрать страницу плеера")
        return nil
    end
    -- fp (sha256-отпечаток) сервер не сверяет: на живом нули и настоящий sha256
    -- дают одинаковый 200, а хеш-функции в песочнице движка нет.
    local borth = string.rep("0", 64) .. "|" .. borthPayload(viewporti)
    local body = "token=" .. token .. "&av1=true&autoplay=0&audio=&subtitle="
    local pr = http_post(ALLOHA_ORIGIN .. "/bnsi/movies/" .. activeId, body, {
        headers = {
            ["Referer"]          = iframeUrl,
            ["Origin"]           = ALLOHA_ORIGIN,
            ["X-Requested-With"] = "XMLHttpRequest",
            ["Borth"]            = borth,
        },
    })
    if not pr.success then
        log_error("Alloha /bnsi " .. tostring(pr.code))
        return nil
    end
    local data = json_parse(pr.body)
    local tracks = data and data.hlsSource
    if type(tracks) ~= "table" then return nil end
    -- CDN vkvideo отвечает 403 без Origin → заголовки источника обязательны
    local headers = { ["Referer"] = iframeUrl, ["Origin"] = ALLOHA_ORIGIN }
    local out = {}
    for _, track in ipairs(tracks) do
        local quals = type(track) == "table" and track.quality or nil
        if type(quals) == "table" then
            for _, k in ipairs(sortedQualityKeys(quals)) do
                local u = quals[k]
                if type(u) == "string" and u ~= "" then
                    out[#out + 1] = {
                        url     = u,
                        quality = "Alloha · " .. dubbing .. " · " .. tostring(k) .. "p",
                        headers = headers,
                    }
                end
            end
        end
    end
    return out
end
```

## cdnvideohub (CVH)

Домен: `plapi.cdnvideohub.com`. Это не embed-хостер, а API-источник сайта
(запасной, в конец списка): `GET /video/<vkId>` с `Referer`/`Origin` = сайт-источник
→ `sources.hlsUrl`. Заголовки потоку **не** ставятся: подписанные сегменты okcdn
(путь `.../sig/<подпись>/…`) отвечают 400, если в запросе есть Referer или Origin —
проверено, без них сегмент 200. Referer/Origin нужны только для API-запросов.

```lua
local function cvhVideoUrl(vkId)
    if vkId == nil then return nil end
    return CVH_API .. "/video/" .. vkId
end

local function cvhSourceFrom(item, r)
    if type(r) ~= "table" or not r.success then return nil end
    local data = json_parse(r.body)
    local hls = data and data.sources and data.sources.hlsUrl
    if type(hls) ~= "string" or hls == "" then return nil end
    return { url = hls, quality = voiceLabel(item) }
end
```

`voiceLabel(item)` — метка озвучки из записи плейлиста; `CVH_HDR` =
`{ Referer = https://ru.yani.tv, Origin = https://ru.yani.tv }`.

## D.Tube

Домен: `play.d.tube`. SPA, но JSON-обложка открыта: из ссылки берётся `v=<id>` →
`GET https://api.d.tube/videos/<id>` с `Referer: https://play.d.tube/` →
`video_url` = `master.m3u8`. Отдельный GET не нужен — тело приходит батчем.

```lua
local function planDTube(embed)
    local id = embed:match("[?&]v=([^&#]+)")
    if not id then return nil end
    return {
        url = "https://api.d.tube/videos/" .. id,
        headers = { ["Referer"] = "https://play.d.tube/" },
        hoster = "dtube",
    }
end

local function resolveDTube(body)
    if type(body) ~= "string" then return {} end
    local data = json_parse(body)
    if type(data) ~= "table" then return {} end
    local url = data.video_url
    if type(url) ~= "string" or url == "" then return {} end
    return { { url = url, mime = "hls" } }
end
```

## dailymotion (+ geo.dailymotion)

Embed бывает `geo.dailymotion.com/player/xhojl.html?video=<id>` — сам embed
читать не нужно. Из ссылки берётся id, затем
`GET https://www.dailymotion.com/player/metadata/video/<id>?locale=en-US` с
`Accept: */*`, `Referer` и `Origin` на dailymotion → JSON `qualities.auto[].url`
(master m3u8). Вариант со страницы видео: `dmInternalData {ts, v1st}` → тот же
endpoint с `&dmV1st=&dmTs=&is_native_app=0`, субтитры — из `subtitles.data`.
Ветка `password_protected` не портирована (логируется и пропускается).

Живьём 2026-10-07: metadata отдаётся 200 и URL извлекается; воспроизведение
подтверждено в приложении (Stellar S4 → m3u8 отдаёт кадр), но часть роликов
`cdndirector.dailymotion.com` отвечает 403 (`x-error-code: E005`) — тогда в
диалоге вариантов бейдж «Недоступен» и нужно брать другое зеркало. Манифест
отдаётся как есть, без пробы.

```lua
local function planDailymotion(embed)
    local id = embed:match("[?&]video=([^&]+)")
    if not id then return nil end
    return {
        url = "https://www.dailymotion.com/player/metadata/video/" .. id,
        headers = { ["Referer"] = "https://www.dailymotion.com/" },
        hoster = "dailymotion",
    }
end

local function resolveDailymotion(body)
    if type(body) ~= "string" then return {} end
    local data = json_parse(body)
    local out = {}
    if type(data) == "table" and type(data.qualities) == "table" then
        local auto = data.qualities.auto
        if type(auto) == "table" then
            for _, q in ipairs(auto) do
                if type(q) == "table" and type(q.url) == "string" and q.url ~= "" then
                    out[#out + 1] = { url = q.url, mime = "hls" }
                end
            end
        end
    end
    if #out == 0 then
        -- в JSON слеши экранированы (application\/x-mpegURL), поэтому сперва
        -- разэкранируем, потом ищем по «auto»-схеме и общим regex
        local flat = body:gsub("\\/", "/")
        local m = flat:match('"auto"%s*:%s*%[{%s*"type"%s*:%s*"application[^"]*mpegURL","url"%s*:%s*"([^"]+)"')
            or flat:match('(https://[^"]+%.m3u8[^"]*)')
        if m then out[#out + 1] = { url = m, mime = "hls" } end
    end
    return out
end
```

## direct-scan (прямые m3u8/mp4, cdn-token)

Базовый разбор для хостов без отдельного резолвера: скан тела эмбеда на явные
`.m3u8`/`.mp4` плюс переменная `streamUrl` (собственный плеер зеркал). Строгий
фильтр обязателен: без него хост вида `www.mp4upload.com` матчится паттерном `.mp4`
и даёт ссылку на страницу плеера.

Отдельный случай — URL без медиа-расширения (`https://cdn…/?token=`): media3
типизирует поток по последнему сегменту пути (`/` → OTHER → Progressive) и падает
`UnrecognizedInputFormatException`. Лечится `mime = "hls"` — тогда `Source.Factory`
не гадает по URL.

```lua
-- Есть ли медиа-расширение в пути URL (до "?" / "#").
local function hasMediaExt(u)
    local base = u:match("^[^%?#]*") or u
    return base:match("%.m3u8$") ~= nil or base:match("%.mp4$") ~= nil
end

local function directLinks(body)
    local out, seen = {}, {}
    -- strict=true: только явные медиа-суффиксы
    local function add(u, strict)
        u = u:gsub("&amp;", "&")
        if seen[u] then return end
        if strict and not hasMediaExt(u) then return end
        seen[u] = true
        out[#out + 1] = u
    end
    -- streamUrl на зеркалах VnxPlayer — cdn-токен без расширения,
    -- он идёт в список с mime = "hls"
    local stream = body:match('streamUrl%s*=%s*"([^"]+)"')
        or body:match("streamUrl%s*=%s*'([^']+)'")
    if stream then add(stream, false) end
    for u in body:gmatch('https?://[^"\'%s<>]+%.m3u8[^"\'%s<>]*') do add(u, true) end
    for u in body:gmatch('https?://[^"\'%s<>]+%.mp4[^"\'%s<>]*') do add(u, true) end
    return out
end

-- Кандидат: URL без медиа-расширения — это HLS-источник, с mime = "hls"
-- media3 не гадает по URL.
local function pushCandidate(candidates, url, quality, referer, headers)
    if type(url) ~= "string" or url == "" then return false end
    candidates[#candidates + 1] = {
        url = url, quality = quality, referer = referer, headers = headers,
        mime = hasMediaExt(url) and nil or "hls",
    }
    return true
end
```

## docs.google

Домен: `docs.google.com`. Это ссылка на документ, а не на видеофайл: превью
рендерится JS, прямых ссылок в HTML нет.

Сайты: witanime.site, anime-phoenix.com (скип «Google Docs: превью на JS»).

Причина: контент отдаётся только после выполнения скрипта просмотра.

## dood / dsvplay / playmogo

DoodStream и зеркала. Схема: `GET embed` → в разметке путь `/pass_md5/<path>` →
`GET <origin>/pass_md5/<path>` с `Referer` = embed → тело = начало URL → к нему
дописываются 10 случайных символов, `?token=<последний сегмент пути>&expiry=<unixtime>`.

Статус 2026-10-07: схема реализована и проверена живьём — `plugin_tester --cf`
и стендовые прогоны на всех 4 сайтах дают `206 video/mp4` (сигнатура
`ftypisom`) с финалом `cloudatacdn.com/…~…?token=…&expiry=…`. Важное: **движок
сам обходит Cloudflare** (`cf_options`, авто-решение Turnstile в скрытом WebView
+ запекание `cf_clearance`; замер curl 403 на это не влияет — в приложении тело
embed приходит решённым). `expiry` — **миллисекунды** (`Date.now()` плеера;
`os_time()` в Lua тоже мс). Referer финального потока — origin embed со слэшем
(`https://playmogo.com/`), полный embed тоже принимается.

Ограничения: часть embed-файлов отдаёт Turnstile-гейт (`.captcha_l`, без
`/pass_md5`) — даже браузеру, после клика по play гейт снимается; резолвер на
таком варианте корректно отвечает «в embed нет /pass_md5». Embed домен-лок:
чужой Referer → 38 байт «Video embed restricted for this domain». Ответ
`"RELOAD"` → перезагрузка (обработан как отказ). `dsvplay.com` мёртв:
TLS rc=35 и с браузерным UA (2026-10-07) — skip оставлен. CF-clearance живёт
~30 минут.

Сайты: witanime.site, w1.anime4up.rest, animexin.dev, anichin.moe.
Примечание: у witanime.site 2026-10-07 `GET /watch/stream-gate/<token>` → 404
даже из реального браузера (сломано на стороне сайта для всех хостеров), и
DoodStream-плееров на сайте сейчас нет — там ветка работает, но
нецелесообразна в выборке.

```lua
local RANDOM_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function extractDood(embedUrl, body)
    local md5 = body:match("(/pass_md5/[^'\"]+)")
    if not md5 then return nil end
    local o = origin(embedUrl)
    if not o then return nil end
    local token = md5:match("([^/]+)$")
    local r = http_get(o:sub(1, -2) .. md5, { headers = { ["Referer"] = embedUrl } })
    if not r.success then return nil end
    local start = r.body:gsub("%s+$", ""):gsub("^%s+", "")
    if not start:find("^https?://") then return nil end

    local rnd = {}
    for i = 1, 10 do
        local k = math.random(1, #RANDOM_CHARS)
        rnd[i] = RANDOM_CHARS:sub(k, k)
    end
    local url = start .. table.concat(rnd) .. "?token=" .. tostring(token) .. "&expiry=" .. tostring(os_time())
    return url, "mp4", o
end
```

## dotplay

Домен: `dotplay.net`; встречается только внутри ответа yonaplay. `GET эмбеда`
(поднимает куку) → `GET {origin}/api.php?code=<id>` с `Accept: application/json`
и `Referer` = embed → JSON `video_url` = base64 → значимая часть строки до `|`
(хвост — подпись-время). Чужой хост в этой позиции запрос заведомо мёртвый
(отдаст HTML), поэтому проверяется домен до выхода в сеть.

```lua
local function resolveDotplay(episodeUrl, link, quality)
    local code = link:match("/embed/([^/?#]+)")
    local origin = link:match("^(https?://[^/]+)") or ""
    -- api.php?code= — это API именно dotplay; посторонний хост (в ответе
    -- yonapplay бывает 4shared) отдаёт HTML вместо JSON
    if not code or not string_lower(origin):find("dotplay.net", 1, true) then
        log_error("dotplay — не dotplay-ссылка, пропущена: " .. tostring(link))
        return nil
    end
    http_get(link, { headers = { ["Referer"] = "https://mid.yonaplay.net/" } })

    local api = origin .. "/api.php?code=" .. url_encode(code)
    local r = http_get(api, {
        headers = {
            ["Accept"]  = "application/json",
            ["Referer"] = link,
        },
    })
    if not r.success then
        log_error("dotplay — HTTP " .. tostring(r.code))
        return nil
    end
    local data = json_parse(r.body)
    local url = data and data.video_url and base64Bytes(data.video_url)
    if not url or #url == 0 then
        log_error("dotplay — пустой video_url")
        return nil
    end
    -- значимая часть до '|' (там подпись-время)
    local raw = bytesToString(url):match("^([^|]+)") or ""
    if raw == "" then return nil end
    return { sourceOf(episodeUrl, raw, quality, link) }
end
```

## dropbox

Домен: `dropbox.com`; в живой выдаче не встречался. Схема: до 5 итераций `GET`
с `binary = true` и `followRedirects = false` → читаем `location` → absolutize.
Ошибка — только при `code >= 400`: 3xx у binary-ответа приходит с `success = false`.

```lua
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
            log_error("dropbox — HTTP " .. tostring(r.code))
            return nil
        end
        local loc = headerValue(r.headers, "location")
        if not loc then break end
        current = absUrl(loc)
    end
    return { sourceOf(episodeUrl, current, qualityOf(entry)) }
end
```

## file-upload.org

Домен: `file-upload.org`. Живьём 2026-10-05: `file-upload.org/e-<id>.html`
отвечает 200, но формат embed не подтверждён — устаревшие id отдавали
«File was deleted» (HTTP 200, 16 байт), варианты на `www.file-upload.com`
(`/e/…`, `/embed/…`) дают 404. `robots.txt` закрыт от индексации.

Сайты: w1.anime4up.rest.

Причина: с подтверждённой живой ссылкой резолвера нет; домен скипается
проверкой формата, ссылки без подтверждённого формата не раскрываются.

## gdriveplayer

Домен: `gdriveplayer.com`. Это обёртка над Google Drive: сам плеер — `file.js`
на стороне хоста, ссылка на файл лежит за JS-логикой.

Сайты: w1.anime4up.rest.

Причина: разбор JS-состояния страницы не портирован. Сам Google Drive
раскрывается отдельно (см. раздел google drive).

Другой домен — `gdriveplayer.to` (embeds `//gdriveplayer.to/embed2.php?link=<encrypted>`,
сайт animexin.dev): embed отдаёт инлайн-скрипт `var k="<xorkey>",b=atob("<base64>")`
+ XOR-цикл по байтам (ASCII key), расшифровка → JS с `HLS="hlsplaylist.php?s=<b64>&idhls=<b64>.m3u8"`.
Реализовано в animexin.lua (`planGdriveplayer` / `resolveGdriveplayer`,
XOR без bit32 — байтовый цикл по строкам). Живьём 2026-10-07:
`GET hlsplaylist.php` → 200 `application/vnd.apple.mpegurl` (media playlist,
сегменты `//lowhls*.stream121.space/...` → 200 octet-stream, протоколо-относительные
URL требуют `https:`). Воспроизведение подтверждено в приложении (кадр, титры
+ субтитры, без ошибок плеера).

## google drive

Домен: `drive.google.com`. Не embed, а ссылка на файл (`/file/d/<id>`):
id вытаскивается и подставляется в
`https://drive.usercontent.google.com/download?id=<id>&export=download&confirm=t`,
`resourcekey` из исходной ссылки прокидывается. Живьём 2026-10-03: отдаёт
206 Partial Content **без единого заголовка**, включая файлы больше 100 МБ;
`uc?export=download` не используется (303 → HTML-интерстишл). Ссылка
разрешается без сети — в батч уходит только embed-ссылка; `mime` не ставится
(контейнер sniff'ит), Referer источника = `https://drive.google.com/`.

```lua
-- ponytail: playback-API-фоллбэк для «download disabled» (403 + привязка
-- транскодов к UA/IP) не делаем — ставим, если встретятся залоченные ссылки.
local function driveDirectUrl(link)
    local host = (link:match("^https?://([^/]+)"):gsub("^www%.", "")):lower()
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
```

## hentaila CDN (cdn.hvidserv)

Внутренний CDN площадки: ссылка вида
`https://cdn.hvidserv.com/play/<id>` — это страница плеера, а плейлист лежит
на том же хосте, достаточно заменить `/play/` на `/m3u8/`. Запрос идёт
с `sec-fetch-site: same-origin`, mime = `hls`.

```lua
-- Внутренний CDN: /play/ — страница плеера, /m3u8/ — плейлист.
if url:find("cdn.hvidserv.com/play/", 1, true) then
    return {
        url     = url:gsub("/play/", "/m3u8/"),
        mime    = "hls",
        headers = { ["sec-fetch-site"] = "same-origin" },
    }
end
```

## hgcloud

Домен: `hgcloud.to`. Сайты: w1.anime4up.rest, witanime.site.

Схема (живьём 2026-10-06): заглушка → main.js → случайное зеркало →
packed-JS → master.txt.

1. Gate отдаёт `https://hgcloud.to/e/<id>`; сам `/e/<id>` **без
   HTTP-редиректа** возвращает 200 и 452 байта статичной заглушки
   (`last-modified: 19 Jul 2026`) с `<script src="/main.js?v=1.1.9">`.
2. `main.js` (обфусцирован, ~71 КБ, обфускатор.io: массив 582 строк +
   RC4/base64) в браузере делает `location.href = <зеркало>/e/<id>`,
   выбирая зеркало **случайно** из списка
   **{hanerix.com, vibuxer.com, audinifer.com}** — 5 прогонов:
   hanerix, vibuxer, audinifer, hanerix, hanerix, на другом id — audinifer,
   список от id не зависит. Домен собирается в рантайме, plaintext-доменов
   и URL в тексте нет (хук декодера при реальном прогоне — 57 498 вызовов,
   2 818 строк, ни одного домена), поэтому резолвер его не вычисляет: в
   движке JS нет, только `http_get` / `http_post` / `http_get_batch`.
3. Эндпоинта со списком зеркал у входного домена нет (`/mirrors`,
   `/domains`, `/config.json` → 522 или заглушка) → зеркала перебираются
   сами: сначала оригинал (на случай, если хост начнёт отдавать контент или
   302 напрямую), затем по порядку три домена ротатора. Путь `/e/<id>`
   берётся из gate-ссылки, не выдумывается; таймаут 8 с на запрос, максимум
   оригинал + 3 зеркала; побеждает первый ответ с packed-конфигом.
4. Зеркало отдаёт 15,5 КБ страницы с packed-конфигом: `links = {hls2, hls3}`
   (плюс `hls4`), `jwplayer(...).setup({sources:[{file:links.hls4||links.hls3||links.hls2,type:"hls"}]})`
   → первым идёт `master.txt`. Ссылки лежат в объекте `links`, а не в
   `file:"…"`, поэтому общий сбор по `file:` их не матчит — нужен свой.
5. Referer потока = страница, с которой взят конфиг, то есть
   `https://<mirror>/`. Если ни одно зеркало не отдало packed — лог с
   кодами всех ответов.

Требования хоста (мерено 2026-10-06, browser UA, реальные id из ответов
`/sources` → `stream-gate`):
- `master.txt` и плейлист варианта: **Referer обязателен** — в резолвере это
  `https://<mirror>/`; значение подходит любое: `hanerix.com`, `hgcloud.to`,
  `witanime.site`, `example.com` → 200 `application/vnd.apple.mpegurl`;
  без Referer → 404; только Origin → 404.
- Сегменты TS (`seg-*.woff2`, `video/MP2T`) — та же проверка: с Referer → 206,
  без → 404. `Origin` не требуется, browser UA не обязателен (curl без UA с
  Referer → 200).
- `hls2` (`premilkyway.com`, `master.m3u8`) отдаётся и без Referer.

Прогнано: `master.txt` (285 б) → `index-v1-a1.txt` (11 814 б, 142 сегмента)
→ `seg-1-v1-a1.woff2` → 206 `video/MP2T`, первый байт `0x47`.

```lua
-- Зеркала ротатора hgcloud.to (main.js, наблюдение 2026-10-06); если
-- перестанут отдавать конфиг — обновить по main.js ротатора.
local HGCLOUD_MIRRORS = { "hanerix.com", "vibuxer.com", "audinifer.com" }

-- Конфиг лежит в links = {hls2:…, hls3:…}, setup берёт
-- file: links.hls4||links.hls3||links.hls2 — голый file:"…" не матчит.
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
    local function attempt(url, referer)
        local r = http_get(url, {
            headers = { ["Referer"] = referer },
            timeout = 8000,          -- оригинал + максимум 3 зеркала
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
        -- Заглушка: main.js редиректит на случайное зеркало. Путь эмбеда
        -- (/e/<id>) сохраняем из gate-ссылки, не выдумываем.
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
        log_error("hgcloud: нет packed-конфига; ответы: " .. table.concat(tried, ", "))
        return nil
    end
    -- finalRef = страница, с которой взят конфиг: без неё master.txt и
    -- сегменты отдают 404 (живьём 2026-10-06).
    local out, seen = {}, {}
    for _, u in ipairs(urls) do
        local src = sourceOf(episodeUrl, u, qualityOf(entry), finalRef)
        if not hasMediaExt(u) then src.mime = "hls" end -- master.txt — без расширения
        pushSource(out, seen, src)
    end
    return out
end
```

## kodik

Домен: `kodikplayer.com` (плюс зеркала), iframe `<host>/<type>/<id>/<hash>`.
`GET iframe` батчем → JSON `urlParams` с подписями `d_sign`/`pd_sign` и
`type`/`id`/`hash` из `vInfo` (запасной путь — сегменты пути) →
`POST https://kodikplayer.com/ftor` формой → JSON `links["240".."720"]`,
`src` через `kodikDecode`: абсолютный URL либо ROT-18 по буквам + base64.
Поля `ref`/`ref_sign` не отправляются — сервер подписывает их под Referer
запроса iframe, которого движок не повторяет, и `/ftor` отдаёт 500; без них 200.
Плейлист отдаётся и без Referer/Origin.

```lua
-- src в ответе /ftor либо абсолютный, либо ROT-18 по буквам + base64.
local function kodikDecode(src)
    if src:find("//", 1, true) then return src end
    local t = {}
    for i = 1, #src do
        local b = src:byte(i)
        if b >= 65 and b <= 90 then
            b = b + 18
            if b > 90 then b = b - 26 end
        elseif b >= 97 and b <= 122 then
            b = b + 18
            if b > 122 then b = b - 26 end
        end
        t[#t + 1] = string.char(b)
    end
    local url = base64DecodePure(table.concat(t))
    if url == "" then return nil end
    if url:sub(1, 2) == "//" then return "https:" .. url end
    return url
end

local function resolveKodik(iframeUrl, dubbing, page)
    if type(page) ~= "table" or not page.success then
        log_error("Kodik iframe " .. tostring(page and page.code))
        return nil
    end
    local url = iframeUrl
    if url:sub(1, 2) == "//" then url = "https:" .. url end
    local html = page.body
    -- urlParams — JSON с подписями, без них /ftor отдаёт 500
    local raw = html:match("urlParams%s*=%s*'([^']+)'")
        or html:match('urlParams%s*=%s*"([^"]+)"')
    local params = raw and json_parse(raw) or nil
    if type(params) ~= "table" or type(params.d_sign) ~= "string" or params.d_sign == "" then
        log_error("Kodik — не найдены urlParams")
        return nil
    end
    local vtype = html:match("vInfo%.type%s*=%s*'([^']+)'")
        or html:match('var%s+type%s*=%s*"([^"]+)"')
    local vhash = html:match("vInfo%.hash%s*=%s*'([^']+)'")
    local vid   = html:match('videoId%s*=%s*"([^"]+)"')
        or html:match("vInfo%.id%s*=%s*'([^']+)'")
    if not vtype or not vhash or not vid then
        -- запасной путь: сегменты пути iframe — host/type/id/hash
        local seg = {}
        for part in url:gsub("[?#].*$", ""):gmatch("[^/]+") do seg[#seg + 1] = part end
        vtype = vtype or seg[2]
        vid   = vid   or seg[3]
        vhash = vhash or seg[4]
    end
    if not vtype or not vid or not vhash then
        log_error("Kodik — не удалось получить type/id/hash")
        return nil
    end
    local function field(v)
        return url_encode(type(v) == "string" and v or "")
    end
    -- ponytail: ref/ref_sign не отправляем — сервер подписывает их под Referer
    -- запроса iframe, из-за чего подпись не сходится и /ftor отдаёт 500
    local body = table.concat({
        "d=",        field(params.d),
        "&d_sign=",  field(params.d_sign),
        "&pd=",      field(params.pd),
        "&pd_sign=", field(params.pd_sign),
        "&type=",    url_encode(vtype),
        "&id=",      url_encode(vid),
        "&hash=",    url_encode(vhash),
        "&bad_user=false&cdn_is_working=true",
    })
    local pr = http_post("https://kodikplayer.com/ftor", body)
    if not pr.success then
        log_error("Kodik /ftor " .. tostring(pr.code))
        return nil
    end
    local data = json_parse(pr.body)
    local links = data and data.links
    if type(links) ~= "table" then return nil end
    -- ключи links — качества в строковом виде, от большего к меньшему
    local qs = {}
    for k in pairs(links) do
        if type(k) == "string" and k:match("^%d+$") then qs[#qs + 1] = k end
    end
    table.sort(qs, function(a, b) return tonumber(a) > tonumber(b) end)
    local out = {}
    for _, q in ipairs(qs) do
        local items = links[q]
        if type(items) == "table" then
            for _, it in ipairs(items) do
                local src = type(it) == "table" and it.src or nil
                local hls = type(src) == "string" and kodikDecode(src) or nil
                if hls then
                    out[#out + 1] = {
                        url     = hls,
                        quality = "Kodik · " .. dubbing .. " · " .. q .. "p",
                    }
                end
            end
        end
    end
    return out
end
```

## larhu

Домен: `larhu` (embed `fav.larhu.website`). Живьём 2026-10-05: embed разбирается
(`jwplayer` с `sources:[{file:…m3u8}]`), но сам CDN без DNS-записи A/AAAA
(`dig` 8.8.8.8 / 1.1.1.1 → NODATA) — поток недостижим.

Сайты: w1.anime4up.rest.

Причина: ссылка есть, CDN не резолвится. Вернуть, если хост снова заработает.

## listeamed / strwish

Домены: `listeamed.net`, `strwish.com`. Что известно: страница плеера — JS-заглушка
(VidGuard / StreamWish), прямой ссылки в HTML нет.

Сайты: anichin.moe.

Причина: конфиг плеера собирается JS; запрос уходит из браузера, статический
разбор не даёт ничего.

## Lua-unpacker (packed-JS)

Общий инструмент для хостов, отдающих упакованный JS:
`eval(function(p,a,c,k,e,d){…}('payload',radix,count,'a|b|c'.split('|'),0,0))` —
Dean Edwards packer. Схема: вырезать вызов (нужно **четыре** захвата: payload,
radix, count, syms), разбить symtab по `|` с сохранением пустых слотов
(индексация строгая: `dict[v+1]`), перевести каждый токен payload из radix-нотации
и подставить из словаря. `packedMediaUrls` дополнительно собирает ссылки из
`file:"…"`: распакованный текст + исходный, только по медиа-суффиксу (в `file:`
лежат и сабы с логотипами). Проверено живьём 2026-10-05 на uqload.

```lua
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

-- Ссылки на поток из тела плеера: распакованный текст + исходный. Конфиг
-- jwplayer лежит в распакованном виде, поэтому голый sources:-паттерн по телу
-- не матчит.
local function packedMediaUrls(body)
    local text = body
    local un = unpackPacked(body)
    if un ~= "" then text = un .. "\n" .. body end
    local out, seen = {}, {}
    local function add(u)
        if seen[u] or not string_starts_with(u, "http") then return end
        if not hasMediaExt(u) then return end
        seen[u] = true
        out[#out + 1] = u:gsub("\\/", "/"):gsub("&amp;", "&")
    end
    for u in text:gmatch('file:%s*"([^"]+)"') do add(u) end
    for u in text:gmatch("file:%s*'([^']+)'") do add(u) end
    for u in text:gmatch('"file"%s*:%s*"([^"]+)"') do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.m3u8[^"'%s<>\\]*]]) do add(u) end
    for u in text:gmatch([[https?://[^"'%s<>\\]+%.mp4[^"'%s<>\\]*]]) do add(u) end
    return out
end
```

`hasMediaExt` и `string_starts_with` — из раздела direct-scan.

## mail.ru

Домен: `my.mail.ru` (embed `https://my.mail.ru/video/embed/<id>`). Схема: `GET embed`
→ в разметке `"metadataUrl":"//my.mail.ru/+/video/meta/<id>"` → этот JSON с
`Referer` = embed и `X-Requested-With` → `videos[].url` (mp4). Живьём 2026-10-05:
mp4 отдаёт 206 на запрос с Range и Referer'ом эмбеда; кука `Set-Cookie: video_key=…`
не требуется.

```lua
local function resolveMailRu(body, entry, candidates)
    local meta = body:match('metadataUrl":"([^"]+)')
    if not meta then
        log_error(entry.quality .. " — mail.ru: в embed нет metadataUrl")
        return 0
    end
    local r = http_get((meta:gsub("^//", "https://")), {
        headers = {
            ["Referer"] = entry.link,
            ["X-Requested-With"] = "XMLHttpRequest",
        },
        timeout = 10000,
    })
    if not r.success then
        log_error(entry.quality .. " — mail.ru: meta HTTP " .. tostring(r.code))
        return 0
    end
    local data = json_parse(r.body)
    local videos = type(data) == "table" and data.videos or nil
    if type(videos) ~= "table" then
        log_error(entry.quality .. " — mail.ru: в meta нет videos[]")
        return 0
    end
    local added = 0
    for _, v in ipairs(videos) do
        local u = type(v) == "table" and v.url or nil
        local key = type(v) == "table" and type(v.key) == "string" and v.key or nil
        if type(u) == "string" and u ~= "" then
            local q = key and ("Mail.ru · " .. key) or ("Mail.ru · " .. entry.quality)
            if pushCandidate(candidates, u:gsub("^//", "https://"), q, entry.link) then
                added = added + 1
            end
        end
    end
    if added == 0 then log_error(entry.quality .. " — mail.ru: в videos[] нет ссылок") end
    return added
end
```

## mediafire / gofile / terabox / mirrored.to

Это файловые хосты, а не видео-плееры: mediafire отдаёт страницу скачивания
с JS, gofile — ссылку, за которой стоит сессионный токен, выдаваемый JS страницы.
terabox и mirrored.to — файловые хосты без резолвера, живость не проверялась.

Сайты: latanime.org (mediafire, gofile, mega.io), animexin.dev (terabox, mirrored.to).

Причина: прямая ссылка появляется только после выполнения JS страницы
(сессионный токен / редирект), в статическом разборе её нет.

## mega.nz / mega.io

Домены: `mega.nz`, `mega.io`. Поток зашифрован AES-CTR и отдаётся чанками:
декрипт ключа — из собственного URL, чтение идёт частичными запросами (Range) с
пересборкой чанков. Прямой ссылки в HTML нет.

Сайты: witanime.site, w1.anime4up.rest, anime-phoenix.com, animexin.dev,
anichin.moe, latanime.org.

Причина: в движке нет крипто (AES) и нет частичных запросов — оба требования
не выполнимы статически.

## mixdrop

Домен: `mixdrop`. Конфиг плеера лежит в упакованном JS (packer, см. раздел
Lua-unpacker), поток — в поле `MDCore.wurl`; значение относительное, отсюда
`resolve` даёт абсолютный URL. Referer источника = origin эмбеда.

```lua
local function extractMixdrop(both, embedUrl)
    local u = both:match('MDCore%.wurl%s*=%s*"([^"]+)"')
    if u then return resolve(u, embedUrl), "mp4", origin(embedUrl) end
    return nil
end
```

`both` — тело эмбеда, в котором уже распакованный JS склеен с исходным;
`resolve(u, base)` — абсолютный URL, `origin(url)` — `https://host`.

## mp4upload

Домен: `mp4upload.com`, embed `…/embed-<id>.html`. Схема: в теле
`player.src("…")` (либо `player.src({… src: "…"})`), оттуда mp4; Referer
источника = `https://www.mp4upload.com/`. Часто ловится и общим сканом
(раздел direct-scan) — отдельный разбор нужен, когда в теле есть и мусор.

```lua
local function extractMp4upload(both)
    local u = both:match('player%.src%(%s*"([^"]+)"')
        or both:match('player%.src%(%s*{.-src%s*:%s*"([^"]+)"')
        or both:match('src%s*:%s*"(https?://[^"]+%.mp4[^"]*)"')
    if u then return u, "mp4", "https://www.mp4upload.com/" end
    return nil
end
```

## odysee

Домен: `odysee.com`. SPA-оболочка; данные лежат за LBRY-вызовом, который
требует валидной подписи — статический разбор страницы не даёт ссылки.

Сайты: animexin.dev, anichin.moe.

Причина: нужен подписанный LBRY-запрос (claim-сервис), в статике недоступен.

## ok.ru

Домен: `ok.ru`, embed `https://ok.ru/videoembed/<id>?nochat=1`. `GET` с
`Referer: https://ok.ru/` → атрибут `data-options` (HTML-сущности обратно
в кавычки) → JSON → `flashvars.metadata` (строка → повторный `json_parse`) →
`hlsManifestUrl` (master HLS) и `videos[].url` c `name` как качеством.
Живьём 2026-10-05 подтверждено; без Referer манифест даёт 400.

```lua
local function planOkRu(embed)
    return {
        url = embed,
        headers = { ["Referer"] = "https://ok.ru/" },
        hoster = "okru",
    }
end

local function resolveOkRu(body)
    if type(body) ~= "string" then return {} end
    local opts = body:match('data%-options="([^"]+)"')
    if not opts then return {} end
    opts = opts:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<")
        :gsub("&gt;", ">"):gsub("&amp;", "&")
    local data = json_parse(opts)
    if type(data) ~= "table" or type(data.flashvars) ~= "table" then return {} end
    local meta = data.flashvars.metadata
    if type(meta) == "string" then meta = json_parse(meta) end
    if type(meta) ~= "table" then return {} end
    local out = {}
    if type(meta.hlsManifestUrl) == "string" and meta.hlsManifestUrl ~= "" then
        out[#out + 1] = { url = meta.hlsManifestUrl, mime = "hls" }
    end
    if type(meta.videos) == "table" then
        for _, v in ipairs(meta.videos) do
            local u = type(v) == "table" and v.url or nil
            if type(u) == "string" and u ~= "" then
                out[#out + 1] = {
                    url = u,
                    mime = "mp4",
                    name = type(v.name) == "string" and v.name or nil,
                }
            end
        end
    end
    return out
end
```

## pixeldrain

Домен: `pixeldrain.com`. Ссылка вида `https://pixeldrain.com/u/<id>` — страница
файла; прямая ссылка получается заменой пути на `/api/file/<id>` (id — последний
сегмент). Заголовки не нужны, mime = `mp4`.

```lua
-- PixelDrain: /u/<id> page → /api/file/<id> direct file.
if lower == "pdrain" or url:find("pixeldrain", 1, true) then
    local fileId = url:match("/u/([%w_%-]+)") or url:match("/api/file/([%w_%-]+)")
    if fileId then
        return { url = "https://pixeldrain.com/api/file/" .. fileId, mime = "mp4" }
    end
    return nil
end
```

## racaty.my.id

Домен: `racaty.my.id` — гейт-хостер: отвечает 502 без содержимого.

Сайты: anichin.moe.

Причина: хост не отдаёт страницу плеера.

## rpmvid

Домен: `anichin.rpmvid.com`. API отдаёт тело, зашифрованное AES-GCM; id и
endpoint известны, но ветка расшифровки не портирована.

Сайты: anichin.moe.

Причина: нет рабочей расшифровки ответа для этого endpoint (движок даёт
только CBC; AES-GCM для этого API не реализован).

## rubyvidhub / streamruby / rubystm / turbovidhls

Домены: `rubyvidhub.com`, `streamruby.com`, `rubystm.com`, `turbovidhls.com`.
Статус 2026-10-07 (перепроверка браузером и curl): DNS/TCP живы, но рабочего
плеера нет. Реальный embed `rubyvidhub.com/embed-*.html` (с клика по плееру
w1.anime4up.rest) отвечает Cloudflare 522 (origin не отвечает); `streamruby.com`
не отвечает на HTTP вовсе (curl timeout); `turbovidhls.com` не устанавливает
соединение (curl 000).

Сайты: anichin.moe, w1.anime4up.rest (rubyvidhub, streamruby).

Причина: обмена нет — нечего раскрывать.

## Rumble

Домен: `rumble.com`. Embed отдаёт jwplayer-конфиг: сначала ищется muxed mp4
(`hugh.cdn.rumble.cloud/….mp4`), иначе HLS — `rumble.com/hls-vod/…playlist.m3u8`
либо `chunklist.m3u8` на CDN. В JSON слеши экранированы, тело сначала
разэкранируется. Важно: хвост вида `file.tar?r_file=chunklist.m3u8` не считается
потоком — в скане не должно быть `?` до расширения.

```lua
local function planRumble(embed)
    return {
        url = embed,
        headers = { ["Referer"] = "https://rumble.com/" },
        hoster = "rumble",
    }
end

local function resolveRumble(body)
    if type(body) ~= "string" then return {} end
    local raw = body:gsub("\\/", "/")
    local out = {}
    local mp4 = raw:match('"url":"(https://hugh%.cdn%.rumble%.cloud/[^"]+%.mp4)"')
        or raw:match('(https://hugh%.cdn%.rumble%.cloud/[^"]+%.mp4)')
    if mp4 then out[#out + 1] = { url = mp4, mime = "mp4" } end
    local hls = raw:match('(https://rumble%.com/hls%-vod/[^"]+playlist%.m3u8)')
        or raw:match('(https://hugh%.cdn%.rumble%.cloud/[^"]+chunklist%.m3u8[^"]*)')
    if hls then out[#out + 1] = { url = hls, mime = "hls" } end
    return out
end
```

## seekplayer.vip

Домен: `seekplayer.vip`. SPA-клон StreamWish. Схема (живьём 2026-10-07):
id эпизода = первый сегмент пути embed до `&` → `GET <origin>/api/v1/video?id=<id>&w=…&h=…&r=<host>`
с браузерным User-Agent (curl-UA → HTTP 400; Referer эмбеда передаётся) →
тело — hex-строка → base64 → `aes_decrypt` (AES-128-CBC/PKCS5) → JSON.
Ключ `kiemtienmua911ca`, IV `1234567890oiuytr` — ASCII-константы бандла
плеера; `aes_decrypt` ждёт данные в base64, key/iv — строки без байт ≥0x80.

JSON: `streamingConfig` (строка с `order`/`adjust`), `hlsVideoTiktok`
(относительный), `hlsVideoGoogle`, `cfNative`, `cf` (отвечает 403 — не брать),
`source`. Порядок Tiktok → Google → Cloudflare → In-House; в `adjust` —
пропуск `disabled`, `params` в query, переписывание `/hls/` → `/hlsmod/<domain>/`,
относительные URL резолвятся в origin эмбеда. Ответ `/api/v1/info?id=` —
только метаданные (title/poster/playerId), источников не несёт.

Проверено живьём: API 200, все источники 200/206 `application/vnd.apple.mpegurl`,
цепочка master → variant → init 206 + сегменты 206 `video/mp4`. Ограничения:
capacityToken-retry («saturated») и субтитры не реализованы; embed-форма с
w1.anime4up.rest подтверждена только кодом плеера (curl на сайт → CF 403,
живьём вытаскивается только в WebView).

Сайты: animexin.dev (`animexinfansub.seekplayer.vip`), w1.anime4up.rest
(ссылки с меткой streamwish — тот же SPA; матч по обоим токенам
«seekplayer»/«streamwish» в ссылке).

## sendvid

Домен: `sendvid.com`, embed `…/embed/<id>`. Отдельного разбора не требует:
`<source id="video_source" src="…mp4?hash=…">` ловится общим сканом
(раздел direct-scan). Живьём проверено: 206 + сигнатура `ftyp`.

## share4max

Домен: `share4max.com`. Inertia-приложение: версия лежит в
`<script data-page="app" type="application/json">` (`"version":"a601a2d0…"`),
потоки — в `props.streams` частичного ответа
(`X-Inertia: true` + `X-Inertia-Version` + `X-Inertia-Partial-Component: files/mirror/video` +
`X-Inertia-Partial-Data: streams`). Адрес с медиа-расширением — готовая ссылка,
адрес зеркала-по-leера уходит на повторный проход по диспетчеру.

UNVERIFIED: живую ссылку на файл получить не удалось — на главной нет листингов,
`robots.txt` = `Disallow: /`, все угаданные пути отдают 404. Схема перенесена с
работающего экстрактора; версия Inertia проверена на главной живьём 2026-10-05.

```lua
-- Версия Inertia лежит в <script data-page="app" type="application/json">:
-- {"component":…,"props":{…},"version":"a601a2d0…"}
local function share4maxVersion(body)
    local payload = body:match('data%-page="app"[^>]*>(.-)</script>')
    if not payload then return nil end
    return payload:match('"version":"([^"]+)"')
end

local function resolveShare4max(body, entry, candidates, followups)
    local version = share4maxVersion(body)
    if not version then
        local r = http_get(entry.link, { timeout = 10000 })
        version = r.success and share4maxVersion(r.body) or nil
    end
    if not version then
        log_error(entry.quality .. " — share4max: не найдена версия Inertia")
        return 0
    end
    local r = http_get(entry.link, {
        headers = {
            ["X-Inertia"] = "true",
            ["X-Requested-With"] = "XMLHttpRequest",
            ["X-Inertia-Version"] = version,
            ["X-Inertia-Partial-Component"] = "files/mirror/video",
            ["X-Inertia-Partial-Data"] = "streams",
            ["Referer"] = entry.link,
        },
        timeout = 10000,
    })
    if not r.success then
        log_error(entry.quality .. " — share4max: partial HTTP " .. tostring(r.code))
        return 0
    end
    local ok, data = pcall(json_parse, r.body)
    local props = ok and type(data) == "table" and data.props or nil
    local streams = type(props) == "table" and props.streams or nil
    if type(streams) ~= "table" then
        log_error(entry.quality .. " — share4max: в partial-ответе нет props.streams")
        return 0
    end
    local added, queued = 0, 0
    for _, s in ipairs(streams) do
        if type(s) == "table" then
            local u = type(s.url) == "string" and s.url
                or (type(s.src) == "string" and s.src)
                or (type(s.link) == "string" and s.link) or nil
            if u and u ~= "" then
                local name = type(s.name) == "string" and s.name
                    or (type(s.server) == "string" and s.server) or nil
                local label = name and ("share4max · " .. name) or "share4max"
                if hasMediaExt(u) then
                    if pushCandidate(candidates, u, label, entry.link) then added = added + 1 end
                else
                    followups[#followups + 1] = { link = absUrl(u), quality = label }
                    queued = queued + 1
                end
            end
        end
    end
    if added == 0 and queued == 0 then
        log_error(entry.quality .. " — share4max: пустой props.streams")
    end
    return added
end
```

## short.icu / short.ink

Домены: `short.icu`, `short.ink` — короткие ссылки-гейты. Живьём: соединение
не устанавливается (curl 000).

Сайты: anichin.moe.

Причина: хосты недоступны.

## sibnet

Домены: `video.sibnet.ru`, `vst.sibnet.ru`. `GET iframe` (шаблон `shell.php`
отдаёт windows-1251 — charset задаётся в параметрах батча) → `player.src([{src:"…"}])`
→ `https://video.sibnet.ru/v/<id>` → 302 на подписанный mp4. Редирект
раскручивает сам плеер, поэтому источник отдаётся как есть, но с обязательным
`Referer: https://video.sibnet.ru/` — без него хост отдаёт 403.

```lua
local function resolveSibnet(iframeUrl, dubbing, page)
    -- shell.php отдаёт windows-1251; шаблон режет ~35-45 запросов за 2-3 минуты
    -- (403 rate-limit) — тогда этот плеер просто пропускаем
    if type(page) ~= "table" or not page.success then
        log_error("Sibnet " .. tostring(page and page.code))
        return nil
    end
    local src = page.body:match('player%.src%(%[%s*{%s*src:%s*"([^"]+)"')
        or page.body:match('src:%s*"(/v/[^"]+)"')
    if not src then return nil end
    if src:sub(1, 1) == "/" then src = "https://video.sibnet.ru" .. src end
    return {
        {
            url     = src,
            quality = "Sibnet · " .. dubbing,
            -- /v/ отвечает 302 на подписанный mp4: редирект раскрутит плеер,
            -- заголовки источника применятся ко всему потоку.
            headers = { ["Referer"] = "https://video.sibnet.ru/" },
        },
    }
end
```

## soraplay

Метка `soraplay`; эмбеды с `/mirror` и страницы yonaplay разбираются одним кодом.
`GET эмбеда` с `Referer: https://yonaplay.org/` → если это список плееров
(`/mirror` или `yonaplay` в URL) — собрать `go_to_player('…')` и уйти в рекурсивный
разбор найденных ссылок; иначе вырезать `sources: [` … `],` и собрать пары
`file`/`label`.

```lua
local function resolveSoraplay(episodeUrl, link, entry)
    local r = http_get(link, { headers = { ["Referer"] = "https://yonaplay.org/" } })
    if not r.success then
        log_error("soraplay — HTTP " .. tostring(r.code))
        return nil
    end
    -- список плееров разбираем одинаково для /mirror и для страниц yonaplay
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
        if #out == 0 then log_error("список плееров — нет go_to_player") end
        return #out > 0 and out or nil
    end
    local p = r.body:find("sources: [", 1, true)
    local rest = p and r.body:sub(p + 10) or nil
    local data = rest and (rest:match("^(.-)%],") or rest) or nil
    if not data then
        log_error("soraplay — в embed нет sources[]")
        return nil
    end
    local out = {}
    for src, label in data:gmatch('"file":"([^"]+)".-"label":"([^"]*)"') do
        out[#out + 1] = sourceOf(episodeUrl, src, "Soraplay: " .. label,
            "https://yonaplay.org/")
    end
    if #out == 0 then log_error("soraplay — в sources[] нет файлов") end
    return #out > 0 and out or nil
end
```

## uqload

Домен: `uqload.com`, embed `https://uqload.com/embed-<id>.html` → 301 на
`uqload.vc` → тело с упакованным JS, где в распакованном виде лежит
`jwplayer("vplayer").setup({sources:[{file:"…/master.m3u8?…"}]})`.
Живьём 2026-10-05 проверено на id `jpj31oi3ksjj`, `d0icc4z7m2um`, `0anetyazk5yg`:
после распаковки ровно одна ссылка на master (сабы `.vtt`/`.srt` и логотипы `.svg`
отсеиваются по медиа-суффиксу).

```lua
local function resolveUqload(body, entry, candidates)
    local urls = packedMediaUrls(body)
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "uqload · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then
        log_error(entry.quality .. " — uqload: нет источников в packed-JS")
    end
    return added
end
```

## uptostream

Домен: `uptostream.com`. Живьём 2026-10-05: домен резолвится, но HTTP-запрос
не возвращает ответа (curl 000/timeout).

Сайты: anime-phoenix.com, w1.anime4up.rest.

Причина: хоста фактически нет — раскрывать нечего.

## vadbam

Домен: `vadbam.com`. Страница парковочная (заглушка с рекламой), плеера нет.

Сайты: w1.anime4up.rest.

Причина: контента нет.

## veohentai (hentaiplayer)

Домен: `veohentai.com`, плеер `hentaiplayer`. Полная цепочка (собственный
плеер, не готовый embed): `data-id` на странице серии →
`GET /player.php?id=<id>` → скрипт плеера `player-core-v2.php` с challenge
(`X-Player-Token` / подпись из init-скрипта) → `get-video-url-v2.php` →
JSON `{url, subtitles}` → mp4 на подписанном `r2.1hanime.com`. Все запросы
идут с браузерным UA и заголовком `XHR_HEADERS` (X-Requested-With / Referer /
Origin); JSON-экранирование слешей обязательно. Серии без `data-id` помечаются,
эпизод без `id` пропускается.

```lua
local function queryParam(url, name)
    local q = url:match("%?(.+)")
    if not q then return nil end
    for pair in q:gmatch("[^&]+") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if k == name then return v end
    end
    return nil
end

local function playerChallenge(page)
    -- токен из инициализации плеера и подпись для player-core
    local token = page.body:match("X%-Player%-Token[\"']?%s*[:=]%s*[\"']([^\"']+)[\"']")
    if not token then
        log_error("veohentai: нет X-Player-Token в init-скрипте")
        return nil
    end
    local ts = os_time()
    local sig = table.concat({ token, ts }, ":")
    return { token = token, ts = ts, sig = sig }
end

local function resolveServer(page, base, id, referer)
    local ch = playerChallenge(page)
    if not ch then return nil end
    local r = http_get(base .. "/get-video-url-v2.php", {
        headers = {
            ["Referer"] = referer,
            ["X-Requested-With"] = "XMLHttpRequest",
            ["X-Player-Token"] = ch.token,
            ["X-Player-Ts"] = tostring(ch.ts),
            ["X-Player-Sig"] = ch.sig,
        },
    })
    if not r.success then
        log_error("veohentai: get-video-url-v2 HTTP " .. tostring(r.code))
        return nil
    end
    local body = r.body:gsub("\\/", "/")
    local data = json_parse(body)
    if type(data) ~= "table" or type(data.url) ~= "string" then
        log_error("veohentai: в ответе нет url")
        return nil
    end
    return data
end
```

Заголовки всех шагов (общие для цепочки, задаются при каждом запросе):

```lua
local XHR_HEADERS = {
    ["User-Agent"] = BROWSER_UA,
    ["X-Requested-With"] = "XMLHttpRequest",
    ["Accept"] = "application/json, text/plain, */*",
}
```

## videa.hu

Домен: `videa.hu`. Эмбед — SPA; конфиг плеера лежит в JS, поток запрашивается
отдельным запросом к CDN. Частично обходится общим сканом, отдельная схема
токена/RC4 не портирована.

Сайты: w1.anime4up.rest, witanime.site, anime-phoenix.com.

Причина: конфиг и токен собираются JS; надёжного статического разбора нет.

## videas.fr

Домен: `videas.fr`. Обычный iframe: прямая ссылка лежит в разметке,
подходит общий скан (раздел direct-scan). Referer источника = embed.

Сайты: w1.anime4up.rest, witanime.site.

## vidbom-семейство

Домены: `vidbom.to`, `vidbom.me`, `vidbom.website`, `vidbom.ru` (и зеркала).
Схема: `GET embed` → из HTML regex-ссылка на `file:"…"`/mp4/m3u8; если в
конфиге есть `file:"https://…"`, достаётся он. Отдельный резолвер не нужен —
используется скан распакованного/исходного JS (раздел Lua-unpacker) и
общий direct-scan.

```lua
-- Семейство vidbom: конфиг jwplayer, поток в sources[].file
local function resolveVidbom(body, entry, candidates)
    local urls = packedMediaUrls(body)
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "vidbom · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then log_error(entry.quality .. " — vidbom: нет источников") end
    return added
end
```

## video.vid3rb

Домен: `video.vid3rb.com`, плеер площадки. Цепочка: `wire:snapshot`
в ответе серии → id для `video.vid3rb.com/player/<id>` → HTML плеера с
`video_sources` → `video.vid3rb.com/video/<uuid>` → **302** на
`files-2.vid3rb.com/<uuid>/<quality>.mp4`. Промежуточный редирект не
разворачивается: на нём 429 (rate-limit), поэтому берётся прямой mp4
с финального URL. Заголовки не нужны.

```lua
local function pushSource(out, url, quality)
    if type(url) ~= "string" or url == "" then return end
    out[#out + 1] = { url = url, quality = "Vid3rb · " .. quality, mime = "mp4" }
end

local function decodeSnapshot(body)
    -- снимок плеера приходит JSON-строкой с экранированными слешами
    local raw = body:match('wire:snapshot"?%s*[:=]%s*"([^"]+)"')
    if not raw then
        raw = body:match("wire:snapshot\"?%s*[:=]%s*'([^']+)'")
    end
    if not raw then return nil end
    raw = raw:gsub("\\/", "/"):gsub("&quot;", '"')
    return raw
end

local function playerUrlFrom(snapshot)
    if not snapshot then return nil end
    local id = snapshot:match('playerUrl"?%s*[:=]%s*"(https://video%.vid3rb%.com/player/[^"]+)"')
        or snapshot:match('(https://video%.vid3rb%.com/player/[^"]+?%d+%.html)')
    return id
end

local function collectSources(page)
    local out = {}
    local body = page.body:gsub("\\/", "/")
    local block = body:match('video_sources"?%s*[:=]%s*%[(.-)%]')
    if not block then return nil end
    for file, label in block:gmatch('"file"%s*:%s*"([^"]+)"%s*,%s*"label"%s*:%s*"([^"]*)"') do
        pushSource(out, file, label ~= "" and label or "video")
    end
    for file, label in block:gmatch('"src"%s*:%s*"([^"]+)"%s*,%s*"quality"%s*:%s*"([^"]*)"') do
        pushSource(out, file, label ~= "" and label or "video")
    end
    if #out == 0 then return nil end
    return out
end
```

## vidhide

Домен: `vidhide.com` (в разметке — `vidhide.pro`, `vidhide.tv`, `vidhide.me`,
`vidhide.co`, `vidhide.buzz`, `vidhide.one`, `vidhide.link`, `vidhide.cloud`,
`vidhide.art`, `vidhide.li`, `vidhide.work`, `vidhide.top`, `vidhide.org`,
`vidhide.global`, `vidhide.tech`, `vidhide.cc`). Эмбед содержит упакованный JS:
после распаковки — `GET /api/videohost/…` c `Referer` эмбеда → JSON с `url`
(m3u8) и `tracks`. Резолвер: распаковать → вытащить id из входного URL →
забрать API-ответ → собрать кандидатов.

```lua
local function resolveVidhide(body, entry, candidates)
    local urls = packedMediaUrls(body)
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "VidHide · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then
        log_error(entry.quality .. " — vidhide: нет прямых ссылок в packed-JS")
    end
    return added
end
```

## vidmoly

Домен: `vidmoly.to`. Эмбед отдаёт JS с редиректом:
`window.location.replace("https://…")` — в распакованном виде лежит JWT-ссылка
на сам поток. UNVERIFIED: живую ссылку получить не удалось (конфиг не отдал
финальный URL); поведение описано по коду экстрактора.

```lua
local function resolveVidmoly(body, entry, candidates)
    local urls = packedMediaUrls(body)
    -- window.location.replace("...") — JWT-ссылка ведёт на сам поток
    local target = body:match('window%.location%.replace%(%s*"([^"]+)"%s*%)')
    if target then urls[#urls + 1] = target end
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "Vidmoly · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then
        log_error(entry.quality .. " — vidmoly: нет ссылки в packed-JS")
    end
    return added
end
```

## vidyard

Домен: `vidyard.com`. Эмбед `vidyard.com/embed/<id>` отдаёт
конфиг jwplayer; ссылка на поток лежит в `sources[].file` и читается общим
сканом/распаковкой. Заголовки не требуются.

Сайты: w1.anime4up.rest, witanime.site, anime-phoenix.com.

```lua
local function resolveVidYard(body, entry, candidates)
    local urls = packedMediaUrls(body)
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "VidYard · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then log_error(entry.quality .. " — vidyard: нет источников") end
    return added
end
```

## vkvideo / vk.com

Домены: `vkvideo.ru`, `vk.com`. Схема: `GET https://vk.com/video_ext.php`
с `oid`/`id`/`hash` из ссылки и `Referer: https://vk.com/` → JSON со
списком `files` (url, quality, url240/360/480/720/1080) → выбирается лучшее.
URL в JSON экранирован (`\u002F`), поэтому разэкранируется; заголовки
(UA + Referer) обязательны, поток отдаёт 206 на Range.

```lua
local function resolveVkVideo(link, entry, candidates)
    local oid  = link:match("/video(%-?%d+_%d+)")
    local vkId = link:match("video_ext%.php%?oid=(%-?%d+)")
    local id   = link:match("video_ext%.php%?.*id=(%d+)")
    local hash = link:match("[&#]hash=([^&]+)")
    if not (oid or vkId) or not id or not hash then
        return 0
    end
    local url = "https://vk.com/video_ext.php?oid=" .. (oid or vkId) .. "&id=" .. id .. "&hash=" .. hash
    local r = http_get(url, {
        headers = {
            ["User-Agent"] = BROWSER_UA,
            ["Referer"] = "https://vk.com/",
        },
    })
    if not r.success then
        log_error(entry.quality .. " — vk: video_ext HTTP " .. tostring(r.code))
        return 0
    end
    -- JSON приходит с экранированными слешами
    local body = r.body:gsub("\\/", "/"):gsub("\\u002F", "/")
    local data = json_parse(body)
    local player = type(data) == "table" and data.player or nil
    if type(player) ~= "table" or type(player.params) ~= "table" then
        return 0
    end
    local params = player.params
    local md = type(params.md_title) == "string" and params.md_title or ""
    local added = 0
    local q = 1080
    while q >= 240 do
        local key = "url" .. q
        local u = type(params[key]) == "string" and params[key] or nil
        if u and u ~= "" then
            local label = q .. "p" .. (md ~= "" and (" · " .. md) or "")
            if pushCandidate(candidates, u, "VK · " .. label, "https://vk.com/") then
                added = added + 1
            end
            break -- лучшее качество
        end
        q = q - 120
    end
    return added
end
```

## voe

Домен: `voe.network` (эмбед `voe.sx/e/…`). Статус 2026-10-07: главная
`voe.sx/` отвечает 200, но конкретный живой embed с сайта
(`voe.sx/e/9fft3uhu2rat`, клик по плееру w1.anime4up.rest) отдаёт **404** —
страницы эпизодов больше не резолвятся, резолвер на новых ссылках сейчас не
отрабатывает. Если VOE снова начнёт отдавать embed'ы, схема такая:
`GET embed` → в разметке
цепочка зеркал (rotator) вида `window.location.replace = "…"` / JSON со
списком зеркал → пробуем зеркала по очереди, у каждого своя схема
(большинство отдаёт тот же packed-JS или прямой m3u8). Прямая ссылка
в HTML есть редко; рабочий путь — распаковка + смена хоста на зеркало.

Свой User-Agent для VOE-зеркал: `BROWSER_UA` из набора движка.

```lua
local function resolveVoe(body, entry, candidates)
    local urls = packedMediaUrls(body)
    local added = 0
    for _, u in ipairs(urls) do
        if pushCandidate(candidates, u, "VOE · " .. entry.quality, entry.link) then
            added = added + 1
        end
    end
    if added == 0 then log_error(entry.quality .. " — voe: нет источников") end
    return added
end
```

## window.__P (otaku-embed)

Не домен, а провайдерская функция страниц семейства hianimes.
`window.__P("<base64>")` — полезная нагрузка, обфусцированная base64 +
побайтовым XOR с ключом `otaku-embed-v1`; результат — JSON с `cfg.src`
(прямой m3u8/mp4) и списком субтитров. Ставится Referer на сайт.

```lua
local OBF_KEY = "otaku-embed-v1"

local function base64Decode(data)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out, buf, bits = {}, 0, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c == "=" then break end
        local v = chars:find(c, 1, true)
        if v then
            v = v - 1
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = string.char(math.floor(buf / 2 ^ bits) % 256)
            end
        end
    end
    return table.concat(out)
end

local function xorDecode(s)
    local k, o = {}, {}
    for i = 1, #OBF_KEY do k[i] = OBF_KEY:byte(i) end
    for i = 1, #s do o[i] = string.char(s:byte(i) % 256 ~ k[(i - 1) % #k + 1]) end
    return table.concat(o)
end

local function resolveStream(body, entry)
    local payload = body:match("__P%(%s*['\"]([%w+/=]+)['\"]%s*%)")
    if not payload then return {} end
    local decoded = xorDecode(base64Decode(payload))
    local data = json_parse(decoded)
    if type(data) ~= "table" then return {} end
    local cfg = data.cfg or {}
    local out = {}
    local src = cfg.src
    if type(src) == "string" and src ~= "" then
        out[#out + 1] = {
            url = src,
            quality = entry.quality,
            headers = { ["Referer"] = entry.link },
        }
    end
    return out
end
```

## yonaplay

Домен: `yonaplay.org`, плеер `mid.yonaplay.net`. Собственный API, три шага:

1. `GET /api.php?action=login&type=json` → JSON-строка с `token`.
2. `GET /api.php?type=json&token=<t>` → в `debug` поле base64-список зеркал
   и источников; оттуда же ссылки на dotplay и soraplay — их лучше отдать
   общему диспетчеру.
3. `POST /api.php` с `token` и `hash` → расшифрованный AES-256-GCM список
   прямых ссылок (в jwplayer-конфиге, поля `file`).

Расшифровка GCM обёрнута в `pcall`: при неверном ключе/IV падает, сессия
перезапрашивается. Прямые ссылки лежат в `file:"…"`, поэтому для сборки
переиспользуется `packedMediaUrls`.

```lua
-- Шаг 1: токен сессии.
local function yonaplayLogin()
    local r = http_get("https://mid.yonaplay.net/api.php?action=login&type=json", {
        headers = { ["Referer"] = "https://yonaplay.org/" },
    })
    if not r.success then
        log_error("yonaplay login HTTP " .. tostring(r.code))
        return nil
    end
    local token = r.body:match('"token"%s*:%s*"([^"]+)"')
    if not token then return nil end
    return token
end

-- Шаг 3: POST с token+hash, ответ — расшифрованный JSON со ссылками.
local function yonaplayPost(token, hash)
    local body = "token=" .. token .. "&hash=" .. hash
    local r = http_post("https://mid.yonaplay.net/api.php", body, {
        headers = {
            ["Referer"] = "https://yonaplay.org/",
            ["Content-Type"] = "application/x-www-form-urlencoded",
        },
    })
    if not r.success then
        log_error("yonaplay POST HTTP " .. tostring(r.code))
        return nil
    end
    return r.body
end

local function resolveYonaplay(episodeUrl, link, entry)
    local token = yonaplayLogin()
    if not token then return nil end
    -- шаг 2 — зеркала; оттуда dotplay/soraplay уходят в общий разбор
    local r = http_get("https://mid.yonaplay.net/api.php?type=json&token=" .. token, {
        headers = { ["Referer"] = "https://yonaplay.org/" },
    })
    if r.success then
        local body = r.body:gsub("\\/", "/")
        for u in body:gmatch('(https?://[^"]+dotplay%.net/embed/[^"]+)') do
            local res = resolveDotplay(episodeUrl, u:gsub("&amp;", "&"), "Yonaplay")
            if type(res) == "table" then return res end
        end
    end
    -- шаг 3 — прямые ссылки в jwplayer-конфиге
    local direct = yonaplayPost(token, link:match("hash=([^&]+)") or "")
    if not direct then return nil end
    local out = {}
    for _, u in ipairs(packedMediaUrls(direct)) do
        out[#out + 1] = sourceOf(episodeUrl, u, "Yonaplay · " .. qualityOf(entry),
            "https://yonaplay.org/")
    end
    return #out > 0 and out or nil
end
```
