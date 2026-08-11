# Horcrux on Docker Desktop (local)

Runs the whole grid on one PC in 5 containers: 1 introducer, 3 storage
nodes, 1 client at 2-of-3 encoding. Losing any single storage node does not
lose data. This is a practice and development setup: all containers share
one disk, so it does not protect against that disk dying.

## Layout

Copy these into the repo so it looks like:

```
C:\Users\Tester\Documents\GitHub\Horcrux\
├── docker-compose.yml
├── run-workflow.ps1
└── docker\
    ├── Dockerfile
    └── entrypoint.sh
```

## Run the workflow

```powershell
cd C:\Users\Tester\Documents\GitHub\Horcrux
.\run-workflow.ps1
```

The script starts the grid, saves a file, stops a storage node, recovers
the file while the node is down, then restarts the node and repairs shares.
Every step is written to workflow.log. Node output is kept by Docker; view
it any time with:

```powershell
docker compose logs -f
```

## What it leaves behind

- horcrux-state.json: introducer address and rootcap. The only key to the
  data. Back it up somewhere safe and never commit it.
- recovered.txt: the file pulled back out of the degraded grid.
- workflow.log: full transcript of the run.
- Named Docker volumes holding all grid data, which survive restarts.

## Everyday commands

```powershell
docker compose up -d          # start the grid
docker compose down           # stop it (data kept)
docker compose down -v        # destroy the grid and all stored data
docker exec horcrux-client tahoe -d /var/tahoe/node ls agentstore:
```

Web UI while running: http://localhost:3456
