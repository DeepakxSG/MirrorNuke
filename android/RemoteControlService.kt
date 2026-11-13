package com.mirrornuke.mirrornuke_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class RemoteControlService : AccessibilityService() {
    companion object {
        @Volatile var instance: RemoteControlService? = null
    }

    override fun onServiceConnected() { instance = this }
    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    @Suppress("DEPRECATION")
    private fun screenSize(): Pair<Float, Float> {
        val dm = DisplayMetrics()
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(dm)
        return Pair(dm.widthPixels.toFloat(), dm.heightPixels.toFloat())
    }

    /** points = x1,y1,x2,y2... normalized 0..1. One point = tap. */
    fun gesture(points: List<Double>, durationMs: Long) {
        if (points.size < 2) return
        val (w, h) = screenSize()
        val path = Path()
        path.moveTo((points[0] * w).toFloat(), (points[1] * h).toFloat())
        var i = 2
        while (i + 1 < points.size) {
            path.lineTo((points[i] * w).toFloat(), (points[i + 1] * h).toFloat())
            i += 2
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.coerceIn(30, 5000))
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun global(action: String) {
        when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
        }
    }

    private fun setFocusedText(transform: (String) -> String) {
        val node = findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return
        val cur = node.text?.toString() ?: ""
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, transform(cur))
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun typeText(s: String) = setFocusedText { it + s }
    fun backspace() = setFocusedText { it.dropLast(1) }
}
