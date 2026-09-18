package app.biblerecite

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var backupFileExportChannel: BackupFileExportChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppUpdateChannel(this).register(flutterEngine)
        QrImageStoreChannel(this).register(flutterEngine)
        PlanJsonStoreChannel(this).register(flutterEngine)
        backupFileExportChannel = BackupFileExportChannel(this)
        backupFileExportChannel.register(flutterEngine)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::backupFileExportChannel.isInitialized &&
            backupFileExportChannel.handleActivityResult(requestCode, resultCode, data)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
