package com.mirrornuke.mirrornuke_app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * Foreground service for Android 14+ MediaProjection screen & internal audio capture,
 * plus low-latency AudioTrack playback when this Android device acts as a receiver.
 */
class CaptureService : Service() {
    companion object {
        const val ACTION_START_FOREGROUND = "mirrornuke.START_FOREGROUND"
        const val ACTION_START_AUDIO = "mirrornuke.START_AUDIO"
        const val ACTION_STOP_AUDIO = "mirrornuke.STOP_AUDIO"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        @Volatile
        var audioEventSink: EventChannel.EventSink? = null

        // MainActivity waits for the service to confirm startForeground() before
        // asking flutter_webrtc to create the MediaProjection capture.
        @Volatile
        var foregroundStartCallback: ((Boolean) -> Unit)? = null

        @Volatile
        private var playerTrack: AudioTrack? = null

        fun reportForegroundStart(ready: Boolean) {
            val callback = foregroundStartCallback
            foregroundStartCallback = null
            callback?.invoke(ready)
        }

        fun playRemotePcm(pcmBytes: ByteArray) {
            try {
                var track = playerTrack
                if (track == null || track.state != AudioTrack.STATE_INITIALIZED) {
                    val sampleRate = 48000
                    val minBuf = AudioTrack.getMinBufferSize(
                        sampleRate,
                        AudioFormat.CHANNEL_OUT_STEREO,
                        AudioFormat.ENCODING_PCM_16BIT
                    )
                    track = AudioTrack.Builder()
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                .build()
                        )
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setSampleRate(sampleRate)
                                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                                .build()
                        )
                        .setBufferSizeInBytes(maxOf(minBuf * 2, 8192))
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build()
                    track.play()
                    playerTrack = track
                }
                track.write(pcmBytes, 0, pcmBytes.size, AudioTrack.WRITE_NON_BLOCKING)
            } catch (_: Throwable) {
            }
        }

        fun stopRemotePlayback() {
            try {
                playerTrack?.stop()
                playerTrack?.release()
            } catch (_: Throwable) {
            }
            playerTrack = null
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var seqNum: Int = 0

    @Volatile
    private var capturingAudio = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (!ensureForeground()) {
            if (action == ACTION_START_FOREGROUND) reportForegroundStart(false)
            stopSelf()
            return START_NOT_STICKY
        }
        if (action == ACTION_START_FOREGROUND) reportForegroundStart(true)
        when (action) {
            ACTION_START_AUDIO -> {
                val code = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                val data: Intent? = intent.getParcelableExtra(EXTRA_RESULT_DATA)
                if (code != 0 && data != null) {
                    startInternalAudioCapture(code, data)
                }
            }
            ACTION_STOP_AUDIO -> stopInternalAudioCapture()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopInternalAudioCapture()
        stopRemotePlayback()
        stopSelf()
    }

    private fun ensureForeground(): Boolean {
        return try {
            val channelId = "mirrornuke_capture"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = getSystemService(NotificationManager::class.java)
                nm.createNotificationChannel(
                    NotificationChannel(channelId, "MirrorNuke Casting", NotificationManager.IMPORTANCE_LOW)
                )
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val notification = builder
                .setContentTitle("MirrorNuke")
                .setContentText("Casting screen and audio")
                .setSmallIcon(applicationInfo.icon)
                .setOngoing(true)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(1, notification)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun startInternalAudioCapture(resultCode: Int, data: Intent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        stopInternalAudioCapture()
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val proj = mpm.getMediaProjection(resultCode, data) ?: return
            audioProjection = proj

            val config = AudioPlaybackCaptureConfiguration.Builder(proj)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            val sampleRate = 48000
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                .build()

            val minBuf = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val frameBytes = 3840
            val record = AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(minBuf * 2, frameBytes * 4))
                .setAudioPlaybackCaptureConfig(config)
                .build()

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                proj.stop()
                return
            }

            audioRecord = record
            capturingAudio = true
            seqNum = 0
            record.startRecording()

            thread(name = "MirrorNukeAudioCapture", isDaemon = true) {
                val pcmBuf = ByteArray(frameBytes)
                while (capturingAudio) {
                    val read = record.read(pcmBuf, 0, frameBytes)
                    if (read == frameBytes) {
                        val seq = seqNum and 0xFFFF
                        seqNum = (seqNum + 1) and 0xFFFF
                        val encoded = ImaAdpcm.encodeStereoFrame(pcmBuf, seq)
                        mainHandler.post {
                            audioEventSink?.success(encoded)
                        }
                    } else if (read < 0) {
                        break
                    }
                }
            }
        } catch (_: Throwable) {
            stopInternalAudioCapture()
        }
    }

    private fun stopInternalAudioCapture() {
        capturingAudio = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Throwable) {
        }
        audioRecord = null
        try {
            audioProjection?.stop()
        } catch (_: Throwable) {
        }
        audioProjection = null
    }

    override fun onDestroy() {
        stopInternalAudioCapture()
        stopRemotePlayback()
        super.onDestroy()
    }
}

