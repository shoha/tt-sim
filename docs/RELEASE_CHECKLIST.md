# Release checklist (DRAFT, nothing is cut)

**Cutting a version needs the owner's OK.** This page prepares a release; it does not make
one. No version bump, tag, release script or tag push has been done, and none may be done
until the owner says so (owner, 2026-10-30: "Prepare release notes and a checklist, no tag").
Source of the steps: `AGENTS.md` "Cutting a release", `.github/workflows/build.yml`,
`docs/CODE_SIGNING.md`. Notes to publish: `docs/RELEASE_NOTES_DRAFT.md`.

Marker key: OWNER = the owner decides or approves; AGENT = a session may do it once the owner
has said go; CI = the workflow does it.

## 0. Facts as of 2026-10-31

| Item | Current value |
|------|---------------|
| Last release tag | `v0.3.0` (2026-10-25, commit 05bd382; assets TTSim-Windows/macOS/Linux zips) |
| Commits on main since it | 173 |
| `project.godot` `config/version` | `0.3.1` (bumped right after v0.3.0, as AGENTS.md says) |
| Per-build prereleases | `v0.3.1-build.<sha>` on every main push (latest `72f6ae2`, 2026-10-30) |
| Core library `version` | `1.0.0-dev` in `libraries/core/library.json` (same in the core-library source) |
| Core library `contract` | `1` |
| Core library `license` | `CC BY 4.0` |
| `export_presets.cfg` version fields | `application/short_version`, `application/version`, `file_version`, `product_version` are all empty strings: nothing to bump there |
| Game licence file | none at the repository root (only `THIRD_PARTY_LICENSES.md`) |

Where the updater's two numbers come from (the log line "Current version 0.3.1, Latest 0.3.0"):
Current is `UpdateVersion.get_current()`, which reads `application/config/version`, and CI
rewrites that to `<version>-build.<sha>` in a build (so a build of main is "0.3.1-build.x").
Latest is the newest non-draft release from the GitHub releases API for `shoha/tt-sim`
(`UpdateManager`); prereleases count only when the player turns on Check prereleases, so
today Latest is v0.3.0. After a v0.3.1 release exists, Latest becomes 0.3.1.

## 1. Preconditions (AGENT runs, OWNER confirms green)

All on `main`, working tree clean, nothing unpushed, no sharded gates running at once.

- [ ] tt-sim gate, from `D:/dev/tabletop/tt-sim` (gdlint reads `.gdlintrc` from the current
      directory only):
      `gdlint autoloads/ scenes/ utils/ resources/ tests/unit/`
      `godot --headless --path D:/dev/tabletop/tt-sim --quit-after 1`
      `godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/gut_shards.gd`
- [ ] procgen module: `pwsh D:/dev/tabletop/procgen/tools/procgen.ps1 test`, and its pins in
      tt-sim and plantgen are the intended commit (the submodule commit CI fetches must be
      pushed to its remote).
- [ ] plantgen: `gdlint core export ui tools tests shaders packaging procgen gen_ui` (from
      `D:/dev/plantgen`), the compile check, and
      `godot --headless --path D:/dev/plantgen --script res://tests/run_tests.gd`.
- [ ] core library: `godot --headless --path D:/dev/plantgen --script res://tools/export_library_cli.gd -- --library D:/dev/tabletop/core-library/library.json --check 1`,
      then confirm `tt-sim/libraries/core/` matches the source (hashes via
      `tools/recompute_library_hashes.gd`).
- [ ] structgen: `godot --headless --path D:/dev/tabletop/structgen --script res://tests/run_tests.gd`
      and `gdlint core ui tests procgen gen_ui` (only if structgen is part of the release).
- [ ] The latest `main` CI run is green end to end: `gh run list --repo shoha/tt-sim --limit 5`,
      read failures with `gh run view <id> --log-failed` (never save whole logs).
      The determinism workflow (`determinism.yml`) is green on its last run.
- [ ] `PROCGEN_READ_TOKEN` is not expired (a missing or expired token fails the procgen
      fetch in every job); the signing and Steam secrets are valid (see `docs/CODE_SIGNING.md`
      rotation notes).
- [ ] Windows, macOS and Linux exports of the latest prerelease start and reach the main
      menu (a tester or the owner). The `testing` Steam branch has the same build.

## 2. Version decision (OWNER)

