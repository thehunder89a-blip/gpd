# Railway deployment notes for TVM Panel

- Railway starts the app with `start.sh`; `install.sh` is the Ubuntu/Debian systemd installer and should not be used as a manual install flow on Railway. If it is run in Railway, it now detects Railway and delegates to `start.sh`.
- Set Railway build command to `pip install -r requirements.txt` if the builder does not install Python dependencies automatically.
- Set a persistent Volume mount path to `/data` to preserve the SQLite database. Without a volume, local database state may be lost on redeploy.
- Railway provides the `PORT` environment variable. The launcher binds to `0.0.0.0` and uses that value.
- `/health` returns HTTP 200 when the panel database can be queried and 503 when it cannot. LXC availability is informational because Railway is not a virtualization host.
- This fixes Railway startup/health handling. It does **not** convert the existing LXC VPS backend into a Docker VPS backend. VPS provisioning still requires an appropriately configured external node.