/**
 * 4:1 stereo IMA-ADPCM encoder with a 10-byte header:
 * [0..1] uint16 LE seq
 * [2..3] int16  LE predL, [4] uint8 idxL, [5] 0
 * [6..7] int16  LE predR, [8] uint8 idxR, [9] 0
 * Each 20 ms frame is self-contained (keyframe state) and sequenced for jitter reordering.
 */
object ImaAdpcm {
    private val INDEX_TABLE = intArrayOf(
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8
    )
    private val STEP_TABLE = intArrayOf(
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
        19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
        5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
    )

    fun encodeStereoFrame(pcmBytes: ByteArray, seq: Int = 0): ByteArray {
        val sb = ByteBuffer.wrap(pcmBytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val totalShorts = sb.limit()
        val frames = totalShorts / 2
        if (frames < 2) return ByteArray(0)

        var predL = sb.get(0).toInt()
        var idxL = 0
        var predR = sb.get(1).toInt()
        var idxR = 0

        val payloadFrames = frames - 1
        val out = ByteBuffer.allocate(10 + payloadFrames).order(ByteOrder.LITTLE_ENDIAN)
        out.putShort((seq and 0xFFFF).toShort())
        out.putShort(predL.toShort())
        out.put(idxL.toByte())
        out.put(0.toByte())
        out.putShort(predR.toShort())
        out.put(idxR.toByte())
        out.put(0.toByte())

        for (i in 1 until frames) {
            val sL = sb.get(i * 2).toInt()
            val sR = sb.get(i * 2 + 1).toInt()

            val nL = encodeSample(sL, predL, idxL)
            predL = nL.first
            idxL = nL.second

            val nR = encodeSample(sR, predR, idxR)
            predR = nR.first
            idxR = nR.second

            out.put(((nL.third and 0x0F) or ((nR.third and 0x0F) shl 4)).toByte())
        }
        return out.array()
    }

    private fun encodeSample(sample: Int, predIn: Int, idxIn: Int): Triple<Int, Int, Int> {
        var pred = predIn
        var idx = idxIn.coerceIn(0, 88)
        val step = STEP_TABLE[idx]
        var diff = sample - pred
        var code = 0
        if (diff < 0) {
            code = 8
            diff = -diff
        }
        var delta = step shr 3
        if (diff >= step) {
            code = code or 4
            diff -= step
            delta += step
        }
        val step2 = step shr 1
        if (diff >= step2) {
            code = code or 2
            diff -= step2
            delta += step2
        }
        val step4 = step shr 2
        if (diff >= step4) {
            code = code or 1
            delta += step4
        }
        pred += if ((code and 8) != 0) -delta else delta
        pred = pred.coerceIn(-32768, 32767)
        idx = (idx + INDEX_TABLE[code and 0x0F]).coerceIn(0, 88)
        return Triple(pred, idx, code)
    }
}
