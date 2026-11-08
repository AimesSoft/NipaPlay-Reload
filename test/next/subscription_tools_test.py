"""Local fixtures only; no network, user configuration or credential backend."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[2] / "assets/next/harness/tools"
sys.path.insert(0, str(TOOLS))
import rss
import torznab
import patrol
import subscription_io

FIXTURES = Path(__file__).parent / "fixtures/subscriptions"
PRIVATE = "fixture-private-key"


class Feeds(unittest.TestCase):
    def test_rss_and_atom_keep_evidence_and_inject_only_named_secret(self):
        with patch.object(rss, "fetch", return_value=(FIXTURES / "rss.xml").read_bytes()) as fetch, \
             patch.object(rss, "secret", return_value=PRIVATE) as secret:
            result = rss.main(["https://fixture.invalid/rss?passkey={secret}", "--secret", "pt-rss"])
            secret.assert_called_once_with("pt-rss")
            self.assertIn(PRIVATE, fetch.call_args.args[0])
            self.assertNotIn(PRIVATE, json.dumps(result))
            self.assertNotIn("source_url", result)
            self.assertIn("{secret}", result["entries"][0]["enclosure"])
            self.assertEqual(result["entries"][0]["size"], 1048576)
        atom = rss.parse((FIXTURES / "atom.xml").read_bytes())[0]
        self.assertEqual(atom["title"], "Show 04")
        self.assertEqual(atom["size"], 2048)
        self.assertEqual(atom["published_at"], "2026-11-08T12:00:00Z")
        with self.assertRaises(ValueError):
            rss.parse(b'<!DOCTYPE rss [<!ENTITY x "expanded">]><rss/>')
        with self.assertRaises(ValueError):
            rss.parse(b'<html>login</html>')
        with self.assertRaises(ValueError):
            rss.read('https://fixture.invalid/rss?passkey=' + PRIVATE)
        self.assertNotIn('other-private', json.dumps(subscription_io.without_secret(
            {'enclosure': 'https://fixture.invalid/dl?passkey=other-private'}, PRIVATE)))

    def test_torznab_caps_search_and_selected_indexer_rss(self):
        with patch.object(torznab, "fetch", return_value=(FIXTURES / "torznab.xml").read_bytes()) as fetch, \
             patch.object(torznab, "secret", return_value=PRIVATE):
            result = torznab.main(["search", "--url", "https://fixture.invalid/api/v2/indexers/chosen/results/torznab/api",
                                   "--secret", "jackett", "--q", "Show", "--cat", "5070", "--tmdbid", "123", "--imdbid", "tt42", "--season", "1", "--ep", "3"])
            url = fetch.call_args.args[0]
            self.assertIn("tmdbid=123", url)
            self.assertIn("t=search", url)
            self.assertIn("apikey=" + PRIVATE, url)
            self.assertNotIn(PRIVATE, json.dumps(result))
            self.assertEqual(result["entries"][0]["seeders"], 7)
            self.assertEqual(result["entries"][0]["indexer"], "Fixture indexer")
            torznab.query("https://fixture.invalid/api", "rss", "jackett")
            self.assertNotIn("q=", fetch.call_args.args[0])
        with patch.object(torznab, "fetch", return_value=b'<caps><searching><tv-search available="yes" supportedParams="q,season,ep"/></searching><categories><category id="5000" name="TV"/></categories></caps>'):
            caps = torznab.query("https://fixture.invalid/api", "caps")
            self.assertEqual(caps["categories"][0]["id"], "5000")
            self.assertEqual(caps["searching"][0]["type"], "tv-search")

    def test_transport_refuses_redirect_to_other_origin_and_error_never_echoes_url(self):
        redirects = subscription_io.SameOrigin(("https", "fixture.invalid", 443))
        with self.assertRaises(ValueError):
            redirects.redirect_request(None, None, 302, "", {}, "https://else.invalid/?passkey=" + PRIVATE)
        stream = io.StringIO()
        with contextlib.redirect_stderr(stream), self.assertRaises(SystemExit):
            subscription_io.emit(lambda: (_ for _ in ()).throw(RuntimeError(PRIVATE)))
        self.assertNotIn(PRIVATE, stream.getvalue())


class Patrol(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.records = patrol.Records(self.temporary.name)
        self.sub = {"id": "follow", "title": "Show", "kind": "series", "workId": "work-1", "revision": 1,
                    "facts": {"sources": [{"kind": "rss", "url": "https://fixture.invalid/rss"}],
                              "rules": {"include": ["Group", "1080p"], "exclude": ["HEVC"],
                                        "episodeRegex": r" - (?P<episode>\d+)", "minBytes": 100},
                              "bindings": {"03": {"files": {"0": {"ref": {"provider": "tmdb", "objectType": "episode", "externalId": "42", "scope": "tv/1/season/1/episode/3"},
                                                                     "localEpisodeIds": ["episode-3"], "reason": "用户确认的第 3 集"}}}}}}
        self.calls = []

    def tearDown(self):
        self.temporary.cleanup()

    def host(self, action, value):
        self.calls.append((action, value))
        if action == "subscription.get":
            return {**self.sub, "state": "active"}
        if action == "download.add":
            return {"job": {"jobId": "job-1"}}
        if action == "media.identity.bind_batch":
            return {"entries": [{"fileId": "file-3"}]}
        if action == "settings.get":
            return {"results": [{"key": "library.fileOrganization", "value": "off"},
                                {"key": "library.fileOrganizationRules", "value": "用户保存的规则"}]}
        return {}

    def loader(self, source):
        return [{"title": "Group Show - 03 1080p", "url": "magnet:?xt=urn:btih:fixture", "size": 1024},
                {"title": "Group Show - 04 1080p HEVC", "url": "magnet:?xt=ignored", "size": 1024}]

    def test_preview_rules_dedup_download_and_report_without_normal_wake(self):
        result = patrol.run_one(self.sub, None, self.host, self.loader, preview=True)
        self.assertEqual(result["found"][0]["episode"], "03")
        self.assertEqual(self.calls, [])
        patrol.run_one(self.sub, self.records, self.host, self.loader)
        patrol.run_one(self.sub, self.records, self.host, self.loader)
        self.assertEqual(sum(a == "download.add" for a, _ in self.calls), 1)
        self.assertFalse(any(a == "agent.wake" for a, _ in self.calls))
        mapping = self.records.read("job:job-1")
        self.assertEqual(mapping["workId"], "work-1")
        self.assertEqual(mapping["episode"], "03")
        self.assertIn("binding", mapping)
        self.assertEqual(sum(a == "subscription.report" for a, _ in self.calls), 2)

    def test_sources_use_credential_names_without_storing_private_url_templates(self):
        with patch.object(rss, 'read', return_value={'entries': [{'title': 'Show', 'enclosure': 'https://fixture.invalid/dl?passkey={secret}', 'size': 42}]}) as reader:
            rows = patrol.candidates({'kind': 'rss', 'url': 'https://fixture.invalid/rss', 'credentialParameter': 'passkey', 'credentialName': 'pt'})
            reader.assert_called_once_with('https://fixture.invalid/rss?passkey={secret}', 'pt')
            self.assertEqual(rows[0]['credentialName'], 'pt')

    def test_conflicts_ask_priority_and_consecutive_errors(self):
        def conflicting(source):
            return self.loader(source)[:1] + [{"title": "Group Other - 03 1080p", "url": "magnet:?xt=other", "size": 1024}]
        patrol.run_one(self.sub, self.records, self.host, conflicting)
        self.assertTrue(any(a == "agent.wake" for a, _ in self.calls))
        self.assertFalse(any(a == "download.add" for a, _ in self.calls))
        self.sub["facts"]["rules"]["priority"] = ["Other"]
        selected, conflicts = patrol.inspect(self.sub, conflicting)
        self.assertFalse(conflicts)
        self.assertIn("Other", selected[0]["title"])
        self.sub["facts"]["rules"]["ask"] = True
        self.calls.clear()
        patrol.run_one(self.sub, self.records, self.host, self.loader)
        self.assertTrue(any(a == "agent.wake" for a, _ in self.calls))
        self.calls.clear()
        def broken(source):
            raise RuntimeError(PRIVATE)
        for _ in range(4):
            patrol.run_one(self.sub, self.records, self.host, broken)
        self.assertEqual(sum(a == "agent.wake" for a, _ in self.calls), 1)
        self.assertNotIn(PRIVATE, json.dumps(self.calls))

    def test_pause_and_unknown_download_outcome_do_not_retry(self):
        def paused(action, inputs):
            if action == "subscription.get":
                return {**self.sub, "state": "paused"}
            return self.host(action, inputs)
        patrol.run_one(self.sub, self.records, paused, self.loader)
        self.assertFalse(any(a == "download.add" for a, _ in self.calls))
        def uncertain(action, inputs):
            if action == "download.add":
                self.calls.append((action, inputs))
                raise RuntimeError("unknown")
            return self.host(action, inputs)
        patrol.run_one(self.sub, self.records, uncertain, self.loader)
        patrol.run_one(self.sub, self.records, uncertain, self.loader)
        self.assertEqual(sum(a == "download.add" for a, _ in self.calls), 1)
        self.assertTrue(any(a == "agent.wake" for a, _ in self.calls))

    def event(self):
        return {"event": "download.file_completed", "objectId": "job-1:0", "occurredAt": "2026-11-08T12:00:00Z",
                "data": {"jobId": "job-1", "file": {"index": 0, "local": True, "verification": "verified", "media": {"fileId": "file-3"}}}}

    def test_completion_uses_explicit_identity_and_existing_organization_policy(self):
        patrol.run_one(self.sub, self.records, self.host, self.loader)
        event = self.event()
        self.assertTrue(patrol.complete(event, self.records, self.host)["handled"])
        bind = next(v for a, v in self.calls if a == "media.identity.bind_batch")
        self.assertEqual(bind["entries"][0]["entityId"], "file-3")
        self.assertEqual(bind["entries"][0]["localEpisodeIds"], ["episode-3"])
        self.assertFalse(patrol.complete(event, self.records, self.host)["handled"])
        self.assertEqual(sum(a == "media.identity.bind_batch" for a, _ in self.calls), 1)
        self.assertFalse(any(a == "agent.wake" for a, _ in self.calls))

    def test_completion_missing_mapping_and_remote_file_wake_without_binding(self):
        patrol.run_one(self.sub, self.records, self.host, self.loader)
        event = self.event()
        event["data"]["file"]["local"] = False
        self.assertTrue(patrol.complete(event, self.records, self.host)["needsDecision"])
        self.assertFalse(any(a == "media.identity.bind_batch" for a, _ in self.calls))
        event["data"]["file"]["local"] = True
        event["data"]["file"]["index"] = 9
        self.assertTrue(patrol.complete(event, self.records, self.host)["needsDecision"])

    def test_completion_auto_organization_hands_saved_rules_to_agent_and_hook_is_importable(self):
        patrol.run_one(self.sub, self.records, self.host, self.loader)
        def auto(action, inputs):
            result = self.host(action, inputs)
            if action == "settings.get":
                result["results"][0]["value"] = "auto"
            return result
        patrol.complete(self.event(), self.records, auto)
        instruction = next(v for a, v in self.calls if a == "agent.wake")
        self.assertEqual(instruction["facts"]["organization"]["library.fileOrganizationRules"], "用户保存的规则")
        runpy.run_path(str(TOOLS.parent / "hooks/download.file_completed.py"))


class SecretPipe(unittest.TestCase):
    def test_secret_cli_never_spills_or_redacts_the_value_sent_to_script(self):
        cli = runpy.run_path(str(TOOLS.parent / "nipa"))
        class Client:
            token = "endpoint-fixture"
            def call(self, action, inputs, execute):
                return {"status": "completed", "result": {"name": "pt", "value": PRIVATE + "x" * 30000}}
        output = io.StringIO()
        with patch.dict(cli["main"].__globals__, {"Client": Client,
                                                   "output_result": lambda *_: self.fail("Secret must not use spill path")}), \
             patch.object(sys, "argv", ["nipa", "call", "secrets.get", '{"name":"pt"}']), \
             contextlib.redirect_stdout(output):
            self.assertEqual(cli["main"](), 0)
        self.assertTrue(json.loads(output.getvalue())["result"]["value"].startswith(PRIVATE))


if __name__ == "__main__":
    unittest.main()
