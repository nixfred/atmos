# Atmos Lab — build tracker

Branch: `lab/atmos-pizzazz` (fork remote = github.com/nixfred/atmos)
Base: `561cc9f` (v0.0.1-alpha.14)
Submission plan: GitHub **Issue** on csfh/atmos + link to this branch. **No PR.**

Master switch: `ATMOS_LAB=0` reverts everything. `ATMOS_LAB_OFF=id,id` disables individually.

| # | Idea | id | State | Commit |
|---|------|-----|-------|--------|
| 6 | Chamfered shape language | `chamfer` | DONE — Fred disliked, kept for csfh to judge | `d645fb4` |
| 1 | Live status glyphs in sidebar | `statusglyph` | DONE — verified on screen + all paths tested | `560d8ad` |
| 8 | Live hover preview | `hoverpreview` | todo | — |
| 3 | "Why is this set?" provenance | `provenance` | DONE — section-level | `164b2ac` |
| 7 | Simple / Everything per page | `disclosure` | DONE | `ed756c7` |
| 5 | Preview mode (diff before write) | `previewmode` | todo | — |
| 4 | Time machine (change history) | `timemachine` | todo | — |
| 10 | Keyboard-first navigation | `keyboard` | DONE | `a765d44` |
| 9 | Machine page | `machine` | DONE | `008520a` |
| 2 | Ask bar (agent proposes, never writes) | `askbar` | DONE | `23e38f1` |

## Then

- [ ] Lab page listing all ten with runtime toggles
- [ ] Full `./tests/run` green (needs PR #26's HOME sandbox fix to complete on this box)
- [ ] Screenshots of each feature
- [ ] Write the Issue for csfh/atmos, plain language, no jargon
- [ ] Push branch to fork, post Issue, give Fred the group-chat text

## Working notes

- `services/Theme.qml` carries csfh's design law: no rounded cards, no shadows,
  no wider column. Honour it. The chamfer is a cut, not a radius.
- Dev loop: `quickshell -n -p /home/pi/Projects/atmos`. Kill with
  `quickshell kill -p /home/pi/Projects/atmos`, never `pkill -f` (it matches
  this shell's own command line and kills the session).
- Never `pkill -x quickshell` either — that takes down Fred's Omarchy bar.
- Screenshot: `grim -g "<x>,<y> <w>x<h>"` using geometry from `hyprctl clients -j`.
