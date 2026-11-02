package dev.mirquova.mirquova

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.AudioTrack
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
    private val audioLock = Any()
    private val pendingAudio = java.io.ByteArrayOutputStream()
    private var recorder: AudioRecord? = null
    private var audioThread: Thread? = null
    private var audioRunning: java.util.concurrent.atomic.AtomicBoolean? = null
    private var playback: AudioTrack? = null
    private var playbackRate = 0
    private var playbackChannels = 0

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
        startAudio()
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

    fun startAudio() {
        val media = projection ?: return
        if (recorder != null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val capture = AudioPlaybackCaptureConfiguration.Builder(media)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(48_000)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()
        val min = AudioRecord.getMinBufferSize(
            48_000,
            AudioFormat.CHANNEL_IN_STEREO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (min <= 0) return
        val record = try {
            AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(min * 2)
                .setAudioPlaybackCaptureConfig(capture)
                .build()
        } catch (_: SecurityException) {
            return
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return
        }
        record.startRecording()
        val running = java.util.concurrent.atomic.AtomicBoolean(true)
        audioRunning = running
        recorder = record
        audioThread = Thread {
            val buffer = ByteArray(min)
            while (running.get()) {
                val read = record.read(buffer, 0, buffer.size)
                if (read <= 0) continue
                synchronized(audioLock) {
                    if (pendingAudio.size() > 64 * 1024) pendingAudio.reset()
                    pendingAudio.write(buffer, 0, read)
                }
            }
        }.also { it.start() }
    }

    fun takeAudio(): ByteArray? {
        synchronized(audioLock) {
            val packetBytes = 48_000 / 100 * 2 * 2
            if (pendingAudio.size() < packetBytes) return null
            val bytes = pendingAudio.toByteArray()
            pendingAudio.reset()
            if (bytes.size > packetBytes) {
                pendingAudio.write(bytes, packetBytes, bytes.size - packetBytes)
            }
            return bytes.copyOf(packetBytes)
        }
    }

    fun playAudio(pcm: ByteArray, sampleRate: Int, channels: Int) {
        if (pcm.isEmpty() || sampleRate <= 0 || (channels != 1 && channels != 2)) return
        val mask = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val current = playback
        if (current == null || playbackRate != sampleRate || playbackChannels != channels) {
            current?.release()
            val min = AudioTrack.getMinBufferSize(sampleRate, mask, AudioFormat.ENCODING_PCM_16BIT)
            if (min <= 0) return
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(mask)
                        .build(),
                )
                .setBufferSizeInBytes(maxOf(min, pcm.size * 2))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            track.play()
            playback = track
            playbackRate = sampleRate
            playbackChannels = channels
        }
        playback?.write(pcm, 0, pcm.size)
    }

    fun stopAudioCapture() {
        audioRunning?.set(false)
        audioRunning = null
        try {
            recorder?.stop()
        } catch (_: IllegalStateException) {
            // The recorder can already be stopped when the share ends.
        }
        audioThread?.join(500)
        audioThread = null
        recorder?.release()
        recorder = null
        synchronized(audioLock) { pendingAudio.reset() }
    }

    fun stopAudioPlayback() {
        playback?.pause()
        playback?.flush()
        playback?.release()
        playback = null
        playbackRate = 0
        playbackChannels = 0
    }

    fun stop() {
        stopAudioCapture()
        stopAudioPlayback()
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
