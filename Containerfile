# syntax=docker/dockerfile:1
# Copyright 2018-present Network Optix, Inc. Licensed under MPL 2.0: www.mozilla.org/MPL/2.0/

ARG VERSION=EDGE
ARG RELEASE=0

########################################
# Download stage
# Fetch the latest Nx Meta VMS Server deb package
########################################
FROM ubuntu:24.04 AS download

# RUN mount cache for multi-arch: https://github.com/docker/buildx/issues/549#issuecomment-1788297892
ARG TARGETARCH
ARG TARGETVARIANT

RUN --mount=type=cache,id=apt-$TARGETARCH$TARGETVARIANT,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=aptlists-$TARGETARCH$TARGETVARIANT,sharing=locked,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl jq

RUN mkdir -p /download && \
    FULL_VERSION=$(curl -s https://updates.networkoptix.com/metavms/releases.json | jq -r '[.releases[] | select(.product == "vms" and .publication_type == "release")] | first | .version') && \
    BUILD_NUMBER=$(echo "$FULL_VERSION" | rev | cut -d. -f1 | rev) && \
    echo "Nx Meta version: ${FULL_VERSION}, build number: ${BUILD_NUMBER}" && \
    curl -L -o /download/nxmeta-server.deb "https://updates.networkoptix.com/metavms/${BUILD_NUMBER}/linux/metavms-server-${FULL_VERSION}-linux_x64.deb"

########################################
# Final stage
# Install and configure Nx Meta VMS Server
########################################
FROM ubuntu:24.04 AS final

# VMS Server user and directory name
ARG COMPANY="networkoptix-metavms"
ENV COMPANY=${COMPANY}

# Disable EULA dialogs and confirmation prompts in installers
ENV DEBIAN_FRONTEND=noninteractive

# RUN mount cache for multi-arch: https://github.com/docker/buildx/issues/549#issuecomment-1788297892
ARG TARGETARCH
ARG TARGETVARIANT

# Install the VMS Server deb package
RUN --mount=type=cache,id=apt-$TARGETARCH$TARGETVARIANT,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,id=aptlists-$TARGETARCH$TARGETVARIANT,sharing=locked,target=/var/lib/apt/lists \
    --mount=type=bind,from=download,source=/download/nxmeta-server.deb,target=/tmp/nxmeta-server.deb \
    apt-get update && \
    apt-get install -y --no-install-recommends binutils && \
    apt-get install -y /tmp/nxmeta-server.deb && \
    chattr -i /lib/systemd/systemd-coredump

# Fix permissions and create volume directories
RUN install -d -m 775 -o ${COMPANY} -g 0 /opt/${COMPANY}/mediaserver/etc && \
    install -d -m 775 -o ${COMPANY} -g 0 /opt/${COMPANY}/mediaserver/var && \
    install -d -m 775 -o ${COMPANY} -g 0 /recordings

# Configure mediaserver for container environment
# Disable root-tool to run in non-privileged mode
# The /recording folder is not recognized correctly without this setting
RUN echo "currentOsVariantOverride=docker" >> /opt/${COMPANY}/mediaserver/etc/mediaserver.conf && \
    echo "ignoreRootTool=true" >> /opt/${COMPANY}/mediaserver/etc/mediaserver.conf

COPY --link --chmod=775 entrypoint.sh /opt/${COMPANY}/mediaserver/entrypoint.sh

ENV PATH="/opt/${COMPANY}/mediaserver/bin${PATH:+:${PATH}}"

WORKDIR /home/${COMPANY}

VOLUME [ "/opt/${COMPANY}/mediaserver/etc", "/opt/${COMPANY}/mediaserver/var", "/recordings" ]

EXPOSE 7001

USER ${COMPANY}

# Runs the media server on container start unless argument(s) specified
ENTRYPOINT "/opt/${COMPANY}/mediaserver/entrypoint.sh"

ARG VERSION
ARG RELEASE
LABEL name="docker-nxvms" \
      vendor="Network Optix" \
      maintainer="jim60105" \
      url="https://github.com/jim60105/docker-nxvms" \
      version=${VERSION} \
      release=${RELEASE} \
      io.k8s.display-name="Nx Meta VMS Server" \
      summary="Nx Meta Video Management System Server" \
      description="Containerized Nx Meta VMS Server: https://meta.nxvms.com"
