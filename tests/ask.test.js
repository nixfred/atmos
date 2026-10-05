const { load, assert, assertEqual } = require("./harness");

const ask = load("services/Ask.js");
const hubs = load("services/Hubs.js").hubs();

for (const [query, id] of [
  ["bluetooth", "bluetooth"],
  ["monitor", "monitor"],
  ["hardware", "hardware"],
  ["appearance", "appearance"],
]) {
  const result = ask.resolve(hubs, query);
  assertEqual(result.kind, "go", "Ask confidently resolves " + query);
  assertEqual(result.target.id, id, "Ask uses the merged catalog for " + query);
}
assertEqual(ask.resolve(hubs, "please how do i").kind, "none", "filler has no destination");
assertEqual(ask.resolve(hubs, "").kind, "empty", "empty questions have no destination");
const answer = ask.readAnswer("PAGE: Monitor\nWHAT: Open CPU for core activity.", hubs);
assertEqual(answer.target.id, "monitor", "agent answers can name the new Monitor hub");
assertEqual(answer.what, "Open CPU for core activity.", "agent explanation is retained");
assertEqual(
  ask.readAnswer("PAGE: Unknown\nWHAT: Unmatched.", hubs).target,
  null,
  "unknown pages cannot navigate",
);
assert(
  ask
    .agentPrompt(
      "show CPU",
      hubs.map((hub) => hub.title),
    )
    .includes("Monitor"),
  "agent prompt includes upstream hubs",
);
