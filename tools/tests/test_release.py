import base64
import hashlib
import io
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

spec = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[1] / "release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "android").mkdir()
        (self.root / "lib/core").mkdir(parents=True)
        (self.root / "docs/releases").mkdir(parents=True)
        (self.root / "pubspec.yaml").write_text("version: 1.4.0+9\n", encoding="utf-8")
        (self.root / "lib/core/updates.dart").write_text("const appVersion = '1.4.0';", encoding="utf-8")
        (self.root / "docs/releases/v1.4.0.md").write_text("Release notes", encoding="utf-8")
        self.env = dict(zip(release.SIGNING_NAMES, [base64.b64encode(b"test-key").decode(), "p a\\ss:=密😀", "alias", "key\npassword"]))

    def test_version_tag_and_display_must_match(self):
        self.assertEqual(release.version(self.root, "v1.4.0+9"), ("1.4.0", 9))
        for tag in ["v1.4.0", "v1.4.0+10", "v1.3.0+9"]:
            with self.assertRaises(ValueError):
                release.version(self.root, tag)
        (self.root / "lib/core/updates.dart").write_text("const appVersion = '1.3.0';", encoding="utf-8")
        with self.assertRaises(ValueError):
            release.version(self.root)

    def test_missing_notes_and_unsafe_build_numbers_fail(self):
        (self.root / "docs/releases/v1.4.0.md").unlink()
        with self.assertRaises(ValueError):
            release.version(self.root)
        for value in ["1.4.0+0", "1.4.0+1000", "1.4.0", "1.4.0+9\nvalue", "01.4.0+9"]:
            with self.assertRaises(ValueError):
                release.parse_version(value)

    def test_java_password_escaping(self):
        self.assertEqual(release.property_escape(self.env["ANDROID_KEYSTORE_PASSWORD"]), r"p\ a\\ss\:\=\u5bc6\ud83d\ude00")
        self.assertEqual(release.property_escape(" a\n\r\t\f#!"), r"\ a\n\r\t\f\#\!")

    def test_missing_and_corrupt_secrets_create_no_files(self):
        for env in [{}, {**self.env, "ANDROID_KEYSTORE_BASE64": "!!"}, {**self.env, "ANDROID_KEY_ALIAS": ""}]:
            with self.assertRaises(ValueError):
                release.prepare_signing(self.root, env)
        self.assertFalse((self.root / "android/key.properties").exists())
        self.assertFalse((self.root / ".private/ci-release.jks").exists())

    def test_wrong_certificate_is_removed(self):
        cert = subprocess.CompletedProcess([], 0, stdout=b"different-cert", stderr=b"")
        with patch.object(release.subprocess, "run", return_value=cert):
            with self.assertRaisesRegex(ValueError, "certificate"):
                release.prepare_signing(self.root, self.env)
        self.assertFalse((self.root / ".private/ci-release.jks").exists())
        self.assertFalse((self.root / "android/key.properties").exists())

    def test_original_certificate_writes_escaped_properties_and_cleans(self):
        cert = subprocess.CompletedProcess([], 0, stdout=b"test-cert", stderr=b"")
        with patch.object(release, "EXPECTED_CERT", hashlib.sha256(cert.stdout).hexdigest()), patch.object(release.subprocess, "run", return_value=cert) as run:
            release.prepare_signing(self.root, self.env)
        args = run.call_args.args[0]
        self.assertIn("-storepass:env", args)
        self.assertNotIn(self.env["ANDROID_KEYSTORE_PASSWORD"], args)
        props = self.root / "android/key.properties"
        self.assertIn(r"keyPassword=key\npassword", props.read_text(encoding="ascii"))
        release.clean_signing(self.root)
        self.assertFalse(props.exists())
        self.assertFalse((self.root / ".private/ci-release.jks").exists())

    def test_local_signing_files_cannot_be_overwritten_or_cleaned(self):
        props = self.root / "android/key.properties"
        props.write_text("storeFile=../.private/saisuite-release.jks\n", encoding="ascii")
        with self.assertRaises(ValueError):
            release.prepare_signing(self.root, self.env)
        release.clean_signing(self.root)
        self.assertTrue(props.exists())

    def test_upgrade_requires_higher_build_and_no_version_downgrade(self):
        release.check_upgrade(("1.10.0", 10), "v1.9.0+9")
        release.check_upgrade(("1.4.0", 10), "v1.4.0+9")
        for current in [("1.5.0", 9), ("1.3.0", 10), ("1.4.0", 8)]:
            with self.assertRaises(ValueError):
                release.check_upgrade(current, "v1.4.0+9")

    def test_artifact_tampering_blocks_publish(self):
        self.make_assets(self.root)
        self.assertEqual(len(release.verify_checksums(self.root, "1.4.0")), 9)
        (self.root / release.filenames("1.4.0")[0]).write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            release.verify_checksums(self.root, "1.4.0")

    def test_missing_or_tampered_windows_package_blocks_release(self):
        self.make_assets(self.root / 'dist')
        env = {'GH_REPO': 'wxia529/SaiSuite', 'RELEASE_TAG': 'v1.4.0+9', 'RELEASE_WINDOWS': 'true'}
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'version', return_value=('1.4.0', 9)), patch.dict(os.environ, env), patch.object(release.subprocess, 'run') as run:
            with self.assertRaises(FileNotFoundError):
                release.publish()
            package = self.root / 'dist/SaiSuite-1.4.0-windows-x64.zip'
            package.write_bytes(b'windows fixture')
            package.with_suffix('.zip.sha256').write_text('incorrect checksum', encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'Windows package checksum'):
                release.publish()
            package.with_suffix('.zip.sha256').write_text(f'{release.digest(package)}  {package.name}\n', encoding='ascii')
            with self.assertRaises(FileNotFoundError):
                release.publish()
            installer = self.root / 'dist/SaiSuite-1.4.0-windows-x64-setup.exe'
            installer.write_bytes(b'installer fixture')
            installer.with_suffix('.exe.sha256').write_text('incorrect checksum', encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'Windows package checksum'):
                release.publish()
            run.assert_not_called()

    def test_windows_installer_and_zip_are_both_required_and_published(self):
        dist = self.root / 'dist'
        self.make_assets(dist)
        for suffix in ('.zip', '-setup.exe'):
            package = dist / f'SaiSuite-1.4.0-windows-x64{suffix}'
            package.write_bytes(b'windows fixture')
            package.with_suffix(package.suffix + '.sha256').write_text(f'{release.digest(package)}  {package.name}\n', encoding='ascii')
        assets = list(dist.iterdir())
        draft = {'id': 42, 'tag_name': 'v1.4.0+9', 'draft': True, 'assets': [{'name': p.name, 'size': p.stat().st_size, 'state': 'uploaded'} for p in assets]}
        env = {'GH_REPO': 'wxia529/SaiSuite', 'RELEASE_TAG': 'v1.4.0+9', 'RELEASE_WINDOWS': 'true', 'GITHUB_SHA': 'a' * 40}
        ref = {'object': {'type': 'commit', 'sha': 'a' * 40}}
        published = {**draft, 'draft': False}
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'version', return_value=('1.4.0', 9)), patch.dict(os.environ, env), patch.object(release, 'find_release', return_value=None) as find, patch.object(release, 'github_get', side_effect=[None, ref, draft]), patch.object(release, 'github_write', side_effect=[{**draft, 'assets': []}, published]) as write, patch.object(release, 'upload_assets') as upload:
            release.publish()
        self.assertIn(dist / 'SaiSuite-1.4.0-windows-x64-setup.exe', upload.call_args.args[2])
        self.assertIn(dist / 'SaiSuite-1.4.0-windows-x64.zip', upload.call_args.args[2])
        self.assertEqual(write.call_args_list[0].args[1], 'releases')
        self.assertEqual(write.call_args_list[1].args[1], 'releases/42')
        find.assert_called_once()
        self.assertEqual(len(assets), 13)

    def make_assets(self, folder):
        folder.mkdir(exist_ok=True)
        lines = []
        for name in release.filenames("1.4.0"):
            apk = folder / name
            apk.write_bytes(b"fixture " + name.encode())
            line = f"{release.digest(apk)}  {name}\n"
            apk.with_suffix(".apk.sha256").write_text(line, encoding="ascii")
            lines.append(line)
        (folder / "SHA256SUMS.txt").write_text("".join(lines), encoding="ascii")

    def test_publish_checks_complete_draft_before_publication(self):
        dist = self.root / "dist"
        self.make_assets(dist)
        assets = release.verify_checksums(dist, "1.4.0")
        draft = {"id": 42, "tag_name": "v1.4.0+9", "draft": True, "assets": [{"name": p.name, "size": p.stat().st_size, "state": "uploaded"} for p in assets]}
        for complete in [False, True]:
            response = draft if complete else {**draft, "assets": []}
            ref = {"object": {"type": "commit", "sha": "a" * 40}}
            with patch.object(release, "ROOT", self.root), patch.object(release, "version", return_value=("1.4.0", 9)), patch.dict(os.environ, {"GH_REPO": "wxia529/SaiSuite", "RELEASE_TAG": "v1.4.0+9", "GITHUB_SHA": "a" * 40}), patch.object(release, "find_release", return_value=None) as find, patch.object(release, "github_get", side_effect=[None, ref] + [response] * 4) as get, patch.object(release, "github_write", side_effect=[{**draft, 'assets': []}, {**draft, 'draft': False}]) as write, patch.object(release, "upload_assets") as upload, patch.object(release.time, 'sleep'):
                if complete:
                    release.publish()
                else:
                    with self.assertRaisesRegex(ValueError, "incomplete"):
                        release.publish()
                self.assertEqual(get.call_args.args[1], "releases/42")
            find.assert_called_once()
            self.assertTrue(write.call_args_list[0].args[2]['draft'])
            self.assertEqual(write.call_args_list[0].args[2]['tag_name'], 'v1.4.0+9')
            self.assertEqual(write.call_args_list[0].args[2]['target_commitish'], 'a' * 40)
            upload.assert_called_once()
            self.assertEqual(write.call_count, 2 if complete else 1)
            if complete:
                self.assertEqual(write.call_args.kwargs['method'], 'PATCH')
                self.assertFalse(write.call_args.args[2]['draft'])

    def test_public_release_cannot_be_replaced(self):
        self.make_assets(self.root / "dist")
        with patch.object(release, "ROOT", self.root), patch.object(release, "version", return_value=("1.4.0", 9)), patch.dict(os.environ, {"GH_REPO": "wxia529/SaiSuite", "RELEASE_TAG": "v1.4.0+9"}), patch.object(release, "find_release", return_value={"draft": False}), patch.object(release, "github_write") as write, patch.object(release, 'upload_assets') as upload:
            with self.assertRaisesRegex(ValueError, "already public"):
                release.publish()
        write.assert_not_called()
        upload.assert_not_called()

    def test_draft_is_found_when_published_tag_endpoint_returns_404(self):
        draft = {"id": 42, "tag_name": "v1.4.0+9", "draft": True}
        page = [{"tag_name": "v1.3.1+8", "draft": False}] * 100
        with patch.object(release, "github_get", side_effect=[None, page, [draft]]) as get:
            self.assertEqual(release.find_release("wxia529/SaiSuite", "v1.4.0+9"), draft)
        self.assertEqual(get.call_args.args[1], "releases?per_page=100&page=2")
        with patch.object(release, "github_get", side_effect=[None, []]):
            self.assertIsNone(release.find_release("wxia529/SaiSuite", "v1.4.0+9"))

    def test_failed_draft_upload_can_resume_without_creating_another_release(self):
        dist = self.root / "dist"
        self.make_assets(dist)
        assets = release.verify_checksums(dist, "1.4.0")
        draft = {"id": 42, "tag_name": "v1.4.0+9", "draft": True, "assets": [{"name": p.name, "size": p.stat().st_size, "state": "uploaded"} for p in assets]}
        ref = {"object": {"type": "commit", "sha": "a" * 40}}
        with patch.object(release, "ROOT", self.root), patch.object(release, "version", return_value=("1.4.0", 9)), patch.dict(os.environ, {"GH_REPO": "wxia529/SaiSuite", "RELEASE_TAG": "v1.4.0+9", "GITHUB_SHA": "a" * 40}), patch.object(release, "find_release", return_value=draft), patch.object(release, "github_get", side_effect=[None, ref, draft]), patch.object(release, "github_write", return_value={**draft, 'draft': False}) as write, patch.object(release, 'upload_assets') as upload:
            release.publish()
        upload.assert_called_once()
        write.assert_called_once_with('wxia529/SaiSuite', 'releases/42', {'draft': False, 'prerelease': False, 'make_latest': 'true'}, method='PATCH')

    def test_streamed_upload_uses_release_id_and_encoded_filename(self):
        file = self.root / 'SaiSuite + notes.txt'
        file.write_bytes(b'asset content')
        draft = {'id': 42, 'assets': [{'id': 7, 'name': file.name, 'size': 1, 'state': 'uploaded'}]}
        def uploaded(request, timeout):
            self.assertEqual(request.full_url, 'https://uploads.github.com/repos/wxia529/SaiSuite/releases/42/assets?name=SaiSuite%20%2B%20notes.txt')
            self.assertEqual(request.get_method(), 'POST')
            self.assertEqual(request.get_header('Content-length'), str(file.stat().st_size))
            self.assertTrue(hasattr(request.data, 'read'))
            self.assertEqual(request.data.read(), b'asset content')
            return {'name': file.name, 'size': file.stat().st_size, 'state': 'uploaded'}
        with patch.dict(os.environ, {'GH_TOKEN': 'fake-token'}), patch.object(release, 'github_write') as write, patch.object(release, 'github_response', side_effect=uploaded):
            release.upload_assets('wxia529/SaiSuite', draft, [file])
        write.assert_called_once_with('wxia529/SaiSuite', 'releases/assets/7', method='DELETE')

    def test_resume_reuses_only_matching_server_digest(self):
        file = self.root / 'asset.apk'
        file.write_bytes(b'fresh')
        asset = {'id': 7, 'name': file.name, 'size': 5, 'state': 'uploaded', 'digest': 'sha256:' + release.digest(file)}
        with patch.object(release, 'github_write') as write, patch.object(release, 'github_response') as response:
            release.upload_assets('wxia529/SaiSuite', {'id': 42, 'assets': [asset]}, [file])
        write.assert_not_called()
        response.assert_not_called()
        for checksum in ('sha256:' + '0' * 64, None):
            with patch.dict(os.environ, {'GH_TOKEN': 'fake-token'}), patch.object(release, 'github_write') as write, patch.object(release, 'github_response', return_value=asset):
                release.upload_assets('wxia529/SaiSuite', {'id': 42, 'assets': [{**asset, 'digest': checksum}]}, [file])
            write.assert_called_once()

    def test_complete_draft_waits_for_id_visibility_and_checks_digest(self):
        file = self.root / 'asset.apk'
        file.write_bytes(b'fixture')
        draft = {'id': 42, 'tag_name': 'v1.4.0+9', 'draft': True, 'assets': []}
        complete = {**draft, 'assets': [{'name': file.name, 'size': file.stat().st_size, 'state': 'uploaded', 'digest': 'sha256:' + release.digest(file)}]}
        with patch.object(release, 'github_get', side_effect=[None, draft, complete]) as get, patch.object(release.time, 'sleep') as sleep:
            self.assertEqual(release.complete_draft('wxia529/SaiSuite', 42, 'v1.4.0+9', [file]), complete)
        self.assertTrue(all(call.args[1] == 'releases/42' for call in get.call_args_list))
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2])
        complete['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with patch.object(release, 'github_get', return_value=complete), patch.object(release.time, 'sleep'):
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                release.complete_draft('wxia529/SaiSuite', 42, 'v1.4.0+9', [file])

    def test_draft_identity_must_match_tag_and_have_numeric_id(self):
        draft = {'id': 42, 'tag_name': 'v1.4.0+9', 'draft': True}
        release.validate_draft(draft, 'v1.4.0+9')
        for invalid in (None, {**draft, 'draft': False}, {**draft, 'tag_name': 'other'}, {**draft, 'id': '42'}, {**draft, 'id': True}, {**draft, 'id': 0}):
            with self.assertRaises(ValueError):
                release.validate_draft(invalid, 'v1.4.0+9')

    def test_json_write_preserves_release_notes_and_http_method(self):
        body = {'tag_name': 'v1.4.0+9', 'draft': True, 'body': '中文\nsecond line'}
        with patch.dict(os.environ, {'GH_TOKEN': 'fake-token'}), patch.object(release, 'github_response', return_value={'id': 42}) as response:
            self.assertEqual(release.github_write('wxia529/SaiSuite', 'releases', body), {'id': 42})
        request = response.call_args.args[0]
        self.assertEqual(request.get_method(), 'POST')
        self.assertEqual(release.json.loads(request.data), body)

    def test_no_content_delete_and_write_404_are_handled_correctly(self):
        response = io.BytesIO(b'')
        response.status = 204
        with patch.object(release, 'urlopen', return_value=response):
            self.assertIsNone(release.github_response(Request('https://api.github.com/example', method='DELETE')))
        error = HTTPError('https://api.github.com/example', 404, 'Not found', {}, None)
        with patch.object(release, 'urlopen', side_effect=error):
            self.assertIsNone(release.github_response(Request('https://api.github.com/example')))
            with self.assertRaisesRegex(ValueError, 'HTTP 404'):
                release.github_response(Request('https://api.github.com/example', method='POST'))

    def test_duplicate_publication_is_skipped_but_drafts_can_resume(self):
        for response, expected in [(None, False), ({"draft": True}, False), ({"draft": False}, True)]:
            with patch.object(release, "github_get", return_value=response):
                self.assertEqual(release.is_published("wxia529/SaiSuite", "v1.4.0+9"), expected)

    def test_existing_tag_must_match_artifact_source(self):
        source = "a" * 40
        with patch.object(release, "github_get", return_value={"object": {"type": "commit", "sha": source}}):
            release.verify_tag_source("wxia529/SaiSuite", "v1.4.0+9", source)
        with patch.object(release, "github_get", return_value=None):
            with self.assertRaisesRegex(ValueError, "Push the release tag"):
                release.verify_tag_source("wxia529/SaiSuite", "v1.4.0+9", source)
        with patch.object(release, "github_get", side_effect=[{"object": {"type": "tag", "sha": "b" * 40}}, {"object": {"type": "commit", "sha": source}}]):
            release.verify_tag_source("wxia529/SaiSuite", "v1.4.0+9", source)
        with patch.object(release, "github_get", return_value={"object": {"type": "commit", "sha": "b" * 40}}):
            with self.assertRaisesRegex(ValueError, "another commit"):
                release.verify_tag_source("wxia529/SaiSuite", "v1.4.0+9", source)


if __name__ == "__main__":
    unittest.main()
