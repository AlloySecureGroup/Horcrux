# Storing, Retrieving, and Maintaining Files

All commands run on the client node while it is running.

## Aliases: human-friendly roots

Raw caps are unwieldy. Create a root directory once and alias it:

```bash
tahoe create-alias work
tahoe ls work:
```

Aliases live in `~/.tahoe/private/aliases`. That file holds the write caps
to every aliased directory, so:

- back it up somewhere offline and safe, and
- never commit it or paste it into chats/tickets.

## Upload and download

```bash
tahoe put localfile.pdf work:reports/localfile.pdf   # upload into a directory
tahoe put localfile.pdf                              # upload, prints a raw cap
tahoe get work:reports/localfile.pdf restored.pdf    # download
tahoe ls work:reports                                # list
tahoe rm work:reports/old.pdf                        # unlink (data may persist
                                                     # until garbage collected)
```

Immutable files get read caps; mutable files and directories get write caps.
When sharing with someone who should only read, derive and share the
read-only cap (visible in the web UI "More Info" page for the object, or via
`tahoe webopen work:`).

## Recurring backups

`tahoe backup` does incremental, deduplicated snapshots:

```bash
tahoe backup ~/documents work:backups/documents
```

Each run creates a new timestamped snapshot under `work:backups/documents/`
containing `Archives/` (all snapshots) and `Latest/` (a link to the newest).
Unchanged files are not re-uploaded. Schedule it with cron/systemd timers,
for example nightly:

```cron
15 2 * * * /usr/local/bin/tahoe backup /home/user/documents work:backups/documents
```

## Health checks and repair (the resilience loop)

Shares vanish over time as disks fail. Without checks, a file can quietly
drop below K shares and become unrecoverable. Recommend a schedule:

```bash
# check one file/directory
tahoe check work:reports/localfile.pdf

# recursively check everything under the alias and repair anything degraded
tahoe deep-check --repair --add-lease work:
```

- `--repair` regenerates and re-places missing shares while at least K
  shares still exist.
- `--add-lease` renews leases so servers running garbage collection do not
  expire the shares.
- Run deep-check-with-repair at least monthly; weekly for important data.

Interpreting results: "healthy" means all N shares present; "not healthy"
with recoverable=true means degraded but repairable now; unrecoverable means
fewer than K shares remain and the file is lost unless offline copies exist.

## Restoring after disaster

If the client machine is lost, data is safe as long as the caps survive.
Recovery = new client node joined to the same introducer + restore
`~/.tahoe/private/aliases` from the offline backup, then `tahoe get` /
`tahoe cp -r` files back out. This is why the aliases file backup is
non-negotiable.
