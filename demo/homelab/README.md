# homelab

Three services on the NAS box, behind Caddy. Nightly restic backup to the NAS share.

- `docker-compose.yml` - the stack
- `scripts/restic-nightly.sh` - the 23:40 backup job
- `logs/restic-nightly.log` - what it wrote
