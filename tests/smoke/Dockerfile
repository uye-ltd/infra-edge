# Smoke-test runner: hurl + curl (curl is needed for checks hurl cannot express,
# e.g. "the connection must be closed without a response" for 444).
FROM ghcr.io/orange-opensource/hurl:7.0.0
# hadolint ignore=DL3018
RUN apk add --no-cache curl
ENTRYPOINT []
