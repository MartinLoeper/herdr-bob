# herdr-bob

A [Herdr](https://herdr.dev) plugin that makes **IBM Bob Shell** (`bob`) a
first-class agent in Herdr's agent panel, alongside Claude Code, Codex and Pi —
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
update". A local detection manifest cannot register a new agent — it only
patches agents Herdr already knows.

So this plugin takes the route Herdr documents for third-party agents under
[Integrate your own agent](https://herdr.dev/docs/integrations/#integrate-your-own-agent):
it reports Bob's lifecycle state itself, which makes it the pane's status
authority. The same mechanism OMP uses.

## How state is determined

Two signals, covering **disjoint** gaps — not redundancy.

Bob has a Claude-Code-shaped hook system with five events, and `bin/bob-hook`
maps them to Herdr states:

| Bob event | Herdr state |
| --- | --- |
| `SessionStart` | `idle` (and records the task id) |
| `UserPromptSubmit` | `working` |
| `PreToolUse` / `PostToolUse` | `working` |
| `Stop` | `idle` — Herdr shows this as `done` until you view it |

Bob has **no approval or notification event**, so a tool-approval prompt is
invisible to the hooks. `bin/bob-watch` therefore polls registered Bob panes and
matches `rules.json` against the screen to report `blocked`. While a hook
heartbeat is fresh the watcher never touches `idle`/`working`, so those always
have exactly one authority.

## Requirements

- Herdr 0.9.0 or newer
- `bob` on `PATH` — see [ibm-bob-shell](https://github.com/MartinLoeper/ibm-bob-shell)
  for a Nix flake, or IBM's own installer
- `jq`

## Install

```console
$ herdr plugin link /path/to/herdr-bob
$ herdr plugin action invoke mloeper.herdr-bob.install-hook
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
  canonical agent id and rejects `bob`. The plugin sets a `display_agent` of
  `Bob` instead, and the default agent row is used.
- **Herdr cannot restore a Bob pane.** Automatic restore needs Herdr to know how
  to relaunch an agent, which it cannot for a non-native kind. The plugin records
  each pane's task id under its state directory; `status` shows them, and you can
  resume by hand with `bob chat --resume <task-id>`.

## License

MIT; see [LICENSE](LICENSE). It covers this integration only. Bob Shell itself
is neither covered by that licence nor included in this repository.
