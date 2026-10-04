"""Cross-platform signing, packaging and GitHub Release checks (standard library only)."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CERT = "86d06951211ad5412b4dd90079a379b46bbc223933b9891599835ff2dd99b250"
PACKAGE = "io.github.wxia529.saisuite"
VARIANTS = {"universal": 0, "armeabi-v7a": 1000, "arm64-v8a": 2000, "x86_64": 4000}
SIGNING_NAMES = (
    "ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD",
)


def parse_version(value: str) -> tuple[str, int]:
    match = re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)", value)
    if not match or not 0 < int(match[4]) < 1000:
        raise ValueError("Version must be X.Y.Z+BUILD with BUILD between 1 and 999")
    return value.split("+")[0], int(match[4])


def version(root: Path = ROOT, tag: str = "") -> tuple[str, int]:
    matches = re.findall(r"^version:\s*(\S+)\s*$", (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if len(matches) != 1:
        raise ValueError("pubspec.yaml must contain exactly one version")
    name, build = parse_version(matches[0])
    displayed = re.search(r"const appVersion = '([^']+)';", (root / "lib/core/updates.dart").read_text(encoding="utf-8"))
    if not displayed or displayed[1] != name:
        raise ValueError("pubspec.yaml and appVersion disagree")
    if tag and tag != f"v{name}+{build}":
        raise ValueError("Release tag does not match the source version and build number")
    if not (root / f"docs/releases/v{name}.md").is_file():
        raise ValueError("Release notes are missing")
    return name, build


def property_escape(value: str) -> str:
    """Java Properties.load(InputStream) expects Latin-1 and escaped Unicode."""
    escaped = []
    for char in value:
        if char in "\\ =:#!":
            escaped.append("\\" + char)
        elif char in "\n\r\t\f":
            escaped.append({"\n": "\\n", "\r": "\\r", "\t": "\\t", "\f": "\\f"}[char])
        elif not 32 <= ord(char) <= 126:
            encoded = char.encode("utf-16-be")
            escaped.extend(f"\\u{int.from_bytes(encoded[i:i+2], 'big'):04x}" for i in range(0, len(encoded), 2))
        else:
            escaped.append(char)
    return "".join(escaped)


def prepare_signing(root: Path = ROOT, env=None):
    env = os.environ if env is None else env
    missing = [name for name in SIGNING_NAMES if not env.get(name)]
    if missing:
        raise ValueError("Missing GitHub repository Secrets: " + ", ".join(missing))
    props, key = root / "android/key.properties", root / ".private/ci-release.jks"
    if props.exists() or key.exists():
        raise ValueError("Refusing to overwrite existing signing files")
    try:
        decoded = base64.b64decode("".join(env[SIGNING_NAMES[0]].split()), validate=True)
    except ValueError:
        raise ValueError("ANDROID_KEYSTORE_BASE64 is not valid Base64") from None
    if not decoded:
        raise ValueError("The signing keystore is empty")
    key.parent.mkdir(parents=True, exist_ok=True)
    try:
        with key.open("xb") as handle:
            key.chmod(0o600)
            handle.write(decoded)
        cert = subprocess.run(
            ["keytool", "-exportcert", "-keystore", str(key), "-storepass:env",
             "ANDROID_KEYSTORE_PASSWORD", "-alias", env["ANDROID_KEY_ALIAS"]],
            env=dict(env), capture_output=True, check=False,
        )
        if cert.returncode or hashlib.sha256(cert.stdout).hexdigest() != EXPECTED_CERT:
            raise ValueError("Keystore credentials or certificate do not match the existing release key")
        values = {"storeFile": "../.private/ci-release.jks",
                  "storePassword": env["ANDROID_KEYSTORE_PASSWORD"],
                  "keyAlias": env["ANDROID_KEY_ALIAS"], "keyPassword": env["ANDROID_KEY_PASSWORD"]}
        with props.open("x", encoding="ascii", newline="\n") as handle:
            props.chmod(0o600)
            handle.write("".join(f"{name}={property_escape(value)}\n" for name, value in values.items()))
    except Exception:
        key.unlink(missing_ok=True)
        raise
    print("Existing release certificate verified; temporary signing files prepared")


def clean_signing(root: Path = ROOT):
    # Only remove properties pointing at our CI key; never remove local signing material.
    props = root / "android/key.properties"
    if props.exists() and "storeFile=../.private/ci-release.jks\n" in props.read_text(encoding="ascii"):
        props.unlink()
    (root / ".private/ci-release.jks").unlink(missing_ok=True)


def filenames(name: str) -> list[str]:
    return [f"SaiSuite-{name}-{abi}.apk" for abi in VARIANTS]


def collect(universal: bool, split: bool):
    name, _ = version()
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    for abi in VARIANTS:
        if (abi == "universal" and universal) or (abi != "universal" and split):
            source = "app-release.apk" if abi == "universal" else f"app-{abi}-release.apk"
            shutil.copyfile(ROOT / "build/app/outputs/flutter-apk" / source, dist / f"SaiSuite-{name}-{abi}.apk")


def sdk_tool(name: str) -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise ValueError("Set ANDROID_HOME to the Android SDK directory")
    suffix = ".bat" if name == "apksigner" and os.name == "nt" else ".exe" if os.name == "nt" else ""
    tool = Path(sdk) / "build-tools/36.0.0" / (name + suffix)
    if not tool.is_file():
        raise ValueError(f"Android build-tools 36.0.0 tool missing: {name}")
    return str(tool)


def digest(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def verify():
    name, build = version()
    sums = []
    for abi, offset in VARIANTS.items():
        path = ROOT / "dist" / f"SaiSuite-{name}-{abi}.apk"
        badging = subprocess.run([sdk_tool("aapt"), "dump", "badging", str(path)], capture_output=True, text=True, encoding="utf-8", check=True).stdout
        package_line = next((line for line in badging.splitlines() if line.startswith("package:")), "")
        expected = [f"name='{PACKAGE}'", f"versionCode='{build + offset}'", f"versionName='{name}'"]
        if not all(item in package_line for item in expected) or "sdkVersion:'24'" not in badging or "targetSdkVersion:'36'" not in badging:
            raise ValueError(f"Package, version or SDK mismatch: {path.name}")
        permissions = set(re.findall(r"uses-permission(?:-sdk-\d+)?: name='([^']+)'", badging))
        if "android.permission.INTERNET" not in permissions or "android.permission.REQUEST_INSTALL_PACKAGES" in permissions:
            raise ValueError(f"Update network or install permission mismatch: {path.name}")
        certs = subprocess.run([sdk_tool("apksigner"), "verify", "--print-certs", str(path)], capture_output=True, text=True, encoding="utf-8", check=True).stdout
        hashes = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)", certs)
        if [item.lower() for item in hashes] != [EXPECTED_CERT]:
            raise ValueError(f"Release certificate mismatch: {path.name}")
        with zipfile.ZipFile(path) as apk:
            abis = {entry.split("/")[1] for entry in apk.namelist() if entry.startswith("lib/") and entry.endswith(".so")}
        if abis != (set(VARIANTS) - {"universal"} if abi == "universal" else {abi}):
            raise ValueError(f"Native ABI mismatch: {path.name}")
        line = f"{digest(path)}  {path.name}\n"
        path.with_suffix(".apk.sha256").write_text(line, encoding="ascii")
        sums.append(line)
        print(f"Verified {path.name}: versionCode={build + offset}, original certificate, ABI={abi}")
    (ROOT / "dist/SHA256SUMS.txt").write_text("".join(sums), encoding="ascii")


def verify_checksums(root: Path, name: str) -> list[Path]:
    assets, lines = [], []
    for filename in filenames(name):
        apk = root / filename
        checksum = apk.with_suffix(".apk.sha256")
        line = f"{digest(apk)}  {apk.name}\n"
        if checksum.read_text(encoding="ascii") != line:
            raise ValueError(f"Artifact checksum mismatch: {apk.name}")
        assets.extend([apk, checksum])
        lines.append(line)
    summary = root / "SHA256SUMS.txt"
    if summary.read_text(encoding="ascii") != "".join(lines):
        raise ValueError("Checksum summary does not match the four packages")
    return assets + [summary]


def github_headers():
    return {
        "Authorization": f"Bearer {os.environ['GH_TOKEN']}", "User-Agent": "SaiSuite-release",
        "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
        "Cache-Control": "no-cache",
    }


def github_response(req: Request, timeout: int = 30):
    try:
        with urlopen(req, timeout=timeout) as response:
            return json.load(response) if response.status != 204 else None
    except HTTPError as error:
        if error.code == 404 and req.get_method() == "GET":
            return None
        raise ValueError(f"GitHub API request failed: HTTP {error.code}") from None


def github_get(repo: str, path: str):
    return github_response(Request(f"https://api.github.com/repos/{repo}/{path}", headers=github_headers()))


def github_write(repo: str, path: str, payload=None, method: str = "POST"):
    headers = github_headers()
    headers["Content-Type"] = "application/json"
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
    return github_response(Request(f"https://api.github.com/repos/{repo}/{path}",
                                   data=data, headers=headers, method=method))


def validate_draft(draft, tag: str):
    if not isinstance(draft, dict) or draft.get("draft") is not True or draft.get("tag_name") != tag:
        raise ValueError("Expected the matching unpublished release draft")
    if type(draft.get("id")) is not int or draft["id"] <= 0:
        raise ValueError("Release draft is missing a valid ID")


def upload_assets(repo: str, draft: dict, files: list[Path]):
    # Use the ID returned by creation, not a second lookup by tag or release list.
    existing = {asset["name"]: asset for asset in draft.get("assets", [])}
    for path in files:
        previous = existing.get(path.name)
        if previous:
            if (previous.get("state") == "uploaded" and previous.get("size") == path.stat().st_size
                    and previous.get("digest") == "sha256:" + digest(path)):
                print(f"Reused verified asset {path.name}")
                continue
            asset_id = previous.get("id")
            if type(asset_id) is not int or asset_id <= 0:
                raise ValueError("Existing release asset is missing a valid ID")
            github_write(repo, f"releases/assets/{asset_id}", method="DELETE")
        headers = github_headers()
        headers.update({"Content-Type": "application/octet-stream", "Content-Length": str(path.stat().st_size)})
        url = f"https://uploads.github.com/repos/{repo}/releases/{draft['id']}/assets?name={quote(path.name, safe='')}"
        # Stream large APKs and ZIPs; do not buffer the entire package in memory.
        with path.open("rb") as body:
            uploaded = github_response(Request(url, data=body, headers=headers, method="POST"), timeout=180)
        if (not uploaded or uploaded.get("name") != path.name or uploaded.get("size") != path.stat().st_size
                or uploaded.get("state") != "uploaded"):
            raise ValueError(f"Release asset upload did not complete: {path.name}")
        print(f"Uploaded {path.name}")


def complete_draft(repo: str, release_id: int, tag: str, files: list[Path]):
    expected = {asset.name: asset.stat().st_size for asset in files}
    hashes = {asset.name: "sha256:" + digest(asset) for asset in files}
    for delay in (0, 1, 2, 4):
        if delay:
            time.sleep(delay)
        draft = github_get(repo, f"releases/{release_id}")
        if draft:
            validate_draft(draft, tag)
            uploaded = draft.get("assets", [])
            if ({asset["name"]: asset["size"] for asset in uploaded} == expected
                    and len(uploaded) == len(expected)
                    and all(asset["state"] == "uploaded" and
                            (not asset.get("digest") or asset["digest"] == hashes[asset["name"]]) for asset in uploaded)):
                return draft
    raise ValueError("Draft release assets are incomplete or unexpected; leaving draft unpublished")


def check_upgrade(current: tuple[str, int], previous_tag: str):
    previous = parse_version(previous_tag.removeprefix("v"))
    if current[1] <= previous[1] or tuple(map(int, current[0].split("."))) < tuple(map(int, previous[0].split("."))):
        raise ValueError("Release must increase the build number and must not decrease the version")


def is_published(repo: str, tag: str) -> bool:
    existing = github_get(repo, "releases/tags/" + quote(tag, safe=""))
    return bool(existing and not existing["draft"])


def find_release(repo: str, tag: str):
    # The by-tag endpoint only returns published releases. Authenticated release
    # listings also include drafts; preserve their numeric ID for later reads.
    published = github_get(repo, "releases/tags/" + quote(tag, safe=""))
    if published:
        return published
    page = 1
    while True:
        releases = github_get(repo, f"releases?per_page=100&page={page}")
        if releases is None:
            raise ValueError("Could not list repository releases")
        for item in releases:
            if item["tag_name"] == tag:
                return item
        if len(releases) < 100:
            return None
        page += 1


def verify_tag_source(repo: str, tag: str, source: str):
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise ValueError("A valid source commit SHA is required for publication")
    ref = github_get(repo, "git/ref/tags/" + quote(tag, safe=""))
    if ref is None:
        raise ValueError("Push the release tag before publishing")
    obj = ref["object"]
    for _ in range(5):
        if obj["type"] == "commit":
            if obj["sha"] != source:
                raise ValueError("Existing release tag points to another commit; update the unpublished tag or increase the build number")
            return
        if obj["type"] != "tag":
            break
        obj = github_get(repo, "git/tags/" + obj["sha"])["object"]
    raise ValueError("Release tag does not resolve to a commit")


def publish():
    name, build = version(tag=os.environ["RELEASE_TAG"])
    repo, tag = os.environ["GH_REPO"], os.environ["RELEASE_TAG"]
    if repo != "wxia529/SaiSuite":
        raise ValueError("Unexpected release repository")
    assets = verify_checksums(ROOT / "dist", name)
    if os.environ.get("RELEASE_WINDOWS") == "true":
        for suffix in ('.zip', '-setup.exe'):
            windows = ROOT / "dist" / f"SaiSuite-{name}-windows-x64{suffix}"
            checksum = windows.with_suffix(windows.suffix + ".sha256")
            if checksum.read_text(encoding="ascii") != f"{digest(windows)}  {windows.name}\n":
                raise ValueError("Windows package checksum mismatch")
            assets.extend([windows, checksum])
    existing = find_release(repo, tag)
    if existing and not existing["draft"]:
        raise ValueError("Release is already public; refusing to replace published packages")
    latest = github_get(repo, "releases/latest")
    if latest:
        check_upgrade((name, build), latest["tag_name"])
    source = os.environ.get("GITHUB_SHA", "")
    verify_tag_source(repo, tag, source)
    if not existing:
        existing = github_write(repo, "releases", {
            "tag_name": tag, "target_commitish": source, "draft": True, "prerelease": False,
            "name": f"SaiSuite v{name}",
            "body": (ROOT / f"docs/releases/v{name}.md").read_text(encoding="utf-8"),
        })
    validate_draft(existing, tag)
    upload_assets(repo, existing, assets)
    complete_draft(repo, existing["id"], tag, assets)
    published = github_write(repo, f"releases/{existing['id']}",
                             {"draft": False, "prerelease": False, "make_latest": "true"}, method="PATCH")
    if not published or published.get("draft") is not False or published.get("tag_name") != tag:
        raise ValueError("GitHub did not confirm release publication")
    print(f"Published {tag} with all {len(assets)} verified assets")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["version", "prepare-signing", "clean-signing", "collect", "verify", "publish"])
    parser.add_argument("--universal", action="store_true")
    parser.add_argument("--split", action="store_true")
    args = parser.parse_args()
    if args.command == "version":
        name, build = version(tag=os.environ.get("RELEASE_TAG", ""))
        tag = f"v{name}+{build}"
        should_build = True
        if os.environ.get("RELEASE_PUBLISH") == "true":
            should_build = not is_published(os.environ["GH_REPO"], tag)
            if not should_build:
                print("Version is already published; skipping duplicate publication. Increase the build number for a new release.")
        output = f"version={name}\nbuild={build}\ntag={tag}\nshould_build={str(should_build).lower()}\n"
        print(output, end="")
        if os.environ.get("GITHUB_OUTPUT"):
            with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as handle:
                handle.write(output)
    elif args.command == "collect":
        collect(args.universal, args.split)
    else:
        {"prepare-signing": prepare_signing, "clean-signing": clean_signing,
         "verify": verify, "publish": publish}[args.command]()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Never include signing environment values or command output in failure logs.
        print(f"Release check failed: {error}", file=sys.stderr)
        sys.exit(1)
