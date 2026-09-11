// Lab(machinecard): turn a sentence into a picture, without an image model.
//
// You describe a feeling -- "dragons and fire", "cold machine underwater",
// "quiet paper" -- and this decides what gets drawn. It will not draw a
// dragon. What it does is pick a motif family and set its parameters, so
// "dragons and fire" produces a hot, dense, upward ember field with angular
// scale tessellation, and "quiet paper" produces sparse pale horizontals.
// Saying that plainly matters: a feature that quietly fails to deliver a
// dragon is worse than one that never promised it.
//
// Everything returns plain data -- a list of shapes with coordinates and
// colours -- rather than drawing. That keeps the whole engine testable in
// Node, which is the only way to know a card is not empty or off-canvas
// without staring at every one of them.
//
// The skeleton stays fixed no matter what you type. Same mark, same spec
// block, same wordmark, same proportions. Only the art layer moves, so
// every card still reads as an Atmos host card at a glance.

var MOTIFS = ["embers", "scales", "waves", "circuit", "stars", "peaks", "rain", "bloom"];

// Words to motifs. Deterministic, runs with no model installed, and it is
// also the safety net for a model that replies with nonsense.
var CUES = [
  {
    motif: "embers",
    words: [
      "fire",
      "flame",
      "ember",
      "burn",
      "dragon",
      "lava",
      "forge",
      "heat",
      "inferno",
      "magma",
      "phoenix",
      "hell",
    ],
  },
  {
    motif: "scales",
    words: [
      "scale",
      "dragon",
      "armor",
      "armour",
      "reptile",
      "serpent",
      "shield",
      "tile",
      "mosaic",
      "facet",
      "crystal",
    ],
  },
  {
    motif: "waves",
    words: [
      "water",
      "ocean",
      "sea",
      "wave",
      "underwater",
      "tide",
      "liquid",
      "flow",
      "calm",
      "smooth",
      "silk",
    ],
  },
  {
    motif: "circuit",
    words: [
      "circuit",
      "machine",
      "cyber",
      "tech",
      "wire",
      "board",
      "matrix",
      "data",
      "digital",
      "robot",
      "grid",
      "terminal",
    ],
  },
  {
    motif: "stars",
    words: [
      "star",
      "space",
      "night",
      "cosmos",
      "galaxy",
      "void",
      "universe",
      "sky",
      "constellation",
      "deep",
    ],
  },
  {
    motif: "peaks",
    words: [
      "mountain",
      "peak",
      "ridge",
      "alpine",
      "rock",
      "cliff",
      "summit",
      "horizon",
      "landscape",
    ],
  },
  {
    motif: "rain",
    words: ["rain", "storm", "matrix", "fall", "drip", "monsoon", "code", "cascade"],
  },
  {
    motif: "bloom",
    words: [
      "flower",
      "bloom",
      "garden",
      "organic",
      "soft",
      "petal",
      "spring",
      "nature",
      "leaf",
      "growth",
    ],
  },
];

var HOT = [
  "fire",
  "flame",
  "ember",
  "burn",
  "dragon",
  "lava",
  "heat",
  "hot",
  "inferno",
  "magma",
  "red",
  "orange",
  "sun",
  "desert",
];
var COLD = [
  "ice",
  "cold",
  "frost",
  "winter",
  "arctic",
  "blue",
  "water",
  "ocean",
  "underwater",
  "steel",
  "chrome",
  "moon",
  "snow",
];
var LOUD = [
  "loud",
  "bold",
  "aggressive",
  "intense",
  "chaos",
  "wild",
  "brutal",
  "heavy",
  "max",
  "extreme",
  "dense",
  "storm",
  "inferno",
];
var QUIET = [
  "quiet",
  "calm",
  "minimal",
  "subtle",
  "soft",
  "clean",
  "sparse",
  "gentle",
  "simple",
  "still",
  "plain",
  "paper",
];

function words(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/^ | $/g, "")
    .split(" ")
    .filter(function (w) {
      return w.length > 0;
    });
}

function countHits(list, bag) {
  var n = 0;
  for (var i = 0; i < bag.length; i++) {
    for (var j = 0; j < list.length; j++) {
      if (bag[i] === list[j]) n += 1;
    }
  }
  return n;
}

function clamp(value, low, high) {
  var n = Number(value);
  if (!isFinite(n)) return low;
  return Math.max(low, Math.min(high, n));
}

function defaultSpec() {
  return {
    motif: "circuit",
    density: 0.5,
    intensity: 0.5,
    warmth: 0,
    direction: "up",
    seed: 1,
  };
}

