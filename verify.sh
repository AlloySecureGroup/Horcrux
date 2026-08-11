#!/usr/bin/env bash
# Horcux verification script.
#
# Modes:
#   ./verify.sh selftest
#       Builds a throwaway localhost grid (1 introducer, 3 storage nodes,
#       1 client at 2-of-3), then proves: store, retrieve, checkpoint,
#       restore, and survival of a single storage node failure.
#       Leaves nothing behind.
#
#   ./verify.sh live <state.json>
#       Checks an existing grid using a Horcux state file
#       (introducer_furl + rootcap). Proves the agent can store and
#       retrieve against the real grid. Requires a running client node
#       whose aliases include the rootcap, or it will add a temporary
#       alias "horcuxverify" pointing at the rootcap.
#
# Exit code 0 means every check passed. Any failure exits nonzero with
# a FAIL line naming the check.

set -u

PASS=0
FAIL=0

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
need() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL  missing dependency: $1"; exit 1; }; }

need tahoe
tahoe --version >/dev/null 2>&1 && ok "tahoe is installed ($(tahoe --version 2>/dev/null))" || { bad "tahoe --version"; exit 1; }

wait_for_servers() {
    # wait_for_servers <node.url file> <count> <timeout_s>
    local urlfile="$1" want="$2" timeout="$3" waited=0
    while [ ! -f "$urlfile" ] && [ "$waited" -lt "$timeout" ]; do
        sleep 2; waited=$((waited+2))
    done
    [ -f "$urlfile" ] || return 1
    local base
    base=$(cat "$urlfile")
    while [ "$waited" -lt "$timeout" ]; do
        local n
        n=$(curl -s "${base}?t=json" 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(sum(1 for s in d.get("servers", []) if s.get("connection_status","").lower().startswith("connected")))
except Exception:
    print(0)' 2>/dev/null)
        [ "${n:-0}" -ge "$want" ] && return 0
        sleep 2; waited=$((waited+2))
    done
    return 1
}

roundtrip() {
    # roundtrip <alias>  : put a probe file, get it back, compare
    local alias="$1" src dst
    src=$(mktemp); dst=$(mktemp)
    echo "horcux probe $(date +%s) $$" > "$src"
    if ! tahoe put "$src" "${alias}:verify/probe.txt" >/dev/null 2>&1; then
        rm -f "$src" "$dst"; return 1
    fi
    if ! tahoe get "${alias}:verify/probe.txt" "$dst" >/dev/null 2>&1; then
        rm -f "$src" "$dst"; return 1
    fi
    cmp -s "$src" "$dst"; local rc=$?
    rm -f "$src" "$dst"
    return $rc
}

selftest() {
    WORK=""
    WORK=$(mktemp -d /tmp/horcux-selftest.XXXXXX)
    local PIDS=()
    cleanup() {
        for p in "${PIDS[@]:-}"; do kill "$p" >/dev/null 2>&1; done
        sleep 1
        [ -n "${WORK:-}" ] && rm -rf "$WORK"
    }
    trap cleanup EXIT

    export HOME_BAK="$HOME"

    # 1. introducer
    tahoe create-introducer --hostname=127.0.0.1 "$WORK/introducer" >/dev/null 2>&1 \
        && ok "create introducer" || { bad "create introducer"; exit 1; }
    tahoe run --allow-stdin-close "$WORK/introducer" >"$WORK/introducer.log" 2>&1 &
    PIDS+=($!)
    local FURL="" t=0
    while [ -z "$FURL" ] && [ $t -lt 30 ]; do
        sleep 2; t=$((t+2))
        [ -f "$WORK/introducer/private/introducer.furl" ] && FURL=$(cat "$WORK/introducer/private/introducer.furl")
    done
    [ -n "$FURL" ] && ok "introducer running, FURL published" || { bad "introducer FURL"; exit 1; }

    # 2. three storage nodes
    local i
    for i in 1 2 3; do
        tahoe create-node --hostname=127.0.0.1 --introducer="$FURL" \
            --nickname="storage$i" --webport=none "$WORK/storage$i" >/dev/null 2>&1 \
            || { bad "create storage$i"; exit 1; }
        tahoe run --allow-stdin-close "$WORK/storage$i" >"$WORK/storage$i.log" 2>&1 &
        PIDS+=($!)
    done
    ok "3 storage nodes started"

    # 3. client at 2-of-3 (tolerates one dead node)
    tahoe create-client --introducer="$FURL" --nickname=horcuxclient \
        --shares-needed=2 --shares-happy=3 --shares-total=3 \
        --webport="tcp:3499:interface=127.0.0.1" "$WORK/client" >/dev/null 2>&1 \
        && ok "create client (2-of-3)" || { bad "create client"; exit 1; }
    tahoe run --allow-stdin-close "$WORK/client" >"$WORK/client.log" 2>&1 &
    local CLIENT_PID=$!
    PIDS+=($CLIENT_PID)

    wait_for_servers "$WORK/client/node.url" 3 60 \
        && ok "client connected to 3 storage servers" \
        || { bad "client never saw 3 servers"; exit 1; }

    # tahoe CLI finds the node via -d
    local T="tahoe -d $WORK/client"

    # 4. alias + state file (what an agent must preserve)
    $T create-alias agentstore >/dev/null 2>&1 && ok "create alias agentstore" || { bad "create alias"; exit 1; }
    local ROOTCAP
    ROOTCAP=$(grep '^agentstore:' "$WORK/client/private/aliases" | cut -d' ' -f2)
    [ -n "$ROOTCAP" ] && ok "rootcap extracted for state file" || { bad "rootcap missing"; exit 1; }

    # 5. store and retrieve
    local src dst
    src=$(mktemp); dst=$(mktemp)
    echo "agent output $(date +%s)" > "$src"
    $T put "$src" agentstore:state/probe.txt >/dev/null 2>&1 \
        && ok "store (tahoe put)" || { bad "store"; exit 1; }
    $T get agentstore:state/probe.txt "$dst" >/dev/null 2>&1 \
        && cmp -s "$src" "$dst" \
        && ok "retrieve matches original (tahoe get)" || { bad "retrieve"; exit 1; }

    # 6. checkpoint and restore
    local OUTDIR="$WORK/outputs" RESTORE="$WORK/restored"
    mkdir -p "$OUTDIR"; cp "$src" "$OUTDIR/artifact.txt"
    $T backup "$OUTDIR" agentstore:checkpoints/outputs >/dev/null 2>&1 \
        && ok "checkpoint (tahoe backup)" || { bad "backup"; exit 1; }
    mkdir -p "$RESTORE"
    $T cp -r agentstore:checkpoints/outputs/Latest/ "$RESTORE" >/dev/null 2>&1 \
        && cmp -s "$OUTDIR/artifact.txt" "$RESTORE/Latest/artifact.txt" \
        && ok "restore from Latest checkpoint" || { bad "restore"; exit 1; }

    # 7. resilience: kill one storage node, data must still be readable
    kill "${PIDS[1]}" >/dev/null 2>&1   # first storage node
    sleep 3
    local dst2
    dst2=$(mktemp)
    $T get agentstore:state/probe.txt "$dst2" >/dev/null 2>&1 \
        && cmp -s "$src" "$dst2" \
        && ok "retrieve still works with one storage node down" \
        || bad "retrieval after node failure"
    rm -f "$src" "$dst" "$dst2"
}

live() {
    local STATE="$1"
    [ -f "$STATE" ] || { bad "state file not found: $STATE"; exit 1; }
    local FURL ROOTCAP
    FURL=$(python3 -c "import json;print(json.load(open('$STATE'))['introducer_furl'])" 2>/dev/null)
    ROOTCAP=$(python3 -c "import json;print(json.load(open('$STATE'))['rootcap'])" 2>/dev/null)
    [ -n "$FURL" ] && [ -n "$ROOTCAP" ] && ok "state file parsed" || { bad "state file fields"; exit 1; }

    grep -q '^horcuxverify:' "$HOME/.tahoe/private/aliases" 2>/dev/null \
        || tahoe add-alias horcuxverify "$ROOTCAP" >/dev/null 2>&1
    roundtrip horcuxverify \
        && ok "live grid store and retrieve" \
        || bad "live grid store and retrieve (is the client node running?)"
}

case "${1:-selftest}" in
    selftest) selftest ;;
    live)     live "${2:?usage: verify.sh live <state.json>}" ;;
    *) echo "usage: verify.sh [selftest | live <state.json>]"; exit 2 ;;
esac

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
