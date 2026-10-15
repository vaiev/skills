"""Shared, non-executable KEY=VALUE configuration with environment precedence."""
import os
from pathlib import Path
import shlex

NAMES = ("PERSIST_HOST PERSIST_USER PERSIST_KEY PERSIST_PORT PERSIST_KNOWN_HOSTS "
         "PERSIST_REMOTE_DIR PERSIST_STORE PERSIST_PY PERSIST_INCLUDE HUB_DB").split()

def load():
    values = {}
    path = Path(os.environ.get("PERSIST_CONFIG", "~/.config/lead-kit/persist.env")).expanduser()
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, sep, value = line.partition("=")
            if not sep or name.strip() not in NAMES:
                raise ValueError("Unsupported configuration entry")
            words = shlex.split(value, comments=True)
            values[name.strip()] = " ".join(words)
    values.update({name: os.environ[name] for name in NAMES if name in os.environ})
    if not values.get("PERSIST_STORE"):
        raise ValueError("PERSIST_STORE is required")
    return values

if __name__ == "__main__":
    for name, value in load().items():
        print(f"export {name}={shlex.quote(value)}")
