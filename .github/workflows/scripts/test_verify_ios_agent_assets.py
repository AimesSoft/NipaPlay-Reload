import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile


spec = importlib.util.spec_from_file_location(
    'verify_ios_assets', Path(__file__).with_name('verify-ios-agent-assets.py'))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
ASSETS = 'Frameworks/App.framework/flutter_assets/'


class IosAssetVerificationTest(unittest.TestCase):
    def test_body_app_accepts_regular_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Runner.app'
            assets = app / ASSETS
            assets.mkdir(parents=True)
            (assets / 'AssetManifest.bin').write_bytes(b'manifest')
            (assets / 'player.png').write_bytes(b'image')
            verifier.verify(app)

    def test_ipa_rejects_each_executable_seed_family(self):
        for asset in ['harness/tools/discovery.py', 'harness/nipa',
                      'harness/hooks/session_start.py', 'agent/dsh/nipa-app-server.mjs']:
            with self.subTest(asset=asset), tempfile.TemporaryDirectory() as directory:
                ipa = Path(directory) / 'test.ipa'
                with zipfile.ZipFile(ipa, 'w') as archive:
                    archive.writestr('Payload/Runner.app/' + ASSETS + 'AssetManifest.bin', b'manifest')
                    archive.writestr('Payload/Runner.app/' + ASSETS + 'assets/next/' + asset, b'code')
                with self.assertRaisesRegex(ValueError, 'must not bundle'):
                    verifier.verify(ipa)

    def test_clean_ipa_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'test.ipa'
            with zipfile.ZipFile(ipa, 'w') as archive:
                archive.writestr('Payload/Runner.app/' + ASSETS + 'AssetManifest.bin', b'manifest')
            verifier.verify(ipa)

    def test_wrong_input_cannot_pass_as_an_empty_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'No Flutter asset manifest'):
                verifier.verify(Path(directory))


if __name__ == '__main__':
    unittest.main()
