package app.tagmusic.player

import android.app.Activity
import android.app.NotificationManager
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.Settings
import android.database.Cursor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** SAF only: never resolve document URIs into filesystem paths. */
class DocumentBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.tagmusic.player/documents")
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "notificationsEnabled") {
                result.success(notificationsEnabled())
            } else if (call.method == "requestNotifications") {
                if (notificationRequest != null) result.error("busy", "通知授权正在处理", null)
                else if (Build.VERSION.SDK_INT >= 33 &&
                    activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    notificationRequest = result
                    try {
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATIONS)
                    } catch (e: Exception) {
                        notificationRequest = null
                        result.error("notifications", e.message, null)
                    }
                } else result.success(notificationsEnabled())
            } else if (call.method == "openNotificationSettings") {
                try {
                    activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("notifications", e.message, null)
                }
            } else if (call.method == "pickDirectory") {
                if (picker != null) result.error("busy", "目录选择器已打开", null)
                else {
                    picker = result
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        }, PICK_DIRECTORY)
                    } catch (e: Exception) {
                        picker = null
                        result.error("picker", e.message, null)
                    }
                }
            } else {
                worker.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "beginScan" -> {
                                val tree = Uri.parse(requireNotNull(call.argument<String>("uri")))
                                require(tree.scheme == "content" && DocumentsContract.isTreeUri(tree))
                                val token = ++scanToken
                                scans[token] = Scan(tree, activity.applicationContext.contentResolver)
                                token
                            }
                            "nextScan" -> requireNotNull(scans[call.argument<Int>("token")]).next()
                            "endScan" -> { scans.remove(call.argument<Int>("token"))?.close(); null }
                            "list" -> list(Uri.parse(requireNotNull(call.argument<String>("uri"))))
                            "open" -> {
                                val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                                require(uri.scheme == "content") { "仅支持 SAF content URI" }
                                val pfd = requireNotNull(activity.contentResolver.openFileDescriptor(uri, "r"))
                                descriptors[pfd.fd] = pfd
                                pfd.fd
                            }
                            "close" -> {
                                descriptors.remove(call.argument<Int>("fd"))?.close()
                                null
                            }
                            "diagnostics" -> mapOf(
                                "managedDescriptors" to descriptors.size,
                                "inputAcceptingText" to (activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).isAcceptingText,
                                "inputActive" to (activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).isActive,
                                "processDescriptors" to (java.io.File("/proc/self/fd").list()?.size ?: -1),
                                "persistedReadGrants" to activity.contentResolver.persistedUriPermissions.count { it.isReadPermission }
                            )
                            else -> throw IllegalArgumentException("未知文档操作")
                        }
                        main.post { result.success(value) }
                    } catch (e: Exception) {
                        main.post { result.error("documents", e.message ?: e.javaClass.simpleName, null) }
                    }
                }
            }
        }
    }

    private fun notificationsEnabled(): Boolean =
        activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != NOTIFICATIONS) return false
        notificationRequest?.success(notificationsEnabled())
        notificationRequest = null
        return true
    }

    fun onActivityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != PICK_DIRECTORY) return false
        val pending = picker ?: return true
        picker = null
        if (result != Activity.RESULT_OK || data?.data == null) pending.success(null)
        else try {
            val uri = data.data!!
            val flags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            require(flags != 0) { "目录没有只读授权" }
            activity.contentResolver.takePersistableUriPermission(uri, flags)
            pending.success(uri.toString())
        } catch (e: Exception) {
            pending.error("permission", e.message, null)
        }
        return true
    }

    private fun list(tree: Uri): List<Map<String, String>> {
        require(tree.scheme == "content" && DocumentsContract.isTreeUri(tree)) { "需要系统目录授权 URI" }
        val pending = java.util.ArrayDeque<String>()
        pending.add(DocumentsContract.getTreeDocumentId(tree))
        val visited = mutableSetOf<String>()
        val tracks = mutableListOf<Map<String, String>>()
        while (!pending.isEmpty()) {
            val id = pending.removeFirst()
            if (!visited.add(id)) continue
            require(visited.size <= 10000) { "R1 验证目录超过一万个子目录" }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            val projection = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
            val cursor = activity.contentResolver.query(children, projection, null, null, null)
                ?: throw IllegalStateException("目录不可访问，请重新授权")
            cursor.use {
                while (it.moveToNext()) {
                    val childId = it.getString(0)
                    val name = it.getString(1) ?: childId
                    if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) pending.add(childId)
                    else if (name.substringAfterLast('.', "").lowercase() in extensions) {
                        require(tracks.size < 10000) { "R1 验证最多读取一万首" }
                        tracks.add(mapOf("location" to DocumentsContract.buildDocumentUriUsingTree(tree, childId).toString(), "name" to name))
                    }
                }
            }
        }
        return tracks.sortedBy { it["name"] }
    }

    /** Bounded pages; the single worker can service playback FD calls between pages. */
    private class Scan(private val tree: Uri, private val resolver: android.content.ContentResolver) {
        private val pending = java.util.ArrayDeque<Pair<String, String>>()
        private val visited = mutableSetOf<String>()
        private var cursor: Cursor? = null
        private var parentPath = ""
        init { pending.add(DocumentsContract.getTreeDocumentId(tree) to "") }
        fun close() { cursor?.close(); cursor = null; pending.clear() }
        fun next(): Map<String, Any> {
            val files = mutableListOf<Map<String, Any?>>()
            var examined = 0
            try {
                while (examined < 128) {
                    if (cursor == null) {
                        if (pending.isEmpty()) break
                        val (id, path) = pending.removeFirst()
                        if (!visited.add(id)) continue
                        require(visited.size <= 100000) { "目录数量超过安全上限" }
                        parentPath = path
                        cursor = resolver.query(
                            DocumentsContract.buildChildDocumentsUriUsingTree(tree, id),
                            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                                DocumentsContract.Document.COLUMN_MIME_TYPE,
                                DocumentsContract.Document.COLUMN_SIZE,
                                DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null)
                            ?: throw IllegalStateException("子目录不可访问，请重新授权")
                    }
                    val row = requireNotNull(cursor)
                    if (!row.moveToNext()) { row.close(); cursor = null; continue }
                    examined++
                    val id = row.getString(0)
                    val name = row.getString(1) ?: id
                    val path = if (parentPath.isEmpty()) name else "$parentPath/$name"
                    if (row.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) pending.add(id to path)
                    else if (name.substringAfterLast('.', "").lowercase() in extensions) {
                        files.add(mapOf("identity" to "${tree.authority}:$id",
                            "location" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                            "name" to name, "relativePath" to path,
                            "size" to if (row.isNull(3)) null else row.getLong(3),
                            "modified" to if (row.isNull(4) || row.getLong(4) <= 0) null else row.getLong(4)))
                    }
                }
                return mapOf("files" to files, "done" to (cursor == null && pending.isEmpty()))
            } catch (e: Exception) { close(); throw e }
        }
    }

    companion object {
        private val extensions = setOf("mp3", "flac", "m4a", "aac", "wav", "ogg", "opus")
        private const val PICK_DIRECTORY = 4011
        private const val NOTIFICATIONS = 4012
        // AudioService's FlutterEngine survives Activity recreation. Descriptor
        // ownership must survive it too; every access is serialized by worker.
        private val worker = Executors.newSingleThreadExecutor()
        private val descriptors = mutableMapOf<Int, ParcelFileDescriptor>()
        private var picker: MethodChannel.Result? = null
        private var notificationRequest: MethodChannel.Result? = null
        private var scanToken = 0
        private val scans = mutableMapOf<Int, Scan>()
    }
}
