// Lab(machinecard): a layout language the agent writes and Atmos renders.
//
// The earlier version let the agent set five knobs inside a frozen skeleton.
// This hands it the whole composition -- where the mark sits, where the type
// sits, how the specs are arranged, what the art does and where -- because
// "always identical except the texture" is a template, not a design, and
// nobody screenshots a template.
//
// What keeps every card recognisably an Atmos card is not the arrangement.
// It is the content and the rules:
//
//   * The Omarchy mark is always on it. The agent may move and size it; it
//     cannot remove it, and normalise() puts it back if it tries.
//   * Every spec row is always on it, in the app's own monospace.
//   * Text always sits on enough scrim to be readable, whatever the art did.
//   * Nothing lands off-canvas, and nothing is drawn that is not one of the
//     primitives below.
//
// That last point is the safety story. The agent returns data, never code.
// An unknown block type is dropped rather than interpreted, every number is
// clamped to a sane range, and every colour is resolved from the user's own
// theme by name -- so a hostile or confused reply produces an ugly card at
// worst, never an unsafe one.

var BLOCKS = ["logo", "title", "tagline", "specs", "wordmark"];
var ART = ["embers", "scales", "waves", "circuit", "stars", "peaks", "rain", "bloom", "none"];
var ROLES = ["accent", "foreground", "muted", "background"];
var ALIGN = ["left", "center", "right"];

function clamp(value, low, high, fallback) {
  var n = Number(value);
  if (!isFinite(n)) return fallback === undefined ? low : fallback;
  return Math.max(low, Math.min(high, n));
}

function oneOf(value, list, fallback) {
  var v = String(value || "").toLowerCase();
  for (var i = 0; i < list.length; i++) {
    if (list[i] === v) return v;
  }
  return fallback;
}

// Fractions of the card, never pixels. The same layout then works at 1080p,
// at 1440p and in the small preview without a second set of numbers.
function normBlock(raw, fallback) {
  var b = raw || {};
  var f = fallback || {};
  return {
    x: clamp(b.x, 0, 1, f.x !== undefined ? f.x : 0.05),
    y: clamp(b.y, 0, 1, f.y !== undefined ? f.y : 0.05),
    w: clamp(b.w, 0.05, 1, f.w !== undefined ? f.w : 0.9),
    scale: clamp(b.scale, 0.4, 2.2, f.scale !== undefined ? f.scale : 1),
    align: oneOf(b.align, ALIGN, f.align || "left"),
    color: oneOf(b.color, ROLES, f.color || "foreground"),
    columns: Math.round(clamp(b.columns, 1, 3, f.columns || 2)),
  };
}

function defaultLayout() {
  return {
    background: "background",
    art: {
      motif: "circuit",
      density: 0.5,
      intensity: 0.5,
      warmth: 0,
      direction: "up",
      color: "accent",
      seed: 1,
      x: 0,
      y: 0,
      w: 1,
      h: 1,
    },
    scrim: 0.62,
    blocks: {
      logo: { x: 0.033, y: 0.04, w: 0.2, scale: 1, align: "left", color: "foreground", columns: 2 },
      title: { x: 0.033, y: 0.6, w: 0.9, scale: 1, align: "left", color: "foreground", columns: 2 },
      tagline: { x: 0.033, y: 0.68, w: 0.9, scale: 1, align: "left", color: "accent", columns: 2 },
      specs: {
        x: 0.033,
        y: 0.74,
        w: 0.93,
        scale: 1,
        align: "left",
        color: "foreground",
        columns: 2,
      },
      wordmark: { x: 0.033, y: 0.95, w: 0.5, scale: 1, align: "left", color: "muted", columns: 2 },
    },
  };
}

function normArt(raw, fallback) {
  var a = raw || {};
  var f = fallback || {};
  return {
    motif: oneOf(a.motif, ART, f.motif || "circuit"),
    density: clamp(a.density, 0, 1, f.density),
    intensity: clamp(a.intensity, 0, 1, f.intensity),
    warmth: clamp(a.warmth, -1, 1, f.warmth),
    direction: String(a.direction || "").toLowerCase() === "down" ? "down" : "up",
    color: oneOf(a.color, ROLES, f.color || "accent"),
    seed: Math.round(clamp(a.seed, 1, 4294967295, f.seed || 1)),
    // The art may cover a region rather than the whole card, which is what
    // makes a band of fire along one edge possible.
    x: clamp(a.x, 0, 1, f.x !== undefined ? f.x : 0),
    y: clamp(a.y, 0, 1, f.y !== undefined ? f.y : 0),
    w: clamp(a.w, 0.05, 1, f.w !== undefined ? f.w : 1),
    h: clamp(a.h, 0.05, 1, f.h !== undefined ? f.h : 1),
  };
}

// Take whatever came back and make it renderable. Every field falls back
// independently, so a reply that gets the art right and the geometry wrong
// keeps the art.
function normalize(raw, seed) {
  var base = defaultLayout();
  if (seed) base.art.seed = seed;
  var r = raw && typeof raw === "object" ? raw : {};
  var out = {
    background: oneOf(r.background, ROLES, "background"),
    art: normArt(r.art, base.art),
    scrim: clamp(r.scrim, 0, 1, base.scrim),
    blocks: {},
  };
  var given = r.blocks && typeof r.blocks === "object" ? r.blocks : {};
  for (var i = 0; i < BLOCKS.length; i++) {
    var name = BLOCKS[i];
    out.blocks[name] = normBlock(given[name], base.blocks[name]);
  }
  // The mark is not optional. An agent that drops it, or hides it by scaling
  // it away, gets it back -- this is the one thing every Atmos card shares.
  if (out.blocks.logo.scale < 0.5) out.blocks.logo.scale = 0.5;
  return out;
}

