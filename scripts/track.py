#!/usr/bin/env python3
"""Look for new releases of SuperSonic and isospin, and make one bump.

The tracking workflow (.github/workflows/track.yml) runs this script once a
day. For each target that has a newer release, the script changes the
working tree:

  supersonic  The SuperSonic submodule goes to the newest release tag
              (vX.Y.Z only; no pre-releases, no branches), with its own
              submodules.
  isospin     The [isospin] entry of ugens.toml gets the version and the
              SHA-256 of the newest isospin release.

Then engine-version.env gets one new version for all the changes:
<X.Y.Z>-flux.1 when SuperSonic is at a new version X.Y.Z, else the flux.<n>
part goes up by one. Thus a SuperSonic and an isospin release on the same
day give one bump, with one branch and one pull request.

With no target, the script looks at all targets.

The script does not commit. It writes the result for GitHub Actions to
stdout, one key=value line each: found (true or false), version, branch,
pr-title and issue-title. It writes the text of the pull request or issue to
the --body file. Log lines go to stderr.

--tag <tag> takes that SuperSonic tag instead of the newest, for a test run
(for example a tag that is known to break the hook patch).

Needs Python 3.11 or later (standard library only), git and network access.

Usage: scripts/track.py [supersonic] [isospin] --body <file> [--tag <tag>]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
SUPERSONIC = ROOT / "supersonic"
HOOK_PATCH = ROOT / "patches" / "supersonic-extra-plugins.patch"
ENGINE_VERSION_FILE = ROOT / "engine-version.env"
UGENS_FILE = ROOT / "ugens.toml"

SUPERSONIC_REPO = "https://github.com/samaaron/supersonic"
ISOSPIN_API = "https://api.github.com/repos/aeskildsen/isospin/releases/latest"
ISOSPIN_FILE = "isospin-sc-static-{version}.tar.gz"
ISOSPIN_SHA256_URL = ("https://github.com/aeskildsen/isospin/releases/download/"
                      "v{version}/isospin-sc-static-{version}.tar.gz.sha256")

# SuperSonic pins its web toolchain (Emscripten, Rust nightly,
# wasm-bindgen-cli) in these files. The toolchain image (Containerfile) must
# have the same versions.
SUPERSONIC_TOOLCHAIN_FILES = ["Dockerfile"]

RELEASE_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
ENGINE_VERSION = re.compile(r"^(\d+\.\d+\.\d+)-flux\.(\d+)$")


class TrackError(Exception):
    """A problem that stops the script, with a message for the log."""


def log(message: str) -> None:
    print(f"track: {message}", file=sys.stderr)


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def is_newer(version: str, than: str) -> bool:
    return version_key(version) > version_key(than)


def newest_tag(tags: list[str]) -> str | None:
    """The release tag (vX.Y.Z) with the highest version, or None."""
    releases = [t for t in tags if RELEASE_TAG.match(t)]
    return max(releases, key=lambda t: version_key(t[1:]), default=None)


def tags_from_ls_remote(output: str) -> list[str]:
    """The tag names in the output of git ls-remote --tags (without the
    peeled ^{} lines)."""
    tags = []
    for line in output.splitlines():
        ref = line.split("\t")[-1]
        if ref.startswith("refs/tags/") and not ref.endswith("^{}"):
            tags.append(ref.removeprefix("refs/tags/"))
    return tags


def engine_version(text: str) -> str:
    match = re.search(r"^FLUX_ENGINE_VERSION=(\S+)$", text, re.MULTILINE)
    if not match:
        raise TrackError("engine-version.env has no FLUX_ENGINE_VERSION line")
    return match.group(1)


def set_engine_version(text: str, version: str) -> str:
    return re.sub(r"^FLUX_ENGINE_VERSION=\S+$", f"FLUX_ENGINE_VERSION={version}",
                  text, count=1, flags=re.MULTILINE)


def next_engine_version(current: str, supersonic: str) -> str:
    """The engine version after a bump: <supersonic>-flux.1 for a new
    SuperSonic version, else flux.<n + 1>."""
    match = ENGINE_VERSION.match(current)
    if not match:
        raise TrackError(f"the engine version {current} is not <X.Y.Z>-flux.<n>")
    if match.group(1) != supersonic:
        return f"{supersonic}-flux.1"
    return f"{supersonic}-flux.{int(match.group(2)) + 1}"


def set_isospin_pin(text: str, version: str, sha256: str) -> str:
    """ugens.toml with a new version and sha256 in its [isospin] entry. The
    script changes the two lines as text, so that the comments stay
    (tomllib can only read TOML)."""
    match = re.search(r"^\[isospin\]\n(.*?)(?=^\[|\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise TrackError("ugens.toml has no [isospin] entry")
    entry = match.group(1)
    new, versions = re.subn(r'^version = ".*"$', f'version = "{version}"', entry,
                            count=1, flags=re.MULTILINE)
    new, digests = re.subn(r'^sha256 = ".*"$', f'sha256 = "{sha256}"', new,
                           count=1, flags=re.MULTILINE)
    if versions != 1 or digests != 1:
        raise TrackError("the [isospin] entry of ugens.toml has no version or sha256 line")
    return text[:match.start(1)] + new + text[match.end(1):]


def sha256_from_file(text: str, name: str) -> str:
    """The digest for the file name in a sha256sum file."""
    for line in text.splitlines():
        digest, _, file = line.strip().partition("  ")
        if file == name:
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise TrackError(f"the SHA-256 of {name} is not 64 hexadecimal digits")
            return digest
    raise TrackError(f"the .sha256 file has no line for {name}")


class Bump(NamedTuple):
    """One target at a new release, with the text for the proposal."""
    name: str
    tag: str
    body: str


def proposal(bumps: list[Bump], engine: str) -> dict[str, str]:
    """The branch and the titles of the pull request and the issue for all
    the bumps together."""
    branch = "+".join(f"{b.name.lower()}-{b.tag}" for b in bumps)
    releases = " and ".join(f"{b.name} {b.tag}" for b in bumps)
    targets = " and ".join(f"{b.name} to {b.tag}" for b in bumps)
    verb = "does" if len(bumps) == 1 else "do"
    return {
        "branch": f"track/{branch}",
        "pr-title": f"Bump {targets} (engine {engine})",
        "issue-title": f"{releases} {verb} not build or pass the tests",
    }


def proposal_body(bumps: list[Bump], engine: str) -> str:
    """The text of the pull request or the issue: the text of each bump, then
    the engine version."""
    parts = [b.body.strip() for b in bumps]
    parts.append(f"The engine version becomes `{engine}`.")
    return "\n\n".join(parts) + "\n"


def output_lines(values: dict[str, str]) -> str:
    """The key=value lines for $GITHUB_OUTPUT."""
    for key, value in values.items():
        if "\n" in value:
            raise TrackError(f"the output {key} has a new line")
    return "".join(f"{key}={value}\n" for key, value in values.items())


def git(*args: str, cwd: Path = ROOT) -> str:
    result = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise TrackError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url)
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def bump_supersonic(tag: str | None) -> Bump | None:
    """Move the SuperSonic submodule to the newest release, or to the given
    tag. None when SuperSonic is at the newest release."""
    current = json.loads((SUPERSONIC / "package.json").read_text())["version"]
    if tag is None:
        tag = newest_tag(tags_from_ls_remote(git("ls-remote", "--tags", SUPERSONIC_REPO)))
        if tag is None:
            raise TrackError(f"{SUPERSONIC_REPO} has no release tag")
        if not is_newer(tag[1:], current):
            log(f"SuperSonic {tag} is the newest release; the engine has {current}")
            return None
    elif not RELEASE_TAG.match(tag) or tag[1:] == current:
        raise TrackError(f"--tag {tag} is not a release tag vX.Y.Z other than v{current}")
    if git("status", "--porcelain", cwd=SUPERSONIC):
        raise TrackError("the SuperSonic submodule has changes (an applied patch?); "
                         "use a clean checkout")

    old = f"v{current}"
    log(f"SuperSonic {old} -> {tag}")
    git("fetch", "--quiet", "--depth", "1", "origin", "tag", old, "tag", tag, cwd=SUPERSONIC)
    git("checkout", "--quiet", tag, cwd=SUPERSONIC)
    git("submodule", "update", "--quiet", "--init", "--recursive", "--depth", "1", cwd=SUPERSONIC)

    check = subprocess.run(["git", "-C", str(SUPERSONIC), "apply", "--check", str(HOOK_PATCH)],
                           capture_output=True, text=True)
    hook = ("The hook patch (`patches/supersonic-extra-plugins.patch`) applies."
            if check.returncode == 0 else
            "**The hook patch (`patches/supersonic-extra-plugins.patch`) does not apply:**\n\n"
            f"```\n{check.stderr.strip()}\n```")
    toolchain = git("diff", old, tag, "--", *SUPERSONIC_TOOLCHAIN_FILES, cwd=SUPERSONIC).strip()
    toolchain_text = (
        "SuperSonic's toolchain pins did not change "
        f"({', '.join(f'`{f}`' for f in SUPERSONIC_TOOLCHAIN_FILES)})."
        if not toolchain else
        "**SuperSonic's toolchain pins changed.** Change the `Containerfile` to the same "
        f"versions:\n\n```diff\n{toolchain}\n```")
    body = (f"SuperSonic {old} → {tag} ({SUPERSONIC_REPO}/compare/{old}...{tag}).\n\n"
            f"{hook}\n\n{toolchain_text}")
    return Bump("SuperSonic", tag, body)


def bump_isospin() -> Bump | None:
    """Pin the newest isospin release in ugens.toml. None when ugens.toml has
    the newest release."""
    import tomllib
    current = tomllib.loads(UGENS_FILE.read_text())["isospin"]["version"]
    release = json.loads(fetch(ISOSPIN_API))
    tag = release["tag_name"]
    if not RELEASE_TAG.match(tag):
        raise TrackError(f"the newest isospin release has the tag {tag}, not vX.Y.Z")
    version = tag[1:]
    if not is_newer(version, current):
        log(f"isospin {tag} is the newest release; ugens.toml has {current}")
        return None

    log(f"isospin v{current} -> {tag}")
    name = ISOSPIN_FILE.format(version=version)
    sha256 = sha256_from_file(fetch(ISOSPIN_SHA256_URL.format(version=version)).decode(), name)
    UGENS_FILE.write_text(set_isospin_pin(UGENS_FILE.read_text(), version, sha256))
    body = (f"isospin v{current} → {tag} (https://github.com/aeskildsen/isospin/releases/tag/{tag}): "
            f"the `[isospin]` entry of `ugens.toml` gets the version and the SHA-256 "
            f"`{sha256}` of `{name}`.")
    return Bump("isospin", tag, body)


def bump_engine_version() -> str:
    """Write the next engine version to engine-version.env, from the
    SuperSonic version in the working tree after the bumps."""
    supersonic = json.loads((SUPERSONIC / "package.json").read_text())["version"]
    text = ENGINE_VERSION_FILE.read_text()
    engine = next_engine_version(engine_version(text), supersonic)
    ENGINE_VERSION_FILE.write_text(set_engine_version(text, engine))
    return engine


TARGETS = ["supersonic", "isospin"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("targets", nargs="*", choices=TARGETS, metavar="target",
                        help="supersonic or isospin (default: all)")
    parser.add_argument("--body", type=Path, required=True,
                        help="the file for the text of the pull request or issue")
    parser.add_argument("--tag", help="a SuperSonic tag to take instead of the newest")
    args = parser.parse_args()
    targets = [t for t in TARGETS if t in args.targets] if args.targets else TARGETS
    if args.tag and "supersonic" not in targets:
        parser.error("--tag is for supersonic only")
    try:
        # SuperSonic first: it stops on a submodule with changes before the
        # script changes a file.
        bumps = []
        if "supersonic" in targets:
            bumps.append(bump_supersonic(args.tag))
        if "isospin" in targets:
            bumps.append(bump_isospin())
        bumps = [b for b in bumps if b is not None]
        if not bumps:
            args.body.write_text("")
            sys.stdout.write(output_lines({"found": "false"}))
            return
        engine = bump_engine_version()
        args.body.write_text(proposal_body(bumps, engine))
        sys.stdout.write(output_lines({"found": "true", "version": engine,
                                       **proposal(bumps, engine)}))
    except TrackError as error:
        sys.exit(f"track: {error}")


if __name__ == "__main__":
    main()
