#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE=${1:?Image tag required}
SIMULATE_FAILURE=${2:-0}

cd "$(dirname "$0")"

CONFIG=/etc/nginx/jenkins-demo/active.conf

# Prevent overlapping deployments on this server.
exec 9>/home/deploy/deployment.lock
flock -n 9 || {
    echo "Another deployment is running"
    exit 1
}

case "$(cat "$CONFIG")" in
    "server 127.0.0.1:8081;")
        OLD_PORT=8081
        NEW_PORT=8082
        NEW_SLOT=green
        ;;
    "server 127.0.0.1:8082;")
        OLD_PORT=8082
        NEW_PORT=8081
        NEW_SLOT=blue
        ;;
    *)
        echo "Unexpected active-slot configuration"
        exit 1
        ;;
esac

CONTAINER="web-$NEW_SLOT"
SWITCH_ATTEMPTED=0
CANDIDATE_CREATED=0

# Retry until the endpoint serves the exact expected page.
match_page() {
    local url=$1
    local expected=$2

    for attempt in {1..20}; do
        if curl --fail --silent --show-error \
            --connect-timeout 2 --max-time 3 \
            "$url" > response.html &&
            cmp -s "$expected" response.html; then
            return 0
        fi
        sleep 1
    done

    echo "Page verification failed: $url"
    return 1
}

finish() {
    local status=$?
    trap - EXIT INT TERM

    if (( status != 0 )); then
        if (( SWITCH_ATTEMPTED == 1 )); then
            echo "Restoring previous upstream: $OLD_PORT"

            if cp previous.conf "$CONFIG.restore" &&
                mv "$CONFIG.restore" "$CONFIG" &&
                sudo -n /usr/sbin/nginx -t &&
                sudo -n /usr/bin/systemctl reload nginx &&
                match_page http://127.0.0.1/ previous.html; then
                echo "ROLLBACK VERIFIED: previous page is live"
            else
                echo "ROLLBACK FAILED: check Nginx and containers manually"
                exit 2
            fi
        else
            echo "Deployment failed before switching traffic"
        fi

        if (( CANDIDATE_CREATED == 1 )); then
            docker rm -f "$CONTAINER" || true
        fi
    fi

    exit "$status"
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Record the previous page and configuration before changing anything.
cp "$CONFIG" previous.conf

curl --fail --silent --show-error --max-time 10 \
    "http://127.0.0.1:$OLD_PORT/" > previous.html

match_page http://127.0.0.1/ previous.html

# Check the transferred archive and the loaded image identity.
sha256sum -c image.tar.sha256
docker load -i image.tar

test "$(docker image inspect --format '{{.Id}}' "$IMAGE")" \
    = "$(cat image.id)"

rm image.tar

# Replace only the inactive slot.
if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
    docker rm -f "$CONTAINER"
fi

docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    -p "127.0.0.1:$NEW_PORT:80" \
    "$IMAGE"

CANDIDATE_CREATED=1

# Wait for Docker's health check.
HEALTHY=0

for attempt in {1..30}; do
    if [[ "$(docker inspect --format '{{.State.Health.Status}}' \
        "$CONTAINER")" == healthy ]]; then
        HEALTHY=1
        break
    fi
    sleep 1
done

if (( HEALTHY != 1 )); then
    docker logs "$CONTAINER"
    echo "Candidate container did not become healthy"
    exit 1
fi

# Test the candidate directly before routing visitors to it.
match_page "http://127.0.0.1:$NEW_PORT/" index.html

echo "Candidate passed. Switching traffic to $NEW_SLOT"

printf 'server 127.0.0.1:%s;\n' "$NEW_PORT" > "$CONFIG.next"

# Set the flag before replacing the configuration so failures trigger rollback.
SWITCH_ATTEMPTED=1
mv "$CONFIG.next" "$CONFIG"

sudo -n /usr/sbin/nginx -t
sudo -n /usr/bin/systemctl reload nginx

# Test through the public-facing Nginx listener.
match_page http://127.0.0.1/ index.html

if [[ "$SIMULATE_FAILURE" == 1 ]]; then
    echo "Deliberately failing to exercise rollback"
    exit 1
fi

echo "DEPLOYMENT VERIFIED: $NEW_SLOT is live"
echo "Previous container remains running on port $OLD_PORT"
