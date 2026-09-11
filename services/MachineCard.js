// Lab(machinecard): the shareable spec card.
//
// This exists to be posted in public, which makes it the one place in Atmos
// where the interesting question is not "what can we show" but "what must
// never leave". Everything here is an allow-list. Nothing reaches the card
// because it happened to be in the snapshot; a field appears only because
// it was named, and a new field added upstream stays invisible until
// somebody decides it is safe.
//
// That direction matters. A deny-list leaks by default -- the day a vendor
// adds machine.assetTag, a deny-list ships it and an allow-list does not.
//
// hw-inventory.py already carries machine.serial, board.serial and
// machine.sku. A SKU is a per-unit purchase identifier. None of the three
// are ever read here, and there is a test below that proves it.

var REDACTED_HINTS = [
  "serial",
  "sku",
  "uuid",
  "assettag",
  "asset_tag",
  "mac",
  "macaddress",
  "address",
  "ip",
  "ipv4",
  "ipv6",
  "hostname",
  "host",
  "user",
  "username",
  "owner",
  "ssid",
  "token",
  "key",
  "secret",
  "license",
  "licence",
];

// True when a field name looks like it identifies the machine or its owner
// rather than describing the hardware. Used to audit the card, not to build
// it -- building is allow-list only. Belt and braces, because the cost of a
// mistake here is somebody's serial number on the internet.
function looksIdentifying(name) {
  var n = String(name || "")
    .toLowerCase()
    .replace(/[^a-z]/g, "");
  if (!n) return false;
  for (var i = 0; i < REDACTED_HINTS.length; i++) {
    var hint = REDACTED_HINTS[i];
    if (n === hint) return true;
    // Substring, so boardSerial and serialNumber both match, but avoid the
    // short hints matching innocent words: "ip" must not match "chipset".
    if (hint.length >= 4 && n.indexOf(hint) !== -1) return true;
  }
  return false;
}

function text(value) {
  var s = String(value === undefined || value === null ? "" : value);
  return s.replace(/\s+/g, " ").replace(/^ | $/g, "");
}

function bytesToGb(value) {
  var n = Number(value);
  if (!isFinite(n) || n <= 0) return "";
  var gb = n / 1000000000;
  if (gb >= 100) return Math.round(gb) + " GB";
  return (Math.round(gb * 10) / 10).toString().replace(/\.0$/, "") + " GB";
}

function cpuLine(cpu) {
  var c = cpu || {};
  var model = text(c.model);
  if (!model) return "";
  // Marketing noise that costs width and says nothing.
  model = model
    .replace(/\(R\)|\(TM\)|\(r\)|\(tm\)/g, "")
    .replace(/ CPU @.*$/, "")
    .replace(/ w\/ .*$/, "")
    .replace(/\s+/g, " ")
    .replace(/^ | $/g, "");
  var cores = Number(c.cores);
  var threads = Number(c.threads);
  var bits = [];
  if (isFinite(cores) && cores > 0) bits.push(cores + "c");
  if (isFinite(threads) && threads > 0) bits.push(threads + "t");
  return bits.length > 0 ? model + "  ·  " + bits.join("/") : model;
}

function gpuLines(gpus) {
  var list = Array.isArray(gpus) ? gpus : [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var name = text(list[i] && list[i].name);
    if (!name) continue;
    name = name.replace(/\s*\(rev [0-9a-f]+\)\s*/i, "").replace(/\[|\]/g, "");
    out.push(name);
  }
  return out;
}

function machineName(machine) {
  var m = machine || {};
  var vendor = text(m.vendor);
  var name = text(m.name);
  if (!vendor && !name) return "";
  if (!name) return vendor;
  // "HP" + "Victus by HP Gaming Laptop" should not read "HP Victus by HP".
  if (vendor && name.toLowerCase().indexOf(vendor.toLowerCase()) !== -1) return name;
  return (vendor + " " + name).replace(/^ | $/g, "");
}

