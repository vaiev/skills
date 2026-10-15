#!/usr/bin/env python3
"""Configured SSH transport: push, pull, ls, run, prune."""
import os
import posixpath
import shlex
import sys

import paramiko
from config import load

def main():
    config = load()
    required = ("PERSIST_HOST", "PERSIST_USER", "PERSIST_KEY", "PERSIST_PORT",
                "PERSIST_KNOWN_HOSTS", "PERSIST_REMOTE_DIR")
    for name in required:
        if not config.get(name):
            raise ValueError(f"{name} is required for remote operations")
    remote = config["PERSIST_REMOTE_DIR"]
    if remote.startswith("~") or ".." in remote.split("/"):
        raise ValueError("Remote directory must be absolute or relative to SSH home, without ~ or ..")
    op, *args = sys.argv[1:]
    def relative(name):
        if not name or name.startswith("/") or ".." in name.split("/"):
            raise ValueError("Expected relative remote path")
        return posixpath.join(remote, name)
    with paramiko.SSHClient() as client:
        client.load_host_keys(os.path.expanduser(config["PERSIST_KNOWN_HOSTS"]))
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        client.connect(config["PERSIST_HOST"], username=config["PERSIST_USER"],
                       key_filename=os.path.expanduser(config["PERSIST_KEY"]),
                       port=int(config["PERSIST_PORT"]), timeout=20,
                       allow_agent=False, look_for_keys=False)
        def run(command):
            _, out, err = client.exec_command(command)
            output, error = out.read().decode(), err.read().decode()
            status = out.channel.recv_exit_status()
            if status:
                raise RuntimeError(error or f"Remote command failed: {status}")
            return output
        if op == "run" and len(args) == 1:
            print(run(args[0]), end="")
            return
        with client.open_sftp() as sftp:
            if op == "push" and len(args) in (1, 2):
                target = relative(args[1]) if len(args) == 2 else remote
                run(f"mkdir -p -- {shlex.quote(target)} && chmod 700 -- {shlex.quote(target)}")
                sftp.put(args[0], posixpath.join(target, os.path.basename(args[0])))
            elif op == "pull" and len(args) == 2:
                sftp.get(relative(args[0]), args[1])
            elif op == "ls" and len(args) <= 1:
                print("\n".join(sorted(sftp.listdir(relative(args[0]) if args else remote))))
            elif op == "prune" and args in ([], ["plain"]):
                target = relative("plain") if args else remote
                suffix = ".tgz" if args else ".tgz.enc"
                prefix = "plain-" if args else "state-"
                names = sorted((n for n in sftp.listdir(target)
                                if n.startswith(prefix) and n.endswith(suffix)
                                and "/" not in n), reverse=True)
                for name in names[5:]:
                    sftp.remove(posixpath.join(target, name))
                    if args:
                        for extra in (".sha256", ".dropped"):
                            try:
                                sftp.remove(posixpath.join(target, name + extra))
                            except FileNotFoundError:
                                pass
            else:
                raise ValueError("Usage: vps.py push LOCAL [SUBDIR] | pull NAME LOCAL | ls [SUBDIR] | run CMD | prune [plain]")

if __name__ == "__main__":
    main()
