package app.biblerecite

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val qrImageStoreChannelName = "app.biblerecite/qr_image_store"

class QrImageStoreChannel(private val activity: MainActivity) {
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, qrImageStoreChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "savePng") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: throw IllegalArgumentException("PNG data is required")
                    val displayName = call.argument<String>("displayName")
                        ?: "BibleRecite-Android-QR.png"
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/BibleRecite")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                    }
                    val resolver = activity.contentResolver
                    val uri = resolver.insert(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        values,
                    ) ?: throw IllegalStateException("Unable to create gallery image")
                    try {
                        resolver.openOutputStream(uri)?.use { it.write(bytes) }
                            ?: throw IllegalStateException("Unable to write gallery image")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            values.clear()
                            values.put(MediaStore.Images.Media.IS_PENDING, 0)
                            resolver.update(uri, values, null, null)
                        }
                        result.success(uri.toString())
                    } catch (error: Exception) {
                        resolver.delete(uri, null, null)
                        throw error
                    }
                } catch (error: Exception) {
                    result.error("qr_image_store_error", error.message, null)
                }
            }
    }
}
