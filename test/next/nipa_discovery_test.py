"""Remote description comes from the target; executing a tool stays one call."""
import runpy
import unittest


class RemoteDiscovery(unittest.TestCase):
    def setUp(self):
        module = runpy.run_path('assets/next/harness/nipa')
        self.client = module['Client'].__new__(module['Client'])
        self.actions = [
            {'id': 'playback.kernel', 'effect': 'read', 'description': 'target catalog', 'available': False},
            {'id': 'capability.describe', 'effect': 'read'},
            {'id': 'db.write', 'effect': 'write'},
        ]
        self.client.device = {'deviceId': 'target', 'actions': self.actions}
        self.client.catalog = lambda: {'actions': self.actions}
        self.calls = []

    def answer(self, reply):
        def request(operation, **kwargs):
            self.calls.append((operation, kwargs))
            return reply
        self.client.request = request

    def test_exact_description_is_target_contract_not_local_prose(self):
        self.answer({'status': 'completed', 'result': {
            'id': 'playback.kernel', 'description': 'target version guide',
            'usage': {'familyDescription': 'target scope'}}})
        result = self.client.describe('playback.kernel')
        self.assertEqual(result['usage']['familyDescription'], 'target scope')
        self.assertFalse(result['available'])
        self.assertEqual(self.calls[0][1]['input']['action'], 'capability.describe')
        self.assertEqual(self.calls[0][1]['input']['input'], {'family': 'playback.kernel'})

    def test_old_host_falls_back_without_inventing_usage(self):
        self.answer({'status': 'failed', 'error': {'code': 'not_found'}})
        result = self.client.describe('playback.kernel')
        self.assertEqual(result['guidanceStatus'], 'catalogOnlyUnverified')
        self.assertNotIn('usage', result)

    def test_unreachable_target_is_not_hidden_as_legacy(self):
        self.answer({'status': 'failed', 'error': {'code': 'unavailable'}})
        with self.assertRaises(ValueError):
            self.client.describe('playback.kernel')

    def test_execution_does_not_describe_or_execute_twice(self):
        self.answer({'status': 'completed', 'result': {'committed': True}})
        result = self.client.call('db.write', {'previewId': 'original'})
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0][1]['input']['action'], 'db.write')
        self.assertEqual(self.calls[0][1]['input']['input'], {'previewId': 'original'})

    def test_family_discovery_uses_same_remote_action_without_recursion(self):
        self.answer({'status': 'completed', 'result': {'family': 'playback', 'actions': []}})
        result = self.client.describe('playback')
        self.assertEqual(result['family'], 'playback')
        self.assertEqual(result['targetDeviceId'], 'target')
        self.assertEqual(result['cliPrefix'], ['nipa', '--device', 'target'])
        self.assertIn('--device', result['commandScope'])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0][1]['input']['action'], 'capability.describe')


if __name__ == '__main__':
    unittest.main()
