// Data helpers for the Anime Airing plugin.
//
// Data source: Tenrai (https://tenrai.org) — a free, authless API that
// serves structured MyAnimeList data in the Jikan v4 schema. We hit
// /v1/seasons/now, which mirrors https://myanimelist.net/anime/season, and
// list every entry of the current season (currently airing, finished while
// this season ran, or still upcoming), sorted by broadcast day/time (JST).

// URL for the current season from MyAnimeList via Tenrai. No API key needed.
// `sfw=true` drops 18+ entries (behind the MAL safe-for-work filter).
function seasonUrl() {
  return "https://api.tenrai.org/v1/seasons/now?sfw=true"
}

// Ordered list of broadcast weekdays (JST). Used to sort the list by "next"
// airing day and to group rows under a day heading.
var DAYS = [
  "Mondays", "Tuesdays", "Wednesdays", "Thursdays",
  "Fridays", "Saturdays", "Sundays"
]

// Normalize a Jikan broadcast.day string ("Mondays", "Monday", etc.) to our
// canonical "Mondays" form, or "" when unknown.
function canonicalDay(raw) {
  var s = String(raw || "").replace(/s$/i, "").toLowerCase()
  var map = {
    "monday": "Mondays", "tuesday": "Tuesdays", "wednesday": "Wednesdays",
    "thursday": "Thursdays", "friday": "Fridays", "saturday": "Saturdays",
    "sunday": "Sundays"
  }
  return map[s] || ""
}

// Best display title for a season entry.
function titleOf(item) {
  if (item && item.title) return String(item.title)
  if (item && item.title_english) return String(item.title_english)
  if (item && item.title_japanese) return String(item.title_japanese)
  return "Unknown"
}

// Parse the /seasons/now JSON body into a flat, sorted array of season items.
// Every entry of the current season is included regardless of airing status
// ("Currently Airing", "Finished Airing", "Not yet aired"); the per-item
// `status` is kept so the UI can tag non-airing entries. Returns
// { items: [...], season: <label or "">, total: <count of season entries> }.
function parseSeason(raw, maxItems) {
  var out = { items: [], season: "", total: 0 }
  var data
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return out
  }
  var list = data && Array.isArray(data.data) ? data.data : []
  if (!list.length) return out

  // season/year are per-item; take the first present pair for the header,
  // falling back to "Currently Airing" if the API omits them.
  for (var s = 0; s < list.length; s++) {
    if (out.season === "" && list[s]) {
      var cap = String(list[s].season || "")
      var yr = String(list[s].year || "")
      if (cap || yr) out.season = (cap.charAt(0).toUpperCase() + cap.slice(1)) + (cap && yr ? " " : "") + yr
    }
  }

  var airing = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var it = list[i]
    if (!it) continue
    // Jikan returns a title once per category it scrapes; keep the first.
    if (it.mal_id !== undefined && seen[it.mal_id]) continue
    if (it.mal_id !== undefined) seen[it.mal_id] = true
    var broadcast = it.broadcast || {}
    var day = canonicalDay(broadcast.day)
    var dayIndex = DAYS.indexOf(day)
    var time = String(broadcast.time || "")
    airing.push({
      malId: it.mal_id,
      url: it.url || "",
      title: titleOf(it),
      titleEnglish: it.title_english || "",
      titleJapanese: it.title_japanese || "",
      image: it.images && it.images.jpg && it.images.jpg.image_url ? it.images.jpg.image_url : "",
      type: it.type || "",
      episodes: it.episodes,
      score: it.score,
      synopsis: it.synopsis || "",
      status: it.status || "",
      day: day || "TBA",
      dayIndex: dayIndex === -1 ? 99 : dayIndex,
      time: time,
      broadcastString: formatBroadcast(day, time),
      studios: (it.studios || []).map(function(s) { return s.name }).join(", "),
      genres: (it.genres || []).map(function(g) { return g.name }).join(", ")
    })
  }

  // Sort: known days first (by weekday order), then time, then title.
  airing.sort(function(a, b) {
    if (a.dayIndex !== b.dayIndex) return a.dayIndex - b.dayIndex
    if (a.time !== b.time) return a.time < b.time ? -1 : 1
    return a.title < b.title ? -1 : 1
  })

  out.total = airing.length
  var limit = Math.max(1, parseInt(String(maxItems), 10) || 30)
  if (airing.length > limit) airing = airing.slice(0, limit)
  out.items = airing
  out.display = buildDisplay(airing)
  return out
}

// Flatten the season items into a rendering list that interleaves day-group
// headers ("{day}s") with the rows under them. Unknown days collect under one
// "TBA" group at the end.
function buildDisplay(items) {
  var out = []
  var group = ""
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    var heading = (it.dayIndex === 99) ? "TBA" : it.day.replace(/s$/, "s")
    if (heading !== group) {
      group = heading
      out.push({ header: true, label: heading })
    }
    out.push(it)
  }
  return out
}

