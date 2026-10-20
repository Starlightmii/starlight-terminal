# Real pi integration

The app talks to the genuine `@earendil-works/pi-coding-agent` binary through a
local bridge (`/home/user/pi-bridge/server.mjs`), because Flutter web cannot
spawn subprocesses.

    node /home/user/pi-bridge/server.mjs      # port 5077
    python3 serve.py 5060                     # static app + /pi/* proxy

The proxy keeps the app same-origin, so no CORS and no hardcoded host.
