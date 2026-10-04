const githubRepository = 'wxia529/SaiSuite';
const githubReleasesUrl = 'https://github.com/$githubRepository/releases';
const githubDownloadProxy = 'https://gh-proxy.org/';

bool isRepositoryUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    uri.pathSegments.take(2).join('/') == githubRepository;

bool isReleaseDownloadUrl(Uri uri) {
  if (!isRepositoryUrl(uri)) return false;
  final parts = uri.pathSegments;
  if (parts.length != 6 || parts[2] != 'releases' || parts[3] != 'download') {
    return false;
  }
  final version = RegExp(r'^v?(\d+\.\d+\.\d+)(?:\+\d+)?$').firstMatch(parts[4]);
  if (version == null) return false;
  final base = 'SaiSuite-${version[1]}-';
  return parts[5].startsWith(base) &&
      const {
        'universal.apk',
        'armeabi-v7a.apk',
        'arm64-v8a.apk',
        'x86_64.apk',
        'windows-x64-setup.exe',
        'windows-x64.zip',
      }.contains(parts[5].substring(base.length));
}

Uri acceleratedDownloadUrl(Uri source) {
  if (!isReleaseDownloadUrl(source)) {
    throw const FormatException('地址不属于当前仓库的安装包');
  }
  // Preserve encoded tag characters, including %2B, by prefixing the URL text.
  return Uri.parse('$githubDownloadProxy$source');
}

bool isUpdateUrl(Uri uri) {
  if (isRepositoryUrl(uri)) {
    final parts = uri.pathSegments;
    return parts.length >= 3 &&
        parts[2] == 'releases' &&
        (parts.length < 4 ||
            parts[3] != 'download' ||
            isReleaseDownloadUrl(uri));
  }
  final value = uri.toString();
  if (!value.startsWith(githubDownloadProxy) ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  final source = Uri.tryParse(value.substring(githubDownloadProxy.length));
  return source != null && isReleaseDownloadUrl(source);
}