// A stable number from a string, so the same words always draw the same
// card. Two people typing the same thing should get the same picture, and
// one person should not get a different card every time they press Save.
function seedFrom(text) {
  var s = String(text || "");
  var h = 2166136261;
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = (h * 16777619) >>> 0;
  }
  return h || 1;
}

// The no-model path, and the validator for the model path.
function parseWish(text) {
  var bag = words(text);
  var spec = defaultSpec();
  spec.seed = seedFrom(text);
  if (bag.length === 0) return spec;

  var best = "";
  var bestScore = 0;
  for (var i = 0; i < CUES.length; i++) {
    var score = countHits(CUES[i].words, bag);
    if (score > bestScore) {
      bestScore = score;
      best = CUES[i].motif;
    }
  }
  if (best) spec.motif = best;

  var hot = countHits(HOT, bag);
  var cold = countHits(COLD, bag);
  if (hot !== cold) spec.warmth = clamp((hot - cold) / 2, -1, 1);

  var loud = countHits(LOUD, bag);
  var quiet = countHits(QUIET, bag);
  if (loud > quiet) {
    spec.intensity = clamp(0.6 + loud * 0.15, 0, 1);
    spec.density = clamp(0.6 + loud * 0.15, 0, 1);
  } else if (quiet > loud) {
    spec.intensity = clamp(0.4 - quiet * 0.12, 0.05, 1);
    spec.density = clamp(0.35 - quiet * 0.1, 0.05, 1);
  }

  if (bag.indexOf("down") !== -1 || bag.indexOf("falling") !== -1 || bag.indexOf("rain") !== -1) {
    spec.direction = "down";
  }
  return spec;
}

// Ask the local model for parameters, never for prose. A small model is bad
// at art direction and fine at picking one of eight words and four numbers.
function wishPrompt(text) {
  var wish = String(text || "").replace(/^\s+|\s+$/g, "");
  if (!wish) return "";
  return (
    'Someone described the mood they want for a computer wallpaper: "' +
    wish +
    '"\n\nPick settings for an abstract generated pattern. Reply with JSON only, no other words:\n' +
    '{"motif":"one of ' +
    MOTIFS.join("|") +
    '","density":0.0-1.0,"intensity":0.0-1.0,"warmth":-1.0-1.0,"direction":"up|down"}\n\n' +
    "warmth -1 is cold blue, 1 is hot red. density is how much of the canvas is covered. " +
    "intensity is how bright and aggressive it looks."
  );
}

// Accept the model's answer only where it is sane, and fall back per field
// rather than wholesale. A reply that gets the motif right and the numbers
// wrong should still give you the right motif.
function readWishReply(reply, wishText) {
  var fallback = parseWish(wishText);
  var raw = String(reply || "");
  var start = raw.indexOf("{");
  var end = raw.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return fallback;
  var parsed = null;
  try {
    parsed = JSON.parse(raw.slice(start, end + 1));
  } catch (e) {
    return fallback;
  }
  if (!parsed || typeof parsed !== "object") return fallback;

  var spec = {
    motif: fallback.motif,
    density: fallback.density,
    intensity: fallback.intensity,
    warmth: fallback.warmth,
    direction: fallback.direction,
    seed: fallback.seed,
  };
  var motif = String(parsed.motif || "").toLowerCase();
  for (var i = 0; i < MOTIFS.length; i++) {
    if (MOTIFS[i] === motif) spec.motif = motif;
  }
  if (parsed.density !== undefined) spec.density = clamp(parsed.density, 0, 1);
  if (parsed.intensity !== undefined) spec.intensity = clamp(parsed.intensity, 0, 1);
  if (parsed.warmth !== undefined) spec.warmth = clamp(parsed.warmth, -1, 1);
  if (String(parsed.direction || "").toLowerCase() === "down") spec.direction = "down";
  return spec;
}

