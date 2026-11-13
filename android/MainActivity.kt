package com.mirrornuke.mirrornuke_app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQ_AUDIO_PERM = 4101
        private const val REQ_AUDIO_PROJECTION = 4102
    }

    private var pendingAudioResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mirrornuke/audio_stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    CaptureService.audioEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    CaptureService.audioEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mirrornuke/control")
            .setMethodCallHandler { call, result ->
                val svc = RemoteControlService.instance
                when (call.method) {
                    "isEnabled" -> result.success(svc != null)
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "gesture" -> {
                        val pts = call.argument<List<Double>>("points") ?: emptyList()
                        val dur = (call.argument<Number>("dur") ?: 100).toLong()
                        svc?.gesture(pts, dur)
                        result.success(svc != null)
                    }
                    "global" -> {
                        svc?.global(call.argument<String>("a") ?: "")
                        result.success(svc != null)
                    }
                    "text" -> {
                        svc?.typeText(call.argument<String>("s") ?: "")
                        result.success(svc != null)
                    }
                    "backspace" -> {
                        svc?.backspace()
                        result.success(svc != null)
                    }
                    "startCapture" -> {
                        val intent = Intent(this, CaptureService::class.java).apply {
                            action = CaptureService.ACTION_START_FOREGROUND
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "startAudioCapture" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        pendingAudioResult?.success(false)
                        pendingAudioResult = result
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                            != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.RECORD_AUDIO),
                                REQ_AUDIO_PERM
                            )
                        } else {
                            launchAudioProjectionPrompt()
                        }
                    }
                    "stopAudioCapture" -> {
                        val intent = Intent(this, CaptureService::class.java).apply {
                            action = CaptureService.ACTION_STOP_AUDIO
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "playAudioPcm" -> {
                        val bytes = call.argument<ByteArray>("pcm")
                        if (bytes != null && bytes.isNotEmpty()) {
                            CaptureService.playRemotePcm(bytes)
                        }
                        result.success(true)
                    }
                    "stopAudioPlayback" -> {
                        CaptureService.stopRemotePlayback()
                        result.success(true)
                    }
                    "stopCapture" -> {
                        CaptureService.stopRemotePlayback()
                        stopService(Intent(this, CaptureService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchAudioProjectionPrompt() {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_AUDIO_PROJECTION)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_AUDIO_PERM) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchAudioProjectionPrompt()
            } else {
                pendingAudioResult?.success(false)
                pendingAudioResult = null
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_AUDIO_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val svcIntent = Intent(this, CaptureService::class.java).apply {
                    action = CaptureService.ACTION_START_AUDIO
                    putExtra(CaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(CaptureService.EXTRA_RESULT_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(svcIntent)
                } else {
                    startService(svcIntent)
                }
                pendingAudioResult?.success(true)
            } else {
                pendingAudioResult?.success(false)
            }
            pendingAudioResult = null
        }
    }
}
