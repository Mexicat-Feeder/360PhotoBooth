# Configuration

Use `booth.env` as the local master config file.

`booth.env` is intentionally gitignored because it may contain SMTP credentials.
`booth.env.example` is the committed template.

## Common Values

- `BOOTH_BACKEND`: URL the phone app uses to reach the FastAPI backend.
- `PUBLIC_BASE_URL`: URL included in result emails.
- `BOOTH_HOST` / `BOOTH_PORT`: backend bind address and port.
- `COMFY_URL`: ComfyUI API URL used by the backend.
- `WORKFLOW_DIR` / `WORKFLOW`: ComfyUI workflow JSON selection.
- `FORCE_WORKFLOW`: optional backend-side workflow override. This is useful
  when an installed phone build still submits an older workflow name.
- `SMTP_*`: email delivery settings.

When changing Wi-Fi networks, update both:

```text
BOOTH_BACKEND=http://<backend-lan-ip>:8000
PUBLIC_BASE_URL=http://<backend-lan-ip>:8000
```

## Run Backend

```powershell
.\scripts\run_backend.ps1
```

## Run Flutter App

```powershell
.\scripts\run_flutter.ps1
```

With a specific device:

```powershell
.\scripts\run_flutter.ps1 -Device 10.6.14.123:45678
```

## Build APK

```powershell
.\scripts\build_apk.ps1 -Mode debug
```

## Gmail

For Gmail SMTP, use an app password:

```text
SMTP_USER=amdrad.team.2@gmail.com
SMTP_PASSWORD=<gmail-app-password>
SMTP_FROM=amdrad.team.2@gmail.com
```

Do not use the normal Google account password.
