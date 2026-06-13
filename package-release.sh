#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/release"
OUT_FILE="$OUT_DIR/VPS-Tunnel.tar.gz"

install -d -m 0755 "$OUT_DIR"

python3 - "$SCRIPT_DIR" "$OUT_FILE" <<'PY'
import os
import tarfile
import sys

script_dir, out_file = sys.argv[1], sys.argv[2]
exclude_dirs = {".git", "work", "release"}
exclude_files = {".DS_Store", "client-sing-box.json", "00-vars.env"}

with tarfile.open(out_file, "w:gz", format=tarfile.GNU_FORMAT) as tar:
    root_info = tarfile.TarInfo("VPS-Tunnel")
    root_info.type = tarfile.DIRTYPE
    root_info.mode = 0o755
    root_info.uid = root_info.gid = 0
    root_info.uname = root_info.gname = "root"
    tar.addfile(root_info)

    for current_root, dirs, files in os.walk(script_dir):
        rel_root = os.path.relpath(current_root, script_dir)
        if rel_root == ".":
            rel_root = ""

        dirs[:] = sorted(d for d in dirs if d not in exclude_dirs and d != "__pycache__")
        files = sorted(f for f in files if f not in exclude_files and not f.endswith(".pyc"))

        for dirname in dirs:
            rel_path = os.path.join(rel_root, dirname) if rel_root else dirname
            arcname = os.path.join("VPS-Tunnel", rel_path)
            full_path = os.path.join(current_root, dirname)
            info = tar.gettarinfo(full_path, arcname)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            tar.addfile(info)

        for filename in files:
            rel_path = os.path.join(rel_root, filename) if rel_root else filename
            arcname = os.path.join("VPS-Tunnel", rel_path)
            full_path = os.path.join(current_root, filename)
            info = tar.gettarinfo(full_path, arcname)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            with open(full_path, "rb") as fh:
                tar.addfile(info, fh)
PY
echo "已写入：$OUT_FILE"
