#!/usr/bin/env python3
"""Unit tests for the scorer's off-the-lab logic.

Section 18 promises the validation logic is "unit-tested off the lab". The three
units it names are the validation states (RFC 6811 origin validation), the
scenario reader (the `target:` block oracle) and the diff (snapshot to events).
Those are the pure functions here: rpki_state, read_target and diff.

The docker-facing I/O (vrps, snapshot, _docker, run_poll, run_bmp) is out of
scope by design: it needs the live lab and is validated there, not mocked here.

Run from the repo root:  python3 -m unittest discover -s tests
"""
import ipaddress
import os
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "scorer"))
import scorer  # noqa: E402


def vrp(prefix, maxlen, origin):
    """Build one VRP tuple the way vrps() yields them."""
    return (ipaddress.ip_network(prefix), maxlen, origin)


class TestRpkiState(unittest.TestCase):
    """RFC 6811 origin validation: notfound / valid / invalid / unknown."""

    def test_notfound_when_no_covering_vrp(self):
        self.assertEqual(scorer.rpki_state("198.51.100.0/24", 65020, []), "notfound")
        other = [vrp("10.0.0.0/8", 24, 65001)]
        self.assertEqual(scorer.rpki_state("198.51.100.0/24", 65020, other), "notfound")

    def test_valid_exact_match(self):
        roas = [vrp("203.0.113.0/24", 24, 65010)]
        self.assertEqual(scorer.rpki_state("203.0.113.0/24", 65010, roas), "valid")

    def test_valid_more_specific_within_maxlength(self):
        roas = [vrp("203.0.113.0/24", 25, 65010)]
        self.assertEqual(scorer.rpki_state("203.0.113.0/25", 65010, roas), "valid")

    def test_invalid_wrong_origin(self):
        roas = [vrp("203.0.113.0/24", 24, 65010)]
        self.assertEqual(scorer.rpki_state("203.0.113.0/24", 65020, roas), "invalid")

    def test_invalid_too_specific_for_maxlength(self):
        # Right origin, but longer than maxLength: covered yet invalid.
        roas = [vrp("203.0.113.0/24", 24, 65010)]
        self.assertEqual(scorer.rpki_state("203.0.113.0/25", 65010, roas), "invalid")

    def test_false_origin_hijack_is_invalid(self):
        # The headline case: the /25 hijack with the attacker's origin, against
        # FDEI's valid /24 ROA. Covered, wrong origin and too specific -> invalid.
        roas = [vrp("203.0.113.0/24", 24, 65010)]
        self.assertEqual(scorer.rpki_state("203.0.113.0/25", 65020, roas), "invalid")

    def test_valid_when_one_of_several_covering_vrps_matches(self):
        roas = [vrp("203.0.113.0/24", 24, 65099),   # covers, wrong origin
                vrp("203.0.113.0/24", 25, 65010)]    # covers, matches
        self.assertEqual(scorer.rpki_state("203.0.113.0/25", 65010, roas), "valid")

    def test_unknown_on_malformed_prefix(self):
        self.assertEqual(scorer.rpki_state("not-a-prefix", 65010, []), "unknown")


class TestReadTarget(unittest.TestCase):
    """The scenario.yaml `target:` reader (stdlib only, no PyYAML)."""

    def _read_in(self, root, scenario):
        cwd = os.getcwd()
        os.chdir(root)
        try:
            return scorer.read_target(scenario)
        finally:
            os.chdir(cwd)

    def test_reads_committed_false_origin_scenario(self):
        # Against the real committed file, not a fixture: proves the reader works
        # on actual input shaped as the scenarios carry it.
        t = self._read_in(REPO, "false-origin-prefix-hijack")
        self.assertEqual(t["legitimate_prefix"], "203.0.113.0/24")
        self.assertEqual(t["legitimate_origin"], "65010")
        self.assertEqual(t["hijack_prefix"], "203.0.113.0/25")
        self.assertEqual(t["hijack_origin"], "65020")

    def test_stops_at_next_top_level_key_and_strips_inline_comments(self):
        body = (
            "name: demo\n"
            "target:\n"
            "  hijack_prefix: 203.0.113.0/25     # more-specific, wins\n"
            "  hijack_origin: 65020\n"
            "  # a standalone comment line, skipped\n"
            "  legitimate_origin: 65010\n"
            "expected_effect: >\n"
            "  this key is outside target and must not leak in\n"
        )
        with tempfile.TemporaryDirectory() as d:
            sdir = os.path.join(d, "scenarios", "demo")
            os.makedirs(sdir)
            with open(os.path.join(sdir, "scenario.yaml"), "w") as f:
                f.write(body)
            t = self._read_in(d, "demo")
        self.assertEqual(t, {
            "hijack_prefix": "203.0.113.0/25",
            "hijack_origin": "65020",
            "legitimate_origin": "65010",
        })
        self.assertNotIn("expected_effect", t)
        self.assertNotIn("name", t)


