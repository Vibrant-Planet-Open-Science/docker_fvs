#!/bin/bash
# fvs-run — FVS runtime entrypoint
#
# Invokes the specified FVS variant binary from the /data working directory
# so that relative paths in keyfiles resolve correctly and all output files
# are written back into the caller-mounted volume.
#
# Usage:
#   fvs-run <VARIANT> <KEYFILE> [FVS_OPTIONS...]
#   fvs-run <VARIANT> --restart=<stopfile> [FVS_OPTIONS...]
#
# Arguments:
#   VARIANT       FVS regional variant name, e.g. FVSak, FVSbc (required)
#   KEYFILE       Keyfile filename relative to /data, e.g. myrun.key
#                 Required unless --restart is provided
#   FVS_OPTIONS   Additional FVS command-line flags passed through verbatim:
#                   --stoppoint=<code>,<year>[,<file>]
#                   --restart=<stopfile>
#
# Examples:
#   fvs-run FVSak myrun.key
#   fvs-run FVSak myrun.key --stoppoint=1,2040,myrun.stop
#   fvs-run FVSak --restart=myrun.stop
#
# Environment:
#   FVS_VERSION   Baked in at image build time for logging only. Binaries are
#                 resolved from PATH (/usr/local/bin).

set -euo pipefail

# ---- Validate environment --------------------------------------------------

if [ -z "${FVS_VERSION:-}" ]; then
  echo "ERROR: FVS_VERSION environment variable is not set." >&2
  echo "       This should be baked into the image at build time." >&2
  exit 1
fi

# ---- Parse arguments -------------------------------------------------------

VARIANT="${1:-}"
if [ -z "$VARIANT" ]; then
  echo "ERROR: VARIANT is required as the first argument." >&2
  echo "Usage: fvs-run <VARIANT> <KEYFILE> [OPTIONS]" >&2
  echo "       fvs-run <VARIANT> --restart=<stopfile>" >&2
  exit 1
fi
shift

if ! command -v "$VARIANT" >/dev/null 2>&1; then
  echo "ERROR: Unknown variant '${VARIANT}' (not found on PATH)." >&2
  echo "Available variants:" >&2
  ls /usr/local/bin | grep '^FVS' | grep -v '\.so$' | sort >&2
  exit 1
fi

if [ ! -x "$(command -v "$VARIANT")" ]; then
  echo "ERROR: '${VARIANT}' exists but is not executable." >&2
  exit 1
fi

# ---- Determine invocation mode ---------------------------------------------
# FVS --keywordfile and --restart are mutually exclusive.
# If --restart appears in the remaining arguments we skip keyfile handling
# and pass everything through directly.

RESTART_MODE=false
for arg in "$@"; do
  if [[ "$arg" == --restart=* ]]; then
    RESTART_MODE=true
    break
  fi
done

if [ "$RESTART_MODE" = true ]; then
  # Restart mode: no keyfile argument expected; all remaining args pass through
  echo "FVS restart mode: ${VARIANT} ${FVS_VERSION}" >&2
  cd /data
  exec "$VARIANT" "$@"
else
  # Normal mode: next argument is the keyfile name
  KEYFILE="${1:-}"
  if [ -z "$KEYFILE" ]; then
    echo "ERROR: KEYFILE is required as the second argument (or use --restart)." >&2
    echo "Usage: fvs-run <VARIANT> <KEYFILE> [OPTIONS]" >&2
    exit 1
  fi
  shift

  # Keyfile suffix must be .key per FVS requirements
  if [[ "$KEYFILE" != *.key ]]; then
    echo "ERROR: Keyfile '${KEYFILE}' must have a .key suffix." >&2
    exit 1
  fi

  if [ ! -f "/data/${KEYFILE}" ]; then
    echo "ERROR: Keyfile '/data/${KEYFILE}' not found." >&2
    echo "Make sure the file exists in the directory mounted at /data." >&2
    exit 1
  fi

  echo "FVS run: variant=${VARIANT} version=${FVS_VERSION} keyfile=${KEYFILE}" >&2

  # Run from /data so all relative paths in the keyfile resolve correctly
  # and FVS writes its output files (*.out, *.trl, *.sum, etc.) into /data.
  cd /data
  exec "$VARIANT" --keywordfile="${KEYFILE}" "$@"
fi
