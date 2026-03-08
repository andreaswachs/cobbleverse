#!/bin/ash
set -e

# Check if EULA has been accepted
if [ -z "$EULA" ]; then
    echo "Variable EULA not defined, see docs to know how to accept EULA."
    exit 1
fi

# Default the allocated RAM to 8G if not set
ALLOCATED_RAM="${ALLOCATED_RAM:-8G}"

# Server files are pre-installed in /home/cobbleverse/server during image build
# The world directory is used for persistent data (mounted as volume)
WORLD_DIR="/home/cobbleverse/world"
SERVER_DIR="/home/cobbleverse/server"

# Create world directory
mkdir -p "$WORLD_DIR"

# On first boot, copy the full server contents to the world volume
# On subsequent boots, only refresh mods and configs (preserves world data)
if [ ! -f "$WORLD_DIR/fabric-server-launcher.jar" ]; then
    echo "First boot: copying server files to world volume..."
    cp -r "$SERVER_DIR/"* "$WORLD_DIR/"
else
    echo "Existing world detected: refreshing mods and configs..."
    # Refresh mods (remove old, copy new)
    rm -rf "$WORLD_DIR/mods"
    cp -r "$SERVER_DIR/mods" "$WORLD_DIR/mods"
    # Refresh config
    cp -r "$SERVER_DIR/config" "$WORLD_DIR/config"
    # Update launcher
    cp "$SERVER_DIR/fabric-server-launcher.jar" "$WORLD_DIR/"
fi

# Set up EULA
echo "eula=${EULA}" > "$WORLD_DIR/eula.txt"

# Fix permissions
chown -R cobbleverse:cobbleverse "$WORLD_DIR"

# Print version info
if [ -f /home/cobbleverse/version.txt ]; then
    echo "=== Cobbleverse Server ==="
    cat /home/cobbleverse/version.txt
    echo "ALLOCATED_RAM=${ALLOCATED_RAM}"
    echo "==========================="
fi

# Start the server with Aikar's flags for optimized GC
cd "$WORLD_DIR"
exec su -c "java \
    -Xms${ALLOCATED_RAM} -Xmx${ALLOCATED_RAM} \
    -XX:+UseG1GC \
    -XX:+ParallelRefProcEnabled \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+DisableExplicitGC \
    -XX:+AlwaysPreTouch \
    -XX:G1NewSizePercent=30 \
    -XX:G1MaxNewSizePercent=40 \
    -XX:G1HeapRegionSize=8M \
    -XX:G1ReservePercent=20 \
    -XX:G1HeapWastePercent=5 \
    -XX:G1MixedGCCountTarget=4 \
    -XX:InitiatingHeapOccupancyPercent=15 \
    -XX:G1MixedGCLiveThresholdPercent=90 \
    -XX:G1RSetUpdatingPauseTimePercent=5 \
    -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem \
    -XX:MaxTenuringThreshold=1 \
    -jar fabric-server-launcher.jar nogui" cobbleverse
