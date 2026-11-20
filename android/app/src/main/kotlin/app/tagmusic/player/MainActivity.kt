package app.tagmusic.player

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var documents: DocumentBridge? = null
    private var songEditor: SongEditorBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        documents = DocumentBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        songEditor = SongEditorBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Android activity result callback is required by Flutter embedding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (songEditor?.onActivityResult(requestCode, resultCode, data) != true &&
            documents?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (documents?.onRequestPermissionsResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