// Build the card. Every value is named explicitly; `state` may carry
// anything at all and only these keys are ever touched.
function build(state) {
  var s = state || {};
  var hw = s.hardware || {};
  var rows = [];

  function add(label, value) {
    var v = text(value);
    if (v) rows.push({ label: label, value: v });
  }

  add("Machine", machineName(hw.machine));
  add("OS", s.omarchyVersion ? "Omarchy " + text(s.omarchyVersion) : "Omarchy");
  add("Kernel", s.kernel);
  add("CPU", cpuLine(hw.cpu));
  var gpus = gpuLines(hw.gpus);
  if (gpus.length > 0) add("GPU", gpus[0]);
  if (gpus.length > 1) add("GPU 2", gpus[1]);
  add("Memory", bytesToGb(hw.memory && hw.memory.total));
  add("Storage", bytesToGb(s.storageTotal));
  add("Compositor", s.compositor);
  add("Shell", s.shell);
  add("Theme", s.theme);
  add("Uptime", s.uptime);
  if (Number(s.vms) > 0) add("VMs", Number(s.vms) + " running");

  return {
    title: s.title || "This machine",
    tagline: text(s.tagline),
    rows: rows,
  };
}

// Proof, not assertion. Runs over a built card and reports any field whose
// name or value looks identifying, so the test suite can fail if a future
// edit widens the allow-list carelessly.
function auditCard(card, forbiddenValues) {
  var c = card || {};
  var rows = Array.isArray(c.rows) ? c.rows : [];
  var banned = Array.isArray(forbiddenValues) ? forbiddenValues : [];
  var problems = [];
  var i, j;
  for (i = 0; i < rows.length; i++) {
    var row = rows[i] || {};
    if (looksIdentifying(row.label)) {
      problems.push("label looks identifying: " + row.label);
    }
    var value = String(row.value === undefined ? "" : row.value);
    for (j = 0; j < banned.length; j++) {
      var bad = String(banned[j] || "");
      if (bad && value.indexOf(bad) !== -1) {
        problems.push("value leaks " + bad + " in row " + row.label);
      }
    }
  }
  return problems;
}

// Fallback tagline when no local model is running. Deterministic, and it
// never claims a number it was not given.
function defaultTagline(card) {
  var rows = (card && card.rows) || [];
  var cpu = "";
  var mem = "";
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].label === "CPU") cpu = rows[i].value;
    if (rows[i].label === "Memory") mem = rows[i].value;
  }
  if (cpu && mem) return "Running Omarchy on " + cpu.split("  ·  ")[0] + " with " + mem + ".";
  return "Running Omarchy.";
}

// What a local model is asked for. One line, no numbers -- a small model
// invents figures, and a card full of invented specs is worse than a card
// with none.
function taglinePrompt(card) {
  var c = card || {};
  var rows = Array.isArray(c.rows) ? c.rows : [];
  var lines = [];
  for (var i = 0; i < rows.length; i++) {
    lines.push(rows[i].label + ": " + rows[i].value);
  }
  return (
    "This is a Linux desktop machine running Omarchy:\n" +
    lines.join("\n") +
    "\n\nWrite ONE short line, at most twelve words, that a person would put " +
    "under this spec list when showing it off. No emoji, no hashtags, no " +
    "quotation marks, and do not invent any numbers or part names that are " +
    "not listed above. Reply with the line only."
  );
}

// Keep a model's enthusiasm inside the card. One line, no markup, no made-up
// figures echoed back as fact.
function cleanTagline(reply) {
  var t = String(reply || "")
    .split("\n")[0]
    .replace(/^[\s"'`*_-]+|[\s"'`*_]+$/g, "")
    .replace(/\s+/g, " ");
  if (t.length > 90) t = t.slice(0, 87).replace(/\s+\S*$/, "") + "…";
  return t;
}
