# Agent Workflow: Persist and Restore via Tahoe-LAFS

This is the procedure for an agent that must save its own working data to
the grid so a workflow survives session, container, or machine loss.

## The state file: the one thing that must survive

Everything on the grid is reachable from two secrets: the introducer FURL
and the rootcap (or the aliases file). Keep them in a single small state
file, and treat getting that file somewhere durable as step zero of
persistence, because the grid is useless without it.

Recommended layout, stored at a path the agent can rely on across runs
(project directory, mounted volume, or a secret store if one is available):

```json
{
  "introducer_furl": "pb://...",
  "rootcap": "URI:DIR2:...",
  "alias": "agentstore",
  "created": "2026-08-11T00:00:00Z"
}
```

Rules:
- File permissions 600. Never echo the rootcap into logs or command lines
  that end up in shell history when avoidable (prefer reading from the file).
- If no durable local path exists (ephemeral sandbox), the state file must
  be handed to the user explicitly at the end of setup with a clear message:
  "store this safely; it is the only key to the stored data."
- Losing the rootcap loses the data. There is no recovery.

## First run: set up, then claim a root

1. Follow `references/grid-setup.md` to get a client connected (building the
   grid first if none exists).
2. Create the agent's root directory and alias:

```bash
tahoe create-alias agentstore
```

3. Extract the rootcap from `~/.tahoe/private/aliases` into the state file.
4. Verify with a round trip (put a small file, get it back, compare).
5. Report to the user: grid shape, chosen K/H/N, where the state file lives,
   and what fault tolerance the setup actually provides.

## During a workflow: checkpoint pattern

Persist at natural boundaries (end of a stage, after producing an output,
before a risky operation):

```bash
# outputs and artifacts
tahoe backup ./outputs agentstore:checkpoints/outputs

# small state blobs (queues, progress markers)
tahoe put progress.json agentstore:state/progress.json
```

`tahoe backup` is incremental and deduplicated, so checkpointing often is
cheap. Keep a plain-text manifest of what was stored and when at
`agentstore:state/manifest.txt` and update it on every checkpoint, so a
future session can discover what exists with a single `tahoe get`.

## Later run: restore

1. Read the state file; recreate the client if needed:

```bash
tahoe create-client --introducer=pb://FURL ~/.tahoe
# add the alias back
echo "agentstore: URI:DIR2:..." >> ~/.tahoe/private/aliases
tahoe run ~/.tahoe &
```

2. Read the manifest, then pull what the task needs:

```bash
tahoe get agentstore:state/progress.json progress.json
tahoe cp -r agentstore:checkpoints/outputs/Latest ./outputs
```

3. Continue the workflow from the restored state.

## Hygiene on every session that touches the grid

- Run `tahoe deep-check --repair --add-lease agentstore:` if it has not run
  in the last week (record the last run time in the manifest).
- After any store, confirm success by checking the command exit code and,
  for critical artifacts, reading the file back.
- If uploads fail on "happiness", diagnose per SKILL.md parameter rules
  before retrying; do not silently lower shares.happy without noting the
  reduced resilience in the report to the user.
