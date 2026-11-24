#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
exec 9>logs/cloud-start.lock
flock 9

ready() {
  curl -fsS --max-time 3 http://127.0.0.1:3000/healthz | grep -q '"ready":true'
}

if ready; then
  echo 'Web-Check is ready.'
  exit 0
fi

if [ ! -d node_modules ] || [ ! -f dist/server/entry.mjs ] || [ "$(git rev-parse HEAD)" != "$(cat logs/cloud-build-revision 2>/dev/null || true)" ]; then
  corepack yarn install --frozen-lockfile --non-interactive --network-timeout 100000
  corepack yarn build
  git rev-parse HEAD > logs/cloud-build-revision
  corepack yarn cache clean
fi

if ! [ -f dist/server/entry.mjs ]; then
  echo 'Web-Check build is missing its server entry.' >&2
  exit 1
fi

export API_CORS_ORIGIN="https://${CODESPACE_NAME}-3000.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
# Do not give the website analysis server the Codespaces GitHub credential.
nohup env -u GITHUB_TOKEN -u GH_TOKEN node server.js >logs/cloud-server.log 2>&1 </dev/null 9>&- &
pid=$!
for ((i=0; i<90; i++)); do
  if ready; then
    echo 'Web-Check is ready.'
    exit 0
  fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
tail -n 30 logs/cloud-server.log >&2
exit 1
