#!/bin/sh
# Processes a Modrinth .mrpack modpack:
# 1. Extracts the archive
# 2. Parses modrinth.index.json to download server-compatible mods
# 3. Copies override configs into the server directory
set -e

MRPACK_FILE="$1"
SERVER_DIR="$2"

if [ -z "$MRPACK_FILE" ] || [ -z "$SERVER_DIR" ]; then
    echo "Usage: install-mrpack.sh <mrpack-file> <server-dir>"
    exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Extracting mrpack..."
unzip -q "$MRPACK_FILE" -d "$WORK_DIR"

INDEX="$WORK_DIR/modrinth.index.json"
if [ ! -f "$INDEX" ]; then
    echo "ERROR: modrinth.index.json not found in mrpack"
    exit 1
fi

# Download server-compatible files from the index
# Skip files where env.server == "unsupported" (client-only mods)
echo "==> Downloading server-compatible mods..."
TOTAL=$(jq '[.files[] | select(.env.server != "unsupported")] | length' "$INDEX")
echo "    Found $TOTAL server-compatible files"

DOWNLOADED=0
FAILED=0

jq -r '.files[] | select(.env.server != "unsupported") | "\(.path)\t\(.downloads[0])"' "$INDEX" | while IFS="$(printf '\t')" read -r path url; do
    dest="$SERVER_DIR/$path"
    mkdir -p "$(dirname "$dest")"

    if wget -q -O "$dest" "$url"; then
        DOWNLOADED=$((DOWNLOADED + 1))
        echo "    [$DOWNLOADED/$TOTAL] $(basename "$path")"
    else
        FAILED=$((FAILED + 1))
        echo "    WARN: Failed to download $(basename "$path") from $url"
    fi
done

# Copy overrides (modpack config files, datapacks, etc.)
for override_dir in "server-overrides" "overrides"; do
    if [ -d "$WORK_DIR/$override_dir" ]; then
        echo "==> Copying $override_dir..."
        cp -r "$WORK_DIR/$override_dir/"* "$SERVER_DIR/" 2>/dev/null || true
    fi
done

# Fix permissions - some mrpack overrides ship with broken (000) permissions
find "$SERVER_DIR" -type f ! -perm -444 -exec chmod 644 {} +

# Remove client-only mods that the manifest doesn't properly flag
# Based on https://github.com/Blue-Kachina/cobbleverse-docker
echo "==> Removing client-only mods..."
CLIENT_ONLY_PATTERNS="
modmenu-*.jar
RoughlyEnoughItems-*.jar
sound-physics-remastered-*.jar
moreculling-*.jar
infinite-music-*.jar
MusicNotification-*.jar
Ping-Wheel-*.jar
particle-rain-*.jar
paginatedadvancements-*.jar
notenoughcrashes-*.jar
respackopts-*.jar
defaultoptions-*.jar
BetterF1-*.jar
BetterThirdPerson-*.jar
MouseTweaks-*.jar
EuphoriaPatcher-*.jar
"

cleaned=0
for pattern in $CLIENT_ONLY_PATTERNS; do
    for file in "$SERVER_DIR/mods/"$pattern; do
        if [ -f "$file" ]; then
            echo "    Removed $(basename "$file")"
            rm -f "$file"
            cleaned=$((cleaned + 1))
        fi
    done
done
echo "    Removed $cleaned client-only mod(s)"

echo "==> Modpack installation complete"
