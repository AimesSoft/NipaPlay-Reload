"""Regressions for deduplication before candidate conflict decisions."""
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'assets/next/harness/tools'))
import patrol


class Deduplication(unittest.TestCase):
    def test_handled_episode_does_not_conflict_with_new_versions(self):
        entries = [{'title': 'Show - 03', 'size': 100, 'url': 'magnet:?xt=first'},
                   {'title': 'Show - 03 v2', 'size': 100, 'url': 'magnet:?xt=second'},
                   {'title': 'Show - 04', 'size': 100, 'url': 'magnet:?xt=new'}]
        rules = {'include': ['Show'], 'episodeRegex': r' - (?P<episode>\d+)'}
        selected, conflicts = patrol.select(entries, rules, 'series', {'03'})
        self.assertEqual(conflicts, [])
        self.assertEqual([e['episode'] for e in selected], ['04'])

    def test_unknown_intent_is_not_retried_or_silenced_by_episode_dedup(self):
        with tempfile.TemporaryDirectory() as root:
            records = patrol.Records(root)
            records.write('subscription:follow', {'episodes': {'03': 'old'},
                          'processed': {'old': {'status': 'intent', 'episode': '03'}}})
            sub = {'id': 'follow', 'title': 'Show', 'kind': 'series', 'facts': {
                'sources': [{}], 'rules': {'include': ['Show'], 'episodeRegex': r' - (?P<episode>\d+)'}}}
            calls = []
            def host(action, inputs):
                calls.append((action, inputs))
                self.assertNotEqual(action, 'download.add')
                return {}
            def loader(source):
                return [{'title': 'Show - 03', 'size': 100, 'url': 'magnet:?xt=first'},
                        {'title': 'Show - 03 v2', 'size': 100, 'url': 'magnet:?xt=second'}]
            for _ in range(2):
                report = patrol.run_one(sub, records, host, loader)
                self.assertEqual(report['found'], [])
                self.assertEqual(report['errors'], [])
            self.assertEqual(sum(a == 'agent.wake' for a, _ in calls), 1)
            self.assertTrue(records.read('subscription:follow')['processed']['old']['notified'])


if __name__ == '__main__':
    unittest.main()
