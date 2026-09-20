package com.lordofthedummies.margin

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.provider.DocumentsContract
import android.view.WindowManager
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.api.ResetCommand
import org.eclipse.jgit.lfs.BuiltinLFS
import org.eclipse.jgit.transport.UsernamePasswordCredentialsProvider
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "margin/app"

    // Storage Access Framework folder pick is an async activity result; the
    // pending Flutter callback waits here until onActivityResult fires.
    private var pendingFolderPick: MethodChannel.Result? = null
    private val reqPickFolder = 6011

    // JGit clone is blocking network+disk work; keep it off the main thread.
    private val ioExecutor = Executors.newSingleThreadExecutor()

    // Held only while a long sync/clone runs so the screen turning off does not
    // suspend the CPU or idle Wi-Fi mid-transfer (which drops the connection).
    // Both carry a timeout so a crash can never leak them indefinitely.
    private var syncWakeLock: PowerManager.WakeLock? = null
    private var syncWifiLock: WifiManager.WifiLock? = null

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
                    // --- Git-read spike: clone a repo read-only (JGit) ---
                    "gitClone" -> gitClone(call, result)
                    // Path of an existing local clone (offline reopen), or null.
                    "gitLocalPath" -> {
                        val name = sanitizeRepoName(call.argument<String>("name") ?: "")
                        val dir = File(File(filesDir, "git"), name)
                        result.success(if (dir.isDirectory) dir.absolutePath else null)
                    }
                    // Pull the latest into an existing clone (Refresh).
                    "gitPull" -> gitPull(call, result)
                    // --- Keep-awake while a long sync/clone transfers bytes ---
                    "acquireSyncWakeLock" -> {
                        acquireSyncWakeLock(call.argument<Int>("timeoutMs"))
                        result.success(true)
                    }
                    "releaseSyncWakeLock" -> {
                        releaseSyncWakeLock()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Acquires a partial CPU wake lock and a high-performance Wi-Fi lock so a
    // sync in progress survives the screen turning off. [timeoutMs] is a safety
    // cap (the CPU lock auto-releases after it); release() is called normally in
    // the Dart `finally`. Idempotent — a second acquire is a no-op.
    private fun acquireSyncWakeLock(timeoutMs: Int?) {
        try {
            if (syncWakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                syncWakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "margin:sync",
                )
            }
            val lock = syncWakeLock!!
            if (!lock.isHeld) {
                val cap = (timeoutMs ?: 0).toLong()
                if (cap > 0) lock.acquire(cap) else lock.acquire()
            }
            if (syncWifiLock == null) {
                val wm = applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                syncWifiLock = wm.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "margin:sync",
                )
            }
            syncWifiLock?.let { if (!it.isHeld) it.acquire() }
            // Keep the screen on for the duration: the strongest, simplest
            // guard against the auto screen-timeout that drops the connection
            // mid-transfer. The CPU/Wi-Fi locks above are best-effort backup
            // (and cover a manual power-off); this keeps the app foreground and
            // the network unthrottled while a long clone/sync runs.
            runOnUiThread {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        } catch (e: Exception) {
            // Keep-awake is best-effort; if it fails the sync still runs, just
            // without protection from the screen turning off.
        }
    }

    private fun releaseSyncWakeLock() {
        try {
            runOnUiThread {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        } catch (e: Exception) {
        }
        try {
            syncWakeLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
        }
        try {
            syncWifiLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
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
        // Fast, reliable path: construct the child document URI directly from the
        // tree's document id (hierarchical providers like externalstorage). Avoids
        // DocumentFile.findFile enumerating a whole directory per segment, which is
        // slow and flaky in large folders (e.g. a cloned code repo).
        try {
            val rootId = DocumentsContract.getTreeDocumentId(treeUri)
            val childId = if (path.isEmpty()) rootId else "$rootId/$path"
            val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
            val bytes = contentResolver.openInputStream(childUri)?.use { it.readBytes() }
            if (bytes != null) return bytes
        } catch (_: Exception) {
            // Fall through to the DocumentFile walk for non-hierarchical providers.
        }
        val file = resolve(treeUri, path) ?: return null
        if (!file.isFile) return null
        return contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
    }

    private fun safExists(treeUri: Uri, path: String): Boolean =
        resolve(treeUri, path)?.exists() == true

    // --- Git-read spike ------------------------------------------------------
    // Clone a repo (HTTPS, optional user/password — a PAT for GitHub) into
    // app-private storage and return the working-tree path, which Margin then
    // browses read-only with a LocalFolderBackend. BuiltinLFS.register() installs
    // the smudge filter so LFS pointer files are checked out as real bytes
    // (downloaded on demand) instead of 130-byte stubs. Read-only; never pushes.
    // This validates JGit + LFS on-device before the full backend is built.
    private fun gitClone(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("badArgs", "Missing repository URL", null)
            return
        }
        val user = call.argument<String>("user") ?: ""
        val pass = call.argument<String>("pass") ?: ""
        val name = sanitizeRepoName(call.argument<String>("name") ?: "repo")
        // JGit looks up config under HOME; Android has no ~, so point it at
        // writable app storage. It finds nothing there, which is fine.
        System.setProperty("user.home", filesDir.absolutePath)
        ioExecutor.execute {
            val dest = File(File(filesDir, "git"), name)
            try {
                BuiltinLFS.register()
                if (dest.exists()) dest.deleteRecursively()
                dest.parentFile?.mkdirs()
                val clone = Git.cloneRepository().setURI(url).setDirectory(dest)
                if (user.isNotEmpty() || pass.isNotEmpty()) {
                    clone.setCredentialsProvider(
                        UsernamePasswordCredentialsProvider(user, pass)
                    )
                }
                clone.call().use { }
                // JGit checks out LFS files as pointer stubs (it doesn't fetch
                // blobs). Materialise them ourselves via the LFS batch API so
                // images/binaries are real bytes. Best-effort: a failure here
                // still opens the repo (pointers just show the "git lfs" hint).
                try {
                    lfsSmudge(dest, url, user, pass)
                } catch (_: Exception) {
                }
                runOnUiThread { result.success(dest.absolutePath) }
            } catch (e: Exception) {
                try { dest.deleteRecursively() } catch (_: Exception) {}
                runOnUiThread {
                    result.error("cloneFailed", e.message ?: e.toString(), null)
                }
            }
        }
    }

    // Update an existing clone to the latest (Refresh). Read-only mirror: fetch,
    // then hard-reset the working tree to the fetched remote branch (the local
    // copy never diverges, so there's nothing to merge), then re-materialise LFS
    // (reset writes LFS files back out as pointer stubs). Runs off the main thread.
    private fun gitPull(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("badArgs", "Missing clone path", null)
            return
        }
        val url = call.argument<String>("url") ?: ""
        val user = call.argument<String>("user") ?: ""
        val pass = call.argument<String>("pass") ?: ""
        System.setProperty("user.home", filesDir.absolutePath)
        ioExecutor.execute {
            val dir = File(path)
            try {
                BuiltinLFS.register()
                Git.open(dir).use { git ->
                    val fetch = git.fetch().setRemote("origin")
                    if (user.isNotEmpty() || pass.isNotEmpty()) {
                        fetch.setCredentialsProvider(
                            UsernamePasswordCredentialsProvider(user, pass)
                        )
                    }
                    fetch.call()
                    val branch = git.repository.branch
                    val target = git.repository.resolve("refs/remotes/origin/$branch")
                        ?: git.repository.resolve("FETCH_HEAD")
                    if (target != null) {
                        git.reset()
                            .setMode(ResetCommand.ResetType.HARD)
                            .setRef(target.name)
                            .call()
                    }
                }
                if (url.isNotEmpty()) lfsSmudge(dir, url, user, pass)
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("pullFailed", e.message ?: e.toString(), null)
                }
            }
        }
    }

    // A filesystem-safe folder name from a repo name/URL segment ("…/repo.git").
    private fun sanitizeRepoName(raw: String): String {
        val base = raw.substringAfterLast('/').removeSuffix(".git")
        val safe = base.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return safe.ifBlank { "repo" }
    }

    // --- Git LFS materialisation ---------------------------------------------
    // JGit's clone leaves LFS-tracked files as ~130-byte pointer stubs. We fetch
    // the real blobs via the Git LFS batch API (the same protocol `git lfs pull`
    // uses) and overwrite the pointers in the working tree. This is the piece
    // other on-device git clients (MGit) get wrong.
    private data class LfsPtr(val oid: String, val size: Long)

    private fun lfsSmudge(repoDir: File, cloneUrl: String, user: String, pass: String) {
        val pointers = collectLfsPointers(repoDir)
        if (pointers.isEmpty()) return

        val auth = if (user.isNotEmpty() || pass.isNotEmpty())
            "Basic " + Base64.encodeToString(
                "$user:$pass".toByteArray(), Base64.NO_WRAP
            )
        else null

        // One batch request for all distinct OIDs (a blob may back many paths).
        val byOid = LinkedHashMap<String, LfsPtr>()
        for ((_, p) in pointers) byOid[p.oid] = p
        val objs = JSONArray()
        for (p in byOid.values) {
            objs.put(JSONObject().put("oid", p.oid).put("size", p.size))
        }
        val body = JSONObject()
            .put("operation", "download")
            .put("transfers", JSONArray().put("basic"))
            .put("objects", objs)
            .toString()

        val batch = openConn(lfsBatchUrl(cloneUrl)).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Accept", "application/vnd.git-lfs+json")
            setRequestProperty("Content-Type", "application/vnd.git-lfs+json")
            if (auth != null) setRequestProperty("Authorization", auth)
        }
        batch.outputStream.use { it.write(body.toByteArray()) }
        val resp = batch.inputStream.bufferedReader().use { it.readText() }
        batch.disconnect()

        // oid -> checked-out working-tree file, downloaded once and reused.
        val fetched = HashMap<String, File>()
        val respObjs = JSONObject(resp).getJSONArray("objects")
        for (i in 0 until respObjs.length()) {
            val o = respObjs.getJSONObject(i)
            val oid = o.getString("oid")
            val dl = o.optJSONObject("actions")?.optJSONObject("download") ?: continue
            val href = dl.getString("href")
            val tmp = File.createTempFile("lfs", null, repoDir.parentFile)
            val conn = openConn(href)
            dl.optJSONObject("header")?.let { h ->
                for (k in h.keys()) conn.setRequestProperty(k, h.getString(k))
            }
            conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
            conn.disconnect()
            fetched[oid] = tmp
        }

        for ((file, p) in pointers) {
            fetched[p.oid]?.copyTo(file, overwrite = true)
        }
        for (f in fetched.values) f.delete()
    }

    private fun openConn(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 60_000
        }

    // Git LFS default endpoint for an HTTPS remote: "<url>.git/info/lfs".
    private fun lfsBatchUrl(cloneUrl: String): String {
        var base = cloneUrl.trim().removeSuffix("/")
        if (!base.endsWith(".git")) base += ".git"
        return "$base/info/lfs/objects/batch"
    }

    // Working-tree files that are LFS pointer stubs (skips the .git dir). A
    // pointer is a tiny text file beginning with the LFS spec version line.
    private fun collectLfsPointers(repoDir: File): List<Pair<File, LfsPtr>> {
        val out = ArrayList<Pair<File, LfsPtr>>()
        val oidRe = Regex("oid sha256:([0-9a-f]+)")
        val sizeRe = Regex("size (\\d+)")
        repoDir.walkTopDown().onEnter { it.name != ".git" }.forEach { f ->
            if (!f.isFile || f.length() !in 1..1024) return@forEach
            val text = try { f.readText() } catch (_: Exception) { return@forEach }
            if (!text.startsWith("version https://git-lfs.github.com/spec/v1")) {
                return@forEach
            }
            val oid = oidRe.find(text)?.groupValues?.get(1)
            val size = sizeRe.find(text)?.groupValues?.get(1)?.toLongOrNull()
            if (oid != null && size != null) out.add(f to LfsPtr(oid, size))
        }
        return out
    }
}
