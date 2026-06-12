package com.lordofthedummies.margin

import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "margin/app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Send the app to the background (like Home) instead of
                    // finishing the activity, so a Back gesture hides rather
                    // than closes it — keeping the Flutter engine and UI state
                    // alive for an instant resume.
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    // Read an image from the clipboard (Flutter's Clipboard API
                    // is text-only, so a copied screenshot is invisible to it).
                    // Returns {bytes, mime} or null when the clipboard holds no
                    // readable image.
                    "readClipboardImage" -> {
                        result.success(readClipboardImage())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The clipboard's image as raw bytes + mime type, or null. Images arrive
    // as a content URI in the ClipData; the ContentResolver reads the bytes.
    private fun readClipboardImage(): Map<String, Any>? {
        return try {
            val clipboard =
                getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = clipboard.primaryClip ?: return null
            if (clip.itemCount == 0) return null
            val uri = clip.getItemAt(0).uri ?: return null
            val mime = contentResolver.getType(uri) ?: return null
            if (!mime.startsWith("image/")) return null
            contentResolver.openInputStream(uri)?.use { stream ->
                mapOf("bytes" to stream.readBytes(), "mime" to mime)
            }
        } catch (e: Exception) {
            null // no permission / provider gone -> behave as "no image"
        }
    }
}
