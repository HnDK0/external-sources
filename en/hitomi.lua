-- ── Hitomi ──
-- Источник: https://hitomi.la/ — галереи изображений (доудзинси/манга/арты).
-- Сайт отдаёт списки/поиск/чтение только через клиентские скрипты, поэтому
-- плагин повторяет логику JS-клиента сайта:
--   * каталог — свежие галереи из бинарного индекса .nozomi (или RSS-фолбэк);
--   * поиск по тегам — пересечение/вычитание ID из бинарных индексов .nozomi;
--   * чтение — картинки галереи по хешам из galleries/<id>.js.

-- ── Метаданные ──
id           = "hitomi"
name         = "Hitomi"
version  = "1.14.2"
baseUrl      = "https://hitomi.la/"
language     = "en"
content_type = "manga"
icon         = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/hitomi.png"

-- CDN-база: на ней живут .nozomi-индексы, карточки галерей и служебные JS.
local CDN = "https://ltn.gold-usergeneratedcontent.net"

-- ── Хелперы ──

-- Превращает любую ссылку с сайта в абсолютную.
local function absUrl(href)
	if href == nil or href == "" then return "" end
	if string.sub(href, 1, 2) == "//" then return "https:" .. href end
	if string.match(href, "^https?://") then return href end
	return url_resolve(baseUrl, href)
end

-- ID галереи из URL вида /<type>/<slug>-<123456>.html
local function galleryIdFromUrl(url)
	return string.match(url, "(%d+)%.html$")
end

-- ── SHA256 (чистый Lua) ──
-- Нужен для B-tree: hash_term(term) = SHA256(term)[0..3].
-- Битовые операции через пошаговый перебор бит (Lua 5.1 совместимо).

local function bxor32(a, b)
	local r, p = 0, 1
	for _ = 1, 32 do
		if (a % 2 + b % 2) % 2 == 1 then r = r + p end
		a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
	end
	return r
end

local function band32(a, b)
	local r, p = 0, 1
	for _ = 1, 32 do
		if a % 2 == 1 and b % 2 == 1 then r = r + p end
		a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
	end
	return r
end

local function bnot32(a) return 4294967295 - a end
local function rshift32(a, n) return math.floor(a / 2 ^ n) end
local function lshift32(a, n) return (a * 2 ^ n) % 4294967296 end
local function rotl32(a, n) return bxor32(lshift32(a, n), rshift32(a, 32 - n)) end
local function rotr32(a, n) return bxor32(rshift32(a, n), lshift32(a, 32 - n)) end

local SHA256_K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function sha256(msg)
	-- Пре-процессинг: добавляем padding
	local len = #msg
	local bits = len * 8
	msg = msg .. "\128"
	while #msg % 64 ~= 56 do msg = msg .. "\0" end
	-- Длина в big-endian (MSB первый), как требует SHA-256
	local lenBytes = {}
	for i = 1, 8 do
		lenBytes[i] = bits % 256
		bits = math.floor(bits / 256)
	end
	for i = 8, 1, -1 do
		msg = msg .. string.char(lenBytes[i])
	end

	local H = {
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
	}

	for offset = 1, #msg, 64 do
		local W = {}
		for t = 0, 15 do
			local a, b, c, d = string.byte(msg, offset + t * 4, offset + t * 4 + 3)
			W[t] = a * 16777216 + b * 65536 + c * 256 + d
		end
		for t = 16, 63 do
			local s0 = bxor32(rotr32(W[t - 15], 7), bxor32(rotr32(W[t - 15], 18), rshift32(W[t - 15], 3)))
			local s1 = bxor32(rotr32(W[t - 2], 17), bxor32(rotr32(W[t - 2], 19), rshift32(W[t - 2], 10)))
			W[t] = (W[t - 16] + s0 + W[t - 7] + s1) % 4294967296
		end

		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for t = 0, 63 do
			local S1 = bxor32(rotr32(e, 6), bxor32(rotr32(e, 11), rotr32(e, 25)))
			local ch = bxor32(band32(e, f), band32(bnot32(e), g))
			local t1 = (h + S1 + ch + SHA256_K[t + 1] + W[t]) % 4294967296
			local S0 = bxor32(rotr32(a, 2), bxor32(rotr32(a, 13), rotr32(a, 22)))
			local maj = bxor32(band32(a, b), bxor32(band32(a, c), band32(b, c)))
			local t2 = (S0 + maj) % 4294967296
			h = g; g = f; f = e; e = (d + t1) % 4294967296
			d = c; c = b; b = a; a = (t1 + t2) % 4294967296
		end
		H[1] = (H[1] + a) % 4294967296; H[2] = (H[2] + b) % 4294967296
		H[3] = (H[3] + c) % 4294967296; H[4] = (H[4] + d) % 4294967296
		H[5] = (H[5] + e) % 4294967296; H[6] = (H[6] + f) % 4294967296
		H[7] = (H[7] + g) % 4294967296; H[8] = (H[8] + h) % 4294967296
	end

	local hash = ""
	for i = 1, 8 do
		local v = H[i]
		hash = hash .. string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
	end
	return hash
