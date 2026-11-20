package app.tagmusic.player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/** Only the editor uses a temporary writable grant, scoped to the chosen parent folder. */
class SongEditorBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val resolver = activity.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "app.tagmusic.player/song_editor").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickParent" -> pickParent(result) {
                    Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        .putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                        .putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri(call.argument("uri")))
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }
                "copySong", "replaceSong" -> worker.execute {
                    try {
                        val original = uri(call.argument("uri"))
                        val value = if (call.method == "copySong") {
                            val destination = cacheFile(call.argument("path"))
                            input(original).use { stream -> destination.outputStream().use { stream.copyTo(it) } }
                            null
                        } else replace(
                            original,
                            uri(call.argument("parent")),
                            cacheFile(call.argument("path")),
                            requireNotNull(call.argument<String>("digest")),
                            requireNotNull(call.argument<String>("editedDigest")),
                            requireNotNull(call.argument<String>("originalName")),
                            requireNotNull(call.argument<String>("name"))
                        )
                        main.post { result.success(value) }
                    } catch (e: Exception) {
                        main.post { result.error("song_editor", e.message ?: "文件操作失败", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickParent(result: MethodChannel.Result, intent: () -> Intent) {
        if (pending != null) {
            result.error("busy", "文件选择器已打开", null)
            return
        }
        pending = result
        try {
            activity.startActivityForResult(intent(), PICK_PARENT)
        } catch (e: Exception) {
            pending = null
            result.error("picker", e.message, null)
        }
    }

    fun onActivityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != PICK_PARENT) return false
        val callback = pending ?: return true
        pending = null
        val selected = data?.data
        if (result != Activity.RESULT_OK || selected == null) {
            callback.success(null)
        } else {
            val writable = (requireNotNull(data).flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) != 0
            if (writable) callback.success(selected.toString())
            else callback.error("permission", "系统未授予文件夹写入权限", null)
        }
        return true
    }

    private fun uri(value: String?): Uri = Uri.parse(requireNotNull(value)).also {
        require(it.scheme == "content") { "需要系统授予的文件访问权限" }
    }

    private fun cacheFile(value: String?): File = File(requireNotNull(value)).canonicalFile.also {
        val directory = it.parentFile
        require(directory?.parentFile == activity.cacheDir.canonicalFile &&
            directory.name.startsWith("tag-music-edit-")) { "无效的编辑临时文件" }
    }

    private fun input(uri: Uri): InputStream =
        checkNotNull(resolver.openInputStream(uri)) { "无法读取歌曲文件" }

    private data class Info(val name: String, val flags: Int, val size: Long?, val modified: Long?)

    private fun info(uri: Uri): Info = checkNotNull(resolver.query(uri, arrayOf(
        Document.COLUMN_DISPLAY_NAME, Document.COLUMN_FLAGS, Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED
    ), null, null, null)).use { cursor ->
        check(cursor.moveToFirst()) { "文件已移动或不可访问" }
        Info(cursor.getString(0), cursor.getInt(1), if (cursor.isNull(2)) null else cursor.getLong(2),
            if (cursor.isNull(3)) null else cursor.getLong(3).takeIf { it > 0 })
    }

    private fun digest(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        input(uri).use { stream ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun replace(
        selected: Uri, tree: Uri, edited: File, expectedDigest: String, editedDigest: String,
        originalName: String, name: String
    ): Map<String, Any?> {
        require(DocumentsContract.isTreeUri(tree)) {
            "请选择歌曲所在的文件夹"
        }
        require(tree.authority == selected.authority) {
            "请授权这首歌曲所在的文件夹"
        }
        val parentId = DocumentsContract.getTreeDocumentId(tree)
        val oldId = DocumentsContract.getDocumentId(selected)
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, parentId)
        val original = DocumentsContract.buildDocumentUriUsingTree(tree, oldId)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        checkNotNull(resolver.query(children, arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME),
            null, null, null)) { "无法读取歌曲文件夹" }.use { cursor ->
            var found = false
            while (cursor.moveToNext()) {
                if (cursor.getString(0) == oldId) found = true
                else check(!cursor.getString(1).equals(name, ignoreCase = true)) { "文件夹里已有同名文件：$name" }
            }
            check(found) { "请选择直接包含这首歌曲的文件夹" }
        }

        val originalInfo = info(original)
        check(originalInfo.name == originalName) { "原文件已改名，请重新选择歌曲" }
        check(originalInfo.flags and Document.FLAG_SUPPORTS_RENAME != 0 &&
            info(parent).flags and Document.FLAG_DIR_SUPPORTS_CREATE != 0) { "这个文件夹不支持安全保存，请选择本地可写存储" }

        val token = UUID.randomUUID().toString()
        var staged = checkNotNull(DocumentsContract.createDocument(
            resolver, parent, "application/octet-stream", ".tag-music-edit-$token.tmp"
        )) { "无法建立临时文件" }
        var backup: Uri? = null
        val backupName = "Tag Music 原件-$token.bak"
        try {
            checkNotNull(resolver.openOutputStream(staged, "w")).use { out ->
                edited.inputStream().use { it.copyTo(out) }
            }
            check(digest(staged) == editedDigest) { "临时文件校验未通过" }
            check(digest(original) == expectedDigest) { "原文件已被其他程序修改，请重新选择歌曲" }

            backup = checkNotNull(DocumentsContract.renameDocument(resolver, original, backupName)) {
                "无法暂存原文件"
            }
            staged = checkNotNull(DocumentsContract.renameDocument(resolver, staged, name)) { "无法重命名歌曲" }
            val saved = info(staged)
            check(saved.name == name) { "系统未使用所需文件名，文件夹可能已有同名文件" }
            val id = DocumentsContract.getDocumentId(staged)
            return mapOf(
                "location" to staged.toString(), "documentId" to id, "name" to saved.name,
                "identity" to "${staged.authority}:$id", "size" to saved.size, "modified" to saved.modified,
                "backup" to if (delete(backup)) null else backupName
            )
        } catch (e: Exception) {
            delete(staged)
            if (backup != null) {
                val restored = runCatching {
                    val result = DocumentsContract.renameDocument(resolver, backup, originalName)
                    result != null && info(result).name == originalName
                }.getOrDefault(false)
                check(restored) { "保存失败。原歌曲仍保留在同一文件夹，请查看 $backupName" }
            }
            throw e
        }
    }

    private fun delete(uri: Uri): Boolean =
        runCatching { DocumentsContract.deleteDocument(resolver, uri) }.getOrDefault(false)

    companion object {
        private const val PICK_PARENT = 4022
        private val worker = Executors.newSingleThreadExecutor()
    }
}
