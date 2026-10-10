-- =====================================================================
-- Lib: bysekoze — цепочка доступа Byse (filemoon-клон):
--      details -> access/challenge -> access/attest (ECDSA P-256) ->
--      embed/captcha (PoW) -> captcha/verify -> embed/playback ->
--      AES-256-GCM -> sources[].url.
-- Loaded via require_lib("bysekoze"). No dependencies on other libs.
--
-- Живой сквозной прогон 2026-10-10 (Node/curl, код fsjcjqhnhtph):
--   details 200 -> challenge 200 -> attest 200 (confidence 0.45..0.7) ->
--   captcha 200 (pow_difficulty 16) -> verify 200 -> playback 200 ->
--   decrypt -> master.m3u8 -> 200 application/vnd.apple.mpegurl.
-- Все URL/тела/заголовки ниже — те же, что в этом прогоне.
-- Телеметрию (view/heartbeat/timeslider/settings) не реализуем.
-- =====================================================================
local version = "1.0.0"

local M = {}

-- Бюджет запросов: origin-iframe за CF, авто-обход ждёт до 15с.
local EMBED_TIMEOUT = 22000
local SITE = "https://bysekoze.com"
local BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    .. "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

-- ── JSON-тела вручную (движок отдаёт json_encode только как опцию; тела
--    ниже — фиксированный набор полей, сериализация тривиальна). ──────────
local function jstr(s)
    local esc = tostring(s):gsub('([\\"])', '\\%0')
    return '"' .. esc .. '"'
end

-- fingerprint из ответа attest; confidence пересылаем как сырой числовой
-- текст из ответа — без повторного форматирования числа.
local function fingerprintJson(fp)
    local s = '{"token":' .. jstr(fp.token)
        .. ',"viewer_id":' .. jstr(fp.viewer_id)
        .. ',"device_id":' .. jstr(fp.device_id)
    if fp.confidence then s = s .. ',"confidence":' .. fp.confidence end
    return s .. '}'
end

-- ── PoW: решает движок — pow_solve (PowSolver.kt, тот же gr/wr, что в
--    JS-бандле origin-iframe; ~1с на difficulty 16).
--
--    Чистого-Lua решателя здесь НЕТ сознательно: порт gr() на LuaJ даёт
--    ~150 хэшей/с (замер 2026-10-10; lua CLI — ~540/с), а реальные
--    решения уходят в 35k..150k итераций — это минуты блокировки вместо
--    секунды на JVM. Оба движка (NoveLA LuaSourceLoader.kt и
--    plugin-tester) обязаны регистрировать pow_solve. ─────────────────────
function M.solvePow(nonce, difficulty)
    if type(pow_solve) ~= "function" then
        log_error("bysekoze: pow_solve unavailable")
        return nil
    end
    local ok, sol = pcall(pow_solve, nonce, difficulty)
    if not ok then
        log_error("bysekoze: pow_solve failed: " .. tostring(sol))
        return nil
    end
    if type(sol) ~= "string" and type(sol) ~= "number" then
        log_error("bysekoze: pow_solve returned " .. type(sol)
            .. " (difficulty " .. tostring(difficulty) .. ")")
        return nil
    end
    return tostring(sol)
end

