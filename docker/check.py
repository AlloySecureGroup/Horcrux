# Prints the number of storage servers the client is connected to. Never errors.
import json, urllib.request
try:
    d = json.load(urllib.request.urlopen("http://127.0.0.1:3456/?t=json", timeout=3))
    n = sum(1 for s in d.get("servers", [])
            if s.get("connection_status", "").lower().startswith("connected"))
    print(n)
except Exception:
    print(0)
