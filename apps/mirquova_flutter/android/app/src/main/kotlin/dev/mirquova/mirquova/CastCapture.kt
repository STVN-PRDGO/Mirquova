package dev.mirquova.mirquova

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import java.io.ByteArrayOutputStream
import kotlin.math.min

object CastCapture {
    @Volatile
    private var latestJpeg: ByteArray? = null
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())

    fun isRunning(): Boolean = projection != null

    fun start(context: Context, resultCode: Int, data: Intent) {
        if (projection != null) return
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val media = manager.getMediaProjection(resultCode, data) ?: return
        media.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stop()
            }
        }, handler)
        val metrics = displayMetrics(context)
        val scale = min(1f, min(1280f / metrics.widthPixels, 720f / metrics.heightPixels))
        val width = ((metrics.widthPixels * scale).toInt() and 1.inv()).coerceAtLeast(2)
        val height = ((metrics.heightPixels * scale).toInt() and 1.inv()).coerceAtLeast(2)
        val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader.setOnImageAvailableListener({ incoming ->
            incoming.acquireLatestImage()?.use { image ->
                latestJpeg = jpegFromImage(image, width, height)
            }
        }, handler)
        projection = media
        reader = imageReader
        display = media.createVirtualDisplay(
            "mirquova-cast",
            width,
            height,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader.surface,
            null,
            handler,
        )
    }

    fun latestFrame(): ByteArray? = latestJpeg

    fun stop() {
        display?.release()
        display = null
        reader?.close()
        reader = null
        projection?.stop()
        projection = null
        latestJpeg = null
    }

    private fun displayMetrics(context: Context): DisplayMetrics {
        val metrics = DisplayMetrics()
        if (context is Activity && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.display?.getRealMetrics(metrics)
        } else {
            @Suppress("DEPRECATION")
            (context.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager)
                .defaultDisplay
                .getRealMetrics(metrics)
        }
        if (metrics.widthPixels <= 0 || metrics.heightPixels <= 0) {
            metrics.widthPixels = 1280
            metrics.heightPixels = 720
            metrics.densityDpi = 320
        }
        return metrics
    }

    private fun jpegFromImage(image: android.media.Image, width: Int, height: Int): ByteArray? {
        val plane = image.planes.firstOrNull() ?: return null
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width
        val bitmap = Bitmap.createBitmap(
            width + rowPadding / pixelStride,
            height,
            Bitmap.Config.ARGB_8888,
        )
        bitmap.copyPixelsFromBuffer(buffer)
        val cropped = if (bitmap.width == width && bitmap.height == height) {
            bitmap
        } else {
            Bitmap.createBitmap(bitmap, 0, 0, width, height).also { bitmap.recycle() }
        }
        val encoded = ByteArrayOutputStream()
        val ok = cropped.compress(Bitmap.CompressFormat.JPEG, 55, encoded)
        if (cropped != bitmap) cropped.recycle() else bitmap.recycle()
        return if (ok) encoded.toByteArray() else null
    }
}
