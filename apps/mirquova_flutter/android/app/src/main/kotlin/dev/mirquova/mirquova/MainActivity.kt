package dev.mirquova.mirquova

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var captureReply: MethodChannel.Result? = null
    private var pendingProjection: MethodChannel.Result? = null

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
                    "setTransferKeepAwake" -> {
                        val active = call.arguments as? Boolean ?: false
                        if (active) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
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
                    "getDeviceName" -> {
                        val named = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                        val model = listOf(Build.MANUFACTURER, Build.MODEL)
                            .filter { it.isNotBlank() }
                            .distinctBy { it.lowercase() }
                            .joinToString(" ") { it.replaceFirstChar(Char::titlecase) }
                        result.success(named?.takeIf { it.isNotBlank() } ?: model)
                    }
                    "getReceiveDirectory" -> {
                        // Native Rust writes cannot use public Downloads on
                        // scoped storage: Java mkdir can succeed and still
                        // refuse the `.mqpart` inbox file.
                        val folder = appReceiveDirectory()
                        if (folder != null) result.success(folder.canonicalPath)
                        else result.error("storage_unavailable", "No folder is available for received files.", null)
                    }
                    "publishReceivedFiles" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val directory = (arguments?.get("directory") as? String)?.let(::File)
                        val names = arguments?.get("names") as? List<*>
                        if (directory == null || names.isNullOrEmpty()) {
                            result.error("invalid_input", "Received files could not be published.", null)
                        } else {
                            val published = names.mapNotNull { name ->
                                val fileName = name as? String ?: return@mapNotNull null
                                publishReceivedFile(directory, fileName)
                            }
                            result.success(
                                if (published.isNotEmpty()) "Downloads/Mirquova" else directory.canonicalPath
                            )
                        }
                    }
                    "startScreenCapture" -> {
                        if (CastCapture.isRunning()) {
                            result.success(true)
                        } else if (captureReply != null || pendingProjection != null) {
                            result.error("busy", "A screen-capture prompt is already open.", null)
                        } else {
                            requestCapture(result)
                        }
                    }
                    "startSystemAudio" -> {
                        CastCapture.startAudio()
                        result.success(null)
                    }
                    "captureSystemAudio" -> result.success(CastCapture.takeAudio())
                    "playSystemAudio" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val pcm = arguments?.get("pcm") as? ByteArray
                        val rate = (arguments?.get("sampleRate") as? Number)?.toInt() ?: 0
                        val channels = (arguments?.get("channels") as? Number)?.toInt() ?: 0
                        if (pcm != null) CastCapture.playAudio(pcm, rate, channels)
                        result.success(null)
                    }
                    "stopSystemAudioCapture" -> {
                        CastCapture.stopAudioCapture()
                        result.success(null)
                    }
                    "stopSystemAudioPlayback" -> {
                        CastCapture.stopAudioPlayback()
                        result.success(null)
                    }
                    "captureFrame" -> {
                        val frame = CastCapture.latestFrame()
                        if (frame == null) result.success(null)
                        else result.success(frame)
                    }
                    "stopScreenCapture" -> {
                        stopService(Intent(this, CastCaptureService::class.java).setAction(CastCaptureService.ACTION_STOP))
                        CastCapture.stop()
                        result.success(null)
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

    private fun appReceiveDirectory(): File? {
        val candidates = listOfNotNull(
            getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.let { File(it, "Mirquova") },
            File(filesDir, "Mirquova"),
        )
        return candidates.firstOrNull { writable(it) }
    }

    // Scoped storage can list a folder as writable and still refuse new files.
    private fun writable(folder: File): Boolean = try {
        (folder.isDirectory || folder.mkdirs()) &&
            File(folder, ".mirquova-${System.nanoTime()}.probe").let { probe ->
                probe.createNewFile().also { probe.delete() }
            }
    } catch (_: Exception) {
        false
    }

    /// Copies a verified inbox file into the public Downloads collection so it
    /// appears next to other downloads. The native session already saved it.
    private fun publishReceivedFile(directory: File, name: String): Boolean {
        if (name.isEmpty() || name.contains('/') || name.contains('\\') || name == "." || name == "..") {
            return false
        }
        val source = File(directory, name).canonicalFile
        if (source.parentFile?.canonicalFile != directory.canonicalFile || !source.isFile) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        when (existingPublishedFile(name, source)) {
            true -> return true
            false -> return false
            null -> Unit
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Mirquova")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            contentResolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: return false
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            true
        } catch (_: Exception) {
            contentResolver.delete(uri, null, null)
            false
        }
    }

    /// Returns null when the public collection has no matching filename, or
    /// whether an existing row has the same bytes as the verified inbox file.
    private fun existingPublishedFile(name: String, source: File): Boolean? {
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val cursor = contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.MediaColumns._ID),
            selection,
            arrayOf(name, "${Environment.DIRECTORY_DOWNLOADS}/Mirquova/"),
            null,
        ) ?: return null
        val existing = mutableListOf<Uri>()
        cursor.use {
            while (it.moveToNext()) {
                existing += ContentUris.withAppendedId(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    it.getLong(0),
                )
            }
        }
        if (existing.isEmpty()) return null
        val expected = source.inputStream().use(::sha256)
        return existing.any { uri ->
            contentResolver.openInputStream(uri)?.use(::sha256)?.contentEquals(expected) == true
        }
    }

    private fun sha256(input: java.io.InputStream): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
        return digest.digest()
    }

    private fun releaseMulticast() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }
    private fun requestCapture(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingProjection = result
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_AUDIO)
            return
        }
        launchProjection(result)
    }

    private fun launchProjection(result: MethodChannel.Result) {
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        captureReply = result
        @Suppress("DEPRECATION")
        startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CAST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_AUDIO) return
        val pending = pendingProjection ?: return
        pendingProjection = null
        launchProjection(pending)
    }

    @Deprecated("Required for MediaProjection until the Activity Result API is wired.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAST) return
        val reply = captureReply ?: return
        captureReply = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            reply.success(false)
            return
        }
        val service = Intent(this, CastCaptureService::class.java)
            .putExtra(CastCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(CastCaptureService.EXTRA_RESULT_DATA, data)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(service)
        } else {
            startService(service)
        }
        reply.success(true)
    }

    override fun onStop() { releaseMulticast(); super.onStop() }
    override fun onDestroy() {
        captureReply = null
        pendingProjection = null
        releaseMulticast()
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_CAST = 40734
        private const val REQUEST_AUDIO = 40735
    }
}
