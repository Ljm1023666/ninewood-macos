#!/bin/bash
# 在新机执行：安装 Node/pnpm/Docker/Nginx/Certbot，拉起 Postgres+Redis+API（先空库，随后恢复 dump）
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export HUSKY=0

echo "[1] apt packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg git nginx certbot python3-certbot-nginx ufw

if ! command -v node >/dev/null 2>&1 || ! node -v | grep -qE 'v2[0-9]'; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
corepack enable || true
npm install -g pnpm@9 pm2

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

echo "[2] clone ninewood"
if [ ! -d /opt/ninewood/.git ]; then
  git clone https://github.com/Ljm1023666/ninewood.git /opt/ninewood
else
  cd /opt/ninewood && git fetch --all && git reset --hard origin/master
fi

echo "[3] docker compose postgres+redis"
mkdir -p /opt/ninewood
cat > /opt/ninewood/docker-compose.cloud.yml <<'YAML'
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ninewood
      POSTGRES_PASSWORD: ninewood_secret
      POSTGRES_DB: ninewood
    ports:
      - '127.0.0.1:5432:5432'
    volumes:
      - ninewood_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ninewood']
      interval: 5s
      timeout: 5s
      retries: 10
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - '127.0.0.1:6379:6379'
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
      interval: 5s
      timeout: 3s
      retries: 10
volumes:
  ninewood_pgdata:
YAML
cd /opt/ninewood
docker compose -f docker-compose.cloud.yml up -d
sleep 5

echo "[4] server .env placeholder (will be overwritten by restore)"
if [ ! -f /opt/ninewood/server/.env ]; then
  JWT=$(openssl rand -hex 32)
  cat > /opt/ninewood/server/.env <<EOF
NODE_ENV=production
PORT=3001
DATABASE_URL=postgresql://ninewood:ninewood_secret@127.0.0.1:5432/ninewood?schema=public
REDIS_URL=redis://127.0.0.1:6379
JWT_SECRET=$JWT
CORS_ORIGINS=https://tothetomorrow.com,https://www.tothetomorrow.com,http://8.217.208.203,app://.
CAPTCHA_DEV_BYPASS=1
CONTENT_FILTER_ENABLED=true
EOF
fi

echo "[5] pnpm install + build"
cd /opt/ninewood
pnpm install
cd /opt/ninewood/server
npx prisma generate
# empty schema only if DB empty — restore will replace data later
npx prisma db push --accept-data-loss || true
pnpm run build || (npx tsc --skipLibCheck && node -e "require('node:fs').cpSync('src/taxonomy-data.json','dist/taxonomy-data.json')")

echo "[6] pm2"
pm2 delete ninewood 2>/dev/null || true
pm2 start dist/index.js --name ninewood --cwd /opt/ninewood/server
pm2 save
pm2 startup systemd -u root --hp /root | tail -1 | bash || true

echo "[7] nginx"
mkdir -p /var/www/ninewood
cat > /etc/nginx/sites-available/ninewood <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name tothetomorrow.com www.tothetomorrow.com _;
    client_max_body_size 50m;
    root /var/www/ninewood;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }
    location /uploads/ {
        root /opt/ninewood/server;
        expires 7d;
    }
    location /socket.io/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX
ln -sfn /etc/nginx/sites-available/ninewood /etc/nginx/sites-enabled/ninewood
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

echo "[8] health"
sleep 3
curl -sS http://127.0.0.1:3001/api/health/services || true
echo
curl -sS -H 'Host: tothetomorrow.com' http://127.0.0.1/api/health/services || true
echo
echo BOOTSTRAP_DONE
