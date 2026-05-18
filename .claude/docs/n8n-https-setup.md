# n8n HTTPS / Secure Cookie Fix

## Current workaround

The secure cookie error is bypassed by setting this environment variable in the n8n stack:

```
N8N_SECURE_COOKIE=false
```

This is acceptable for **local network access only**. n8n is not exposed to the internet in Phase 1, so there is no security risk in the current setup.

---

## Proper fix (for future implementation)

Replace the workaround with a TLS certificate mounted directly into the n8n container — no extra reverse proxy container required.

### Step 1 — Generate a self-signed certificate on the Pi

```bash
sudo mkdir -p /etc/n8n/certs

sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/n8n/certs/n8n.key \
  -out /etc/n8n/certs/n8n.crt \
  -subj "/CN=n8n-local" \
  -addext "subjectAltName=IP:192.168.x.x"
  #                              ↑ replace with Pi's local IP

sudo chmod 600 /etc/n8n/certs/n8n.key
sudo chmod 644 /etc/n8n/certs/n8n.crt
```

### Step 2 — Update docker-compose.yml

Remove `N8N_SECURE_COOKIE=false` and add the following:

```yaml
n8n:
  volumes:
    - /etc/n8n/certs:/certs:ro   # certs live on Pi, not in Git
  environment:
    - N8N_PROTOCOL=https
    - N8N_SSL_CERT=/certs/n8n.crt
    - N8N_SSL_KEY=/certs/n8n.key
    - WEBHOOK_URL=https://192.168.x.x:5678/   # update if webhooks are used
  secrets:
    - n8n_cert
    - n8n_key

secrets:
  n8n_cert:
    file: /etc/n8n/certs/n8n.crt
  n8n_key:
    file: /etc/n8n/certs/n8n.key
```

### Step 3 — Accept the certificate in your browser (once)

On first visit to `https://192.168.x.x:5678`, the browser will warn about a self-signed certificate:

- **Chrome / Edge:** Advanced → Proceed to site
- **Firefox:** Advanced → Accept the Risk and Continue

To silence the warning permanently, import `n8n.crt` into your OS or browser trust store.

---

## What not to do

- **Never commit certificate files to Git.** Only the paths are in the compose file.
- **Never expose n8n on a public IP without valid TLS.** Use Cloudflare Tunnel or a proper CA-signed cert if remote access is ever needed.