// Blocks must not sit on top of each other so badly that the card is
// unreadable. This does not rearrange the agent's design; it only reports,
// so a test can catch a prompt that reliably produces a mess.
function overlaps(layout, aspect) {
  var l = layout || defaultLayout();
  var ratio = Number(aspect) || 1.777;
  var boxes = [];
  var heights = { logo: 0.06, title: 0.08, tagline: 0.05, specs: 0.2, wordmark: 0.03 };
  for (var i = 0; i < BLOCKS.length; i++) {
    var n = BLOCKS[i];
    var b = l.blocks[n];
    boxes.push({
      name: n,
      x: b.x,
      y: b.y,
      w: b.w,
      h: heights[n] * b.scale * (1.777 / ratio),
    });
  }
  var hits = [];
  for (var a = 0; a < boxes.length; a++) {
    for (var c = a + 1; c < boxes.length; c++) {
      var A = boxes[a];
      var B = boxes[c];
      var over = A.x < B.x + B.w && A.x + A.w > B.x && A.y < B.y + B.h && A.y + A.h > B.y;
      if (over) hits.push(A.name + "/" + B.name);
    }
  }
  return hits;
}

// What the agent is told. It gets the real specs, the real theme, the size
// it is designing for, and the rules -- then it is asked to design rather
// than to fill in a form.
function designPrompt(opts) {
  var o = opts || {};
  var card = o.card || { rows: [] };
  var rows = Array.isArray(card.rows) ? card.rows : [];
  var lines = [];
  for (var i = 0; i < rows.length; i++) lines.push("  " + rows[i].label + ": " + rows[i].value);
  var theme = o.theme || {};

  return (
    "You are designing a wallpaper-sized card that a Linux user will post to show off their computer.\n\n" +
    "WHAT THEY ASKED FOR:\n" +
    String(o.wish || "something striking") +
    "\n\nTHE MACHINE (these exact rows must all appear on the card):\n" +
    lines.join("\n") +
    "\n\nTHEIR DESKTOP THEME (use these, do not invent colours):\n" +
    "  background " +
    (theme.background || "") +
    "\n" +
    "  foreground " +
    (theme.foreground || "") +
    "\n" +
    "  accent     " +
    (theme.accent || "") +
    "\n" +
    "  muted      " +
    (theme.muted || "") +
    "\n" +
    "  theme name " +
    (o.themeName || "") +
    "\n\n" +
    "CANVAS: " +
    (o.width || 1920) +
    " x " +
    (o.height || 1080) +
    " pixels.\n\n" +
    "You are laying out five blocks. Positions are fractions of the canvas, " +
    "0 to 1, measured from the top left:\n" +
    "  logo     the Omarchy mark. It MUST be on the card. You choose where and how big.\n" +
    "  title    the machine name, large\n" +
    "  tagline  one line under it\n" +
    "  specs    every row listed above, in 1, 2 or 3 columns\n" +
    "  wordmark small OMARCHY / ATMOS credit\n\n" +
    "You also direct the art behind them. Pick a motif and where it sits:\n" +
    "  " +
    ART.join(", ") +
    "\n\n" +
    "Go wild with the arrangement. Corner-weighted, split down the middle, " +
    "specs up top with the art below, mark in the bottom right -- anything, " +
    "as long as blocks do not overlap and everything stays on the canvas. " +
    "Make it look designed, not centred.\n\n" +
    "Reply with JSON only, no prose, no markdown fence:\n" +
    '{"background":"background","scrim":0.0-1.0,' +
    '"art":{"motif":"one of the above","density":0.0-1.0,"intensity":0.0-1.0,' +
    '"warmth":-1.0-1.0,"direction":"up|down","color":"accent|foreground|muted",' +
    '"x":0.0-1.0,"y":0.0-1.0,"w":0.05-1.0,"h":0.05-1.0},' +
    '"blocks":{' +
    '"logo":{"x":0,"y":0,"w":0.2,"scale":1,"align":"left|center|right","color":"foreground"},' +
    '"title":{"x":0,"y":0,"w":0.9,"scale":1,"align":"left","color":"foreground"},' +
    '"tagline":{"x":0,"y":0,"w":0.9,"scale":1,"align":"left","color":"accent"},' +
    '"specs":{"x":0,"y":0,"w":0.9,"scale":1,"align":"left","color":"foreground","columns":2},' +
    '"wordmark":{"x":0,"y":0,"w":0.4,"scale":1,"align":"left","color":"muted"}}}\n\n' +
    "scrim is how much the area behind the text is darkened toward the " +
    "background colour, so the specs stay readable over busy art. " +
    'Also add "tagline_text" with one short line, at most twelve words, ' +
    "that suits what they asked for. Invent no numbers."
  );
}

// Pull JSON out of whatever came back. Agents wrap things in fences and
// commentary no matter how firmly the prompt says not to.
function readDesign(reply, seed) {
  var raw = String(reply || "");
  var start = raw.indexOf("{");
  var end = raw.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) {
    return { layout: normalize(null, seed), tagline: "", ok: false };
  }
  var parsed = null;
  try {
    parsed = JSON.parse(raw.slice(start, end + 1));
  } catch (e) {
    return { layout: normalize(null, seed), tagline: "", ok: false };
  }
  var tagline = String((parsed && parsed.tagline_text) || "")
    .split("\n")[0]
    .replace(/^[\s"'`*_-]+|[\s"'`*_]+$/g, "");
  if (tagline.length > 90) tagline = tagline.slice(0, 87).replace(/\s+\S*$/, "") + "…";
  return { layout: normalize(parsed, seed), tagline: tagline, ok: true };
}
