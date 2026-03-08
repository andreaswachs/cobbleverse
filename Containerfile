# Stage 1: Download and process the modpack
FROM alpine:3 AS builder

ARG COBBLEVERSE_VERSION=1.7.3
ARG MINECRAFT_VERSION=1.21.1
ARG FABRIC_LOADER_VERSION=0.18.4
ARG FABRIC_INSTALLER_VERSION=1.1.1
ARG COBBLEVERSE_MRPACK_ID=Cg3gXABt

RUN apk add --no-cache jq wget unzip

WORKDIR /build
RUN mkdir -p server/mods

# Download the Fabric server launcher
RUN wget -O server/fabric-server-launcher.jar \
    "https://meta.fabricmc.net/v2/versions/loader/${MINECRAFT_VERSION}/${FABRIC_LOADER_VERSION}/${FABRIC_INSTALLER_VERSION}/server/jar"

# Download the mrpack
RUN wget -O modpack.mrpack \
    "https://cdn.modrinth.com/data/Jkb29YJU/versions/${COBBLEVERSE_MRPACK_ID}/COBBLEVERSE%20${COBBLEVERSE_VERSION}.mrpack"

# Install server-side mods and configs from the mrpack
COPY install-mrpack.sh .
RUN chmod +x install-mrpack.sh && ./install-mrpack.sh modpack.mrpack server

# Stage 2: Runtime image
FROM alpine:3

ARG COBBLEVERSE_VERSION=1.7.3
ARG MINECRAFT_VERSION=1.21.1

RUN apk add --no-cache \
    openjdk21-jre \
    jq \
    rcon

# Create a user and group with high UID/GID to not overlap with host users
RUN addgroup -g 10001 cobbleverse && \
    adduser -D -u 10000 -G cobbleverse cobbleverse

WORKDIR /home/cobbleverse

# Copy the fully-built server from the builder stage
COPY --from=builder /build/server ./server

# Copy the entrypoint script
COPY cobbleverse.sh ./

# Fix permissions
RUN chown -R cobbleverse:cobbleverse /home/cobbleverse && \
    chmod +x cobbleverse.sh

# Store version info for runtime reference
RUN echo "COBBLEVERSE_VERSION=${COBBLEVERSE_VERSION}" > /home/cobbleverse/version.txt && \
    echo "MINECRAFT_VERSION=${MINECRAFT_VERSION}" >> /home/cobbleverse/version.txt

ENTRYPOINT ["/home/cobbleverse/cobbleverse.sh"]
