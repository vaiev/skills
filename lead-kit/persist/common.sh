# Shared configuration loader. Python parses config as data, never shell code.
K=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_EXPORTS=$(python3 "$K/config.py")
eval "$CONFIG_EXPORTS"
STORE=$PERSIST_STORE
PY=${PERSIST_PY:-python3}
