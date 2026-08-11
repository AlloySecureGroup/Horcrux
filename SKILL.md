---
name: tahoe-lafs-resilience
description: >
  Set up and operate Tahoe-LAFS (the Least-Authority File Store) for
  distributed, encrypted, fault-tolerant file storage. Use this skill whenever
  the user mentions Tahoe-LAFS, TahoeLFS, LAFS, storage grids, introducers,
  storage nodes, capability strings (URI:...), erasure coding of files, or
  wants files to be "distributed and secure", resilient to server failure,
  encrypted backups across multiple machines, or provider-independent
  security. Also use it for maintaining an existing grid: checking file
  health, repairing shares, and running recurring `tahoe backup` jobs. If the
  user is deciding how many storage nodes they need or what shares.needed /
  shares.happy / shares.total should be, use this skill. Also use it when an
  agent should persist its own working data, outputs, checkpoints, or state
  to distributed storage for workflow resilience, so work survives machine
  or session loss and can be restored on a later run.
---

# Tahoe-LAFS Resilience

Tahoe-LAFS encrypts files on the client, erasure-codes them into N shares,
and spreads those shares across independent storage servers. Any K of the N
shares can reconstruct the file, so the grid survives server loss, and the
servers themselves can never read the data. This skill covers building a grid
from nothing, storing and retrieving files, and keeping stored data healthy.

## Before anything else

1. Determine what exists already, without asking if it can be detected:
   an introducer FURL or rootcap provided in the task/environment means a
   grid exists, so connect to it instead of building one.
2. If nothing exists, decide the grid shape from what is reachable: separate
   machines/VMs if credentials or hosts are given, otherwise a localhost
   grid on the current machine (state clearly that a single-machine grid
   protects against process/data-corruption issues only, not disk loss).
3. Check the install: run `tahoe --version`. If missing, install with
   `pip install tahoe-lafs` (use a virtualenv; on Debian/Ubuntu
   `apt-get install tahoe-lafs` also works). Known issue with 1.20.0 on
   recent Python: newer pyOpenSSL removed `X509Req`, which crashes node
   startup with `AttributeError: module 'OpenSSL.crypto' has no attribute
   'X509Req'`. Fix by pinning:
   `pip install "pyopenssl==24.2.1" "cryptography<44" "service-identity==24.2.0"`.
4. When starting nodes non-interactively (scripts, services, agents), always
   use `tahoe run --allow-stdin-close <basedir>`; without the flag, the node
   exits the moment stdin closes, which under nohup or a service manager is
   immediately and silently.
5. Prefer sensible defaults over questions when operating autonomously; ask
   only when a choice is irreversible or touches machines not clearly in
   scope.

## Core concepts (use these when explaining or deciding)

- **Capability strings (caps)**: A cap (`URI:...`) is both the location of a
  file and the key to it. Whoever holds a cap can access the file; nobody
  else can, including the server operators. Read caps grant read only;
  write caps grant modification. Treat caps like passwords.
- **Erasure coding parameters**:
  - `shares.total` (N): shares created per file.
  - `shares.needed` (K): shares required to reconstruct.
  - `shares.happy` (H): minimum distinct servers that must hold shares for an
    upload to succeed.
  - The grid tolerates the loss of N minus K shares. Defaults are 3-of-10.
- **Node roles**: an *introducer* helps nodes find each other, *storage
  nodes* hold shares, and a *client* uploads/downloads. One machine can run
  more than one role.

## Choosing parameters for resilience

Ask how many storage servers exist and how many failures the user wants to
survive. Then set K, H, N so that:

- N is at most the number of servers times a small factor (ideally N equals
  the server count so each server gets one share).
- H is at least K + number of tolerated failures, and H is not larger than
  the server count (otherwise uploads fail).
- Example for 5 servers, tolerate 2 failures: K=3, H=5, N=5.
- Never leave the 3-of-10 default on a grid with fewer than 10 servers
  without checking H; if H exceeds the server count, uploads will error.

Set these in the client's `tahoe.cfg` under `[client]`.

## Workflow routing

- Building a grid (introducer, storage nodes, client, config):
  read `references/grid-setup.md`.
- Storing, retrieving, backing up, checking, and repairing files:
  read `references/operations.md`.
- Persisting agent workflow state/outputs and restoring them in a later
  session: read `references/agent-workflow.md`.

Follow the reference file step by step rather than working from memory;
node configuration details are easy to get subtly wrong.

## Security rules to always apply

1. Never print, log, or store capability strings in world-readable places.
   The root cap of a user's directory is the master secret; recommend
   keeping an offline copy (the aliases file at `~/.tahoe/private/aliases`).
2. Warn that losing all caps means losing the data permanently; there is no
   password reset.
3. Remind the user that resilience requires *independent* servers: five
   storage nodes on one physical disk protect against nothing. Prefer
   separate machines, locations, or providers.
4. Encourage a periodic deep-check-and-repair schedule (see operations
   reference), because shares silently disappear when disks die.

## Output expectations

When helping a user through setup, produce concrete, copy-pasteable shell
commands and exact `tahoe.cfg` snippets, state which machine each command
runs on, and finish with a verification step (`tahoe --version`, the node's
web UI URL, or a test upload/download round trip).
