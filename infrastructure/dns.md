# DNS — Phase 1

One record is all Phase 1 needs:

    auth.example.co.za.   A   <FLOATING_IP>

Point it at the **xneelo floating IP**, not the instance's ephemeral IP. The
floating IP is the whole reason the rebuild test works without waiting on DNS:
when you destroy the VM and build a new one, you re-associate the same floating
IP to the new instance and this record never changes.

Notes:
- Set a **low TTL** (e.g. 300s) while testing, so the rare occasion you *do*
  change the IP propagates quickly. Raise it later.
- The A record must resolve and port 80 must be reachable **before** first boot
  of Caddy — Let's Encrypt validates over HTTP-01. If the cert never issues,
  check DNS and that ufw allows 80/443.
- IPv6: add a matching `AAAA` record if the instance has a public v6 address.
