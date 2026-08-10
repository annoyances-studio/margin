package com.lordofthedummies.margin

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "margin/app"

    // Storage Access Framework folder pick is an async activity result; the
    // pending Flutter callback waits here until onActivityResult fires.
    private var pendingFolderPick: MethodChannel.Result? = null
    private val reqPickFolder = 6011

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
                    // --- Companion mode: read a user-granted folder (SAF) ---
                    // Opens the system folder picker; returns {uri, name} or null
                    // if cancelled, and persists read permission for reopening.
                    "safPickFolder" -> pickFolder(result)
                    // Lists a folder's immediate children (repo-relative path,
                    // "" = the granted root). null if the folder is gone.
                    "safList" -> result.success(
                        safList(uriArg(call), pathArg(call))
                    )
                    // Reads a file's bytes; null if missing.
                    "safRead" -> result.success(
                        safRead(uriArg(call), pathArg(call))
                    )
                    "safExists" -> result.success(
                        safExists(uriArg(call), pathArg(call))
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun uriArg(call: io.flutter.plugin.common.MethodCall): Uri =
        Uri.parse(call.argument<String>("uri"))

    private fun pathArg(call: io.flutter.plugin.common.MethodCall): String =
        call.argument<String>("path") ?: ""

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

    // Launches the system folder picker (ACTION_OPEN_DOCUMENT_TREE). The result
    // returns via onActivityResult.
    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolderPick != null) {
            result.error("busy", "A folder pick is already in progress", null)
            return
        }
        pendingFolderPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, reqPickFolder)
        } catch (e: Exception) {
            pendingFolderPick = null
            result.error("noPicker", "No folder picker available", e.message)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqPickFolder) return
        val pending = pendingFolderPick ?: return
        pendingFolderPick = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            pending.success(null) // cancelled
            return
        }
        // Persist read access so a recent-Folios entry can reopen it later.
        try {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
        }
        val name = DocumentFile.fromTreeUri(this, uri)?.name ?: "Folder"
        pending.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    // Resolves a repo-relative path (forward slashes; "" = the granted root)
    // to a DocumentFile under the tree, or null if any segment is missing.
    private fun resolve(treeUri: Uri, path: String): DocumentFile? {
        var doc = DocumentFile.fromTreeUri(this, treeUri) ?: return null
        for (seg in path.split('/')) {
            if (seg.isEmpty()) continue
            doc = doc.findFile(seg) ?: return null
        }
        return doc
    }

    private fun safList(treeUri: Uri, path: String): List<Map<String, Any?>>? {
        val dir = resolve(treeUri, path) ?: return null
        if (!dir.isDirectory) return null
        return dir.listFiles().map { f ->
            val modified = f.lastModified()
            mapOf(
                "name" to (f.name ?: ""),
                "isDir" to f.isDirectory,
                "size" to if (f.isDirectory) null else f.length(),
                "modified" to if (modified > 0) modified else null
            )
        }
    }

    private fun safRead(treeUri: Uri, path: String): ByteArray? {
        val file = resolve(treeUri, path) ?: return null
        if (!file.isFile) return null
        return contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
    }

    private fun safExists(treeUri: Uri, path: String): Boolean =
        resolve(treeUri, path)?.exists() == true
}
