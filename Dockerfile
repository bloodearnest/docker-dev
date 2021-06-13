# syntax=docker/dockerfile:1.2
#
# DL3007 ignored because base-docker a) doesn't have any other tags currently,
# and b) we specifically always want to build on the latest base image, by
# design.
#
# hadolint ignore=DL3007
FROM ghcr.io/opensafely-core/base-docker:latest as base-python

# we are going to use an apt cache on the host, so disable the default debian
# docker clean up that we delete that cache on every apt install
RUN rm -f /etc/apt/apt.conf.d/docker-clean

# ensure fully working base python3 installation
# see: https://gist.github.com/tiran/2dec9e03c6f901814f6d1e8dad09528e
# use space efficient utility from base image
RUN --mount=type=cache,target=/var/cache/apt \ 
  /root/docker-apt-install.sh python3 python3-venv python3-pip python3-distutils tzdata ca-certificates


# install any system dependencies
RUN --mount=type=bind,source=dependencies.txt,target=/dependencies.txt \
    --mount=type=cache,target=/var/cache/apt \ 
    /root/docker-apt-install.sh /dependencies.txt


# Ok, now we have local base image with python and our system dependencies on.
# We'll use this as the base for our builder image, where we'll build and
# install any python packages needed. We'll also use it as our base for the
# actual production image.

# We use a disposable build image to avoid carrying the build dependencies into
# the production image.
FROM base-python as builder

# Install any system build dependencies
RUN --mount=type=bind,source=build-dependencies.txt,target=/build-dependencies.txt \
    --mount=type=cache,target=/var/cache/apt \ 
    /root/docker-apt-install.sh /build-dependencies.txt

# Install everything in venv for isolation from system python libraries
RUN python3 -m venv /opt/venv
ENV VIRTUAL_ENV=/opt/venv/ PATH="/opt/venv/bin:$PATH"

# The cache mount means a) /root/.cache is not in the image, and b) it's preserved
# between docker builds locally, for faster dev rebuild.
#
RUN --mount=type=cache,target=/root/.cache \
    python -m pip install -U pip setuptools wheel && \
    python -m pip install --requirement //requirements.prod.txt


# Ok, we've built everything we need, so time to build the prod image
FROM base-python as prod-image

# Adjust this metadata to fit project. Note that the base-docker image does set
# some basic metadata.
LABEL org.opencontainers.image.title="project" \
      org.opencontainers.image.description="project description" \
      org.opencontainers.image.source="https://github.com/opensafely-core/project"

# Create a non-root user to run the app as
RUN useradd --create-home appuser

# copy venv over from builder image. These will have root:root ownership, but
# are readable by all.
COPY --from=builder /opt/venv /opt/venv

# Set up the path to pick up the venv path
ENV VIRTUAL_ENV=/opt/venv/ PATH="/opt/venv/bin:$PATH"

# copy application code
COPY . /app
WORKDIR /app
VOLUME /app

# This may not be nessecary, but it probably doesn't hurt
ENV PYTHONPATH=/app

# switch to running as the user
USER appuser

ENTRYPOINT []
# We set command rather than entrypoint, to make it easier to run differenting
# things from the cli
CMD ["/app/entrypoints/prod.sh"]

# finally, tag with build information. These will change regularly, therefore
# we do them as the last action.
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.created=$BUILD_DATE
ARG GITREF=unknown
LABEL org.opencontainers.image.revision=$GITREF


# Now build a dev image from our prod image
FROM prod-image as dev-image

# switch back to root to run the install of dev requirements.txt
USER root

# install development requirements
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=bind,source=requirements.dev.txt,target=/requirements.dev.txt \
    python -m pip install --requirement /requirements.dev.txt

# switch to the dev entrypoing
CMD ["/app/entrypoints/dev.sh"]

# in dev, ensure appuser uid is equial to
# ensure app
ARG USERID=1000
RUN usermod -u $USERID appuser
# switch back to appuser
USER appuser
