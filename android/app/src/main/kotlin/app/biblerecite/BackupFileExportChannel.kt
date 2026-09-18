package app.biblerecite

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val backupFileExportChannelName = "app.biblerecite/backup_file"
private const val backupFileExportRequestCode = 8842

private data class PendingBackupExport(
    val bytes: ByteArray,
    val result: MethodChannel.Result,
)

/**
 * Exports a backup with Android's document provider instead of writing directly
 * to shared storage. This works on both legacy devices and scoped-storage devices
 * without requesting storage permissions.
 */
class BackupFileExportChannel(private val activity: MainActivity) {
    private var pending: PendingBackupExport? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupFileExportChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "exportJson") return@setMethodCallHandler result.notImplemented()
                if (pending != null) {
                    result.error("backup_export_in_progress", "Another backup export is already in progress", null)
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                    ?: return@setMethodCallHandler result.error(
                        "backup_export_invalid_data",
                        "Backup data is required",
                        null,
                    )
                val name = call.argument<String>("displayName") ?: "BibleRecite-backup.json"
                pending = PendingBackupExport(bytes, result)
                try {
                    activity.startActivityForResult(
                        Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, name)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        },
                        backupFileExportRequestCode,
                    )
                } catch (error: Exception) {
                    pending = null
                    result.error("backup_export_error", error.message, null)
                }
            }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != backupFileExportRequestCode) return false
        val export = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            export.result.success(null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            export.result.error("backup_export_error", "No backup destination was selected", null)
            return true
        }
        try {
            activity.contentResolver.openOutputStream(uri)?.use { it.write(export.bytes) }
                ?: error("Unable to write the selected backup file")
            export.result.success(uri.toString())
        } catch (error: Exception) {
            export.result.error("backup_export_error", error.message, null)
        }
        return true
    }
}