-- ── Дешифровка playback: key = key_parts[version] .. key_parts[31-version]
--    (1-based; так же делает Qa()/ws() в JS, версии 1..20). ───────────────
local function decryptPlayback(body)
    local obj = body:match('"playback"%s*:%s*(%b{})')
    if not obj then
        log_error("bysekoze: no playback object, head=" .. body:sub(1, 200))
        return nil
    end
    local ivB64 = obj:match('"iv"%s*:%s*"([^"]+)"')
    local payloadB64 = obj:match('"payload"%s*:%s*"([^"]+)"')
    local version = tonumber(obj:match('"version"%s*:%s*"?([%d]+)"?'))
    local arr = obj:match('"key_parts"%s*:%s*(%b[])')
    if not ivB64 or not payloadB64 or not arr then
        log_error("bysekoze: playback misses iv/payload/key_parts")
        return nil
    end
    local parts = {}
    for p in arr:gmatch('"([^"]+)"') do parts[#parts + 1] = p end

    local i1, i2
    if version and version >= 1 and version <= 20 then
        i1, i2 = version, 31 - version
    end
    if not i1 or not parts[i1] or not parts[i2] then
        log_error("bysekoze: unsupported key version " .. tostring(version)
            .. " (" .. #parts .. " parts)")
        return nil
    end
    if type(aes_gcm_decrypt) ~= "function"
        or type(base64_decode_bytes) ~= "function" then
        log_error("bysekoze: aes_gcm_decrypt/base64_decode_bytes unavailable")
        return nil
    end

    local k1 = base64_decode_bytes(parts[i1])
    local k2 = base64_decode_bytes(parts[i2])
    local iv = base64_decode_bytes(ivB64)
    local payload = base64_decode_bytes(payloadB64)
    if not k1 or not k2 or not iv or not payload or #payload <= 16 then
        local plen = type(payload) == "string" and tostring(#payload) or "nil"
        log_error("bysekoze: bad base64 in playback (parts=" .. #parts
            .. " payload=" .. plen .. "B)")
        return nil
    end
    -- payload = ct .. tag (tag — последние 16 байт).
    local ct = payload:sub(1, #payload - 16)
    local tag = payload:sub(#payload - 15)
    local key = k1 .. k2
    local plain = aes_gcm_decrypt(key, iv, ct, tag)
    if type(plain) ~= "string" or plain == "" then
        log_error("bysekoze: aes_gcm_decrypt failed (key=" .. #key
            .. "B iv=" .. #iv .. "B ct=" .. #ct .. "B)")
        return nil
    end
    return plain
end

-- Первый HLS-источник; остальное (mp4 и пр.) — фоллбэк.
local function pickSource(plain)
    local sources = plain:match('"sources"%s*:%s*(%b[])')
    if not sources then
        log_error("bysekoze: no sources[] in payload, head=" .. plain:sub(1, 200))
        return nil
    end
    local fbUrl, fbMime
    for obj in sources:gmatch('(%b{})') do
        local u = obj:match('"url"%s*:%s*"([^"]+)"')
        local mime = obj:match('"mime_type"%s*:%s*"([^"]+)"')
        if u and u ~= "" then
            if u:find(".m3u8", 1, true)
                or (mime and mime:find("mpegurl", 1, true)) then
                return u, "hls"
            end
            if not fbUrl then fbUrl, fbMime = u, mime end
        end
    end
    if not fbUrl then
        log_error("bysekoze: sources[] has no url")
        return nil
    end
    -- ponytail: bysekoze отдаёт HLS (filemoon-клон); mp4 помечаем по mime.
    return fbUrl, (fbMime and fbMime:find("mp4", 1, true)) and "mp4" or "hls"
end

-- embedUrl: https://bysekoze.com/e/{code}
-- Возвращает url, mime ("hls"|"mp4"), ref; nil при любой неудаче шага.
function M.extractBysekoze(embedUrl)
    local code = type(embedUrl) == "string" and embedUrl:match("/e/([%w_-]+)") or nil
    if not code then
        log_error("bysekoze: no /e/{code} in " .. tostring(embedUrl))
        return nil
    end
    local parent = SITE .. "/e/" .. code

    -- Контракт движка: свежий эфемерный P-256 keypair на каждый вызов.
    -- Проверяем сразу, до сетевых шагов.
    if type(ecdsa_sign_p256) ~= "function" then
        log_error("bysekoze: ecdsa_sign_p256 unavailable")
        return nil
    end

    -- 1. details: путь origin-iframe (и сам origin) рандомны на каждый
    --    запрос — только из embed_frame_url, без хардкода.
    local d = http_get(SITE .. "/api/videos/" .. code .. "/embed/details", {
        timeout = EMBED_TIMEOUT,
        headers = { ["User-Agent"] = BROWSER_UA },
    })
    if not d or not d.success or type(d.body) ~= "string" then
        log_error("bysekoze: details HTTP " .. tostring(d and d.code))
        return nil
    end
    local frame = d.body:match('"embed_frame_url"%s*:%s*"([^"]+)"')
    local origin = frame and frame:match("^(https?://[^/]+)")
    if not origin then
        log_error("bysekoze: no embed_frame_url (HTTP " .. tostring(d.code)
            .. ") head=" .. d.body:sub(1, 200))
        return nil
    end

    -- Все запросы origin-iframe — с X-Embed-Parent (как в браузере).
    local function post(path, body)
        return http_post(origin .. path, body, {
            timeout = EMBED_TIMEOUT,
            headers = {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = BROWSER_UA,
                ["X-Embed-Parent"] = parent,
            },
        })
    end

    -- 2a. challenge
    local c = post("/api/videos/access/challenge", "{}")
    if not c or not c.success or type(c.body) ~= "string" then
        log_error("bysekoze: challenge HTTP " .. tostring(c and c.code)
            .. " " .. tostring(c and c.body and c.body:sub(1, 160)))
        return nil
    end
    local challengeId = c.body:match('"challenge_id"%s*:%s*"([^"]+)"')
    local nonce = c.body:match('"nonce"%s*:%s*"([^"]+)"')
    if not challengeId or not nonce then
        log_error("bysekoze: challenge parse failed head=" .. c.body:sub(1, 200))
        return nil
    end

    -- 2b. attest: свежий эфемерный P-256 keypair на каждый вызов.
    local okSig, sig = pcall(ecdsa_sign_p256, nonce)
    if not okSig or type(sig) ~= "table" or type(sig.signature) ~= "string"
        or type(sig.x) ~= "string" or type(sig.y) ~= "string" then
        log_error("bysekoze: ecdsa_sign_p256 failed: " .. tostring(sig))
        return nil
    end
    -- Минимальный client/storage (так же проходит живой прогон,
    -- confidence 0.45..0.7 — для playback достаточно).
    local attestBody = '{"viewer_id":"","device_id":""'
        .. ',"challenge_id":' .. jstr(challengeId)
        .. ',"nonce":' .. jstr(nonce)
        .. ',"signature":' .. jstr(sig.signature)
        .. ',"public_key":{"kty":"EC","crv":"P-256","x":' .. jstr(sig.x)
        .. ',"y":' .. jstr(sig.y) .. '}'
        .. ',"client":{"user_agent":' .. jstr(BROWSER_UA) .. '}'
        .. ',"storage":{},"attributes":{"entropy":"low"}}'
    local a = post("/api/videos/access/attest", attestBody)
    if not a or not a.success or type(a.body) ~= "string" then
        log_error("bysekoze: attest HTTP " .. tostring(a and a.code)
            .. " " .. tostring(a and a.body and a.body:sub(1, 200)))
        return nil
    end
    local fp = {
        token = a.body:match('"token"%s*:%s*"([^"]+)"'),
        viewer_id = a.body:match('"viewer_id"%s*:%s*"([^"]+)"'),
        device_id = a.body:match('"device_id"%s*:%s*"([^"]+)"'),
        confidence = a.body:match('"confidence"%s*:%s*([%d%.eE+-]+)'),
    }
    if not fp.token or not fp.viewer_id or not fp.device_id then
        log_error("bysekoze: attest parse failed head=" .. a.body:sub(1, 200))
        return nil
    end
    local fpJson = fingerprintJson(fp)

    -- 2c. captcha -> PoW challenge
    local cap = post("/api/videos/" .. code .. "/embed/captcha",
        '{"fingerprint":' .. fpJson .. '}')
    if not cap or not cap.success or type(cap.body) ~= "string" then
        log_error("bysekoze: captcha HTTP " .. tostring(cap and cap.code)
            .. " " .. tostring(cap and cap.body and cap.body:sub(1, 160)))
        return nil
    end
    local powNonce = cap.body:match('"pow_nonce"%s*:%s*"([^"]+)"')
    local powToken = cap.body:match('"pow_token"%s*:%s*"([^"]+)"')
    local difficulty = tonumber(cap.body:match('"pow_difficulty"%s*:%s*(%d+)'))
    if not powNonce or not powToken or not difficulty then
        log_error("bysekoze: captcha parse failed head=" .. cap.body:sub(1, 200))
        return nil
    end

    -- 2d. PoW: leadingZeroBits(gr(nonce .. ":" .. n)) >= difficulty.
    local solution = M.solvePow(powNonce, difficulty)
    if not solution then
        log_error("bysekoze: PoW failed (difficulty " .. difficulty .. ")")
        return nil
    end

    -- 2e. verify (solution — СТРОКА, не число: так принимает сервер).
    local v = post("/api/videos/" .. code .. "/embed/captcha/verify",
        '{"pow_token":' .. jstr(powToken)
        .. ',"solution":' .. jstr(solution)
        .. ',"fingerprint":' .. fpJson .. '}')
    if not v or not v.success or type(v.body) ~= "string" then
        log_error("bysekoze: verify HTTP " .. tostring(v and v.code)
            .. " " .. tostring(v and v.body and v.body:sub(1, 160)))
        return nil
    end
    local captchaToken = v.body:match('"token"%s*:%s*"([^"]+)"')
    if not v.body:match('"status"%s*:%s*"ok"') or not captchaToken then
        log_error("bysekoze: verify rejected head=" .. v.body:sub(1, 200))
        return nil
    end

    -- 2f. playback (заголовок — токен проверки captcha)
    local p = http_post(origin .. "/api/videos/" .. code .. "/embed/playback",
        '{"fingerprint":' .. fpJson .. '}', {
            timeout = EMBED_TIMEOUT,
            headers = {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = BROWSER_UA,
                ["X-Embed-Parent"] = parent,
                ["X-Captcha-Token"] = captchaToken,
            },
        })
    if not p or not p.success or type(p.body) ~= "string" then
        log_error("bysekoze: playback HTTP " .. tostring(p and p.code)
            .. " " .. tostring(p and p.body and p.body:sub(1, 160)))
        return nil
    end

    -- 2g. decrypt -> sources
    local plain = decryptPlayback(p.body)
    if not plain then return nil end
    local url, mime = pickSource(plain)
    if not url or not url:find("^https?://") then
        log_error("bysekoze: bad source url " .. tostring(url))
        return nil
    end
    return url, mime, origin
end

return M
