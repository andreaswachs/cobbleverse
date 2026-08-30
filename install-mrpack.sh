#!/bin/sh
# Processes a Modrinth .mrpack modpack:
# 1. Extracts the archive
# 2. Parses modrinth.index.json to download server-compatible mods
# 3. Copies override configs into the server directory
set -e

MRPACK_FILE="$1"
SERVER_DIR="$2"
MC_VERSION="${3:-1.21.1}"

if [ -z "$MRPACK_FILE" ] || [ -z "$SERVER_DIR" ]; then
    echo "Usage: install-mrpack.sh <mrpack-file> <server-dir> [mc-version]"
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
musicnotification-*.jar
Ping-Wheel-*.jar
particlerain-*.jar
paginatedadvancements-*.jar
notenoughcrashes-*.jar
respackopts-*.jar
defaultoptions-*.jar
BetterF1-*.jar
BetterThirdPerson-*.jar
MouseTweaks-*.jar
EuphoriaPatcher-*.jar
BadOptimizations-*.jar
catchindicator-*.jar
NoChatRestrictions-*.jar
particle_core-*.jar
particular-*.jar
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

# Strip c2me natives-math submodule (requires Java 25, conflicts with Cobblemon's Java 21 pin)
# ponytail: c2me still works without it, just loses native math optimizations
_c2me_jar=$(ls "$SERVER_DIR/mods/c2me-"*.jar 2>/dev/null | head -1)
if [ -n "$_c2me_jar" ]; then
    echo "==> Stripping c2me natives-math submodule (Java 25 requirement)..."
    zip -q -d "$_c2me_jar" "META-INF/jars/c2me-fabric-opts-natives-math-*.jar" 2>/dev/null && echo "    Done" || echo "    No natives-math submodule found"
fi

# Download server-side performance mods
download_perf_mod() {
    _name="$1" _pid="$2" _glob="$3"
    echo "==> Replacing with latest $_name..."
    # ponytail: rm old JAR by glob, if glob misses old versions remain but Fabric picks latest
    rm -f "$SERVER_DIR/mods/$_glob" 2>/dev/null || true
    _info=$(wget -qO- "https://api.modrinth.com/v2/project/${_pid}/version?loaders=[%22fabric%22]&game_versions=[%22${MC_VERSION}%22]" \
        | jq -r '[.[] | select(.version_type == "release")] | first | .files[] | select(.primary) | "\(.url)\t\(.filename)"')
    if [ -z "$_info" ]; then
        echo "    WARN: No release found for $_name (MC $MC_VERSION)"
        return
    fi
    _url=$(printf '%s' "$_info" | cut -f1)
    _file=$(printf '%s' "$_info" | cut -f2)
    wget -q -O "$SERVER_DIR/mods/$_file" "$_url"
    echo "    $_file"
}

download_perf_mod "Lithium" "gvQqBUqZ" "lithium-*.jar"
download_perf_mod "FerriteCore" "uXXizFIs" "ferritecore-*.jar"
download_perf_mod "ModernFix" "nmDcB62a" "modernfix-*.jar"
download_perf_mod "ServerCore" "4WWQxlQP" "servercore-*.jar"

echo "==> Modpack installation complete"
