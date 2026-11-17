package com.boctrust.boctrust_savings_loan

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Build
import com.google.android.gms.tasks.Tasks
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Kept across frames so it isn't rebuilt on every one.
    private val frameRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }
    private var frameRecognizerUsed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boctrust/scan_text")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognizeImage" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_argument", "A path is required.", null)
                        } else {
                            reply(result) { recognizeLines(path) }
                        }
                    }
                    "recognizeFrame" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val width = call.argument<Int>("width")
                        val height = call.argument<Int>("height")
                        val bytesPerRow = call.argument<Int>("bytesPerRow")
                        val rotation = call.argument<Int>("rotation")
                        if (bytes == null || width == null || height == null ||
                            bytesPerRow == null || rotation == null
                        ) {
                            result.error("invalid_argument", "A frame is required.", null)
                        } else {
                            reply(result) { recognizeFrame(bytes, width, height, bytesPerRow, rotation) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boctrust/app_update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availableRelease" -> availableRelease(result)
                    else -> result.notImplemented()
                }
            }
    }

    // Only Play-installed builds are checked. Never starts an update flow.
    private fun availableRelease(result: MethodChannel.Result) {
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
        } catch (e: Exception) {
            null
        }
        if (installer != "com.android.vending") {
            result.success(mapOf("status" to "unsupported"))
            return
        }
        try {
            AppUpdateManagerFactory.create(applicationContext).appUpdateInfo
                .addOnSuccessListener { info ->
                    when (info.updateAvailability()) {
                        UpdateAvailability.UPDATE_AVAILABLE -> result.success(
                            mapOf(
                                "status" to "available",
                                "versionCode" to info.availableVersionCode(),
                            ),
                        )
                        UpdateAvailability.UPDATE_NOT_AVAILABLE ->
                            result.success(mapOf("status" to "not_available"))
                        else -> result.success(mapOf("status" to "error"))
                    }
                }
                .addOnFailureListener { e ->
                    // Only the exception type; the message is not needed.
                    android.util.Log.w("AppUpdate", "Play query failed: ${e.javaClass.simpleName}")
                    result.success(mapOf("status" to "error"))
                }
        } catch (e: Exception) {
            result.success(mapOf("status" to "error"))
        }
    }

    // Runs [work] on the scan executor and posts its lines, or a failure, to Dart.
    private fun reply(result: MethodChannel.Result, work: () -> List<Map<String, Any>>) {
        scanExecutor.execute {
            try {
                val lines = work()
                mainHandler.post { result.success(lines) }
            } catch (e: Throwable) {
                // Includes OutOfMemoryError from the full-resolution decode, so
                // Dart always gets a reply. The message may name the file; send
                // only its type.
                mainHandler.post {
                    result.error("recognition_failed", e.javaClass.simpleName, null)
                }
            }
        }
    }

    override fun onDestroy() {
        if (frameRecognizerUsed) frameRecognizer.close()
        scanExecutor.shutdown()
        super.onDestroy()
    }

    // Runs on the scan executor. fromFilePath decodes at full resolution and
    // applies EXIF rotation, so the image and its width/height are upright.
    private fun recognizeLines(path: String): List<Map<String, Any>> {
        val image = InputImage.fromFilePath(applicationContext, Uri.fromFile(File(path)))
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            return lines(Tasks.await(recognizer.process(image)), image.width, image.height)
        } finally {
            recognizer.close()
        }
    }

    // Runs on the scan executor. An NV21 frame; ML Kit rotates it by [rotation]
    // and reports boxes on the rotated image, so those are measured by its size.
    private fun recognizeFrame(
        bytes: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        rotation: Int,
    ): List<Map<String, Any>> {
        val nv21 = if (bytesPerRow > width) {
            // Repack into a tight buffer: height Y rows, then height / 2 VU rows.
            val tight = ByteArray(width * height * 3 / 2)
            for (row in 0 until height + height / 2) {
                System.arraycopy(bytes, row * bytesPerRow, tight, row * width, width)
            }
            tight
        } else {
            bytes
        }
        val image = InputImage.fromByteArray(
            nv21, width, height, rotation, InputImage.IMAGE_FORMAT_NV21,
        )
        frameRecognizerUsed = true
        val text = Tasks.await(frameRecognizer.process(image))
        val upright = rotation == 90 || rotation == 270
        return lines(text, if (upright) height else width, if (upright) width else height)
    }

    private fun lines(text: Text, imageWidth: Int, imageHeight: Int): List<Map<String, Any>> {
        val width = imageWidth.toDouble()
        val height = imageHeight.toDouble()
        val lines = mutableListOf<Map<String, Any>>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                // Boxes can overhang the image by a few pixels; keep the visible part.
                val left = box.left.coerceIn(0, imageWidth)
                val top = box.top.coerceIn(0, imageHeight)
                val right = box.right.coerceIn(left, imageWidth)
                val bottom = box.bottom.coerceIn(top, imageHeight)
                lines.add(
                    mapOf(
                        "text" to line.text,
                        "left" to left / width,
                        "top" to top / height,
                        "width" to (right - left) / width,
                        "height" to (bottom - top) / height,
                    ),
                )
            }
        }
        return lines
    }
}
