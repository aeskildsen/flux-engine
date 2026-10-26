"""Tests for scripts/track.py: the choice of the newest release, and the
changes that a bump makes to engine-version.env and ugens.toml. They need no
network and no git.

Run: python3 -m unittest discover -s test -p 'test_*.py'
"""
import importlib.util
import sys
import textwrap
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location(
    "track", Path(__file__).resolve().parent.parent / "scripts" / "track.py")
track = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(track)

ROOT = Path(__file__).resolve().parent.parent

ENGINE_VERSION = textwrap.dedent("""\
    # The version of the engine package.
    FLUX_ENGINE_VERSION=0.91.0-flux.3
    """)

UGENS = textwrap.dedent("""\
    # The static UGens of isospin.
    [isospin]
    version = "0.2.0"
    sha256 = "05ebad33e380fa9aab6262cb52f0427a7d3184344b82b24f1b3d681b59b70075"

    [[sources]]
    name = "MiPlaits"
    version = "1.0.0"
    """)

NEW_SHA = "a" * 64


class NewestTag(unittest.TestCase):
    def test_takes_the_highest_release_version(self):
        tags = ["v0.9.0", "v0.91.0", "v0.10.0", "v0.92.0", "v0.89.1"]
        self.assertEqual(track.newest_tag(tags), "v0.92.0")

    def test_leaves_out_tags_that_are_not_releases(self):
        tags = ["v0.92.0", "v0.93.0-beta.1", "v1.0.0rc1", "latest", "0.99.0", "v0.93"]
        self.assertEqual(track.newest_tag(tags), "v0.92.0")

    def test_no_release_tag(self):
        self.assertIsNone(track.newest_tag(["main", "v1.0.0-rc.1"]))

    def test_compares_numbers_not_text(self):
        self.assertTrue(track.is_newer("0.100.0", "0.92.0"))
        self.assertFalse(track.is_newer("0.92.0", "0.92.0"))
        self.assertFalse(track.is_newer("0.91.0", "0.92.0"))


class LsRemote(unittest.TestCase):
    def test_tags_from_ls_remote_output(self):
        out = ("abc\trefs/tags/v0.91.0\n"
               "def\trefs/tags/v0.91.0^{}\n"
               "123\trefs/tags/v0.92.0\n")
        self.assertEqual(track.tags_from_ls_remote(out), ["v0.91.0", "v0.92.0"])


class EngineVersion(unittest.TestCase):
    def test_new_supersonic_version_starts_at_flux_1(self):
        self.assertEqual(track.next_engine_version("0.91.0-flux.3", "0.92.0"), "0.92.0-flux.1")

    def test_same_supersonic_version_counts_up(self):
        self.assertEqual(track.next_engine_version("0.91.0-flux.3", "0.91.0"), "0.91.0-flux.4")

    def test_bad_version_stops(self):
        with self.assertRaises(track.TrackError):
            track.next_engine_version("0.91.0", "0.91.0")

    def test_set_engine_version_keeps_the_comments(self):
        text = track.set_engine_version(ENGINE_VERSION, "0.92.0-flux.1")
        self.assertEqual(text, ENGINE_VERSION.replace("0.91.0-flux.3", "0.92.0-flux.1"))

    def test_read_engine_version(self):
        self.assertEqual(track.engine_version(ENGINE_VERSION), "0.91.0-flux.3")


class IsospinPin(unittest.TestCase):
    def test_changes_only_the_isospin_entry(self):
        text = track.set_isospin_pin(UGENS, "0.3.0", NEW_SHA)
        expected = (UGENS.replace('version = "0.2.0"', 'version = "0.3.0"')
                    .replace("05ebad33e380fa9aab6262cb52f0427a7d3184344b82b24f1b3d681b59b70075", NEW_SHA))
        self.assertEqual(text, expected)
        # The version of the [[sources]] entry stays.
        self.assertIn('version = "1.0.0"', text)

    def test_the_result_is_valid_toml_with_the_new_pin(self):
        import tomllib
        pin = tomllib.loads(track.set_isospin_pin(UGENS, "0.3.0", NEW_SHA))["isospin"]
        self.assertEqual(pin, {"version": "0.3.0", "sha256": NEW_SHA})

    def test_no_isospin_entry_stops(self):
        with self.assertRaises(track.TrackError):
            track.set_isospin_pin("[[sources]]\nname = \"x\"\n", "0.3.0", NEW_SHA)

    def test_an_entry_without_sha256_stops(self):
        with self.assertRaises(track.TrackError):
            track.set_isospin_pin('[isospin]\nversion = "0.2.0"\n', "0.3.0", NEW_SHA)

    def test_the_repository_manifest_can_be_changed(self):
        text = (ROOT / "ugens.toml").read_text()
        import tomllib
        pin = tomllib.loads(track.set_isospin_pin(text, "9.9.9", NEW_SHA))["isospin"]
        self.assertEqual(pin, {"version": "9.9.9", "sha256": NEW_SHA})


class Sha256File(unittest.TestCase):
    def test_reads_the_digest_of_the_named_file(self):
        text = f"{NEW_SHA}  isospin-sc-static-0.3.0.tar.gz\n"
        self.assertEqual(track.sha256_from_file(text, "isospin-sc-static-0.3.0.tar.gz"), NEW_SHA)

    def test_other_file_name_stops(self):
        with self.assertRaises(track.TrackError):
            track.sha256_from_file(f"{NEW_SHA}  other.tar.gz\n", "isospin-sc-static-0.3.0.tar.gz")

    def test_malformed_digest_stops(self):
        with self.assertRaises(track.TrackError):
            track.sha256_from_file("abc  isospin-sc-static-0.3.0.tar.gz\n", "isospin-sc-static-0.3.0.tar.gz")


class Outputs(unittest.TestCase):
    def test_names_of_a_supersonic_bump(self):
        out = track.proposal("SuperSonic", "v0.92.0", "0.92.0-flux.1")
        self.assertEqual(out["branch"], "track/supersonic-v0.92.0")
        self.assertEqual(out["pr-title"], "Bump SuperSonic to v0.92.0 (engine 0.92.0-flux.1)")
        self.assertEqual(out["issue-title"], "SuperSonic v0.92.0 does not build or pass the tests")

    def test_github_output_lines(self):
        lines = track.output_lines({"found": "true", "tag": "v0.92.0"})
        self.assertEqual(lines, "found=true\ntag=v0.92.0\n")

    def test_github_output_refuses_a_new_line_in_a_value(self):
        with self.assertRaises(track.TrackError):
            track.output_lines({"title": "a\nb"})


if __name__ == "__main__":
    unittest.main()
