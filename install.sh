#!/usr/bin/env bash
# Register the Reworkio tools with the rw hub and (optionally) put them on PATH.
#   ./install.sh            write ~/.rw/tools/<tool>/manifest.zsh for each tool (skips existing)
#   ./install.sh --link     also symlink each tool into ~/.local/bin
#   ./install.sh --force    overwrite existing manifests
#   ./install.sh --uninstall  remove the manifests and symlinks this script created
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RW_HOME=${RW_HOME:-$HOME/.rw}
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
TOOLS=(proofpack scopesmith handoff envguard logbook clientcast pulse histbook datamorph)
LINK=0 FORCE=0 UNINSTALL=0
for arg in "$@"; do
  case $arg in
    --link) LINK=1 ;;
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
  echo "install: python3 3.8+ is required" >&2; exit 1
fi

if (( UNINSTALL )); then
  for t in "${TOOLS[@]}"; do
    m=$RW_HOME/tools/$t/manifest.zsh
    if [[ -f $m ]] && grep -q "RW_ROOT=$HERE/$t\$" "$m"; then rm -f "$m"; rmdir "$RW_HOME/tools/$t" 2>/dev/null || true; echo "removed $m"; fi
    l=$BIN_DIR/$t
    if [[ -L $l && $(readlink "$l") == "$HERE/$t/bin/$t" ]]; then rm -f "$l"; echo "removed $l"; fi
  done
  exit 0
fi

for t in "${TOOLS[@]}"; do
  chmod +x "$HERE/$t/bin/$t"
  dest=$RW_HOME/tools/$t/manifest.zsh
  mkdir -p "$(dirname "$dest")"
  if [[ -f $dest && $FORCE == 0 ]]; then
    echo "skip   $t (manifest exists; --force to overwrite)"
  else
    sed "s#@ROOT@#$HERE/$t#" "$HERE/$t/manifest.zsh.in" > "$dest"
    echo "ok     $t -> $dest"
  fi
  if (( LINK )); then
    mkdir -p "$BIN_DIR"
    ln -sfn "$HERE/$t/bin/$t" "$BIN_DIR/$t"
  fi
done

if (( LINK )); then
  echo "linked tools into $BIN_DIR"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: add $BIN_DIR to PATH, e.g. path=($BIN_DIR \$path) in ~/.zshrc" ;; esac
fi
mkdir -p "$RW_HOME/combos"
for c in "$HERE"/examples/combos/*.zsh; do
  [[ -f $c ]] || continue
  name=$(basename "$c")
  if [[ ! -f $RW_HOME/combos/$name ]]; then cp "$c" "$RW_HOME/combos/$name"; echo "combo  $name"; fi
done
echo "done. In zsh: exec zsh && rw ls"
