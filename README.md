# herdr-bob

A [Herdr](https://herdr.dev) plugin that makes **IBM Bob Shell** (`bob`) a
first-class agent in Herdr's agent panel, alongside Claude Code, Codex and Pi â
with live `idle` / `working` / `blocked` state.

> **Not affiliated with, endorsed by, or supported by IBM.** IBM and Bob are
> trademarks of International Business Machines Corp. This repository contains
> an integration only: it redistributes no IBM software and includes no IBM
> source. It drives a `bob` binary you install yourself, under IBM's licence.
> Issues with Bob Shell itself belong to IBM, not here; this repo can only
> support the integration.
>
> Not affiliated with or endorsed by Herdr either. It is an ordinary
> third-party plugin, built against Herdr's public plugin and socket APIs.

## Why this exists

Herdr's agent *kinds* are compiled into its binary, and the documentation is
explicit that "adding a completely new agent still requires a Herdr binary
update". A local detection manifest cannot register a new agent â it only
patches agents Herdr already knows.

So this plugin takes the route Herdr documents for third-party agents under
[Integrate your own agent](https://herdr.dev/docs/integrations/#integrate-your-own-agent):
it reports Bob's lifecycle state itself, which makes it the pane's status
authority. The same mechanism OMP uses.

## How state is determined

Two signals, covering **disjoint** gaps â not redundancy.

Bob has a Claude-Code-shaped hook system with five events, and `bin/bob-hook`
maps them to Herdr states:

| Bob event | Herdr state |
| --- | --- |
| `SessionStart` | `idle` (and records the task id) |
| `UserPromptSubmit` | `working` |
| `PreToolUse` / `PostToolUse` | `working` |
| `Stop` | `idle` â Herdr shows this as `done` until you view it |

Bob has **no approval or notification event**, so a tool-approval prompt is
invisible to the hooks. `bin/bob-watch` therefore polls registered Bob panes and
matches `rules.json` against the screen to report `blocked`. While a hook
heartbeat is fresh the watcher never touches `idle`/`working`, so those always
have exactly one authority.

Bob also fires `SessionStart` on the first prompt rather than at launch, so a
`bob chat` you started yourself is invisible until you say something. The watcher
claims such panes by their foreground process, so they appear straight away.
Panes started through the `start` action are claimed immediately and do not wait
for either.

## Requirements

- Herdr 0.9.0 or newer
- IBM Bob Shell on `PATH` as `bob` â see
  [ibm-bob-shell](https://github.com/MartinLoeper/ibm-bob-shell) for a Nix flake,
  or IBM's own installer
- `jq`

### Versions this was built and verified against

| | Version |
| --- | --- |
| IBM Bob Shell | **2.0.2** (commit `a31a75e3`, released 2026-08-31) |
| Herdr | **0.9.0** (protocol 22) |

Version matters more here than for a typical plugin, because two of the surfaces
this integration reads are not ones IBM documents as stable. If state stops
tracking after an upgrade, suspect these first:

- **The hook contract** â the event names `SessionStart`, `UserPromptSubmit`,
  `PreToolUse`, `PostToolUse` and `Stop`, the `hooks` schema in
  `~/.bob/settings/settings.json`, and the `hook_event_name` / `session_id`
  fields in the JSON Bob sends on stdin.
- **The screen shapes** in `rules.json`, which is the only way `blocked` can be
  detected because Bob has no approval hook event. A redesigned prompt will not
  break Bob, it will just stop showing up as `blocked` in Herdr.

`herdr plugin action invoke mloeper.herdr-bob.status` reports the `bob` on `PATH`
and its version, so it is easy to see what you are actually running.

## Install

```console
$ herdr plugin link /path/to/herdr-bob
$ herdr plugin action invoke mloeper.herdr-bob.install-hook
```

### On NixOS

The flake ships a package and a NixOS module that registers the plugin through
Herdr's own registry API, so other installed plugins stay intact:

```nix
{
  inputs.herdr-bob.url = "github:MartinLoeper/herdr-bob";

  outputs = { nixpkgs, herdr-bob, ... }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      modules = [
        herdr-bob.nixosModules.default
        {
          programs.herdr-bob.enable = true;
          programs.herdr-bob.users = [ "you" ];
        }
      ];
    };
  };
}
```

Herdr's plugin registry is per-user, so `users` lists everyone who should get
it. Set `programs.herdr-bob.herdrPackage` if the Herdr you run is not
`pkgs.herdr` -- registration has to use the same Herdr, since the registry lives
in that Herdr's config directory.

After the first rebuild, run the `install-hook` action once to register the
lifecycle bridge with Bob. You do not need to repeat it on later rebuilds: Bob's
settings point at a stable launcher in the plugin state directory, and the
startup hook re-points that launcher at the new store path on every upgrade.

Or just install the package and link it yourself:

```console
$ nix build github:MartinLoeper/herdr-bob
$ herdr plugin link ./result/share/herdr/plugins/herdr-bob
```

`install-hook` registers the bridge in Bob's global settings
(`~/.bob/settings/settings.json`). It is idempotent, keeps a one-time
`.herdr-bob.bak`, and leaves hooks you configured yourself untouched.
`uninstall-hook` removes exactly its own entries.

Restart any running `bob chat` afterwards so it picks the hooks up.

## Use

| Action | What it does |
| --- | --- |
| `mloeper.herdr-bob.start` | Split a sibling pane, launch `bob chat`, claim it as agent `bob` |
| `mloeper.herdr-bob.status` | Watcher, hook, `bob` and registered-pane status |
| `mloeper.herdr-bob.install-hook` | Register the lifecycle bridge |
| `mloeper.herdr-bob.uninstall-hook` | Remove it |

Bind the launcher to a key:

```toml
# ~/.config/herdr/config.toml
[[keys.command]]
key = "prefix+ctrl+o"
type = "plugin_action"
command = "mloeper.herdr-bob.start"
description = "New Bob pane"
```

Once a pane is running, the usual agent commands work against it:

```console
$ herdr agent list
$ herdr agent prompt bob "summarise the diff" --wait
```

## Tuning blocked detection

`rules.json` is copied into the plugin's config directory on first run
(`herdr plugin config-dir mloeper.herdr-bob`); edit the copy, not the checkout.
Rules match case-insensitively against the bottom of the pane buffer: `all`
patterns must every one match, `any` needs one, `none` must not match.

Keep them strict. An unmatched screen falls back to the hook's state, which is
safe; a false `blocked` stops waits and lights up the sidebar wrongly.

## Known limits

- **No custom sidebar row.** `ui.sidebar.agents.rows_by_agent` is keyed by strict
  canonical agent id and rejects `bob`, so there is no per-agent colour or row
  layout. The plugin sets a `display_agent` instead, which Herdr stores verbatim:
  the panel shows **⬡ Bob** while the canonical id stays `bob`. Override it by
  setting `HERDR_BOB_DISPLAY_NAME` in the environment Herdr launches plugins
  from, e.g. `HERDR_BOB_DISPLAY_NAME="🤖 Bobby"`.
- **No model token.** Pi reports its model to Herdr as a custom `$model` metadata
  token, which the agents panel renders beside the agent name. Bob exposes no
  model name for the plugin to report, so it sets no such token -- deliberately,
  not by omission. Every place worth looking, checked against 2.0.2:
  - Hook payloads carry no model field. `SessionStart` sends `session_id`,
    `cwd`, `hook_event_name` and `source`; the other events add only `prompt`,
    the `tool_*` fields, and `last_assistant_message`.
  - Bob selects model *tiers*, not models -- `fast`, `premium`, `ultra` and a
    hidden `explorer`, defaulting to `premium`. Against the production gateway
    every visible tier resolves to the same underlying model, so a tier names a
    price band rather than a model. `/model` is not offered at all unless more
    than one tier is unlocked.
  - The selected tier is persisted as `_meta.modelTier` on the task snapshot in
    `~/.bob/db/bob.db`. Reading it would add a SQLite dependency next to `jq`
    and a second undocumented schema -- a more fragile surface than the hook
    contract -- for a value that does not vary in practice.
  - Nothing renders the model or the tier on screen, so `bin/bob-watch` cannot
    read it the way it reads `blocked`. The footer shows the *mode* (`Agent`,
    `Plan`, `Ask`), which is a different thing.

  If a later Bob puts a model name in the hook payload or on the screen, this
  becomes small: a `report-metadata --token model=...` call in `lib/common.sh`
  beside the existing `report_display`. Note that the sidebar would still need
  the token in the default `ui.sidebar.agents.rows`, since `rows_by_agent`
  rejects `bob` for the reason above.
- **Herdr cannot restore a Bob pane.** Automatic restore needs Herdr to know how
  to relaunch an agent, which it cannot for a non-native kind. The plugin records
  each pane's task id under its state directory; `status` shows them, and you can
  resume by hand with `bob chat --resume <task-id>`.

## License

MIT; see [LICENSE](LICENSE). It covers this integration only. Bob Shell itself
is neither covered by that licence nor included in this repository.
