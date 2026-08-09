---
name: cut-release
description: Use when asked to cut/ship/push a new TTSim release or Steam release, or to bump the version for a release. Encodes the versioning + tag + CI + Steam deploy process so it doesn't need to be re-derived from AGENTS.md/docs each time.
---

# Cutting a TTSim Release

## The process, condensed

`project.godot`'s `config/version` is the single source of truth. It always
holds the version being worked *toward*, not the one last shipped.

1. `scripts/cut-release.ps1` (run without `-Push` first) does all of this locally:
   - Verifies the tree is clean, on `main`, and tags are fetched.
   - Runs the full GUT test suite -- aborts on any failure.
   - Bumps `config/version` to the release version (next patch by default, or
     pass `-Version X.Y.Z` explicitly), commits `"Bump version to X.Y.Z"`,
     tags `vX.Y.Z`.
   - **Immediately** bumps `config/version` again to the *next* dev version
     and commits that too, so subsequent untagged CI builds on `main` version
     themselves correctly as `<next>-build.<sha>` pre-releases. This step has
     been missed by hand at least twice (v0.1.10 and v0.1.11 both shipped
     without it) -- that's the whole reason this script exists instead of
     doing it manually again.
2. Pushing the tag (`-Push`, or manually: `git push origin main && git push origin vX.Y.Z`)
   triggers `.github/workflows/build.yml` automatically: test → export
   Windows/macOS/Linux → code-sign (Azure) + notarize (Apple) → create a
   GitHub Release → deploy to Steam's `testing` branch. All credentials
   already exist as GitHub Actions secrets -- nothing to supply.
3. **Promoting the Steam build from `testing` to live (`default`) is a manual
   step in the Steamworks partner web UI.** Neither CI nor the script does
   this, and it can't be automated from here.
4. Hotfixes: branch from the release tag, fix, tag a patch release (e.g.
   `v0.1.2.1`), merge back to `main` if applicable. `cut-release.ps1` doesn't
   cover this path -- it assumes a normal patch bump off `main`.

## What to do when asked to cut a release

1. Run `scripts/cut-release.ps1` (no `-Push`) via the PowerShell tool. It stops
   after the local commits/tag -- nothing is pushed yet, so this step is safe
   to run without asking first.
2. Show the resulting commits/tag/version to the user.
3. **Ask before pushing** (global CLAUDE.md: always confirm before pushing to
   remote) -- pushing the tag triggers real signing/notarization/Steam
   deploy against production credentials, which is a hard-to-reverse,
   externally-visible action. Confirm the version number and get explicit
   go-ahead.
4. If confirmed, either re-run with `-Push`, or run the two `git push`
   commands the script printed.
5. After pushing, check the workflow run (`gh run list` / `gh run view`) and
   report status back once it completes -- the pipeline (build, sign,
   notarize, release, Steam deploy) typically takes several minutes.
6. Remind the user that the Steam `testing` → live promotion is still a
   manual step in the Steamworks web UI, even after CI succeeds.

## Reference

Full background (why each credential exists, rotation procedures, Steam
depot IDs, GitHub Releases self-update path) lives in:
- `AGENTS.md` — "Cutting a release" / "Hotfixes" bullets, CI/CD section
- `docs/CODE_SIGNING.md` — signing secrets and rotation
- `docs/plans/2026-02-22-versioning-strategy-design.md`
- `docs/plans/2026-04-05-steampipe-distribution-design.md` / `-distribution.md`
- `.github/workflows/build.yml` — the actual CI pipeline
