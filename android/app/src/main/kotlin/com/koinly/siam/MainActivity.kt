package com.koinly.siam

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val updaterChannel = "com.koinly.siam/updater"
    private val profileMediaChannel = "com.koinly.siam/profile_media"
    private val telegramPhotoChannel = "com.koinly.siam/telegram_photo"
    private val profileMediaPermissionRequestCode = 4107
    private var pendingProfileMediaPermissionResult: MethodChannel.Result? = null
    private var pendingTelegramPhotoResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("missing_path", "APK path is missing.", null)
                    } else {
                        result.success(installApk(path))
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, profileMediaChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> result.success(profileMediaPermissionState())
                "requestPermission" -> requestProfileMediaPermission(result)
                "openAppSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, telegramPhotoChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPhotos" -> getPhotos(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != profileMediaPermissionRequestCode) return
        pendingProfileMediaPermissionResult?.success(profileMediaPermissionState(checkPermanentDenial = true))
        pendingProfileMediaPermissionResult = null
    }

    private fun fullProfileMediaPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
            )
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun requestedProfileMediaPermissions(): Array<String> {
        val permissions = fullProfileMediaPermissions().toMutableList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            permissions.add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        }
        return permissions.toTypedArray()
    }

    private fun hasFullProfileMediaPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return fullProfileMediaPermissions().all { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasSelectedProfileMediaPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun profileMediaPermissionState(checkPermanentDenial: Boolean = false): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "granted"
        if (hasFullProfileMediaPermission() || hasSelectedProfileMediaPermission()) return "granted"
        if (checkPermanentDenial) {
            val permanentlyDenied = fullProfileMediaPermissions().any { permission ->
                ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED &&
                    !ActivityCompat.shouldShowRequestPermissionRationale(this, permission)
            }
            if (permanentlyDenied) return "permanentlyDenied"
        }
        return "denied"
    }

    private fun requestProfileMediaPermission(result: MethodChannel.Result) {
        if (hasFullProfileMediaPermission() || hasSelectedProfileMediaPermission()) {
            result.success("granted")
            return
        }
        if (pendingProfileMediaPermissionResult != null) {
            result.error("request_in_progress", "A Photos and videos permission request is already active.", null)
            return
        }
        pendingProfileMediaPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            requestedProfileMediaPermissions(),
            profileMediaPermissionRequestCode,
        )
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }

    private fun installApk(path: String): Boolean {
        val apkFile = File(path)
        if (!apkFile.exists()) return false
        val apkUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apkFile)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        grantUriPermission(packageName, apkUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(intent)
        return true
    }

    private fun getPhotos(call: MethodCall, result: MethodChannel.Result) {
        try {
            val contentResolver = contentResolver
            val bucketId = call.argument<String>("bucketId") ?: "%"
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.MIME_TYPE,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.SIZE,
            )
            val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val selection = MediaStore.Images.Media.MIME_TYPE + " != null"
            val sortOrder = MediaStore.Images.Media.DATE_ADDED + " DESC"
            val cursor = contentResolver.query(uri, projection, selection, null, sortOrder)
            val photoPaths = mutableListOf<String>()
            if (cursor != null && cursor.moveToFirst()) {
                do {
                    val id = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
                    val displayName = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME))
                    // Build content URI for the image
                    val contentUri = ContentUris.withAppendedId(uri, id.toLong())
                    // Copy file to app's internal directory and get path
                    val outputPath = copyImageToAppDirectory(contentResolver, contentUri, displayName)
                    photoPaths.add(outputPath ?: '')
                } while (cursor.moveToNext())
            }
            cursor?.close()
            result.success(photoPaths)
        } catch (e: Exception) {
            result.error("get_photos_failed", e.message ?: "Failed to get photos", null)
        }
    }

    private fun copyImageToAppDirectory(
        contentResolver: ContentResolver,
        contentUri: Uri,
        displayName: String
    ): String? {
        // Define the app's internal directory for temp photos
        val appDir = applicationContext.filesDir
        val dir = File(appDir, "koinly_temp_photos")
        dir.mkdirs()

        // Output file path
        val outputFile = File(dir, displayName)
        outputFile.parent.mkdirs()

        // Copy input stream to output file
        val inputStream = contentResolver.openInputStream(contentUri) ?: return null
        try {
            inputStream.use { input ->
                FileOutputStream(outputFile).use { output ->
                    input.copyTo(output)
                }
            }
        } catch (_) {
            return null
        }

        // Return the absolute path
        return outputFile.absolutePath
    }
}
