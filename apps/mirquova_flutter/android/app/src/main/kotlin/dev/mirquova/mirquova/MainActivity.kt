package dev.mirquova.mirquova

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.mirquova/discovery")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "acquire" -> {
                            if (multicastLock?.isHeld != true) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("mirquova-discovery").apply {
                                    setReferenceCounted(false)
                                    acquire()
                                }
                            }
                            result.success(null)
                        }
                        "release" -> { releaseMulticast(); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (_: SecurityException) {
                    result.error("permission_denied", "Multicast access is unavailable.", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.mirquova/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBuildInfo" -> {
                        try {
                            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(packageName, 0)
                            }
                            val version = info.versionName
                            if (version.isNullOrEmpty()) {
                                result.error("version_unavailable", "The installed application version could not be read.", null)
                            } else {
                                val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    info.longVersionCode.toString()
                                } else {
                                    @Suppress("DEPRECATION")
                                    info.versionCode.toString()
                                }
                                result.success(mapOf("version" to version, "buildNumber" to buildNumber))
                            }
                        } catch (_: PackageManager.NameNotFoundException) {
                            result.error("version_unavailable", "The installed application version could not be read.", null)
                        }
                    }
                    "getUpdateDirectory" -> {
                        val root = File(cacheDir, "mirquova-updates")
                        if (root.isDirectory || root.mkdirs()) result.success(root.canonicalPath)
                        else result.error("storage_unavailable", "Update storage is unavailable.", null)
                    }
                    "openUpdatePackage" -> {
                        try {
                            val path = call.arguments as? String ?: throw IllegalArgumentException()
                            val original = File(path)
                            val file = original.canonicalFile
                            val root = File(cacheDir, "mirquova-updates").canonicalFile
                            if (original.absolutePath != file.path || !file.isFile ||
                                file.parentFile?.parentFile != root ||
                                file.parentFile?.name?.startsWith("download-") != true ||
                                file.name != "Mirquova-preview-android-arm64-debug.apk") throw IllegalArgumentException()
                            @Suppress("DEPRECATION")
                            val archive = packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNATURES)
                            @Suppress("DEPRECATION")
                            val installed = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                            @Suppress("DEPRECATION")
                            val signaturesMatch = archive?.signatures?.map { it.toCharsString() }?.toSet() ==
                                installed.signatures?.map { it.toCharsString() }?.toSet()
                            val archiveCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) archive?.longVersionCode else {
                                @Suppress("DEPRECATION")
                                archive?.versionCode?.toLong()
                            }
                            val installedCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) installed.longVersionCode else {
                                @Suppress("DEPRECATION")
                                installed.versionCode.toLong()
                            }
                            if (archive?.packageName != packageName || !signaturesMatch ||
                                archiveCode == null || archiveCode <= installedCode) {
                                result.error("incompatible_package", "The APK must be a newer Mirquova build signed with the same key.", null)
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                                result.error("install_permission", "Allow Mirquova to install updates, then open the downloaded update again.", null)
                            } else {
                                val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                                startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success(null)
                            }
                        } catch (_: Exception) {
                            result.error("invalid_package", "The downloaded update could not be opened by the system installer.", null)
                        }
                    }
                    "openReleasePage" -> {
                        val url = call.arguments as? String
                        val allowed = Regex("https://github\\.com/STVN-PRDGO/Mirquova/releases/tag/[A-Za-z0-9][A-Za-z0-9._+\\-]{0,127}")
                        if (url == null || !allowed.matches(url)) {
                            result.error("invalid_release_url", "Only Mirquova GitHub release pages can be opened.", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE))
                                result.success(null)
                            } catch (_: ActivityNotFoundException) {
                                result.error("browser_unavailable", "No browser is available to open this release page.", null)
                            } catch (_: SecurityException) {
                                result.error("browser_unavailable", "This release page could not be opened.", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun releaseMulticast() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }
    override fun onStop() { releaseMulticast(); super.onStop() }
    override fun onDestroy() { releaseMulticast(); super.onDestroy() }
}
