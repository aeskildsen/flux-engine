#!/usr/bin/env python3
"""Make the engine package from a web build.

The package is what Flux takes from flux-engine. It is a folder and a tarball
of that folder:

    build/package/flux-engine-<version>/
        dist/        the web engine: client, workers, wasm (build/web/dist)
        classes/     the SuperCollider class files of the UGens, for sclang
        BUILDINFO    the kind of build, the version and the source commits
        LICENSE      AGPL-3.0-or-later
        NOTICE.md    the licences and where the corresponding source is
        package.json the name and version, so that a package manager can
                     install the tarball from its URL (it is not on npm)
    build/package/flux-engine-<version>.tgz (and .tgz.sha256)
    build/package/latest -> flux-engine-<version>

The version comes from engine-version.env. A development build gets the
suffix "-dev" and kind=development in BUILDINFO: that is, a build with the
isospin UGens from a working copy (ISOSPIN_DIR), or a build from a working
tree with changes. Do not release it.

Run scripts/build-web.sh first. Needs Python 3.11 or later and git.

Usage: scripts/package.py
"""
import gzip
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "build" / "web" / "dist"
ISOSPIN = ROOT / "build" / "isospin"
OUT = ROOT / "build" / "package"

NOTICE = """\
# flux-engine {version}

The SuperSonic engine (scsynth in the browser) with the flux-engine UGens.
Made by flux-engine scripts/package.py. BUILDINFO gives the source commits.

## Contents

- `dist/`: the web engine (client, workers, `wasm/scsynth-nrt.wasm`). Serve
  it as static files; give its URL to the SuperSonic client as `baseURL` and
  as `coreBaseURL`.
- `classes/`: the SuperCollider class files of the UGens. Put them on the
  sclang class path to make SynthDefs that use the UGens.

## UGens

{ugens}

## Licences and source

- As a whole: AGPL-3.0-or-later (see LICENSE), the same as SuperSonic.
- The isospin UGens: AGPL-3.0-or-later, with parts under GPL-3.0-or-later and
  LGPL-2.1-or-later; see the NOTICE.md of the isospin release {isospin}.
- The corresponding source is https://github.com/aeskildsen/flux-engine at
  commit {commit}, with its submodules and the isospin release that
  ugens.toml names.
"""


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.run(["git", "-C", str(cwd), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def read_env(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def pack(src: Path, tarball: Path, top: str) -> None:
    """Writes a tarball with fixed owners, modes and times, so that the same
    input gives the same bytes."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        def add(name: str, path: Path | None) -> None:
            info = tarfile.TarInfo(name)
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            if path is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                tar.addfile(info)
            else:
                data = path.read_bytes()
                info.mode = 0o644
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))

        add(top, None)
        for p in sorted(src.rglob("*")):
            add(f"{top}/{p.relative_to(src).as_posix()}", None if p.is_dir() else p)
    with open(tarball, "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0) as gz:
            gz.write(buf.getvalue())


def main() -> None:
    wasm = DIST / "wasm" / "scsynth-nrt.wasm"
    if not wasm.is_file():
        sys.exit(f"package: no {wasm} (run scripts/build-web.sh)")
    sources = list((ISOSPIN / "src").glob("*.cpp"))
    if any(p.stat().st_mtime > wasm.stat().st_mtime for p in sources):
        sys.exit("package: the UGen sources are newer than the web build (run scripts/build-web.sh)")
    classes = sorted((ISOSPIN / "classes").glob("*.sc"))
    if not classes:
        sys.exit(f"package: no class files in {ISOSPIN / 'classes'} "
                 "(the isospin release or working copy has no classes/ folder)")

    version = read_env(ROOT / "engine-version.env")["FLUX_ENGINE_VERSION"]
    supersonic = json.loads((ROOT / "supersonic" / "package.json").read_text())["version"]
    if not version.startswith(f"{supersonic}-flux."):
        sys.exit(f"package: engine-version.env has {version}, "
                 f"but SuperSonic is {supersonic} (expected {supersonic}-flux.<n>)")

    isospin = read_env(ISOSPIN / "BUILDINFO")
    commit = git("rev-parse", "HEAD")
    # The SuperSonic submodule is changed by the patches; that is expected.
    dirty = bool(git("status", "--porcelain", "--ignore-submodules=dirty"))
    development = isospin.get("kind") != "release" or dirty
    if dirty:
        commit += "-dirty"
    if development:
        version += "-dev"

    name = f"flux-engine-{version}"
    folder = OUT / name
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    shutil.copytree(DIST, folder / "dist")
    (folder / "classes").mkdir()
    for p in classes:
        shutil.copyfile(p, folder / "classes" / p.name)
    (folder / "BUILDINFO").write_text(
        f"kind={'development' if development else 'release'}\n"
        f"version={version}\n"
        f"commit={commit}\n"
        f"supersonic={supersonic} {git('rev-parse', 'HEAD', cwd=ROOT / 'supersonic')}\n"
        f"isospin={isospin.get('version')} {isospin.get('kind')} {isospin.get('commit')}\n")
    shutil.copyfile(ROOT / "LICENSE", folder / "LICENSE")
    ugens = "\n".join(f"- `{p.stem}`" for p in classes)
    (folder / "NOTICE.md").write_text(NOTICE.format(
        version=version, ugens=ugens, isospin=isospin.get("version"), commit=commit))
    manifest = {
        "name": "flux-engine",
        "version": version,
        "description": "SuperSonic (scsynth in the browser) with the flux-engine UGens: "
                       "the web engine in dist/, the SuperCollider class files in classes/",
        "license": "AGPL-3.0-or-later",
        "repository": "github:aeskildsen/flux-engine",
        # Not for the npm registry: the package is a GitHub release file.
        "private": True,
    }
    (folder / "package.json").write_text(json.dumps(manifest, indent=2) + "\n")

    tarball = OUT / f"{name}.tgz"
    pack(folder, tarball, name)
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    (OUT / f"{name}.tgz.sha256").write_text(f"{digest}  {tarball.name}\n")

    latest = OUT / "latest"
    latest.unlink(missing_ok=True)
    latest.symlink_to(name)

    print(f"package: {folder}")
    print(f"package: {tarball}")
    print(f"sha256 {digest}")
    if development:
        print("package: WARNING: development build; do not release it", file=sys.stderr)


if __name__ == "__main__":
    main()
