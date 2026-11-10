#!/bin/bash
# Uploads a local ATLAS.dmg to the production Supabase "atlas-installers"
# bucket. Part of the standard release pipeline (build_dmg.sh -> sign_update
# -> this -> appcast/version update -> git push), used on every ATLAS release.
set -e

DMG_PATH="$1"
DEST_KEY="${2:-ATLAS.dmg}"

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
  echo "Usage: upload_atlas_dmg.sh <path-to-dmg> [dest-key]" >&2
  exit 1
fi

cd /Users/user && node --input-type=module -e '
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "fs"

function readEnvVar(name) {
  const text = readFileSync("/Users/user/.env.local", "utf8")
  const m = text.match(new RegExp(`^${name}=(.*)$`, "m"))
  if (!m) return undefined
  return m[1].trim().replace(/^["'"'"']|["'"'"']$/g, "")
}

const url = readEnvVar("NEXT_PUBLIC_SUPABASE_URL")
const key = readEnvVar("SUPABASE_SERVICE_ROLE_KEY")
if (!url || !key) { console.error("Missing env vars"); process.exit(1) }

const supabase = createClient(url, key)
const filePath = process.argv[1]
const destKey = process.argv[2] || "ATLAS.dmg"
const data = readFileSync(filePath)

const { error } = await supabase.storage.from("atlas-installers").upload(destKey, data, {
  contentType: "application/octet-stream",
  upsert: true,
})

if (error) { console.error("Upload failed:", error.message); process.exit(1) }
console.log(`Uploaded ${filePath} -> atlas-installers/${destKey} (${data.length} bytes)`)
' "$DMG_PATH" "$DEST_KEY"
