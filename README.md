# herdr-bob

A [Herdr](https://herdr.dev) plugin that makes **IBM Bob Shell** (`bob`) a
first-class agent in Herdr's agent panel, alongside Claude Code, Codex and Pi —
with live `idle` / `working` / `blocked` state, session restore, and the normal
`herdr agent` commands.

> **Not affiliated with, endorsed by, or supported by IBM.** IBM and Bob are
> trademarks of International Business Machines Corp. This repository contains
> an integration only: it redistributes no IBM software and includes no IBM
> source. It talks to a `bob` binary you install yourself, under IBM's licence.
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

## Requirements

- Herdr 0.9.0 or newer
- `bob` on `PATH` — see [ibm-bob-shell](https://github.com/MartinLoeper/ibm-bob-shell)
  for a Nix flake, or IBM's own installer
- `jq` and `socat`

## Install

```console
$ herdr plugin link /path/to/herdr-bob
$ herdr plugin action invoke mloeper.herdr-bob.install-hook
```

`install-hook` registers the lifecycle bridge in Bob's global settings
(`~/.bob/settings/settings.json`). Remove it again with
`mloeper.herdr-bob.uninstall-hook`, which touches only its own entries.

## License

MIT; see [LICENSE](LICENSE). It covers this integration only. Bob Shell itself
is neither covered by that licence nor included in this repository.
