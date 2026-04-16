#!/bin/bash
# Install isambard_sbatch: adds to PATH and configures shell integration.
#
# Usage: bash install.sh
#
# This script:
# 1. Makes scripts executable
# 2. Adds ~/isambard_sbatch/bin to PATH (prepended, so it shadows /usr/bin/sbatch)
# 3. Adds a convenience alias for interactive shells
# 4. Sets default ISAMBARD_SBATCH_MAX_NODES if not already configured
# 5. Configures git hooks for development

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$INSTALL_DIR/bin"
MARKER="# isambard_sbatch"
BAD_NODES_FILE_DEFAULT="/projects/a5k/public/isambard_sbatch_bad_nodes.log"

echo "Installing isambard_sbatch from $INSTALL_DIR"

# Make scripts executable
chmod +x "$BIN_DIR/isambard_sbatch" "$BIN_DIR/sbatch"
echo "  Made scripts executable"

# Pre-create the shared bad-nodes log so appends from any team member
# inherit group-writable perms (664). Skipped if the parent dir is missing
# (e.g., /projects/a5k/public/ unmounted).
bad_dir="$(dirname "$BAD_NODES_FILE_DEFAULT")"
if [[ -d "$bad_dir" ]]; then
    if [[ ! -e "$BAD_NODES_FILE_DEFAULT" ]]; then
        if ( umask 002; : > "$BAD_NODES_FILE_DEFAULT" ) 2>/dev/null; then
            chmod 664 "$BAD_NODES_FILE_DEFAULT" 2>/dev/null || true
            echo "  Created shared bad-nodes log: $BAD_NODES_FILE_DEFAULT"
        else
            echo "  Note: could not create $BAD_NODES_FILE_DEFAULT (another user may own the dir). Skipping."
        fi
    else
        echo "  Shared bad-nodes log already exists: $BAD_NODES_FILE_DEFAULT"
    fi
else
    echo "  Note: $bad_dir does not exist. Bad-nodes log will be created on first --mark-bad."
fi

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
export ISAMBARD_SBATCH_MAX_NODES="\${ISAMBARD_SBATCH_MAX_NODES:-256}"
export ISAMBARD_SBATCH_ACCOUNT="\${ISAMBARD_SBATCH_ACCOUNT:-brics.a5k}"
export ISAMBARD_SBATCH_BAD_NODES_FILE="\${ISAMBARD_SBATCH_BAD_NODES_FILE:-$BAD_NODES_FILE_DEFAULT}"
export ISAMBARD_SBATCH_BAD_NODES_TTL="\${ISAMBARD_SBATCH_BAD_NODES_TTL:-604800}"
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
echo "  ISAMBARD_SBATCH_MAX_NODES       — max nodes for the project (default: 256)"
echo "  ISAMBARD_SBATCH_ACCOUNT         — SLURM account to check (default: brics.a5k)"
echo "  ISAMBARD_SBATCH_BAD_NODES_FILE  — shared bad-nodes log"
echo "                                    (default: $BAD_NODES_FILE_DEFAULT)"
echo "  ISAMBARD_SBATCH_BAD_NODES_TTL   — bad-node entry expiry in seconds (default: 604800 = 7 days)"
echo ""
echo "Both 'sbatch' and 'isambard_sbatch' will now enforce the node limit"
echo "and exclude any nodes listed in the shared bad-nodes log."
echo ""
echo "Mark a node as bad:    isambard_sbatch --mark-bad <node> [reason]"
echo "List active bad nodes: isambard_sbatch --list-bad"
