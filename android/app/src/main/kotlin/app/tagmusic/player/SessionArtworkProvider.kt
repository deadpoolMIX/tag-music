package app.tagmusic.player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

class SessionArtworkProvider : FileProvider() {
    companion object {
        private const val MAX_CACHED_COVERS = 4
        private const val READ = Intent.FLAG_GRANT_READ_URI_PERMISSION
        private val readers = listOf("com.vivo.musicwidgetmix", "com.android.systemui")

        fun publish(context: Context, png: ByteArray): Uri {
            require(png.size in 1..(2 * 1024 * 1024))
            val directory = File(context.cacheDir, "session-artwork")
            check(directory.isDirectory || directory.mkdirs())
            val authority = "${context.packageName}.session-artwork"
            val cover = File.createTempFile("cover-", ".png", directory)
            val uri = try {
                cover.writeBytes(png)
                getUriForFile(context, authority, cover)
            } catch (error: Exception) {
                cover.delete()
                throw error
            }
            for (reader in readers) {
                try {
                    context.grantUriPermission(reader, uri, READ)
                } catch (error: SecurityException) {
                    Log.w("SessionArtwork", "Cover access unavailable for $reader", error)
                } catch (error: IllegalArgumentException) {
                    Log.w("SessionArtwork", "Cover reader unavailable: $reader", error)
                }
            }
            // Readers may still be loading the preceding song's artwork.
            directory.listFiles { file -> file != cover && file.extension == "png" }
                ?.sortedByDescending { it.lastModified() }
                ?.drop(MAX_CACHED_COVERS - 1)
                ?.forEach { old ->
                    context.revokeUriPermission(getUriForFile(context, authority, old), READ)
                    old.delete()
                }
            return uri
        }
    }
}
