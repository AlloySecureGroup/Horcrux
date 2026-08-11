#!/bin/bash
# Horcrux node entrypoint. ROLE selects introducer, storage, or client.
# The introducer publishes its FURL to the shared /grid volume; every other
# node waits for it. All node output goes to stdout so Docker captures it.
set -e

ROLE="${ROLE:?set ROLE to introducer, storage, or client}"
NAME="${NODE_NAME:-$ROLE}"
BASE=/var/tahoe/node
GRID=/grid
mkdir -p "$GRID"

log() { echo "[horcrux:$NAME] $*"; }

wait_for_furl() {
    while [ ! -s "$GRID/introducer.furl" ]; do
        log "waiting for introducer FURL"
        sleep 2
    done
    cat "$GRID/introducer.furl"
}

case "$ROLE" in
    introducer)
        if [ ! -f "$BASE/tahoe.cfg" ]; then
            log "creating introducer"
            tahoe create-introducer --hostname="$NAME" "$BASE"
        fi
        (
            while [ ! -s "$BASE/private/introducer.furl" ]; do sleep 1; done
            cp "$BASE/private/introducer.furl" "$GRID/introducer.furl"
            log "FURL published to /grid"
        ) &
        log "starting introducer"
        exec tahoe run --allow-stdin-close "$BASE"
        ;;

    storage)
        FURL=$(wait_for_furl)
        if [ ! -f "$BASE/tahoe.cfg" ]; then
            log "creating storage node"
            tahoe create-node --hostname="$NAME" --introducer="$FURL" \
                --nickname="$NAME" --webport=none "$BASE"
        fi
        log "starting storage node"
        exec tahoe run --allow-stdin-close "$BASE"
        ;;

    client)
        FURL=$(wait_for_furl)
        if [ ! -f "$BASE/tahoe.cfg" ]; then
            log "creating client (2-of-3, tolerates one storage node loss)"
            tahoe create-client --introducer="$FURL" --nickname="$NAME" \
                --shares-needed=2 --shares-happy=3 --shares-total=3 \
                --webport="tcp:3456:interface=0.0.0.0" "$BASE"
        fi
        log "starting client, web UI on port 3456"
        exec tahoe run --allow-stdin-close "$BASE"
        ;;

    *)
        log "unknown ROLE: $ROLE"
        exit 1
        ;;
esac
