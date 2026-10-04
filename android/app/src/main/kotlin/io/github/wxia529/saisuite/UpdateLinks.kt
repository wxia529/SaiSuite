package io.github.wxia529.saisuite

import android.net.Uri

internal object UpdateLinks {
    private const val PROXY = "https://gh-proxy.org/"

    private fun repository(uri: Uri): Boolean =
        uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null &&
            (uri.port == -1 || uri.port == 443) && uri.query == null && uri.fragment == null &&
            uri.pathSegments.take(2) == listOf("wxia529", "SaiSuite")

    private fun download(uri: Uri): Boolean {
        if (!repository(uri)) return false
        val parts = uri.pathSegments
        if (parts.size != 6 || parts[2] != "releases" || parts[3] != "download") return false
        val version = Regex("^v?(\\d+\\.\\d+\\.\\d+)(?:\\+\\d+)?$").matchEntire(parts[4])
            ?.groupValues?.get(1) ?: return false
        val base = "SaiSuite-$version-"
        return parts[5].startsWith(base) && parts[5].removePrefix(base) in setOf(
            "universal.apk", "armeabi-v7a.apk", "arm64-v8a.apk", "x86_64.apk",
            "windows-x64-setup.exe", "windows-x64.zip"
        )
    }

    fun allowed(uri: Uri): Boolean {
        if (repository(uri)) {
            val parts = uri.pathSegments
            return parts.size >= 3 && parts[2] == "releases" &&
                (parts.size < 4 || parts[3] != "download" || download(uri))
        }
        val value = uri.toString()
        if (!value.startsWith(PROXY) || uri.userInfo != null ||
            (uri.port != -1 && uri.port != 443) || uri.query != null || uri.fragment != null) return false
        return download(Uri.parse(value.removePrefix(PROXY)))
    }
}
