package dev.mirquova.mirquova

import android.content.Context
import android.net.wifi.WifiManager
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
    }

    private fun releaseMulticast() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }
    override fun onStop() { releaseMulticast(); super.onStop() }
    override fun onDestroy() { releaseMulticast(); super.onDestroy() }
}