// Deterministic generator. Never Math.random: the same card must redraw
// identically on every repaint, or the preview and the saved file differ.
function rng(seed) {
  var s = seed >>> 0 || 1;
  return function () {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// Blend toward warm or cold without leaving the theme. The palette always
// wins; warmth only leans it, so a card cannot come out in colours the
// user's theme never contained.
function tint(base, warmth, amount) {
  // Lean the palette, hard, when asked. An earlier version moved the colour
  // so gently that "dragons and fire" on a cool theme came out as pale blue
  // bubbles -- technically inside the palette and completely wrong. The
  // theme still sets the base, so a card stays recognisably yours, but a
  // request for heat has to actually look hot or the feature is a lie.
  var w = clamp(warmth, -1, 1) * clamp(amount, 0, 1);
  if (w === 0) return { r: base.r, g: base.g, b: base.b };
  if (w > 0) {
    // Toward ember: red dominant, green follows for orange, blue pulled out.
    return {
      r: clamp(base.r * (1 - w) + 1.0 * w, 0, 1),
      g: clamp(base.g * (1 - w) + 0.42 * w, 0, 1),
      b: clamp(base.b * (1 - w * 1.2), 0, 1),
    };
  }
  var c = -w;
  return {
    r: clamp(base.r * (1 - c * 1.1), 0, 1),
    g: clamp(base.g * (1 - c) + 0.55 * c, 0, 1),
    b: clamp(base.b * (1 - c) + 1.0 * c, 0, 1),
  };
}

// Returns shapes, not pixels. The caller draws them; tests can count them,
// check they are inside the canvas, and prove a motif is not empty.
// `width`/`height` are the whole canvas. The spec's x/y/w/h name the region
// the art should occupy inside it, and every shape comes back already offset
// into that region.
//
// Offsetting here rather than positioning a wrapper Item keeps the whole
// card on one canvas: fewer moving parts, and no second element whose size
// has to be kept in step with the art region.
function plan(spec, width, height, palette) {
  var s = spec || defaultSpec();
  var fullW = Number(width) || 0;
  var fullH = Number(height) || 0;
  var offX = clamp(s.x === undefined ? 0 : s.x, 0, 1) * fullW;
  var offY = clamp(s.y === undefined ? 0 : s.y, 0, 1) * fullH;
  var w = clamp(s.w === undefined ? 1 : s.w, 0.05, 1) * fullW;
  var h = clamp(s.h === undefined ? 1 : s.h, 0.05, 1) * fullH;
  var pal = palette || { r: 0.5, g: 0.5, b: 0.5 };
  var out = [];
  if (w <= 0 || h <= 0 || fullW <= 0 || fullH <= 0) return out;

  var rand = rng(s.seed);
  // Scale with the canvas. Every size below was first written against a
  // small card and then drawn on a 1920x1080 one, where a 3px ember reads
  // as dust -- "dragons and fire" came out looking like light snow. Sizes
  // are relative now, so a card is the same picture at any resolution
  // instead of the same picture only at the size it was tuned at.
  var k = Math.min(w, h) / 620;
  var area = (w * h) / (1000 * 620);
  var density = clamp(s.density, 0, 1);
  var intensity = clamp(s.intensity, 0, 1);
  var warmth = clamp(s.warmth, -1, 1);
  var down = s.direction === "down";
  var ink = tint(pal, warmth, 0.8);

  function push(shape) {
    if (shape.points) {
      for (var pi = 0; pi < shape.points.length; pi++) {
        shape.points[pi].x += offX;
        shape.points[pi].y += offY;
      }
    } else {
      if (shape.x !== undefined) shape.x += offX;
      if (shape.y !== undefined) shape.y += offY;
    }
    out.push(shape);
  }

  function alpha(base) {
    // Intensity has to be felt. The old curve topped out too low for a
    // loud request to actually look loud.
    return clamp(base * (0.5 + intensity * 2.2), 0.02, 0.92);
  }

  var count;
  var i;

  if (s.motif === "embers") {
    count = Math.round((120 + density * 900) * area);
    for (i = 0; i < count; i++) {
      var ex = rand() * w;
      var bias = rand();
      var ey = down ? bias * bias * h : h - bias * bias * h;
      var r = (1 + rand() * (2 + intensity * 7)) * k;
      push({ type: "circle", x: ex, y: ey, r: r, color: ink, alpha: alpha(0.1 + rand() * 0.3) });
    }
    var glowRows = 26;
    for (i = 0; i < glowRows; i++) {
      var gy = down ? (i / glowRows) * h : h - (i / glowRows) * h;
      push({
        type: "rect",
        x: 0,
        y: gy - h / glowRows,
        w: w,
        h: h / glowRows + 1,
        color: ink,
        alpha: alpha(0.05 * (1 - i / glowRows)),
      });
    }
  } else if (s.motif === "scales") {
    var size = Math.max(18, 90 - density * 60) * k;
    var cols = Math.ceil(w / size) + 1;
    var rowsN = Math.ceil(h / (size * 0.6)) + 1;
    for (var ry = 0; ry < rowsN; ry++) {
      for (var cx = 0; cx < cols; cx++) {
        var ox = (ry % 2 === 0 ? 0 : size / 2) + cx * size;
        var oy = ry * size * 0.6;
        push({
          type: "poly",
          points: [
            { x: ox, y: oy },
            { x: ox + size / 2, y: oy + size * 0.35 },
            { x: ox, y: oy + size * 0.7 },
            { x: ox - size / 2, y: oy + size * 0.35 },
          ],
          color: ink,
          alpha: alpha(0.04 + rand() * 0.13),
        });
      }
    }
  } else if (s.motif === "waves") {
    var lines = Math.round((10 + density * 44) * Math.max(1, h / 620));
    for (i = 0; i < lines; i++) {
      var baseY = (i / lines) * h;
      var pts = [];
      var amp = (6 + rand() * 34) * (0.4 + intensity) * k;
      var phase = rand() * 6.283;
      for (var x = 0; x <= w; x += Math.max(6, w / 140)) {
        pts.push({ x: x, y: baseY + Math.sin(x / (90 + rand() * 10) + phase) * amp });
      }
      push({
        type: "line",
        points: pts,
        color: ink,
        alpha: alpha(0.06 + rand() * 0.14),
        width: (1 + rand() * 2) * k,
      });
    }
  } else if (s.motif === "circuit") {
    var traces = Math.round((24 + density * 130) * area);
    for (i = 0; i < traces; i++) {
      var pitch = 20 * k;
      var px = Math.round((rand() * w) / pitch) * pitch;
      var py = Math.round((rand() * h) / pitch) * pitch;
      var seg = [{ x: px, y: py }];
      var steps = 2 + Math.floor(rand() * 5);
      for (var k = 0; k < steps; k++) {
        if (rand() > 0.5) px += (rand() > 0.5 ? 1 : -1) * pitch * (1 + Math.floor(rand() * 4));
        else py += (rand() > 0.5 ? 1 : -1) * pitch * (1 + Math.floor(rand() * 3));
        seg.push({ x: px, y: py });
      }
      push({ type: "line", points: seg, color: ink, alpha: alpha(0.06 + rand() * 0.16), width: 1 });
      push({ type: "circle", x: px, y: py, r: 2 + rand() * 2, color: ink, alpha: alpha(0.15) });
    }
  } else if (s.motif === "stars") {
    count = Math.round((160 + density * 1100) * area);
    for (i = 0; i < count; i++) {
      push({
        type: "circle",
        x: rand() * w,
        y: rand() * h,
        r: (0.6 + rand() * (1.4 + intensity * 2)) * k,
        color: ink,
        alpha: alpha(0.08 + rand() * 0.4),
      });
    }
  } else if (s.motif === "peaks") {
    var ranges = 3 + Math.round(density * 5);
    for (i = 0; i < ranges; i++) {
      var baseline = h * (0.45 + (i / ranges) * 0.55);
      var ptsP = [{ x: 0, y: h }];
      var step = w / (8 + Math.floor(rand() * 10));
      for (var xx = 0; xx <= w; xx += step) {
        ptsP.push({ x: xx, y: baseline - rand() * h * 0.22 * (1 + intensity) });
      }
      ptsP.push({ x: w, y: h });
      push({ type: "poly", points: ptsP, color: ink, alpha: alpha(0.05 + (i / ranges) * 0.12) });
    }
  } else if (s.motif === "rain") {
    count = Math.round((80 + density * 700) * area);
    for (i = 0; i < count; i++) {
      var rx = rand() * w;
      var ry2 = rand() * h;
      var len = (8 + rand() * (20 + intensity * 70)) * k;
      push({
        type: "line",
        points: [
          { x: rx, y: ry2 },
          { x: rx, y: Math.min(h, ry2 + len) },
        ],
        color: ink,
        alpha: alpha(0.06 + rand() * 0.2),
        width: Math.max(1, k * 0.9),
      });
    }
  } else {
    // bloom
    var blobs = Math.round(8 + density * 40);
    for (i = 0; i < blobs; i++) {
      var bx = rand() * w;
      var by = rand() * h;
      var petals = 5 + Math.floor(rand() * 5);
      var rad = (20 + rand() * (60 + intensity * 120)) * k;
      for (var pI = 0; pI < petals; pI++) {
        var ang = (pI / petals) * 6.283;
        push({
          type: "circle",
          x: bx + Math.cos(ang) * rad * 0.5,
          y: by + Math.sin(ang) * rad * 0.5,
          r: rad * 0.32,
          color: ink,
          alpha: alpha(0.03 + rand() * 0.07),
        });
      }
    }
  }

  return out;
}

// Used by tests and by the page's own sanity check: a motif that draws
// nothing, or draws entirely off-canvas, is a bug the eye will miss on a
// dark theme.
function planStats(shapes, width, height) {
  var list = Array.isArray(shapes) ? shapes : [];
  var w = Number(width) || 0;
  var h = Number(height) || 0;
  var inside = 0;
  for (var i = 0; i < list.length; i++) {
    var s = list[i];
    var x = s.x;
    var y = s.y;
    if (s.points && s.points.length > 0) {
      x = s.points[0].x;
      y = s.points[0].y;
    }
    if (x >= -w && x <= w * 2 && y >= -h && y <= h * 2) inside += 1;
  }
  return { count: list.length, inside: inside };
}
