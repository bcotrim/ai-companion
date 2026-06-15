#!/bin/bash
# Validate a Codex-format pet folder or zip.
set -euo pipefail

SOURCE="${1:-}"
if [[ -z "$SOURCE" ]]; then
  echo "usage: $0 /path/to/pet-folder-or.zip" >&2
  exit 2
fi

TMP=""
cleanup() {
  if [[ -n "$TMP" ]]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

if [[ -f "$SOURCE" && "${SOURCE##*.}" == "zip" ]]; then
  TMP="$(mktemp -d)"
  ditto -x -k "$SOURCE" "$TMP"
  SOURCE="$TMP"
fi

python3 - "$SOURCE" <<'PY'
import json
import os
import subprocess
import sys

root = sys.argv[1]

def find_pet_dir(path):
    if os.path.isfile(os.path.join(path, "pet.json")):
        return path
    for current, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if "pet.json" in files:
            return current
    return None

def image_size(path):
    proc = subprocess.run(
        ["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        return None, proc.stderr.strip() or proc.stdout.strip()
    width = height = None
    for line in proc.stdout.splitlines():
        if "pixelWidth:" in line:
            width = int(line.rsplit(":", 1)[1].strip())
        if "pixelHeight:" in line:
            height = int(line.rsplit(":", 1)[1].strip())
    if not width or not height:
        return None, "could not read image dimensions"
    return (width, height), None

pet_dir = find_pet_dir(root)
if not pet_dir:
    print("error: no pet.json found", file=sys.stderr)
    sys.exit(1)

issues = []
pet_json = os.path.join(pet_dir, "pet.json")
try:
    with open(pet_json) as f:
        pet = json.load(f)
except Exception as exc:
    print(f"error: invalid pet.json: {exc}", file=sys.stderr)
    sys.exit(1)

pet_id = pet.get("id") or os.path.basename(pet_dir)
name = pet.get("displayName") or pet_id
sheet_name = pet.get("spritesheetPath") or "spritesheet.webp"
sheet_path = os.path.join(pet_dir, sheet_name)
frame = pet.get("frame") or {}
cell_w = int(frame.get("width") or 192)
cell_h = int(frame.get("height") or 208)
columns = int(frame.get("columns") or 8)
rows = int(frame.get("rows") or 9)

if not os.path.exists(sheet_path):
    issues.append(f"missing spritesheet: {sheet_name}")
else:
    size, error = image_size(sheet_path)
    if error:
        issues.append(f"could not inspect spritesheet: {error}")
    else:
        width, height = size
        expected_w = cell_w * columns
        expected_h = cell_h * rows
        if width < expected_w or height < expected_h:
            issues.append(f"spritesheet is {width}x{height}, expected at least {expected_w}x{expected_h}")

if min(cell_w, cell_h, columns, rows) <= 0:
    issues.append("frame width, height, columns, and rows must be positive")

max_index = columns * rows
for anim_name, anim in (pet.get("animations") or {}).items():
    frames = anim.get("frames") or []
    if not frames:
        issues.append(f"animation {anim_name} has no frames")
    for index in frames:
        if not isinstance(index, int):
            issues.append(f"animation {anim_name} has non-integer frame {index!r}")
        elif index < 0 or index >= max_index:
            issues.append(f"animation {anim_name} references frame {index}, outside 0...{max_index - 1}")

print(f"Pet: {name} ({pet_id})")
print(f"Folder: {pet_dir}")
print(f"Frame: {cell_w}x{cell_h}, grid {columns}x{rows}")

if issues:
    print("\nIssues:")
    for issue in issues:
        print(f"- {issue}")
    sys.exit(1)

print("OK")
PY
