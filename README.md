# Horcux

A tool to build and preserve agentic work.

Agents lose everything when a sandbox is wiped, a container restarts, or a
machine dies. Horcux fixes that by giving an agent a place to keep its work
that no single failure can destroy. It is built on Tahoe-LAFS, a storage
system that encrypts files on the client and splits them into shares spread
across independent servers. Any K of N shares rebuild the file. The servers
never see the plaintext.

The result: an agent can set up its own storage grid, checkpoint outputs and
state as it works, and a later session can restore all of it from one small
state file.

## What's in this repository

```
horcux/
├── skill/                 The tahoe-lafs-resilience skill
│   ├── SKILL.md           Core concepts, parameter selection, security rules
│   └── references/
│       ├── grid-setup.md      Build a grid: introducer, storage nodes, client
│       ├── operations.md      Store, retrieve, backup, check, repair
│       └── agent-workflow.md  Checkpoint and restore pattern for agents
└── tests/
    └── verify.sh          Verification script (self-test and live modes)
```

## Requirements

- Python 3 and pip
- Tahoe-LAFS 1.20.0:

```bash
pip install tahoe-lafs "pyopenssl==24.2.1" "cryptography<44" "service-identity==24.2.0"
```

The version pins matter. Newer pyOpenSSL removed an API that Tahoe's
networking layer still uses, and nodes crash on startup without them.

## Verify your setup

Self-test. Builds a throwaway grid on localhost (one introducer, three
storage nodes, a client at 2-of-3), stores a file, retrieves it, makes a
checkpoint, restores it, then kills a storage node and proves the data is
still readable:

```bash
bash tests/verify.sh selftest
```

Expected output ends with:

```
Results: 13 passed, 0 failed
```

Live check. Points at a real grid using the state file the agent produced
during setup and proves store and retrieve work against it:

```bash
bash tests/verify.sh live path/to/state.json
```

Exit code 0 means everything passed.

## How an agent uses it

1. Install the skill (see below). When a task calls for durable storage, the
   agent reads `skill/SKILL.md` and follows the references.
2. First run: the agent builds or joins a grid, creates a root directory,
   and writes a state file containing the introducer address and the root
   capability. That file is the only key to the data. Keep it safe. There
   is no recovery if it is lost.
3. During work: the agent checkpoints outputs with `tahoe backup` and small
   state blobs with `tahoe put`, keeping a manifest of what was stored.
4. Later run: the agent reads the state file, rejoins the grid, pulls the
   latest checkpoint, and continues where it left off.

## Installing the skill

Copy the `skill/` folder into your agent's skills directory, or install the
packaged `.skill` file from the release assets. In Claude, the skill can be
saved from the `.skill` file card.

## Honest limits

- A single-machine grid protects against process failures and lets you
  practice, but it does not survive disk loss. Real resilience needs
  storage nodes on separate machines, ideally in separate places.
- Capabilities are bearer secrets. Anyone holding the root capability can
  read and change everything under it. Guard the state file like a private
  key.
- Shares decay as disks fail. Schedule
  `tahoe deep-check --repair --add-lease` regularly, or files can quietly
  drop below the recovery threshold.

## Name

A horcrux preserves a part of its maker against destruction, split across
hidden places. Horcux does that for an agent's work, minus the dark magic:
shares instead of soul fragments, and losing one does not hurt a bit.
