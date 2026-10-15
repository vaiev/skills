#!/usr/bin/env python3
"""Fallback when the persistent store is not mounted: build a NON-SECRET plain tarball,
scan every file for secrets/IPs, drop matching files, and print the tarball path.
Never includes CLI logins, tokens or SSH keys."""
import os, re, sqlite3, sys, tarfile, tempfile, time
SECRET_RE = re.compile(rb"(-----BEGIN [A-Z ]*PRIVATE KEY|(?-i:\b(?:sk[-]|gh[pos]_|github[_]pat_|x[o]x[abp]-|AKIA)[-_A-Za-z0-9]{12,})|\b(?:\d{1,3}\.){3}\d{1,3}\b|(?:api[_-]?key|password|passwd|secret|token)\s*[:=]\s*['\"]?[A-Za-z0-9/+_\-]{12,})", re.I)
import shlex
from pathlib import Path
from config import load
SKIP_DIRS = {".git", "venv", "node_modules", "target", ".next", "dist", ".venv", "__pycache__", ".models"}
SKIP_FILE = re.compile(r"(hub\.db(-wal|-shm)?$|hub\.py\.bak-|\.pem$|\.key$|(^|/)\.env|(^|/)id_[a-z0-9]+(\.pub)?$|auth\.json$|passphrase|persist\.env|known_hosts|\.tgz(\.enc)?$|\.tar\.gz$)")
def bad(data):
    for m in SECRET_RE.finditer(data):
        return m.group(0)[:4] + b"..."
    return None
def main():
    config = load()
    include = [os.path.abspath(os.path.expanduser(p)) for p in shlex.split(config.get("PERSIST_INCLUDE", ""))]
    if not include:
        sys.exit("PERSIST_INCLUDE is required")
    sensitive = {os.path.realpath(os.path.expanduser(p)) for p in
                 (config.get("PERSIST_KEY"), config.get("PERSIST_KNOWN_HOSTS"),
                  os.environ.get("PERSIST_CONFIG", "~/.config/lead-kit/persist.env"),
                  config.get("HUB_DB")) if p}
    if config.get("HUB_DB"):
        db_path = os.path.realpath(os.path.expanduser(config["HUB_DB"]))
        sensitive.update(db_path + suffix for suffix in ("-wal", "-shm", "-journal"))
    store = os.path.realpath(os.path.expanduser(config["PERSIST_STORE"]))
    def excluded(path):
        resolved = os.path.realpath(path)
        return resolved in sensitive or os.path.commonpath([store, resolved]) == store
    ts = time.strftime("%Y%m%d-%H%M%S"); out = os.path.join(tempfile.mkdtemp(), f"plain-{ts}.tgz")
    dropped, n = [], 0
    with tarfile.open(out, "w:gz") as tar:
        # hub DB: consistent copy, then scan its dump
        if config.get("HUB_DB"):
            db = Path(config["HUB_DB"]).expanduser().resolve()
            tmpdb = os.path.join(os.path.dirname(out), "hub.db")
            with sqlite3.connect(db.as_uri() + "?mode=ro", uri=True) as source:
                with sqlite3.connect(tmpdb) as target:
                    source.backup(target)
                    # Scan the complete SQL dump, including unknown tables.
                    dump = "\n".join(target.iterdump()).encode()
            if bad(dump):
                sys.exit("ABORT: hub DB dump matches secret/IP pattern; nothing uploaded")
            tar.add(tmpdb, str(db).lstrip("/")); n += 1
        for root in include:
            if not os.path.exists(root) or excluded(root): continue
            if os.path.islink(root): continue
            if os.path.isfile(root):
                entries = [(os.path.dirname(root), [], [os.path.basename(root)])]
            else:
                entries = os.walk(root)
            for dp, ds, fs in entries:
                ds[:] = [x for x in ds if x not in SKIP_DIRS and not x.startswith(".venv-") and not excluded(os.path.join(dp, x)) and not os.path.islink(os.path.join(dp, x))]
                for f in fs:
                    p = os.path.join(dp, f)
                    if excluded(p) or SKIP_FILE.search(p) or os.path.islink(p) or not os.path.isfile(p): continue
                    data = open(p, "rb").read()
                    hit = bad(data)
                    if hit: dropped.append(p); continue
                    tar.add(p, p.lstrip("/")); n += 1
    # final belt-and-braces: rescan the finished archive members
    with tarfile.open(out) as tar:
        for m in tar.getmembers():
            if m.isfile() and m.name != (str(db).lstrip("/") if config.get("HUB_DB") else None) and bad(tar.extractfile(m).read()): sys.exit(f"ABORT: {m.name} matched after build")
    open(out + ".dropped", "w").write("\n".join(dropped) + ("\n" if dropped else ""))
    print(out); print(f"files={n} dropped={len(dropped)}", file=sys.stderr)
    for p in dropped: print(f"  dropped (secret/IP pattern): {p}", file=sys.stderr)
if __name__ == "__main__":
    main()
