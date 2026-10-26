package dev.mirquova.mirquova

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
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
