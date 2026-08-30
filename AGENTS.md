# Cobbleverse Upgrade Guide

## How to upgrade the cobbleverse modpack

### 1. Find the target version on Modrinth

```bash
# List all versions (project slug: Jkb29YJU)
curl -s "https://api.modrinth.com/v2/project/Jkb29YJU/version" | \
  jq '[.[] | {version_number, id, game_versions, loaders}]'
```

Note the `id` (mrpack version ID) and `version_number` for the target release.
Confirm `game_versions` and `loaders` match what's in `versions.env` — if
Minecraft or Fabric loader changed, update those too.

### 2. Update version files

Three files carry version values:

- **`versions.env`** — `COBBLEVERSE_VERSION` and `COBBLEVERSE_MRPACK_ID`
- **`Containerfile`** — the matching `ARG` defaults (builder stage + runtime stage)
- **`image.yaml`** — `version` field (Minecraft version, not modpack version)

All three must stay in sync. The CI pipeline reads `image.yaml` for the image
tag and passes build args from the Containerfile ARGs.

### 3. Check for new client-only mods

The mrpack's `modrinth.index.json` marks all mods as `env.server = "required"`
even for client-only mods. The `install-mrpack.sh` script removes them by
filename glob pattern. When upgrading, check for new client-only mods:

```bash
# Download and extract the new mrpack
curl -sL -o modpack.mrpack "https://cdn.modrinth.com/data/Jkb29YJU/versions/<MRPACK_ID>/COBBLEVERSE%20<VERSION>.mrpack"
unzip -q modpack.mrpack -d mrpack

# Get all project IDs from the modpack, query Modrinth for server_side
pids=$(jq -r '.files[] | select(.path | test("^mods/")) | .downloads[0]' mrpack/modrinth.index.json \
  | sed 's|https://cdn.modrinth.com/data/||;s|/.*||' | sort -u)
json_ids=$(echo "$pids" | jq -R . | jq -s . | jq -c .)
curl -s "https://api.modrinth.com/v2/projects" -G --data-urlencode "ids=$json_ids" \
  | jq -r '.[] | select(.server_side == "unsupported") | .slug' | sort

# Compare against the old version to find newly added client-only mods
# Add filename glob patterns to CLIENT_ONLY_PATTERNS in install-mrpack.sh
```

### 4. Watch for filename case/pattern changes

Mod authors sometimes rename JARs between versions. Two gotchas hit us on
the 1.7.3 → 1.7.42 upgrade:

- **`MusicNotification` → `musicnotification`**: shell globs are
  case-sensitive in Alpine's `ash`. The old pattern missed the new file.
  Keep both case variants or the mod silently stays on the server.
- **`particle-rain-*.jar` → `particlerain-*.jar`**: the hyphen disappeared
  from the filename. The glob must match the actual filename exactly.

Always diff the mod list between old and new mrpack versions:

```bash
diff <(jq -r '.files[].path' old/modrinth.index.json | sort) \
     <(jq -r '.files[].path' new/modrinth.index.json | sort)
```

### 5. Server-side perf mods

`install-mrpack.sh` re-downloads Lithium, FerriteCore, ModernFix, and
ServerCore from Modrinth at build time (latest release for the MC version).
This is intentional — the mrpack may ship outdated versions of these, or
not include them at all. No action needed on upgrade unless a mod is
added/removed from the modpack's perf mod set.

**Noisium was tested and removed** — it conflicts with `zfastnoise` (a
modpack mod). Check for conflicts before adding new perf mods.

### 6. Java runtime version

C2ME (included since 1.7.42) ships a `c2me-opts-natives-math` nested jar
that requires Java 25. However, Cobblemon hard-pins Java 21 — these are
incompatible. The `install-mrpack.sh` script strips the natives-math
submodule from the c2me jar at build time so the server runs on Java 21
(`openjdk21-jre` in the Containerfile). C2ME still works, just without
native math optimizations.

If upgrading and the server fails with a Java version error, check the
modpack's new mods for Java requirements:

```bash
docker logs <container> 2>&1 | grep "requires version"
```

### 7. Verify the build

```bash
# Local build test (adjust platform as needed)
docker build -t cobbleverse-test .
```

The build downloads the mrpack, extracts mods, removes client-only ones,
and downloads perf mods. If a Modrinth URL is wrong or a pattern is broken,
the build fails or the server won't start.
