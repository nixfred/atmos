// Lab(machinecard): the scene the user's own agent draws.
//
// Atmos hands the machine's default coding agent the ingredients -- the
// specs, the theme palette, the canvas, and the sentence the user typed --
// and gets back a drawing. SVG, because it is the one medium every text
// agent can author and Qt renders natively: no API key, no per-user setup,
// and claude, codex, grok and gemini all behave the same way.
//
// That constraint is the whole point. This ships to people who have already
// chosen an agent and configured it once through Omarchy; anything needing a
// second credential would work for the author and nobody else.
//
// What comes back is untrusted markup from a model, so it is sanitised
// rather than trusted: an allow-list of drawing elements, no script, no
// foreignObject, no external references, no event handlers. Anything not on
// the list is dropped instead of interpreted.

// Only shapes, groups, gradients and clip paths. Everything a picture needs
// and nothing that can fetch, execute or embed.
var ALLOWED = [
  "svg",
  "g",
  "defs",
  "path",
  "rect",
  "circle",
  "ellipse",
  "polygon",
  "polyline",
  "line",
  "lineargradient",
  "radialgradient",
  "stop",
  "clippath",
  "mask",
  "filter",
  "fegaussianblur",
  "femerge",
  "femergenode",
  "feoffset",
  "feblend",
  "fecolormatrix",
  "title",
  "desc",
];

// Text is excluded on purpose. Atmos draws the specs and the wordmark itself
// in the app's own monospace, so the card stays crisp and readable and a
// model cannot misspell a user's hardware.
var BANNED = ["script", "foreignobject", "image", "use", "a", "animate", "set", "text", "tspan"];

function stripTag(svg, tag) {
  var open = new RegExp("<" + tag + "\\b[^>]*>", "gi");
  var close = new RegExp("</" + tag + "\\s*>", "gi");
  var selfClose = new RegExp("<" + tag + "\\b[^>]*/>", "gi");
  return String(svg).replace(selfClose, "").replace(open, "").replace(close, "");
}

