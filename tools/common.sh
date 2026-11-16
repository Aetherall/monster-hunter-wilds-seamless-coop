# Sourced by the tools: the game's paths, and the flake's dev shell.
GAME="${MHW_DIR:-$HOME/.local/share/Steam/steamapps/common/MonsterHunterWilds}"
AUTORUN="$GAME/reframework/autorun"

# Runs the calling tool again inside the flake's dev shell when one of the
# commands it needs is not on PATH.
#   in_dev_shell luac luacheck -- "$@"
in_dev_shell() {
    local missing=
    while [ "$1" != "--" ]; do command -v "$1" >/dev/null || missing=1; shift; done
    shift
    [ -z "$missing" ] || exec nix develop -c "$0" "$@"
}