// "Mondays · 22:00" from a canonical day + time, or "TBA".
function formatBroadcast(day, time) {
  if (!day && !time) return "TBA"
  var parts = []
  if (day) parts.push(day)
  if (time) parts.push(time + " JST")
  return parts.join(" · ")
}

// Tool name for the popup's hero detail.
function seasonLabel(parsed) {
  return parsed && parsed.season ? parsed.season : "This Season"
}

// Small description line for a row: TYPE · STATUS · SCORE · EPS. The airing
// status is only shown when it's not "Currently Airing" (that's the default).
function typeScoreLine(item) {
  if (!item) return ""
  var parts = []
  if (item.type) parts.push(item.type)
  if (item.status && item.status !== "Currently Airing") parts.push(item.status)
  if (typeof item.score === "number") parts.push("Score " + item.score.toFixed(2))
  if (item.episodes) parts.push(item.episodes + " eps")
  return parts.join("  ·  ")
}

// Slice of the flattened display list for `page` (0-based), given a fixed
// `pageSize` of entries per page (headers count as entries). Clamps out of
// range pages and also returns the total page count so the panel can render
// prev/next controls. Returns { items, page, totalPages }.
function pageSlice(display, page, pageSize) {
  var list = display || []
  var size = Math.max(1, Math.floor(pageSize || 10))
  var total = Math.max(1, Math.ceil(list.length / size))
  var index = Math.max(0, Math.min(page || 0, total - 1))
  return { items: list.slice(index * size, index * size + size), page: index, totalPages: total }
}

// Up to 4 genre names for a row meta line ("Adventure · Drama · Fantasy").
function genreLine(item) {
  if (!item) return ""
  var out = String(item.genres || "").split(", ").filter(function (g) { return g !== "" })
  return out.slice(0, 4).join(" · ")
}

// Convert a roman numeral token (I..M) to an integer, or 0.
function romanToInt(s) {
  if (!s) return 0
  var map = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 }
  var text = String(s).toUpperCase()
  var total = 0
  for (var i = 0; i < text.length; i++) {
    var cur = map[text[i]] || 0
    var nxt = map[text[i + 1]] || 0
    if (cur < nxt) total -= cur
    else total += cur
  }
  return total
}

// English ordinal / number word -> integer (1..12), or 0.
var NUMBER_WORDS = {
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7,
  eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12,
  second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6,
  seventh: 7, eighth: 8, ninth: 9, tenth: 10
}

// Is this airing entry a brand-new first season or a continuation/sequel
// ("Season 3", "II", "Part 2")? Flags come from the title's structure.
// Returns { number, label } where `number` is the detected part (0/1 => new)
// and `label` is "New" or "S<n>".
function partInfo(item) {
  if (!item) return { number: 0, label: "New" }
  var text = [item.titleEnglish, item.title, item.titleJapanese].filter(Boolean).join(" | ")
  var n = 0
  var m

  // "Season 3", "Season Three", "Season #3", "2nd Season", "Second Season".
  m = text.match(/season\s*#?\s*(\d+|[a-zA-Z]+)/i)
  if (m) n = Math.max(n, parseInt(m[1], 10) || NUMBER_WORDS[String(m[1]).toLowerCase()] || 0)
  m = text.match(/(\d+)\s*(?:st|nd|rd|th)?\s*season/i)
  if (m) n = Math.max(n, parseInt(m[1], 10) || 0)

  // "Part 2", "Part Two".
  m = text.match(/\bpart\s*#?\s*(\d+|[a-zA-Z]+)/i)
  if (m) n = Math.max(n, parseInt(m[1], 10) || NUMBER_WORDS[String(m[1]).toLowerCase()] || 0)

  // Japanese "第{n}期" (season/cour marker) -> n.
  m = text.match(/第\s*([0-9零一二三四五六七八九两两])\s*期/)
  if (m) n = Math.max(n, JP_DIGITS[String(m[1])] || parseInt(m[1], 10) || 0)

  // Standalone "S2", "S3" marker (word-boundaried, not mid-word).
  m = text.match(/(^|[^a-z0-9])s([1-9][0-9]?)([^0-9]|$)/i)
  if (m) n = Math.max(n, parseInt(m[2], 10) || 0)

  // Trailing roman numeral ("Youjo Senki II" -> 2) or trailing integer part
  // marker ("... desu 2" -> 2). Run against each title field separately so
  // the end-of-string anchor is reliable regardless of field order.
  var fields = [item.titleEnglish, item.title, item.titleJapanese].filter(Boolean)
  for (var f = 0; f < fields.length; f++) {
    m = fields[f].match(/\s(X{0,3}(IX|IV|V?I{0,3}))$/i)
    if (m) n = Math.max(n, romanToInt(m[1]))
    m = fields[f].match(/\s(2[0-9]|[3-9]|1[0-9]|[2-9])$/)
    if (m) n = Math.max(n, parseInt(m[1], 10) || 0)
  }

  return { number: n, label: n >= 2 ? ("S" + n) : "New" }
}

// Japanese numeral characters used in "第{n}期" part markers.
var JP_DIGITS = {
  "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
  "六": 6, "七": 7, "八": 8, "九": 9, "两": 2
}
