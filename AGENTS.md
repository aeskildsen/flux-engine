# AGENTS.md

Guidance for coding agents in this repository. `README.md` is the reference for the layout, the build, the tests and the release. Read it first. `docs/add-a-ugen.md` shows how a UGen gets into the engine and into Flux.

## Environment

- This repository has no Nix dev shell (as opposed to other repos in the flux family). Run the build and test scripts in the toolchain image: `scripts/in-image.sh <command>` (needs podman), or use the `just` recipes (`just --list`). `just check` is the fast check.
- The tests of `prepare.py` and `track.py` need only Python 3.11 or later: `python3 -m unittest discover -s test -p 'test_*.py'`.

## Submodules

- After a build, `git status` shows the `supersonic` and `mi-UGens` submodules as changed. `scripts/prepare.py` applied the patches in `patches/` to their working trees. This is correct. Do not commit or reset these changes.
- `git pull` does not move the submodules. After a pull that changed a submodule pin, reverse the patches and update the submodules before a build, `track.py` or `package.py`:

  ```sh
  git -C supersonic apply --reverse ../patches/supersonic-extra-plugins.patch
  git submodule update --init --recursive
  ```

  A stale checkout gives a wrong version in `engine-version.env` (`track.py` reads it from `supersonic/package.json`), and `package.py` can package an old web build with the new version numbers.

## Releases

- Do not make a release package on your machine. A release comes from `.github/workflows/release.yml` on a tag `v<version>`. The order is in the "Release" section of the README.
- A tag push is outward-facing. Push a tag only when the user tells you to.
- A green Track pull request does not test Flux. Before Flux bumps to a new engine, run Flux's `pnpm test:container`.
