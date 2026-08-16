# Firewall — Phase 1

Two layers, both set to the same tiny allow-list:

1. **xneelo security group** (in the cloud dashboard) — allow inbound
   `22`, `80`, `443` only. Scope `22` to your own IP if xneelo lets you.
2. **ufw on the host** — configured by cloud-init: default deny inbound,
   allow `22/80/443`.

## The Docker + ufw caveat (important)

Docker writes iptables rules **directly** and can bypass ufw for any container
port that is *published* to the host (`ports:` in compose). ufw will look like
it's blocking a port that is in fact wide open.

Phase 1 avoids this entirely: **only Caddy publishes ports (80/443)** — and
those are allowed anyway. Keycloak and Postgres use `expose`, so they're only
reachable on the internal Docker network, never on the host interface.

Rule of thumb going forward: **do not add `ports:` to a service unless the whole
internet is meant to reach it.** Anything internal stays on `expose`. If you ever
must publish a port to localhost only, bind it explicitly: `127.0.0.1:PORT:PORT`.
