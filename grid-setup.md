# Building a Tahoe-LAFS Grid from Scratch

Order of operations: introducer first, then storage nodes, then the client.
Each node lives in its own base directory and is managed with
`tahoe run <basedir>` (foreground) or a service manager for production.

## 1. Introducer (one machine)

```bash
tahoe create-introducer --hostname=INTRODUCER_HOST ~/introducer
tahoe run --allow-stdin-close ~/introducer
```

After first start, read the introducer FURL:

```bash
cat ~/introducer/private/introducer.furl
```

The FURL (`pb://...`) is what every other node uses to join the grid. It is
sensitive: anyone with the FURL can join, so share it only with intended
participants.

## 2. Storage nodes (each storage machine)

```bash
tahoe create-node --hostname=THIS_NODES_HOSTNAME \
  --introducer=pb://THE_INTRODUCER_FURL \
  --nickname=storage1 ~/storage
tahoe run --allow-stdin-close ~/storage
```

Key `tahoe.cfg` settings for a storage node:

```ini
[storage]
enabled = true
reserved_space = 10G   ; leave headroom so the node never fills the disk
```

Repeat on every storage machine with a unique nickname. Nodes must be able
to reach each other on their advertised ports (default is a random port;
pin one with `tub.port` and `tub.location` in `tahoe.cfg` if firewalls are
involved).

## 3. Client node (the machine that stores/retrieves files)

```bash
tahoe create-client --introducer=pb://THE_INTRODUCER_FURL \
  --nickname=myclient ~/.tahoe
```

Edit `~/.tahoe/tahoe.cfg` and set erasure coding to match the grid size
(see the parameter guidance in SKILL.md):

```ini
[client]
shares.needed = 3
shares.happy = 5
shares.total = 5
```

Then start it:

```bash
tahoe run --allow-stdin-close ~/.tahoe
```

## 4. Verify the grid

- Open the client web UI at `http://127.0.0.1:3456`. The welcome page lists
  connected storage servers; confirm the count matches expectations.
- Do a round trip:

```bash
echo "grid test" > /tmp/t.txt
tahoe put /tmp/t.txt          # prints a cap
tahoe get URI:...:printed-cap /tmp/t2.txt
diff /tmp/t.txt /tmp/t2.txt
```

If `tahoe put` reports it could not achieve "happiness", the H value exceeds
the number of reachable servers: either bring more servers online or lower
`shares.happy`.

## Single-machine test grid

For learning or CI, everything can run on localhost: one introducer, several
storage nodes in separate base directories (`~/storage1`, `~/storage2`, ...),
and one client. Say explicitly to the user that this setup gives zero real
resilience and is for practice only.

## Running nodes as services

For anything long-lived, wrap `tahoe run <basedir>` in a systemd unit per
node so nodes restart after reboots. A minimal unit:

```ini
[Unit]
Description=Tahoe-LAFS storage node
After=network.target

[Service]
ExecStart=/usr/local/bin/tahoe run --allow-stdin-close /home/tahoe/storage
Restart=on-failure
User=tahoe

[Install]
WantedBy=multi-user.target
```

## Targeting a specific node directory

`tahoe` CLI commands default to `~/.tahoe`. To operate a client in another
base directory, pass `-d`:

```bash
tahoe -d /path/to/client put file.txt agentstore:file.txt
```

## Programmatic verification

The client web API reports connection state as JSON. Poll it to confirm the
grid is ready before uploading (values are lowercase, e.g. "connected"):

```bash
curl -s "$(cat CLIENT_DIR/node.url)?t=json"
```