end

-- ── B-tree: поиск по хешу тега в galleriesindex ──
-- Формат узла (searchlib.js decode_node):
--   int32 numKeys → [int32 keySize + keySize байт] × numKeys
--   int32 numDatas → [uint64 offset + int32 length] × numDatas
--   17 × uint64 subnode_address

local GALLERIES_INDEX_DIR = "galleriesindex"

-- Преобразование body из http_get(binary=true) в строку.
-- Движок может вернуть строку или таблицу байтов (Java byte[] — 0-indexed).
local function toRawString(body)
	if type(body) == "string" then return body end
	if type(body) ~= "table" then return tostring(body) end
	-- Таблица: определяем индексацию по ключам
	local t = {}
	if body[0] ~= nil then
		-- 0-indexed (Java byte[] из binary-ответа).
		-- Java byte[] — signed (-128..127); string.char ожидает 0..255.
		local i = 0
		while body[i] ~= nil do
			local v = body[i]
			if v < 0 then v = v + 256 end
			t[#t + 1] = string.char(v)
			i = i + 1
		end
	else
		-- 1-indexed (стандартная Lua-таблица)
		for i = 1, #body do
			local v = body[i] or 0
			if v < 0 then v = v + 256 end
			t[i] = string.char(v)
		end
	end
	return table.concat(t)
end

local function read32BE(s, o)
	local b0, b1, b2, b3 = string.byte(s, o, o + 3)
	if not b0 or not b1 or not b2 or not b3 then return 0 end
	return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3
end

local function read64BE(s, o)
	return string.byte(s, o) * 72057594037927936 + string.byte(s, o + 1) * 281474976710656
		+ string.byte(s, o + 2) * 1099511627776 + string.byte(s, o + 3) * 4294967296
		+ string.byte(s, o + 4) * 16777216 + string.byte(s, o + 5) * 65536 + string.byte(s, o + 6) * 256
		+ string.byte(s, o + 7)
end

-- Диагностический хелпер: байты → hex строка
local function toHex(bytes)
	local hex = "0x"
	for i = 1, #bytes do
		hex = hex .. string.format("%02x", bytes[i])
	end
	return hex
end

-- Декодирование узла B-tree из бинарных данных.
local function decodeNode(body)
	local s = toRawString(body)
	local o = 1
	local numKeys = read32BE(s, o); o = o + 4
	local keys = {}
	for i = 1, numKeys do
		local keySize = read32BE(s, o); o = o + 4
		local key = {}
		for j = 1, keySize do key[j] = string.byte(s, o); o = o + 1 end
		keys[i] = key
	end
	local numDatas = read32BE(s, o); o = o + 4
	local datas = {}
	for i = 1, numDatas do
		local off = read64BE(s, o); o = o + 8
		local len = read32BE(s, o); o = o + 4
		datas[i] = { offset = off, length = len }
	end
	local subnodes = {}
	for i = 1, 17 do subnodes[i] = read64BE(s, o); o = o + 8 end
	return { keys = keys, datas = datas, subnodes = subnodes }
end

-- Побайтовое сравнение двух массивов байтов (как в locate_key(searchlib.js)).
-- compare_arraybuffers(searchlib.js): compare up to min length, return 0 if equal prefix.
local function compareBytes(a, b)
	local n = math.min(#a, #b)
	for i = 1, n do
		if a[i] < b[i] then return -1 end
		if a[i] > b[i] then return 1 end
	end
	return 0
end

-- Преобразование строки в таблицу байтов.
local function stringToBytes(s)
	local t = {}
	for i = 1, #s do t[i] = string.byte(s, i) end
	return t
end

-- Преобразование hex-строки в таблицу байтов (по 2 hex-символа → 1 байт).
-- Нужен для hash_term: SHA256 → hex → первые 4 байта (как Uint8Array в JS).
local function hexToBytes(hex)
	local t = {}
	for i = 1, math.floor(#hex / 2) do
		t[i] = tonumber(string.sub(hex, i * 2 - 1, i * 2), 16)
	end
	return t
end

local function hashTerm(term)
	-- sha256() возвращает сырые байты (32 байта), а не hex.
	-- hash_term в JS: new Uint8Array(sha256.array(term).slice(0, 4))
	local raw = sha256(term)
	local t = {}
	for i = 1, 4 do t[i] = string.byte(raw, i) end
	return t
end

-- Получение списка ID галерей из блока данных (offset, length) в data-файле.
-- B-tree хранит абсолютный offset начала блока и length = 4 + count*4.
-- Запрашиваем bytes=(offset+4)-(offset+length-1), т.е. пропускаем int32 count
-- и читаем только массив ID (как в node-hitomi requestIds).
local function fetchGalleryIds(version, offset, length)
	local dataStart = offset + 4
	local r = http_get(CDN .. "/" .. GALLERIES_INDEX_DIR .. "/galleries." .. version .. ".data", {
		binary = true,
		headers = { Range = "bytes=" .. dataStart .. "-" .. (dataStart + length - 5) }
	})
	if not r or not r.success or not r.body then return {} end
	local s = toRawString(r.body)
	local ids = {}
	local o = 1
	while o + 3 <= #s do
		ids[#ids + 1] = read32BE(s, o)
		o = o + 4
	end
	return ids
end

-- Версия индекса galleriesindex (кэшируется на сессию).
local _galleriesVersion = nil

local function getGalleriesVersion()
	if _galleriesVersion then return _galleriesVersion end
	local r = http_get(CDN .. "/" .. GALLERIES_INDEX_DIR .. "/version")
	if r and r.success and r.body then
		_galleriesVersion = string.match(r.body, "%d+")
	end
	return _galleriesVersion
end

-- Кэш B-tree узлов: ключ = "version:address", значение = decoded node.
-- Позволяет не перезагружать один и тот же узел при поиске разных термов
-- (все термы проходят через корневой узел address=0).
local _nodeCache = {}

-- B-tree поиск: находит ID галерей для bare-тега/текста (без ':', типа "harem" или "naruto").
-- Логика: hashTerm → get_node_at_address(root=0) → B_search → get_galleryids_from_data.
local function btreeSearch(term)
	local version = getGalleriesVersion()
	if not version then
		log_error("hitomi: galleriesindex version not available")
		return {}
	end

	local target = hashTerm(term)
	local field = "galleries"

	log_error("hitomi: B-tree search term=\"" .. term .. "\" target=" .. toHex(target)
		.. " targetLen=" .. #target)

	local nodeAddress = 0
	for level = 1, 20 do -- защита от бесконечного цикла (глубина дерева ~4-5)
		-- Проверяем кэш узлов: version:address → decoded node
		local cacheKey = version .. ":" .. nodeAddress
		local node = _nodeCache[cacheKey]
		if not node then
			local r = http_get(CDN .. "/" .. GALLERIES_INDEX_DIR .. "/" .. field .. "." .. version .. ".index", {
				binary = true,
				headers = { Range = "bytes=" .. nodeAddress .. "-" .. (nodeAddress + 463) }
			})
			if not r or not r.success or not r.body then
				log_error("hitomi: B-tree node fetch failed addr=" .. nodeAddress .. " level=" .. level)
				return {}
			end
			node = decodeNode(r.body)
			_nodeCache[cacheKey] = node
		end
		if #node.keys == 0 then
			log_error("hitomi: B-tree level=" .. level .. " addr=" .. nodeAddress .. " keys=0 (empty node)")
			return {}
		end

		-- Диагностика: показать ключи узла
		local firstKey = toHex(node.keys[1])
		local lastKey = toHex(node.keys[#node.keys])
		local keySize = #node.keys[1]
		local hasSubnodes = node.subnodes[1] ~= 0
		log_error("hitomi: B-tree level=" .. level .. " addr=" .. nodeAddress
			.. " numKeys=" .. #node.keys .. " keySize=" .. keySize
			.. " first=" .. firstKey .. " last=" .. lastKey
			.. " hasSubnodes=" .. tostring(hasSubnodes))

		-- Линейный поиск: find first key >= target (как locate_key в searchlib.js)
		local where = #node.keys + 1
		for i = 1, #node.keys do
			if compareBytes(target, node.keys[i]) <= 0 then
				where = i
				break
			end
		end

		-- Ключ найден точно — возвращаем данные
		if where <= #node.keys and compareBytes(target, node.keys[where]) == 0 then
			local data = node.datas[where]
			log_error("hitomi: B-tree EXACT MATCH at level=" .. level .. " where=" .. where)
			return fetchGalleryIds(version, data.offset, data.length)
		end

		log_error("hitomi: B-tree level=" .. level .. " no match, where=" .. where
			.. " subnode=" .. tostring(node.subnodes[where]))

		-- Ключ не найден: если лист — пусто; иначе — спускаемся в поддерево
		if node.subnodes[where] == 0 then
			log_error("hitomi: B-tree leaf at level=" .. level .. ", key not found")
			return {}
		end
		nodeAddress = node.subnodes[where]
	end

	log_error("hitomi: B-tree depth exceeded for term=" .. term)
	return {}
end

-- ── Nozomi: бинарный индекс или строковый фолбэк ──

-- Разбор бинарного индекса .nozomi: 4 байта big-endian на ID галереи.
-- toRawString нормализует и строку, и таблицу байтов (в т.ч. signed Java byte[]).
local function parseNozomi(body)
	if not body then return {} end
	local s = toRawString(body)
	if #s < 4 then return {} end
	local ids = {}
	local n = math.floor(#s / 4)
	for i = 0, n - 1 do
		local o = i * 4 + 1
		ids[i + 1] = read32BE(s, o)
	end
	return ids
end

-- URL .nozomi для терма запроса (логика из search.js get_galleryids_for_query):
--   index-all      -> n/index-all.nozomi
--   language:X     -> n/index-X.nozomi
--   male:Y/female:Y -> n/tag/<ns>:<tag>-all.nozomi
--   прочее ns:X    -> n/<ns>/<tag>-all.nozomi (может 404, если нет nozomi)
--   простой тег     -> n/tag/<term>-all.nozomi (может 404)
--   popular-*      -> nil (обрабатывается отдельно в getCatalogFiltered с языком)
local function termToNozomiUrl(term)
	if term == "index-all" then
		return CDN .. "/n/index-all.nozomi"
	end
	-- Популярность по периоду: popular-today, popular-week, popular-month, popular-year
	-- URL формат: n/popular/month-<language>.nozomi (нужен язык из фильтров)
	-- Здесь просто возвращаем nil — обработка в getCatalogFiltered напрямую
	local popPeriod = string.match(term, "^popular%-(.+)$")
	if popPeriod then
		return nil
	end
	local colon = string.find(term, ":")
	if colon then
		local ns = string.sub(term, 1, colon - 1)
		local tag = string.sub(term, colon + 1)
		if ns == "language" then
			return CDN .. "/n/index-" .. tag .. ".nozomi"
		elseif ns == "male" or ns == "female" then
			return CDN .. "/n/tag/" .. ns .. ":" .. url_encode(tag) .. "-all.nozomi"
		else
			return CDN .. "/n/" .. ns .. "/" .. url_encode(tag) .. "-all.nozomi"
		end
	end
	return CDN .. "/n/tag/" .. url_encode(term) .. "-all.nozomi"
end

-- Декодирование URL-кодированных символов (%XX → символ).
-- Читалка может передавать запрос с %3A вместо ':', %20 вместо пробела и т.д.
local function urlDecode(s)
	if not s then return "" end
	return string.gsub(s, "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end)
end

-- Разбивка строки запроса на включаемые (+) и исключаемые (-) термы.
-- Сначала URL-декодируем всю строку, чтобы %3A → ':' и т.д.
local function parseQuery(input)
	local positives, negatives = {}, {}
	local decoded = urlDecode(input or "")
	for w in string.gmatch(decoded, "%S+") do
		w = string.lower(w)
		if string.sub(w, 1, 1) == "-" and #w > 1 then
			table.insert(negatives, string.sub(w, 2))
		else
			table.insert(positives, w)
		end
	end
	return positives, negatives
end

-- ── Движок поиска по ID ──

-- Кэш термов на сессию: повторный запрос того же .nozomi не нужен.
local _termCache = {}

-- Список ID галерей для одного терма (с кэшем; при ошибке — пустой список).
-- Стратегия (как в JS get_galleryids_for_query):
--   * терм с ':' (тег типа female:harem) → nozomi;
--   * bare-слово (galcos, harem) → B-tree (galleriesindex), fallback на nozomi.
local function termIds(term)
	if _termCache[term] then return _termCache[term] end
	local ids = {}

	local colon = string.find(term, ":")
	if colon then
		-- Тег с namespace: nozomi (как в JS-клиенте)
		local url = termToNozomiUrl(term)
		if url then
			log_error("hitomi: termIds(\"" .. term .. "\") → nozomi: " .. url)
			local ok, r = pcall(http_get, url, { binary = true })
			if ok and r and r.success and r.body then
				ids = parseNozomi(r.body)
				log_error("hitomi: nozomi returned " .. #ids .. " IDs for \"" .. term .. "\"")
			else
				log_error("hitomi: nozomi FAILED for \"" .. term .. "\" ok=" .. tostring(ok))
			end
		end
	elseif not string.match(term, "^popular%-") then
		-- Bare-слово: сначала B-tree (как hash_term + B_search в JS)
		ids = btreeSearch(term)
		log_error("hitomi: termIds(\"" .. term .. "\") → B-tree: " .. #ids .. " IDs")
		-- Fallback на nozomi если B-tree пуст (некоторые теги есть в nozomi, но не в B-tree)
		if #ids == 0 then
			local url = termToNozomiUrl(term)
			if url then
				log_error("hitomi: B-tree пуст, fallback nozomi: " .. url)
				local ok, r = pcall(http_get, url, { binary = true })
				if ok and r and r.success and r.body then
					ids = parseNozomi(r.body)
					log_error("hitomi: fallback nozomi returned " .. #ids .. " IDs for \"" .. term .. "\"")
				end
			end
		end
	end

	_termCache[term] = ids
	return ids
end

-- Итоговый список ID для запроса: пересечение включаемых (AND),
-- вычитание исключаемых (-), как это делает клиентский search.js.
local function queryGalleryIds(query)
	local positives, negatives = parseQuery(query)
	-- Фильтруем служебные термы: orderby:*, orderbykey:* — директивы сортировки, не nozomi-индексы.
	-- type:* — не имеет nozomi-файлов, пропускаем (ограничение движка).
	local filteredPos = {}
	for _, t in ipairs(positives) do
		if not string.match(t, "^orderby:") and not string.match(t, "^orderbykey:") and not string.match(t, "^type:") then
			filteredPos[#filteredPos + 1] = t
		end
	end
	positives = filteredPos
	if #positives == 0 then
		table.insert(positives, "index-all")
	end

	-- Предварительная загрузка всех термов: заполняем _termCache и _nodeCache.
	-- Последующие вызовы termIds() будут мгновенными (кэш).
	-- Каждый B-tree запрос делает 7 HTTP, но узлы кэшируются:
	-- первый терм грузит 7 узлов, второй-четвёртый — только новые на глубоких уровнях.
	for _, t in ipairs(positives) do termIds(t) end
	for _, t in ipairs(negatives) do termIds(t) end

	-- База — самый маленький список, чтобы меньше переборов.
	local base, baseTerm = nil, nil
	for _, t in ipairs(positives) do
		local ids = _termCache[t] or {}
		if base == nil or #ids < #base then base, baseTerm = ids, t end
	end
	if base == nil or #base == 0 then return {} end

	-- Множества остальных позитивных термов для быстрой проверки.
	local sets = {}
	local result = {}
	for _, id in ipairs(base) do
		local ok = true
		for _, t in ipairs(positives) do
			if t ~= baseTerm then
				if not sets[t] then
					local s = {}
					for _, i2 in ipairs(_termCache[t] or {}) do s[i2] = true end
					sets[t] = s
				end
				if not sets[t][id] then ok = false break end
			end
		end
		if ok then table.insert(result, id) end
	end

	-- Вычитание исключённых тегов (type:* пропускаем — нет nozomi).
	for _, t in ipairs(negatives) do
		if not string.match(t, "^type:") then
			local s = {}
			for _, i2 in ipairs(_termCache[t] or {}) do s[i2] = true end
			local filtered = {}
			for _, id in ipairs(result) do
				if not s[id] then table.insert(filtered, id) end
			end
			result = filtered
		end
	end
	return result
end

-- ── Данные галереи и URL картинок ──

-- Данные галереи (galleries/<id>.js) с кэшем на сессию.
local _galleryCache = {}

local function galleryData(id)
	if _galleryCache[id] then return _galleryCache[id] end
	local url = CDN .. "/galleries/" .. id .. ".js"
	-- Повтор при 503 (CDN иногда глючит)
	local r = nil
	for attempt = 1, 3 do
		r = http_get(url)
		if r.success then break end
		if r.code == 503 and attempt < 3 then sleep(500 * attempt) end
	end
	if not r.success then
		log_error("hitomi: galleryData fetch failed for id=" .. tostring(id) .. " code=" .. tostring(r.code))
		return nil
	end
	_galleryCache[id] = r.body
	return r.body
end

-- gg.js определяет пути картинок и меняется у сайта каждые ~30 минут.
-- Кэшируем с TTL 30 мин (1800000 мс), чтобы обновлять при протухании.
local _gg, _ggTime = nil, 0

local function getGG()
	local now = (pcall(os_time) and os_time()) or 0
	if _gg and (now == 0 or now - _ggTime < 1800000) then return _gg end
	local res = { b = "1788296402/", def = 0, mval = 1, mlist = {} }
	local r = http_get(CDN .. "/gg.js")
	if r.success and r.body then
		local b = string.match(r.body, "b%s*:%s*'(%d+)/'")
		if b then res.b = b .. "/" end
		local d = string.match(r.body, "var o%s*=%s*(%d+)")
		if d then res.def = tonumber(d) end
		local v = string.match(r.body, "o%s*=%s*(%d+)%s*;%s*break")
		if v then res.mval = tonumber(v) end
		for g in string.gmatch(r.body, "case%s+(%d+)%s*:") do
			res.mlist[tonumber(g)] = true
		end
	end
	_gg = res
	_ggTime = now
	return res
end

-- URL полноразмерной картинки из хеша (схема из common.js url_from_hash):
--   last3 = последние 3 hex-символа хеша
--   g = tonumber(last3[3] .. last3[1..2], 16) — reversed pair
--   sub = (w|a) .. (1 + gg.m(g)); путь = {gg.b}{g}/{hash}.{ext}
local function fullImageUrl(hash, ext)
	local gg = getGG()
	local last3 = string.sub(hash, -3, -1)
	local g = tonumber(string.sub(last3, -1) .. string.sub(last3, 1, 2), 16)
	local m = gg.def
	if gg.mlist[g] and gg.mval then m = gg.mval end
	local sub = (ext == "webp" and "w" or "a") .. (1 + m)
	return "https://" .. sub .. ".gold-usergeneratedcontent.net/" .. gg.b .. g .. "/" .. hash .. "." .. ext
end

-- ── Карточки галерей (galleries/<id>.js) ──

local _blockCache = {}

-- Карточка галереи { title, url, cover } по ID.
-- URL строим как /galleries/<id>.html — чистый, без спецсимволов из тайтлов.
-- galleryurl из CDN содержит | из названий (напр. "Request ... | Per Request ..."),
-- что ломает URL-роутинг в приложении.
local function galleryBlock(id)
	if _blockCache[id] then return _blockCache[id] end
	local body = galleryData(id)
	if not body then return nil end
	local info = string.match(body, "var%s+galleryinfo%s*=%s*(%b{})")
	if not info then return nil end
	local title = string.match(info, '"title"%s*:%s*"([^"]*)"')
	local hash = string.match(info, '"hash"%s*:%s*"([0-9a-f]+)"')
	local url = baseUrl .. "galleries/" .. id .. ".html"
	local cover = hash and fullImageUrl(hash, "webp") or ""
	local item = { title = title or "", url = url, cover = cover }
	_blockCache[id] = item
	return item
end

-- Страница карточек из списка ID: режется по 25 штук, как на сайте.
-- Незакэшированные URL загружаются параллельно через http_get_batch.
local function itemsByIds(ids, index)
	local startIdx = (index or 0) * 25 + 1
	local endIdx = math.min(startIdx + 24, #ids)
	local idList = {}
	for i = startIdx, endIdx do idList[#idList + 1] = ids[i] end

	-- Собираем URL, которых нет в кэше
	local fetchUrls, fetchIds = {}, {}
	for _, id in ipairs(idList) do
		if not _galleryCache[id] then
			fetchUrls[#fetchUrls + 1] = CDN .. "/galleries/" .. id .. ".js"
			fetchIds[#fetchIds + 1] = id
		end
	end

	-- Параллельная загрузка
	if #fetchUrls > 0 then
		local results = http_get_batch(fetchUrls)
		for i, r in ipairs(results) do
			if r and r.success and r.body then
				_galleryCache[fetchIds[i]] = r.body
			end
		end
	end

	-- Собираем карточки из кэша
	local items = {}
	for _, id in ipairs(idList) do
		local item = galleryBlock(id)
		if item then items[#items + 1] = item end
	end
	return { items = items, hasNext = endIdx < #ids }
end

-- ── RSS-фолбэк (когда бинарный nozomi недоступен) ──

local function getCatalogFromRSS(index)
	local r = http_get("https://hitomi.la/index-all.atom")
	if not r.success then return { items = {}, hasNext = false } end
	local items = {}
	local entries = html_select(r.body, "entry")
	for _, e in ipairs(entries) do
		local link = html_attr(e.html, "link", "href")
		if link then
			local id = galleryIdFromUrl(link)
			local item = id and galleryBlock(id) or nil
			if not item then
				local t = html_select_first(e.html, "title")
				item = { title = t and html_text(t.html) or "", url = link, cover = "" }
			end
			items[#items + 1] = item
		end
	end
	return { items = items, hasNext = false }
end

-- ── Каталог и поиск ──

-- Каталог: бинарный .nozomi (полная пагинация), с фолбэком на RSS.
function getCatalogList(index)
	local ids = queryGalleryIds("index-all")
	if #ids == 0 then
		log_error("hitomi: nozomi returned 0 IDs, falling back to RSS")
		return getCatalogFromRSS(index)
	end
	return itemsByIds(ids, index)
end

-- Поиск: строка из поисковой строки читалки в синтаксисе тегов hitomi.
function getCatalogSearch(index, query)
	if not query or query == "" then
		return getCatalogList(index)
	end
	local ids = queryGalleryIds(query)
	log_error("hitomi: search query=\"" .. tostring(query) .. "\" → " .. #ids .. " IDs")
	return itemsByIds(ids, index)
end

-- Фильтры: поле тегов + язык + тип + сортировка.
function getFilterList()
	return {
		{
			type = "text",
			key = "query",
			label = "Tags (example: male:sole_male -male:yaoi)",
			defaultValue = ""
		},
		{
			type = "select",
			key = "language",
			label = "Language",
			options = {
				{ value = "", label = "All" },
				{ value = "japanese", label = "Japanese" },
				{ value = "english", label = "English" },
				{ value = "korean", label = "Korean" },
				{ value = "chinese", label = "Chinese" },
				{ value = "russian", label = "Russian" },
				{ value = "portuguese", label = "Portuguese" },
				{ value = "spanish", label = "Spanish" },
				{ value = "french", label = "French" },
				{ value = "german", label = "German" },
				{ value = "italian", label = "Italian" },
				{ value = "thai", label = "Thai" },
				{ value = "indonesian", label = "Indonesian" },
				{ value = "turkish", label = "Turkish" },
				{ value = "arabic", label = "Arabic" },
				{ value = "vietnamese", label = "Vietnamese" },
				{ value = "dutch", label = "Dutch" },
				{ value = "polish", label = "Polish" },
				{ value = "czech", label = "Czech" },
				{ value = "hungarian", label = "Hungarian" },
				{ value = "romanian", label = "Romanian" },
				{ value = "tagalog", label = "Tagalog" },
				{ value = "persian", label = "Persian" },
			},
			defaultValue = ""
		},
		{
			type = "select",
			key = "type",
			label = "Type",
			options = {
				{ value = "", label = "All" },
				{ value = "manga", label = "Manga" },
				{ value = "doujinshi", label = "Doujinshi" },
				{ value = "anime CG", label = "Anime CG" },
				{ value = "artist CG", label = "Artist CG" },
			},
			defaultValue = ""
		},
		{
			type = "select",
			key = "sort",
			label = "Sort",
			options = {
				{ value = "date_added", label = "Date Added" },
				{ value = "published", label = "Date Published" },
				{ value = "today", label = "Popular: Today" },
				{ value = "week", label = "Popular: Week" },
				{ value = "month", label = "Popular: Month" },
				{ value = "year", label = "Popular: Year" },
				{ value = "random", label = "Random" },
			},
			defaultValue = "date_added"
		}
	}
end

-- Сборка строк запроса из фильтров: язык + тип + пользовательские теги.
local function buildQueryFromFilters(filters)
	local q = filters and filters["query"] or ""
	local lang = filters and filters["language"] or ""
	local typ = filters and filters["type"] or ""
	local parts = {}
	if q ~= "" then table.insert(parts, q) end
	if lang ~= "" then table.insert(parts, "language:" .. lang) end
	if typ ~= "" then table.insert(parts, "type:" .. typ) end
	return table.concat(parts, " ")
end

-- URL nozomi для сортировки по популярности:
--   n/popular/month-<language>.nozomi или n/popular/month-all.nozomi
local function popularNozomiUrl(period, lang)
	local suffix = (lang and lang ~= "") and lang or "all"
	return CDN .. "/n/popular/" .. period .. "-" .. suffix .. ".nozomi"
end

-- Тасование Фишера-Йейтса.
local function shuffleIds(ids)
	for i = #ids, 2, -1 do
		local j = math.random(i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	return ids
end

-- Страница карточек с сортировкой по заголовку: загружаем расширенный
-- блок ID (100 штук), сортируем по title, возвращаем 25.
local function itemsByIdsSorted(ids, index, sort)
	local startIdx = (index or 0) * 25 + 1
	local batchSize = 100
	if sort == "title" or sort == "title_asc" then
		local batch = {}
		for i = startIdx, math.min(startIdx + batchSize - 1, #ids) do
			local item = galleryBlock(ids[i])
			if item then
				batch[#batch + 1] = item
			end
		end
		table.sort(batch, function(a, b)
			if sort == "title_asc" then
				return (a.title or "") > (b.title or "")
			end
			return (a.title or "") < (b.title or "")
		end)
		local items = {}
		local pageStart = ((index or 0) % 4) * 25 + 1
		for i = pageStart, math.min(pageStart + 24, #batch) do
			items[#items + 1] = batch[i]
		end
		local hasNext = (#batch > 24) and (pageStart + 24 < #batch or (startIdx + batchSize) <= #ids)
		return { items = items, hasNext = hasNext }
	end
	return itemsByIds(ids, index)
end

-- Фильтрованный каталог с сортировкой.
function getCatalogFiltered(index, filters)
	local q = buildQueryFromFilters(filters)
	local sort = filters and filters["sort"] or "date_added"
	local lang = filters and filters["language"] or ""

	-- Популярность: прямой запрос nozomi с языком, пересечение с фильтрами
	if sort == "today" or sort == "week" or sort == "month" or sort == "year" then
		local url = popularNozomiUrl(sort, lang)
		local ok, r = pcall(http_get, url, { binary = true })
		local popIds = {}
		if ok and r and r.success and r.body then
			popIds = parseNozomi(r.body)
		end
		if #popIds == 0 then
			log_error("hitomi: popular nozomi empty for " .. sort .. " url=" .. url)
			return itemsByIds(queryGalleryIds(q), index)
		end
		-- Если есть фильтры (язык/тип/теги), пересекаем с popular
		if q ~= "" then
			local filterIds = queryGalleryIds(q)
			local filterSet = {}
			for _, id in ipairs(filterIds) do filterSet[id] = true end
			local intersected = {}
			for _, id in ipairs(popIds) do
				if filterSet[id] then intersected[#intersected + 1] = id end
			end
			return itemsByIds(intersected, index)
		end
		return itemsByIds(popIds, index)
	end

	local ids = queryGalleryIds(q)

	if sort == "date_asc" then
		local reversed = {}
		for i = #ids, 1, -1 do reversed[#reversed + 1] = ids[i] end
		ids = reversed
	elseif sort == "random" then
		shuffleIds(ids)
	end

	return itemsByIdsSorted(ids, index, sort)
end

-- ── Чтение галереи (манга) ──

-- Список глав: вся галерея — одна «глава» (набор картинок).
function getChapterList(bookUrl)
	local id = galleryIdFromUrl(bookUrl)
	if not id then
		log_error("hitomi: getChapterList no id in url=" .. tostring(bookUrl))
		return {}
	end
	local body = galleryData(id)
	if not body then
		log_error("hitomi: getChapterList no galleryData for id=" .. id)
		return {}
	end
	local title = string.match(body, '"title"%s*:%s*"([^"]*)"')
	return { { title = title or "Part 1", url = bookUrl } }
end

-- Страницы главы (манга): движок грузит картинку сам, с Referer'ом origin-хоста.
function getPageList(html, url)
	local id = galleryIdFromUrl(url)
	if not id then
		log_error("hitomi: getPageList no id in url=" .. tostring(url))
		return nil
	end
	local body = galleryData(id)
	if not body then
		log_error("hitomi: getPageList no galleryData for id=" .. id)
		return nil
	end
	local pages = {}
	for h in string.gmatch(body, '"hash"%s*:%s*"([0-9a-f]+)"') do
		pages[#pages + 1] = fullImageUrl(h, "webp")
	end
	if #pages == 0 then
		log_error("hitomi: getPageList 0 pages for id=" .. id)
	end
	return pages
end

-- Текст главы: HTML с <img> для каждой страницы галереи.
function getChapterText(html, url)
	local id = galleryIdFromUrl(url)
	if not id then return "" end
	local body = galleryData(id)
	if not body then return "" end
	local imgs = {}
	for h in string.gmatch(body, '"hash"%s*:%s*"([0-9a-f]+)"') do
		imgs[#imgs + 1] = '<img src="' .. fullImageUrl(h, "webp") .. '">'
	end
	if #imgs == 0 then return "" end
	return table.concat(imgs, "\n")
end

-- ── Детали книги ──

function getBookTitle(bookUrl)
	local id = galleryIdFromUrl(bookUrl)
	if not id then return nil end
	local body = galleryData(id)
	if not body then return nil end
	return string.match(body, '"title"%s*:%s*"([^"]*)"')
end

function getBookCoverImageUrl(bookUrl)
	local id = galleryIdFromUrl(bookUrl)
	if not id then return nil end
	local item = galleryBlock(id)
	if not item then return nil end
	return item.cover ~= "" and item.cover or nil
end

function getBookDescription(bookUrl)
	local id = galleryIdFromUrl(bookUrl)
	if not id then return nil end
	local body = galleryData(id)
	if not body then return nil end
	local artist = string.match(body, '"artist"%s*:%s*"([^"]*)"')
	local lang = string.match(body, '"language"%s*:%s*"([^"]*)"')
	local parts = {}
	if artist then parts[#parts + 1] = "Artist: " .. artist end
	if lang then parts[#parts + 1] = "Language: " .. lang end
	if #parts == 0 then return nil end
	return string_clean(table.concat(parts, " | "))
end

-- Теги/жанры галереи: извлекаем из galleryinfo.tags (массив объектов {tag, url}).
function getBookGenres(bookUrl)
	local id = galleryIdFromUrl(bookUrl)
	if not id then return nil end
	local body = galleryData(id)
	if not body then return nil end
	-- Извлекаем массив tags: "tags": [{...}, {...}]
	local tagsSection = string.match(body, '"tags"%s*:%s*(%b[])')
	if not tagsSection then return nil end
	local tags = {}
	-- Извлекаем каждый tag: "tag": "имя_тега"
	for tagName in string.gmatch(tagsSection, '"tag"%s*:%s*"([^"]*)"') do
		tags[#tags + 1] = tagName
	end
	if #tags == 0 then return nil end
	return tags
end