class TestDiff(unittest.TestCase):
    """Snapshot-to-event diffing, with RPKI annotation carried on each event."""

    SCN = "false-origin-prefix-hijack"
    ROAS = [vrp("203.0.113.0/24", 24, 65010)]

    def test_new_prefix_is_announce(self):
        prev = {}
        cur = {"198.51.100.0/24": (65020, [65002, 65020])}
        events = scorer.diff(prev, cur, [], self.SCN)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["type"], "announce")
        self.assertEqual(events[0]["prefix"], "198.51.100.0/24")
        self.assertEqual(events[0]["origin_as"], 65020)
        self.assertEqual(events[0]["as_path"], [65002, 65020])

    def test_more_specific_of_existing_route(self):
        # The /25 appears alongside the /24 already in the table.
        prev = {"203.0.113.0/24": (65010, [65001, 65010])}
        cur = {
            "203.0.113.0/24": (65010, [65001, 65010]),
            "203.0.113.0/25": (65020, [65001, 65002, 65020]),
        }
        events = scorer.diff(prev, cur, self.ROAS, self.SCN)
        self.assertEqual(len(events), 1)
        e = events[0]
        self.assertEqual(e["type"], "more-specific")
        self.assertEqual(e["prefix"], "203.0.113.0/25")
        self.assertEqual(e["origin_as"], 65020)

    def test_more_specific_event_is_rpki_invalid(self):
        # Ties section 18's recorded live result back to the pure logic:
        # "more-specific 203.0.113.0/25 origin 65020 rpki=invalid".
        prev = {"203.0.113.0/24": (65010, [65001, 65010])}
        cur = {
            "203.0.113.0/24": (65010, [65001, 65010]),
            "203.0.113.0/25": (65020, [65001, 65002, 65020]),
        }
        (e,) = scorer.diff(prev, cur, self.ROAS, self.SCN)
        self.assertEqual(e["type"], "more-specific")
        self.assertEqual(e["rpki"], "invalid")

    def test_origin_change(self):
        prev = {"203.0.113.0/24": (65010, [65001, 65010])}
        cur = {"203.0.113.0/24": (65020, [65002, 65020])}
        (e,) = scorer.diff(prev, cur, [], self.SCN)
        self.assertEqual(e["type"], "origin-change")
        self.assertEqual(e["origin_as"], 65020)

    def test_withdraw(self):
        prev = {"203.0.113.0/25": (65020, [65002, 65020])}
        cur = {}
        (e,) = scorer.diff(prev, cur, [], self.SCN)
        self.assertEqual(e["type"], "withdraw")
        self.assertEqual(e["prefix"], "203.0.113.0/25")

    def test_no_change_yields_no_events(self):
        snap = {"203.0.113.0/24": (65010, [65001, 65010])}
        self.assertEqual(scorer.diff(snap, dict(snap), self.ROAS, self.SCN), [])

    def test_event_envelope_shape(self):
        cur = {"203.0.113.0/24": (65010, [65001, 65010])}
        (e,) = scorer.diff({}, cur, self.ROAS, self.SCN)
        self.assertEqual(set(e), {"ts", "scenario", "source", "type",
                                  "prefix", "origin_as", "as_path", "rpki"})
        self.assertEqual(e["scenario"], self.SCN)
        self.assertEqual(e["source"], "collector:observer")
        self.assertTrue(e["ts"].endswith("Z"))


class TestMoreSpecificHelper(unittest.TestCase):
    """_more_specific: is p a strict subnet of any other prefix in the set?"""

    def test_true_for_subnet(self):
        others = ["203.0.113.0/24", "203.0.113.0/25"]
        self.assertTrue(scorer._more_specific("203.0.113.0/25", others))

    def test_false_for_covering_or_unrelated(self):
        others = ["203.0.113.0/24", "198.51.100.0/24"]
        self.assertFalse(scorer._more_specific("203.0.113.0/24", others))
        self.assertFalse(scorer._more_specific("198.51.100.0/24", others))

    def test_ignores_itself(self):
        self.assertFalse(scorer._more_specific("203.0.113.0/24", ["203.0.113.0/24"]))


if __name__ == "__main__":
    unittest.main()