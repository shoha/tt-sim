#!/usr/bin/env python3
"""
Install git hooks for the tt-sim project.

Creates a symlink (or copy on Windows) from .git/hooks/pre-commit
to tools/hooks/pre-commit so the hook is version-controlled.

Usage:
    python tools/hooks/install.py
"""

import os
import platform
import shutil
import stat
import sys


def main():
    # Find project root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))
    git_hooks_dir = os.path.join(project_root, ".git", "hooks")

    if not os.path.isdir(git_hooks_dir):
        print("Error: .git/hooks directory not found.", file=sys.stderr)
        print("Are you running this from the project root?", file=sys.stderr)
        sys.exit(1)

    hook_source = os.path.join(script_dir, "pre-commit")
    hook_dest = os.path.join(git_hooks_dir, "pre-commit")

    if not os.path.isfile(hook_source):
        print(f"Error: Hook source not found: {hook_source}", file=sys.stderr)
        sys.exit(1)

    # Remove existing hook if present
    if os.path.exists(hook_dest) or os.path.islink(hook_dest):
        os.remove(hook_dest)
        print(f"Removed existing hook: {hook_dest}")

    # Git runs hooks with cwd = repo root, so paths must be relative to project_root.
    rel_from_root = os.path.relpath(hook_source, project_root).replace("\\", "/")

    if platform.system() == "Windows":
        # Write a tiny shell script that git for Windows (bash) can run.
        # Windows sometimes shadows python/python3/py ALL with a non-functional Microsoft
        # Store alias stub ahead of a real install on PATH, so `command -v` alone isn't
        # enough -- actually invoke each candidate and check it succeeds. If none work,
        # skip (exit 0) rather than fail the commit: audio normalization is a nice-to-have,
        # not something that should ever block a commit when the tooling is unavailable.
        with open(hook_dest, "w", newline="\n") as f:
            f.write("#!/bin/sh\n")
            f.write("PY=\"\"\n")
            f.write("for candidate in python3 python py; do\n")
            f.write('    if "$candidate" --version >/dev/null 2>&1; then\n')
            f.write('        PY="$candidate"\n')
            f.write("        break\n")
            f.write("    fi\n")
            f.write("done\n")
            f.write('if [ -z "$PY" ]; then\n')
            f.write(
                '    echo "Warning: no working Python interpreter found on PATH --'
                ' skipping pre-commit hook (audio normalization)." >&2\n'
            )
            f.write("    exit 0\n")
            f.write("fi\n")
            f.write(f'"$PY" "{rel_from_root}" "$@"\n')
    else:
        # Unix: symlink (must be relative to .git/hooks/ for the symlink itself)
        rel_for_symlink = os.path.relpath(hook_source, git_hooks_dir)
        os.symlink(rel_for_symlink, hook_dest)

    # Ensure executable
    st = os.stat(hook_dest)
    os.chmod(hook_dest, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    print(f"Installed pre-commit hook: {hook_dest}")
    print("Audio files in assets/audio/ will be auto-normalized on commit.")


if __name__ == "__main__":
    main()
