#!/bin/sh

# LAME 4.0's configure script requires pkg-config even when optional decoder
# and libsndfile integrations are disabled. This deterministic stub satisfies
# the version probe and reports every optional package as unavailable.
if [ "${1:-}" = "--atleast-pkgconfig-version" ]; then
    exit 0
fi
exit 1