- [x] Release number: **0.4.0** (owner, 2026-10-31, decisions page). This records the
      number only: `project.godot` still says 0.3.1, and it changes in step 5.2 after the
      owner's "go". Same-version gate: players must have exactly the host's version to join,
      so every player has to update.
- [x] Core library version: **1.0.0** with this release (owner, 2026-10-31). Not applied yet.
      Apply at the cut, with the version bump: edit `version` in the core-library source
      `library.json`, rebuild or re-hash, copy to `tt-sim/libraries/core/library.json`,
      check `core ^1.0` dependency ranges in tests and docs still hold, and keep `contract` at
      `1` (the contract number only moves with a format change). Then drop the "still
      1.0.0-dev" line from the notes' known issues.

## 3. Licences and credits (OWNER confirms, AGENT checks)

- [ ] Core library licence is CC BY 4.0: `LICENSE.md`, `NOTICE.md` and `library.json`
      (`"license": "CC BY 4.0"`) exist in the core-library repository and in
      `tt-sim/libraries/core/` (LICENSE.md and NOTICE.md are byte-identical, checked 2026-10-31).
      Suggested credit line, verbatim: "Core library by Hannah Shore, CC BY 4.0".
- [ ] The app shows it: the collections manager's library detail page prints the library's
      licence (`scenes/ui/library_manager/library_detail.gd`, through `LibraryNames.license_text`).
      Check by eye on a build that Core reads "CC BY 4.0".
- [x] `docs/systems/library.md` no longer calls core's licence a placeholder (fixed in
      `1802e34b`, 2026-10-31).
- [ ] Third-party attributions that exist today: `THIRD_PARTY_LICENSES.md` (Tabler Icons, MIT;
      ambientCG sky HDRIs, CC0, with a source table). Owner, 2026-10-31: run the audit now.
      A pass over the shipped fonts, audio (`docs/SOUND_EFFECTS.md`), GodotSteam, godot-cpp
      and the Godot engine notice, so that each has an entry. Status 2026-10-31: pass done,
      findings below, fixes marked. The core-library `NOTICE.md` says third-party material:
      none.
      - Covered already: Tabler Icons (MIT), ambientCG skies (CC0), every recorded sound
        (CC0, with sources), GUT, Icon Explorer, theme_gen, theme_gen_save_sync (each has its
        licence file), GodotSteam (`addons/godotsteam/license.md`, MIT), FastNoiseLite and
        godot-cpp (MIT).
      - Fixed in `THIRD_PARTY_LICENSES.md`: a Fonts section for Fraunces (OFL 1.1, text
        shipped) and Inter (OFL 1.1).
      - GAP, AGENT can fix: no OFL text file for Inter beside the font. The OFL asks that the
        licence travel with the font; take the file from the Inter release the TTF came from.
      - GAP, OWNER or AGENT: `addons/DragAndDrop3D` (author "DevDrache" in plugin.cfg) and
        `addons/brackeys_particle_controls` carry no licence file and the table only says
        "see the directory". Find each upstream licence and copy it in, or replace the addon.
      - GAP, OWNER: the 36 PBR surface sets in `core` (`surfaces/`, 26 ground, 7 built, 3 cliff)
        have no recorded provenance in either repository. `NOTICE.md` claims no third-party
        material, and CC BY 4.0 cannot be applied to textures you do not hold. If they came
        from a CC0 source (ambientCG, Poly Haven) say which in `NOTICE.md` and here; if they
        were made in house, say so; if neither, they must not ship under CC BY.
      - GAP, AGENT can fix: the game has no Licences screen. The Godot engine's MIT notice and
        its third-party notices should be reachable in the shipped game (the engine exposes
        `Engine.get_license_text()` and `Engine.get_license_info()`), or shipped as a file in
        the export. Valve's `steam_api64.dll` also needs its Steamworks SDK redistribution
        terms noted.
- [ ] The game's own licence: **all rights reserved** (owner, 2026-10-31). Still to do, once
      the audit is in: a short `LICENSE` file at the tt-sim root (copyright holder and year,
      all rights reserved, and a pointer that the built-in Core library is CC BY 4.0 under its
      own terms) plus one README line. The repository is public, so the file also tells
      readers that viewing the source is not a licence to reuse it.

## 4. Notes and changelog (OWNER approves)

