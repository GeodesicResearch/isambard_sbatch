#!/bin/bash
# Uninstall isambard_sbatch: removes PATH and alias from shell config.
#
# Usage: bash uninstall.sh

set -euo pipefail

MARKER="# isambard_sbatch"

# Detect shell config file
SHELL_RC=""
for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]] && grep -q "$MARKER" "$rc" 2>/dev/null; then
        SHELL_RC="$rc"
        break
    fi
done

if [[ -z "$SHELL_RC" ]]; then
    echo "isambard_sbatch not found in any shell config file — nothing to uninstall"
    exit 0
fi

echo "Removing isambard_sbatch from $SHELL_RC"

# Remove the block between begin and end markers
sed -i "/$MARKER — begin/,/$MARKER — end/d" "$SHELL_RC"

echo ""
echo "Uninstalled. Restart your shell or run:"
echo ""
echo "  source $SHELL_RC"
echo ""
echo "The ~/isambard_sbatch directory is still present. To fully remove:"
echo "  rm -rf ~/isambard_sbatch"
