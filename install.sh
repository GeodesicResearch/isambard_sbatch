#!/bin/bash
# Install isambard_sbatch: adds to PATH and configures shell integration.
#
# Usage: bash install.sh
#
# This script:
# 1. Makes scripts executable
# 2. Adds ~/isambard_sbatch/bin to PATH (prepended, so it shadows /usr/bin/sbatch)
# 3. Adds a convenience alias for interactive shells
# 4. Sets default SAFE_SBATCH_MAX_NODES if not already configured
# 5. Configures git hooks for development

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$INSTALL_DIR/bin"
MARKER="# isambard_sbatch"

echo "Installing isambard_sbatch from $INSTALL_DIR"

# Make scripts executable
chmod +x "$BIN_DIR/isambard_sbatch" "$BIN_DIR/sbatch"
echo "  Made scripts executable"

# Configure git hooks if this is a git repo
if [[ -d "$INSTALL_DIR/.git" && -d "$INSTALL_DIR/.githooks" ]]; then
    git -C "$INSTALL_DIR" config core.hooksPath .githooks
    echo "  Configured git hooks"
fi

# Detect shell config file
SHELL_RC=""
if [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
    SHELL_RC="$HOME/.bash_profile"
elif [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

# Check if already installed
if grep -q "$MARKER" "$SHELL_RC" 2>/dev/null; then
    echo "  Already installed in $SHELL_RC — skipping"
else
    cat >> "$SHELL_RC" << EOF

$MARKER — begin
export PATH="$BIN_DIR:\$PATH"
alias sbatch='isambard_sbatch'
export SAFE_SBATCH_MAX_NODES="\${SAFE_SBATCH_MAX_NODES:-99}"
export SAFE_SBATCH_ACCOUNT="\${SAFE_SBATCH_ACCOUNT:-brics.a5k}"
$MARKER — end
EOF
    echo "  Added to $SHELL_RC"
fi

echo ""
echo "Installation complete. To activate now, run:"
echo ""
echo "  source $SHELL_RC"
echo ""
echo "Configuration (set in your shell or $SHELL_RC):"
echo "  SAFE_SBATCH_MAX_NODES  — max nodes for the project (default: 99)"
echo "  SAFE_SBATCH_ACCOUNT    — SLURM account to check (default: brics.a5k)"
echo ""
echo "Both 'sbatch' and 'isambard_sbatch' will now enforce the node limit."