- [ ] Owner reviews and edits `docs/RELEASE_NOTES_DRAFT.md`; resolve its TODO items; remove
      the DRAFT banner only on approval. The repository has no CHANGELOG file; the GitHub
      release body is the changelog.
- [ ] The release body is created by CI as "Release <version>" plus the commit link. After
      the release exists, paste the approved notes into it:
      `gh release edit v<version> --repo shoha/tt-sim --notes-file <approved notes>`
      (AGENT, on the owner's word).
- [ ] `docs/` is excluded from the shipped game by the export filter, so the draft file does
      not ship.

## 5. Cutting (OWNER approves each; nothing here has been done)

Names: the release tag is `v<version>` (for example `v0.3.1`); the per-build tags
`v<version>-build.<sha>` are CI's own and are never made by hand.

1. [ ] OWNER: "go for <version>".
2. [ ] AGENT: set `project.godot` `config/version` to the release version (chosen: `0.4.0`;
       it is `0.3.1` now), together with the core library `1.0.0` change from section 2, commit,
       push, and let that main run finish green.
3. [ ] AGENT: `git tag v<version>` on that exact commit, then `git push origin v<version>`.
       CI fails the tag build if the tag differs from `project.godot` (the "Inject version"
       step compares them).
4. [ ] CI on the tag (`build.yml`): native libraries, tests and lint, parity, three exports,
       Windows signing (Azure Artifact Signing: the exe, the native scatter DLL and the
       GodotSteam DLL; Valve's `steam_api64.dll` keeps Valve's signature), macOS signing and
       notarization with a stapled ticket, then Create Release (a full release, not a
       prerelease, with TTSim-Windows, TTSim-macOS and TTSim-Linux zips), and Deploy to Steam.
       Signing runs only on tag builds; main-push builds are unsigned.
5. [ ] Steam: the deploy goes to the `testing` branch (`releaseBranch: testing`), the same
       as every main push. OWNER sets the build live on the default branch in Steamworks by
       hand; the pipeline never does.
6. [ ] AGENT, immediately after the tag: bump `project.godot` to the next version (for a
       0.4.0 release, 0.4.1) and push, so later builds are prereleases of the next number.
       OWNER approves that number too.

## 6. Post-release checks (AGENT does, OWNER reads)

- [ ] `gh release view v<version> --repo shoha/tt-sim` shows three assets and is not a
      prerelease; the tag run is green (`gh run watch <id> --exit-status`).
- [ ] Windows download: the exe's signature verifies; macOS: `spctl --assess` accepts the
      app and the ticket is stapled; Linux starts.
- [ ] Updater: an older build (v0.3.0) with prereleases off reports the new version as
      Latest, downloads it and installs. A build of main reports Current as
      `<version>-build.<sha>` and does not offer an older release.
- [ ] Join smoke test over ENet (host and client on the release builds, a map with
      buildings and a street: the client waits for the map, then plays), and over Steam
      (lobby, version gate between equal versions, a version mismatch is refused with a clear
      message). The Steam map-download path with structures passed on 2026-10-31 (host plus the
      boxed alt-account client, four buildings, fingerprints equal; `docs/NETWORKING.md`
      "Automated runs"). Run the same pair on the release build before announcing.
- [ ] Core library in the release build: Core shows in the collections manager as built in,
      with its CC BY 4.0 licence; the Building tool palette lists 100 buildings and the
      Street tool 11 kinds.
- [ ] Steam `testing` branch has the release build before the owner sets it live.

## 7. Rollback

- Before the tag is pushed: nothing to undo; stop.
- Tag pushed, CI still running: cancel the run (`gh run cancel <id>`); delete the tag with
  `git push origin :refs/tags/v<version>` and `git tag -d v<version>` (OWNER approves).
- Release published but bad: mark it as a prerelease or delete it
  (`gh release edit v<version> --prerelease` / `gh release delete v<version>`), so the
  updater stops offering it; Steam: leave the default branch on the previous build (the
  pipeline only ever touches `testing`) or set the previous build live again in Steamworks.
- Fix forward: branch from the release tag, fix, and tag a patch release (AGENTS.md
  "Hotfixes", for example `v0.3.1.1`), then merge the fix back to main. Players on a bad
  version cannot join players on a fixed one (same-version gate), so a fix needs a
  prompt update path.
- Never delete or rewrite published tags without the owner's OK.
