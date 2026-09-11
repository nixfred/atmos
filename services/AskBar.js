// Lab(askbar): resolve a plain-English request against the hub catalogue.
//
// The design constraint that makes this shippable: the agent never writes.
// It can navigate you somewhere, or it can hand you a plan you confirm, and
// that is the whole of its authority. An LLM that can only ever produce a
// diff is one people will actually leave switched on, and Atmos already has
// the piece that makes it honest -- an import planner that says what a
// change will cost before it costs it.
//
// Resolution is deliberately local first. Most of "take me there" is just
// fuzzy matching over a catalogue that already carries titles, descriptions
// and keywords, and doing that in-process means the common case is instant,
// free, private, and works with no agent installed at all. The agent is the
// fallback for the requests local matching cannot honestly answer.

function norm(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .replace(/^ | $/g, "");
}

// Filler that appears in half of all plain-English requests and belongs to
// none of them. Left in, these match page descriptions at random and drown
// the one word that actually carried the intent -- "battery" lost to
// Notifications because "my" and "is" scored everywhere.
var STOP_WORDS = [
  "a",
  "an",
  "and",
  "are",
  "at",
  "be",
  "can",
  "do",
  "for",
  "from",
  "how",
  "i",
  "in",
  "is",
  "it",
  "me",
  "my",
  "of",
  "on",
  "or",
  "please",
  "so",
  "the",
  "then",
  "this",
  "to",
  "want",
  "was",
  "way",
  "what",
  "when",
  "where",
  "why",
  "with",
  "you",
  "your",
];

// Keys are prefixed before they go into a lookup object. A bare object is
// not a set: STOP["constructor"] and STOP["toString"] are truthy through the
// prototype, so "constructor" would silently become a stop word and any
// keyword named after an Object member would match everything. The prefix
// puts every key outside that namespace.
function mark(map, word) {
  if (word) map["w_" + word] = true;
}

function marked(map, word) {
  return map["w_" + word] === true;
}

var STOP = {};
for (var si = 0; si < STOP_WORDS.length; si++) mark(STOP, STOP_WORDS[si]);

function words(text) {
  var n = norm(text);
  if (!n) return [];
  var raw = n.split(" ");
  var out = [];
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] && !marked(STOP, raw[i])) out.push(raw[i]);
  }
  // If the request was nothing but filler, fall back to the raw words rather
  // than answering "no match" to a question that did have words in it.
  return out.length > 0 ? out : raw;
}

// Intent words that mean "change it", not "show me". Used only to phrase the
// answer honestly -- a request to change still resolves to a destination,
// because navigating is the safe half we can always deliver.
var CHANGE_WORDS = [
  "set",
  "make",
  "change",
  "turn",
  "enable",
  "disable",
  "increase",
  "decrease",
  "raise",
  "lower",
  "stop",
  "start",
];

function looksLikeChange(query) {
  var w = words(query);
  for (var i = 0; i < w.length; i++) {
    for (var j = 0; j < CHANGE_WORDS.length; j++) {
      if (w[i] === CHANGE_WORDS[j]) return true;
    }
  }
  return false;
}

// Score one hub against the query. Title hits beat keyword hits beat
// description hits, because a user who types "bluetooth" means the hub
// called Bluetooth and not the six pages that mention it in passing.
function scoreHub(hub, query) {
  if (!hub) return 0;
  var qs = words(query);
  if (qs.length === 0) return 0;

  var title = norm(hub.title);
  var desc = norm(hub.description);
  var keys = [];
  if (Array.isArray(hub.keywords)) {
    for (var k = 0; k < hub.keywords.length; k++) keys.push(norm(hub.keywords[k]));
  }
  var keyBlob = keys.join(" ");
  var keyWords = {};
  var kwParts = keyBlob.split(" ");
  for (var kw = 0; kw < kwParts.length; kw++) mark(keyWords, kwParts[kw]);

  var score = 0;
  var matched = 0;
  for (var i = 0; i < qs.length; i++) {
    var q = qs[i];
    if (q.length < 2) continue;
    var hit = false;
    if (title === q) {
      score += 100;
      hit = true;
    } else if (title.indexOf(q) !== -1) {
      score += 40;
      hit = true;
    }
    // Whole word, not substring. "on" must not match "notifications" and
    // "bat" must not match "battery" -- a substring hit on a keyword list is
    // how a resolver ends up confidently wrong.
    if (marked(keyWords, q)) {
      score += 18;
      hit = true;
    } else if (q.length >= 4 && keyBlob.indexOf(q) !== -1) {
      score += 9;
      hit = true;
    }
    // Description matches are the weakest signal and the noisiest, so only
    // a substantial word may claim one. Short fragments match everything.
    if (q.length >= 4 && desc.indexOf(q) !== -1) {
      score += 6;
      hit = true;
    }
    if (hit) matched += 1;
  }

  // Every meaningful word landing somewhere is a much stronger signal than
  // one word landing hard, so reward coverage rather than raw hits.
  var meaningful = 0;
  for (var m = 0; m < qs.length; m++) {
    if (qs[m].length >= 2) meaningful += 1;
  }
  if (meaningful > 0 && matched === meaningful) score += 25;
  return score;
}

function rank(hubs, query, limit) {
  var list = Array.isArray(hubs) ? hubs : [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var s = scoreHub(list[i], query);
    if (s > 0) out.push({ hub: list[i], score: s });
  }
  out.sort(function (a, b) {
    return b.score - a.score;
  });
  var max = limit || 5;
  return out.slice(0, max);
}

// A confident local answer is one clear winner. Anything ambiguous is
// offered as a list instead of guessed at, because silently landing someone
// on the wrong page is worse than asking which they meant.
function resolve(hubs, query) {
  var q = norm(query);
  if (!q) return { kind: "empty", matches: [] };

  var ranked = rank(hubs, query, 5);
  if (ranked.length === 0) {
    return { kind: "none", matches: [], change: looksLikeChange(query) };
  }

  var best = ranked[0];
  var runnerUp = ranked.length > 1 ? ranked[1].score : 0;
  // One candidate and nothing else in the running is a confident answer even
  // when the score is modest -- there is nothing to be ambiguous between.
  // Otherwise a winner has to be clearly ahead, not merely ahead, because a
  // near-tie means the request genuinely was ambiguous.
  var confident =
    ranked.length === 1 ? best.score >= 18 : best.score >= 40 && best.score >= runnerUp * 1.5;

  return {
    kind: confident ? "go" : "choose",
    target: confident ? best.hub : null,
    matches: ranked,
    change: looksLikeChange(query),
  };
}

// What Atmos hands the agent when local matching cannot answer. Spelled out
// as a request for a plan, never for an action, so the agent's own output is
// something a person reads and approves rather than something that already
// happened.
function agentPrompt(query, hubTitles) {
  var q = String(query || "").replace(/^\s+|\s+$/g, "");
  if (!q) return "";
  var titles = Array.isArray(hubTitles) ? hubTitles.join(", ") : "";
  return (
    "I am in Atmos, the Omarchy settings app, and I want: " +
    q +
    "\n\n" +
    "Do not change anything. Tell me which settings page this lives on and " +
    "what exactly you would change, naming the config file and the command, " +
    "so I can approve it myself.\n\n" +
    (titles ? "Atmos pages: " + titles + "\n" : "")
  );
}
