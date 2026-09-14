# AGENTS.md

A Herdr plugin that reports IBM Bob Shell's lifecycle state so Bob shows up in
Herdr's agent panel. Read `README.md` first for what it does and why.

## Commit conventions

This repo is **public**. Commit messages carry no AI attribution trailers — no
`Co-Authored-By: Claude …`, no `Claude-Session:`. Just the message.

Describe the behavioural effect and, where it is not obvious, why. Several
decisions here look arbitrary until you know the constraint behind them, so the
history is the place that constraint gets recorded.

## Development

```console
$ herdr plugin link "$PWD"          # live: edits take effect immediately
$ herdr plugin action invoke mloeper.herdr-bob.install-hook
$ herdr plugin action invoke mloeper.herdr-bob.status
```

Action stdout does **not** come back from `plugin action invoke`. Read it with:

```console
$ herdr plugin log list --plugin mloeper.herdr-bob --limit 1 | jq -r '.result.logs[0].stdout'
```

The plugin's own log is `<state>/herdr-bob.log`; `status` prints the state and
config directories.

Before changing anything that touches Bob's behaviour -- the hook bridge, the
settings writers, `rules.json` -- confirm you are working against the current
public Bob release, not a stale local one. See
[First: check what IBM currently ships](#first-check-what-ibm-currently-ships).

Never test `bin/bob-hook` from a pane that is running another agent. It reports
whatever `$HERDR_PANE_ID` says, so it will claim that pane as Bob. Use
`env -u HERDR_ENV -u HERDR_PANE_ID` to exercise the no-op path. If you do claim
a pane by mistake, `herdr pane release-agent` alone does **not** restore native
detection — the pane goes to `unknown` and stays there. `herdr server
reload-agent-manifests` brings it back.

## After an upgrade

The integration reads two surfaces that nobody promises to keep stable. Neither
fails loudly: Bob keeps working, Herdr keeps working, the state in the sidebar
just quietly stops matching reality. So check after upgrading either side.

### First: check what IBM currently ships

Always verify against the **officially released, current** Bob Shell — not
whatever happens to be installed, and never against a pre-release. Documenting or
tuning this plugin against a version the public cannot obtain makes the README's
version table a lie and leaves everyone else with rules that do not match their
screen.

IBM publishes the current version as a plain file next to the tarball, so there
is no registry to query and no login involved:

```console
$ curl -fsSL https://s3.us-south.cloud-object-storage.appdomain.cloud/bob-shell/bobshell2-version.txt
2.0.2
$ bob --version
2.0.2
commit: a31a75e3
```

Three things must agree before a verification run means anything:

1. **What IBM publishes** — the `bobshell2-version.txt` above.
2. **What is installed** — `bob --version`, or the `status` action.
3. **What `README.md` claims** — the version table under Requirements.

If they disagree:

- *Installed lags published* — upgrade first, then verify. For the Nix install
  that is `./update.sh` in
  [ibm-bob-shell](https://github.com/MartinLoeper/ibm-bob-shell), which re-reads
  IBM's version and checksum files and refreshes every hash.
- *Installed leads published* — you are on something unreleased. Do not tune
  `rules.json` or update the version table against it; wait until it ships.
- *README lags installed* — finish the checks below, then update the table.

Note that Bob defaults to `bobShell.autoUpdate: true`, so an npm-style install
can move under you between sessions, while a Nix install is pinned and will sit
still until `update.sh` runs. Check, rather than assume, which situation you are
in — the two drift in opposite directions.

### After upgrading Bob Shell

Locate the bundle — on NixOS `bob` is two wrapper layers above it:

```bash
f=$(command -v bob)
for _ in 1 2 3 4 5; do
  f=$(readlink -f "$f")
  b=$(grep -oE '[^ "]+/dist/bob\.js' "$f" 2>/dev/null | head -1) && [ -n "$b" ] && { bundle=$b; break; }
  n=$(grep -oE '[^ "]+/bin/bob' "$f" 2>/dev/null | tail -1)
  [ -n "$n" ] && [ "$n" != "$f" ] || break
  f=$n
done
```

**1. Are the five hook events still the same set?**

```console
$ grep -o 'BOB_HOOK_EVENTS=\[[^]]*\]' "$bundle"
BOB_HOOK_EVENTS=["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop"]
```

A *new* event is an opportunity — an approval or notification event would let
`blocked` come from the hook and retire most of `bin/bob-watch`. A *removed* or
renamed event breaks the mapping in `bin/bob-hook`.

**2. Are the payload fields still named the same?**

```console
$ grep -o 'session_id:[^,]*,cwd:[^,]*,hook_event_name:"SessionStart"' "$bundle"
session_id:e.rootTaskId,cwd:e.cwd,hook_event_name:"SessionStart"
```

`bin/bob-hook` reads `.hook_event_name` and `.session_id` off stdin. `session_id`
being `rootTaskId` is what makes the recorded id usable with `bob chat --resume`.

**3. Can a hook still block a turn?** Bob treats exit code 2 as "reject this
turn" for `UserPromptSubmit` and `PreToolUse`. `bin/bob-hook` must exit 0 on
every path; confirm nothing has made that stricter:

```console
$ grep -o 'exitCode===2[^;]*' "$bundle" | head -1
```

**4. Is the settings schema unchanged?** Re-run `install-hook` and confirm it
writes five events, then that Bob still honours them:

```console
$ herdr plugin action invoke mloeper.herdr-bob.install-hook
$ jq '.hooks | keys' ~/.bob/settings/settings.json
```

**5. Live test.** Start a pane, send a prompt, watch the state move:

```console
$ herdr plugin action invoke mloeper.herdr-bob.start
$ herdr agent get bob          # working while it runs, done when it stops
$ tail -f <state>/herdr-bob.log
```

If the log shows no `hook …` lines, the bridge is not being called — go back to
step 4. If it shows them but the sidebar disagrees, the problem is the reporting
side, not Bob.

**6. Re-check `blocked`.** This is the one most likely to rot, because it matches
on rendered text. Trigger a real approval prompt (a non-allowlisted command with
`approval.autoApprovalEnabled` off), then:

```console
$ herdr pane read <pane> --source recent-unwrapped --lines 25
$ herdr agent get <pane> | jq -r '.result.agent.agent_status'   # want: blocked
```

If it no longer matches, update `rules.json` against what the pane actually
shows. Keep the rules strict — an unmatched screen falls back to the hook's
state, which is safe; a false `blocked` stops waits and lights the sidebar
wrongly.

**7. Update the version table** in `README.md` once it passes.

### After upgrading Herdr

**1. Does Herdr still accept a non-native agent label?** This is the assumption
the whole plugin rests on. If it ever stops holding, nothing else matters:

```console
$ herdr pane split --current --direction down --ratio 0.2 --no-focus     # note the pane id
$ herdr pane report-agent <pane> --source plugin:mloeper.herdr-bob --agent bob --state working
$ herdr agent list | jq -r '.result.agents[] | "\(.pane_id) \(.agent) \(.agent_status)"'
$ herdr pane release-agent <pane> --source plugin:mloeper.herdr-bob --agent bob
$ herdr pane close <pane>
```

**2. Did the manifest pick up warnings?** Herdr validates event names at link
time and warns rather than failing, so this is easy to miss:

```console
$ herdr plugin list --json | jq '.result.plugins[] | select(.plugin_id=="mloeper.herdr-bob") | {warnings}'
```

**3. Does `herdr pane read` still emit plain text?** `bin/bob-watch` consumes it
directly. It has never been JSON, and an earlier version of the watcher piped it
through `jq` and silently saw an empty screen — detection simply never fired.

```console
$ herdr pane read <pane> --source recent-unwrapped --lines 5
```

**4. Has `bob` become a native Herdr kind?**

```console
$ herdr agent 2>&1 | grep '^  kinds:'
```

If `bob` appears there, most of this plugin is obsolete: Herdr would own process
detection, screen manifests and session restore, and the right move is to retire
the plugin rather than keep two authorities fighting.

**5. Does `rows_by_agent` still reject `bob`?** It is keyed by strict canonical
agent id, which is why the plugin sets a `display_agent` instead. If a Herdr
release relaxes that, a proper coloured sidebar row becomes possible:

```console
$ herdr server reload-config   # after adding a bob key; expect "unknown canonical agent id"
```

**6. Update the version table** in `README.md`.

## Repo specifics

- `lib/common.sh` carries two build-time placeholders, `@runtimePath@` and
  `@bash@`. `package.nix` substitutes them; a plain `herdr plugin link` checkout
  leaves them alone and falls back to the ambient `PATH`. Keep both paths working.
- Bob's settings point at a **stable launcher** in the state directory, never at
  the plugin root, because a Nix store path changes on every rebuild and would
  rot into a dangling command. `bin/bob-watchctl start` rewrites that launcher on
  every startup, so an upgrade self-heals.
- The hook ownership test in the install/uninstall scripts matches `bob-hook`
  rather than an exact path, so an upgrade also cleans up entries written by
  older versions. Changing it to an exact match will strand them.
- `rules.json` in the repo is a seed. The live copy is in the plugin config
  directory; edit that when tuning, and fold anything durable back into the repo.