// Returns { svg, dropped } so a caller can say what was removed rather than
// silently changing what the agent drew.
function sanitize(raw) {
  var text = String(raw || "");
  var dropped = [];

  // Take the LAST complete <svg>...</svg>, not the first.
  //
  // Agents echo their prompt. This prompt necessarily contains the literal
  // strings "<svg" and "</svg>" in its own rules, so a first-to-last slice
  // spans the instructions and whatever followed -- producing markup that
  // parses as nothing. Scanning backwards finds the drawing rather than the
  // instructions describing it.
  var svg = "";
  var searchFrom = text.length;
  while (searchFrom > 0) {
    var end = text.lastIndexOf("</svg>", searchFrom);
    if (end === -1) break;
    var start = text.lastIndexOf("<svg", end);
    if (start === -1) break;
    var candidate = text.slice(start, end + 6);
    // A real drawing has shapes in it; the echoed rules do not.
    if (/<(path|rect|circle|ellipse|polygon|polyline|line)\b/i.test(candidate)) {
      svg = candidate;
      break;
    }
    searchFrom = start - 1;
  }
  if (!svg) {
    return { svg: "", dropped: ["no svg element"] };
  }

  var i;
  for (i = 0; i < BANNED.length; i++) {
    var tag = BANNED[i];
    if (new RegExp("<" + tag + "\\b", "i").test(svg)) {
      dropped.push(tag);
      svg = stripTag(svg, tag);
    }
  }

  // Event handlers and javascript: urls, whatever element they hang off.
  if (/\son\w+\s*=/i.test(svg)) {
    dropped.push("event handlers");
    svg = svg.replace(/\son\w+\s*=\s*"[^"]*"/gi, "").replace(/\son\w+\s*=\s*'[^']*'/gi, "");
  }
  if (/javascript:/i.test(svg)) {
    dropped.push("javascript: urls");
    svg = svg.replace(/javascript:/gi, "");
  }
  // Anything reaching off the machine.
  if (/(xlink:href|href)\s*=\s*["']\s*(https?:|\/\/|data:)/i.test(svg)) {
    dropped.push("external references");
    svg = svg.replace(/(xlink:href|href)\s*=\s*["'][^"']*["']/gi, "");
  }
  if (/<!ENTITY/i.test(svg) || /<!DOCTYPE/i.test(svg)) {
    dropped.push("doctype/entities");
    svg = svg.replace(/<!DOCTYPE[^>]*>/gi, "").replace(/<!ENTITY[^>]*>/gi, "");
  }

  // Report anything outside the allow-list without removing it blindly: an
  // unknown element is usually a typo in a shape name, and dropping the whole
  // scene over one would be worse than rendering it minus that node.
  var tags = svg.match(/<\s*([a-zA-Z][a-zA-Z0-9:-]*)/g) || [];
  var seen = {};
  for (i = 0; i < tags.length; i++) {
    var name = tags[i].replace(/[<\s]/g, "").toLowerCase();
    if (seen["t_" + name]) continue;
    seen["t_" + name] = true;
    var ok = false;
    for (var a = 0; a < ALLOWED.length; a++) {
      if (ALLOWED[a] === name) ok = true;
    }
    if (!ok) {
      dropped.push(name);
      svg = stripTag(svg, name);
    }
  }

  // A viewBox is what lets Atmos scale the drawing to any screen.
  if (!/viewBox\s*=/i.test(svg)) {
    svg = svg.replace(/<svg\b/i, '<svg viewBox="0 0 1920 1080"');
  }
  return { svg: svg, dropped: dropped };
}

// Rough check that something was actually drawn. A model that replies with a
// valid but empty <svg/> should be treated as a failure, not as a black card.
function sceneStats(svg) {
  var s = String(svg || "");
  var shapes = (s.match(/<(path|rect|circle|ellipse|polygon|polyline|line)\b/gi) || []).length;
  var grads = (s.match(/<(linearGradient|radialGradient)\b/gi) || []).length;
  return { shapes: shapes, gradients: grads, bytes: s.length, usable: shapes >= 6 };
}

// The ingredients. Specs are included so the agent can compose around them --
// it is told where they will go and asked to leave that area calm -- but it
// never draws them, so nothing it does can misspell a user's hardware.
function scenePrompt(opts) {
  var o = opts || {};
  var card = o.card || { rows: [] };
  var rows = Array.isArray(card.rows) ? card.rows : [];
  var theme = o.theme || {};
  var w = o.width || 1920;
  var h = o.height || 1080;

  return (
    'Draw a single wide cinematic SVG illustration. viewBox="0 0 ' +
    w +
    " " +
    h +
    '".\n\n' +
    "WHAT THE USER ASKED FOR:\n" +
    String(o.wish || "something striking") +
    "\n\n" +
    "Expand that into a full scene. Take it seriously and make it dramatic: " +
    "foreground subject, mid-ground action, distant background, sky. Depth and " +
    "atmosphere matter more than fine detail.\n\n" +
    "STYLE: bold flat vector illustration. Layered silhouettes, long gradients, " +
    "haze and light shafts. Screen-print poster, not photorealism. Fill the " +
    "whole canvas edge to edge -- no borders, no framing, no blank margins.\n\n" +
    "PALETTE: build everything from this desktop theme, plus warm fire tones " +
    "where a scene needs them:\n" +
    "  background " +
    (theme.background || "#0b1b2b") +
    "\n  foreground " +
    (theme.foreground || "#cacccc") +
    "\n  accent     " +
    (theme.accent || "#8fb8c8") +
    "\n  muted      " +
    (theme.muted || "#707880") +
    "\n\n" +
    "LEAVE ROOM: Atmos draws a specification panel over the " +
    (o.panel || "top right") +
    " quadrant and the Omarchy logo over the " +
    (o.logoWhere || "top left") +
    ". Keep both areas visually calm -- sky, haze, or simple gradient. Do not " +
    "put your subject there.\n\n" +
    "The panel will list:\n" +
    (function () {
      var out = [];
      for (var i = 0; i < rows.length; i++) out.push("  " + rows[i].label + ": " + rows[i].value);
      return out.join("\n");
    })() +
    "\n\nRULES:\n" +
    "- No <text>, no <tspan>. Atmos renders all wording itself.\n" +
    "- No <image>, <use>, <script>, <foreignObject>, no external URLs.\n" +
    "- Only: svg, defs, linearGradient, radialGradient, stop, g, path, rect, " +
    "circle, ellipse, polygon, polyline, line, clipPath, mask, filter.\n" +
    "- Aim for 60 to 200 shapes. Enough for a real scene.\n\n" +
    "Output ONLY the SVG markup, starting with <svg and ending with </svg>. " +
    "No prose, no markdown fence, no explanation."
  );
}
