import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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
        draft = {'id': 42, 'draft': True, 'assets': [{'name': p.name, 'size': p.stat().st_size, 'state': 'uploaded'} for p in assets]}
        env = {'GH_REPO': 'wxia529/SaiSuite', 'RELEASE_TAG': 'v1.4.0+9', 'RELEASE_WINDOWS': 'true', 'GITHUB_SHA': 'a' * 40}
        ref = {'object': {'type': 'commit', 'sha': 'a' * 40}}
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'version', return_value=('1.4.0', 9)), patch.dict(os.environ, env), patch.object(release, 'find_release', side_effect=[None, draft]), patch.object(release, 'github_get', side_effect=[None, ref, draft]), patch.object(release.subprocess, 'run') as run:
            release.publish()
        upload = run.call_args_list[1].args[0]
        self.assertIn(str(dist / 'SaiSuite-1.4.0-windows-x64-setup.exe'), upload)
        self.assertIn(str(dist / 'SaiSuite-1.4.0-windows-x64.zip'), upload)
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
        draft = {"id": 42, "draft": True, "assets": [{"name": p.name, "size": p.stat().st_size, "state": "uploaded"} for p in assets]}
        for complete in [False, True]:
            response = draft if complete else {"draft": True, "assets": []}
            ref = {"object": {"type": "commit", "sha": "a" * 40}}
            with patch.object(release, "ROOT", self.root), patch.object(release, "version", return_value=("1.4.0", 9)), patch.dict(os.environ, {"GH_REPO": "wxia529/SaiSuite", "RELEASE_TAG": "v1.4.0+9", "GITHUB_SHA": "a" * 40}), patch.object(release, "find_release", side_effect=[None, draft]), patch.object(release, "github_get", side_effect=[None, ref, response]) as get, patch.object(release.subprocess, "run") as run:
                if complete:
                    release.publish()
                else:
                    with self.assertRaisesRegex(ValueError, "incomplete"):
                        release.publish()
                self.assertEqual(get.call_args.args[1], "releases/42")
            commands = [call.args[0] for call in run.call_args_list]
            self.assertIn("--draft", commands[0])
            self.assertIn("--verify-tag", commands[0])
            self.assertEqual(commands[1][2], "upload")
            self.assertEqual(any("--draft=false" in command for command in commands), complete)

    def test_public_release_cannot_be_replaced(self):
        self.make_assets(self.root / "dist")
        with patch.object(release, "ROOT", self.root), patch.object(release, "version", return_value=("1.4.0", 9)), patch.dict(os.environ, {"GH_REPO": "wxia529/SaiSuite", "RELEASE_TAG": "v1.4.0+9"}), patch.object(release, "find_release", return_value={"draft": False}), patch.object(release.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "already public"):
                release.publish()
        run.assert_not_called()

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
        draft = {"id": 42, "draft": True, "assets": [{"name": p.name, "size": p.stat().st_size, "state": "uploaded"} for p in assets]}
        ref = {"object": {"type": "commit", "sha": "a" * 40}}
        with patch.object(release, "ROOT", self.root), patch.object(release, "version", return_value=("1.4.0", 9)), patch.dict(os.environ, {"GH_REPO": "wxia529/SaiSuite", "RELEASE_TAG": "v1.4.0+9", "GITHUB_SHA": "a" * 40}), patch.object(release, "find_release", return_value=draft), patch.object(release, "github_get", side_effect=[None, ref, draft]), patch.object(release.subprocess, "run") as run:
            release.publish()
        self.assertEqual([call.args[0][2] for call in run.call_args_list], ["upload", "edit"])

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
