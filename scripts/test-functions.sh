#!/usr/bin/env bash
# Runs the Edge Functions' shared-logic tests (privacy trimming, track codec) against the golden
# files in spec/fixtures. Node 23+ runs the TypeScript directly.
set -euo pipefail
cd "$(dirname "$0")/.."
exec node --test supabase/functions/_shared/*.test.ts
