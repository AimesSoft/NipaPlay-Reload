# Shared settings of the deployment scripts. Sourced, never run. Every value
# can be overridden from the environment (the rehearsal does not need to).
MESH_USER=${MESH_USER:-nipaplay-mesh}
MESH_OPT=${MESH_OPT:-/opt/nipaplay-mesh-coordinator}
MESH_ETC=${MESH_ETC:-/etc/nipaplay-mesh-coordinator}
MESH_ENV=${MESH_ENV:-/etc/nipaplay-mesh-coordinator.env}
MESH_VAR=${MESH_VAR:-/var/lib/nipaplay-mesh-coordinator}
MESH_UNIT=${MESH_UNIT:-/etc/systemd/system/nipaplay-mesh-coordinator.service}
MESH_SERVICE=nipaplay-mesh-coordinator
MESH_PORT=${MESH_PORT:-18082}
GATEWAY_PORT=${GATEWAY_PORT:-18081}
SITE=${SITE:-nipaplay.aimes-soft.com}
NGINX_BIN=${NGINX_BIN:-/www/server/nginx/sbin/nginx}
NGINX_VHOST=${NGINX_VHOST:-/www/server/panel/vhost/nginx/nipaplay.aimes-soft.com.conf}
# Extra curl options for the check through nginx (the rehearsal uses a
# self-signed certificate; production leaves this empty).
CURL_EXTRA=${CURL_EXTRA:-}
HTTPS_PORT=${HTTPS_PORT:-443}
DEPLOY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE_DIR=${STATE_DIR:-/root/mesh-deploy/state}

say() { printf '\n== %s\n' "$*"; }
die() { printf 'ABORT: %s\n' "$*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root"; }
