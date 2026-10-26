# Reworkio tools

Nine small, dependency-free command-line tools (Python 3.8+ standard library only) that each produce
verifiable proof of work, and that plug into the `rw` zsh hub so they can be switched between and chained.

| Tool | What it does | Hub capability |
| --- | --- | --- |
| `proofpack` | Repo to case study: history, stack, test run, checksum, badge | `proof.pack` |
| `scopesmith` | Client brief to scope, estimate, milestones and SOW draft | `scope.plan` |
| `handoff` | Readiness check, `.env.example`, HANDOFF.md runbook, safe sync, delivery package | `deliver.package` |
| `envguard` | Secret scan, `.env` schema validation, dependency audit, pre-commit hook | `audit.security` |
| `logbook` | Time tracking from zsh activity and git commits, invoice CSV | `time.report` |
| `clientcast` | Weekly client update from commits, GitHub issues/PRs and hours; Slack or email | `client.update` |
| `pulse` | HTTP/TCP/disk/TLS/command checks, Slack alerts, static status page, systemd timer | `ops.status` |
| `histbook` | Records shell work and renders a clean runbook plus a re-runnable script | `docs.runbook` |
| `datamorph` | Clean, validate and reshape CSV/JSON with saved, replayable recipes | `data.transform` |

## Install

```sh
./install.sh --link      # register with ~/.rw and symlink into ~/.local/bin
bash tests/smoke.sh      # 61 end-to-end checks in a throwaway sandbox
```

Every tool has `--help`. Output is human-readable in a terminal and JSON when piped (or with `--json`),
so any tool's output can feed another tool or `rw ctx set`.

## Hub contract

Called as `rw do <capability>`, each tool receives the capability name as its first argument,
reads JSON (or raw text/data) on stdin, writes JSON on stdout and logs to stderr.

Example combos live in `examples/combos/` and are copied to `~/.rw/combos/` by the installer.
