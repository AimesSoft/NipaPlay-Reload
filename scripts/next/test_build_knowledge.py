"""Knowledge packaging invariants, without starting an app or reading user data."""
import hashlib
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import build_knowledge as knowledge


class KnowledgeBuildTest(unittest.TestCase):
    def setUp(self):
        mock = patch.object(knowledge, 'git', side_effect=lambda *args: 'a' * 40 if args == ('rev-parse', 'HEAD') else '')
        mock.start()
        self.addCleanup(mock.stop)

    def test_untracked_inputs_override_external_clean_stamp(self):
        with patch.object(knowledge, 'git', side_effect=lambda *args: 'a' * 40 if args == ('rev-parse', 'HEAD') else '?? docs/next/KNOWLEDGE.md'):
            self.assertTrue(knowledge.build(commit='a' * 40, dirty=False)['sourceDirty'])
        with patch.object(knowledge, 'git', return_value=None):
            self.assertIsNone(knowledge.build(commit='a' * 40, dirty=False)['sourceDirty'])

    def test_curated_documents_are_exact_and_bounded(self):
        data = knowledge.build(version='test', commit='a' * 40, dirty=False)
        self.assertFalse(data['sourceDirty'])
        self.assertLess(len(data['documents']), 64)
        for doc in data['documents']:
            self.assertNotIn('/history/', doc['id'])
            self.assertNotIn('_REPORT', doc['id'])
            self.assertEqual(doc['content'], (knowledge.ROOT / doc['id']).read_text())
            self.assertEqual(doc['sha256'], hashlib.sha256(doc['content'].encode()).hexdigest())
            self.assertLess(len(doc['content'].encode()), 512 * 1024)
        self.assertIn('knowledge.search', data['actions'])
        self.assertIn('playback.kernel', data['actions'])
        for sources in data['actions'].values():
            for source in sources:
                self.assertTrue((knowledge.ROOT / source).is_file(), source)

    def test_content_revision_is_independent_of_build_stamp(self):
        one = knowledge.build(version='one', commit='a' * 40, dirty=False)
        two = knowledge.build(version='two', commit='b' * 40, dirty=True)
        self.assertEqual(one['contentRevision'], two['contentRevision'])
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'catalog.json'
            knowledge.write(path, version='one', commit='a' * 40, dirty=False)
            self.assertEqual(json.loads(path.read_text()), one)
            self.assertLess(path.stat().st_size, 4 * 1024 * 1024)

    def test_both_packaging_paths_include_knowledge(self):
        root = knowledge.ROOT
        self.assertIn('assets/next/knowledge/catalog.json', (root / 'pubspec.yaml').read_text())
        self.assertIn('assets/next/knowledge', (root / 'tool/next/headless_bundle.py').read_text())
        package = (root / 'scripts/next/headless/package.sh').read_text()
        self.assertIn('copy_tree assets/next/knowledge', package)
        self.assertIn('-DNIPAPLAY_SOURCE_COMMIT=', package)
        self.assertIn('knowledge["write"]', (root / '.github/workflows/scripts/generate-build-info-json.py').read_text())


if __name__ == '__main__':
    unittest.main()
