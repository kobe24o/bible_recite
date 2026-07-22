package app.biblerecite

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

private const val updateChannelName = "app.biblerecite/update"
private const val updatePackageName = "app.biblerecite"
private const val updateCertificateSha256 =
    "4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7"

class AppUpdateChannel(private val activity: MainActivity) {
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "inspectApk" -> result.success(inspectApk(requirePath(call)))
                        "canRequestPackageInstalls" -> result.success(
                            Build.VERSION.SDK_INT < 26 ||
                                activity.packageManager.canRequestPackageInstalls(),
                        )
                        "openInstallPermission" -> openInstallPermission(result)
                        "installApk" -> installApk(requirePath(call), result)
                        "networkTransport" -> result.success(networkTransport())
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("update_bridge_error", error.message, null)
                }
            }
    }

    private fun requirePath(call: MethodCall): File {
        val value = call.argument<String>("path")
            ?: throw IllegalArgumentException("A file path is required")
        val file = File(value)
        if (!file.isFile || !file.name.endsWith(".apk", ignoreCase = true)) {
            throw IllegalArgumentException("The update APK is unavailable")
        }
        return file
    }

    @Suppress("DEPRECATION")
    private fun inspectApk(file: File): Map<String, Any> {
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val packageInfo = activity.packageManager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("Unable to inspect update APK")
        val certificate = if (Build.VERSION.SDK_INT >= 28) {
            packageInfo.signingInfo?.apkContentsSigners?.singleOrNull()
        } else {
            packageInfo.signatures?.singleOrNull()
        } ?: throw IllegalArgumentException("Update APK has no single signing certificate")

        return mapOf(
            "packageName" to packageInfo.packageName,
            "versionName" to (packageInfo.versionName ?: ""),
            "versionCode" to packageVersionCode(packageInfo),
            "certificateSha256" to sha256(certificate.toByteArray()),
        )
    }

    @Suppress("DEPRECATION")
    private fun packageVersionCode(packageInfo: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) packageInfo.longVersionCode else packageInfo.versionCode.toLong()

    private fun openInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 26) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
            activity.startActivity(intent)
        }
        result.success(null)
    }

    private fun installApk(file: File, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            openInstallPermission(result)
            return
        }
        val inspection = inspectApk(file)
        if (inspection["packageName"] != updatePackageName ||
            inspection["certificateSha256"] != updateCertificateSha256
        ) {
            throw IllegalArgumentException("Update APK identity does not match this app")
        }

        val updateDirectory = File(activity.cacheDir, "updates").canonicalFile
        val apk = file.canonicalFile
        if (apk.parentFile != updateDirectory) {
            throw IllegalArgumentException("Update APK must be in the private update cache")
        }

        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.update-files",
            apk,
        )
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(intent)
        result.success(null)
    }

    private fun networkTransport(): String {
        val manager = activity.getSystemService(ConnectivityManager::class.java) ?: return "none"
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return "none"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
}
