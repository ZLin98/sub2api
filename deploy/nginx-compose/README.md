# nginx-fronted Docker deployment

This bundle is for servers where:

- nginx already owns public `443`
- Docker services must not be exposed to the public network
- runtime data lives under `/home/lin/depoly/<app>`
- app logs live under `/home/log/<app>`

## First deployment

```bash
git clone <your-fork-or-repo> /some/path/sub2api
cd /some/path/sub2api

APP_NAME=sub2api \
APP_DOMAIN=example.com \
DEPLOY_DIR=/home/lin/depoly/sub2api \
LOG_DIR=/home/log/sub2api \
bash ./deploy/nginx-compose/redeploy.sh
```

On first run the script will:

- create `/home/lin/depoly/<app>/.env`
- generate admin, database, JWT, and TOTP secrets
- create the data and log directories
- build the image from the current repo checkout
- stop the old stack only after the new image build succeeds
- start the new stack and verify `http://127.0.0.1:<port>/health`

## Daily update flow

```bash
cd /some/path/sub2api
git pull
bash ./deploy/nginx-compose/redeploy.sh
```

If the executable bit is preserved in your Git checkout, you can also run
`./deploy/nginx-compose/redeploy.sh`.

## Notes

- The compose file only binds `127.0.0.1:${APP_HOST_PORT}` for the app.
- PostgreSQL and Redis do not publish host ports.
- The stack uses two Docker networks:
  - `internal`: app + postgres + redis
  - `egress`: app outbound access for upstream API calls
- nginx should proxy to `127.0.0.1:${APP_HOST_PORT}`.
- See `nginx.sub2api.conf.example` for the nginx server block.
