# Monster Hunter Wilds: seamless co-op

**Seamless Coop**, a [REFramework](https://github.com/praydog/REFramework)
Lua plugin that keeps a link party together without loading screens:
joining and leaving a friend's Environment Link in place, and starting,
joining, ending and abandoning quests inside it without anybody being
sent back to their own world.

Work in progress, for two players so far. Every player needs the plugin.

## State

- A first version was played for a day (2026-11-15): in-place link join
  and leave, quests started and ended in place for host and guest, a
  guest waiting outside the host's quest and rejoining it, notices with
  a Y prompt, the party invited again after a travel.
- `plugin/` is a **rewrite** of that version around an explicit model.
  It keeps the first version's game calls, in the same order. **It has
  not run in a game yet.**
- On top of it, quests in other stages (a travel on one's own, then the
  start or the join in place) were written with one player only: what
  they assume about the game is marked `ASSUMED` or `UNVERIFIED` in the
  code.

Next: a first run of the rewrite with two players.

## Layout

| | |
|---|---|
| `plugin/seamless_coop.lua` | the autorun entry |
| `plugin/seamless_coop/` | the plugin; `main.lua` says what each part is |
| `types/reframework.lua` | type stubs of REFramework's Lua API, for the typecheck |
| `tools/` | check, install, bundle |

## Working on it

Linux, the game through Steam/Proton, REFramework installed in the game
directory. The tools find the game in
`~/.local/share/Steam/steamapps/common/MonsterHunterWilds`; set `MHW_DIR`
when it is elsewhere.

    tools/check-plugin              # compile, lint, typecheck
    tools/install-plugin --entry    # check, then copy into reframework/autorun/ (loaded at boot)

    tools/build-plugin              # check, then bundle into build/seamless_coop.lua

`build/seamless_coop.lua` is the whole plugin in one file, for anyone
who only plays: it goes into the game's `reframework/autorun/`, alone
(not beside an install made by `tools/install-plugin`).

`tools/check-plugin` needs `luac`, `luacheck` and `emmylua_check`: with
Nix it finds them by itself (`flake.nix`; `nix develop` or `direnv allow`
for an editor).

After an edit: `tools/install-plugin`, then "Reset scripts" in
REFramework's menu. The plugin's hooks stay until the game restarts.
Its journal is `reframework/data/seamless_coop.log`; its switch is in
REFramework's menu, under Script Generated UI.

## How the code is held together

- The plugin reads the situation once per frame into one value, the
  world (`world.lua`); does one thing at a time, the state (`state.lua`,
  one class per state in `ops/`); and takes every decision in
  `policy.lua`. The game's objects are behind classes in `game/`.
- No tests, on purpose: the plugin owns nothing by itself, so a test
  would only check our assumptions about the game. Invariants are in the
  model and the types, and `tools/check-plugin` refuses what breaks
  them: a case left out, a transition that does not exist, a function of
  a cyclomatic complexity above 5.
- A game call sequence proven in a run is moved, never reordered or
  retimed, without a new run.

Not affiliated with Capcom. No game code or assets.
