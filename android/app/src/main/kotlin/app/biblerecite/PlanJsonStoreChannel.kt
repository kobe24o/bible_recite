package app.biblerecite

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val planJsonStoreChannelName = "app.biblerecite/plan_json_store"

class PlanJsonStoreChannel(private val activity: MainActivity) {
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, planJsonStoreChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveJson") return@setMethodCallHandler result.notImplemented()
                try {
                    val bytes = call.argument<ByteArray>("bytes") ?: error("JSON data is required")
                    val name = call.argument<String>("displayName") ?: "BibleRecite-plan.json"
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, name)
                        put(MediaStore.Downloads.MIME_TYPE, "application/json")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.Downloads.RELATIVE_PATH, "Download/BibleRecite")
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                    }
                    val resolver = activity.contentResolver
                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: error("Unable to create plan file")
                    resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("Unable to write plan file")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)
                    }
                    result.success(uri.toString())
                } catch (error: Exception) {
                    result.error("plan_json_store_error", error.message, null)
                }
            }
    }
}
