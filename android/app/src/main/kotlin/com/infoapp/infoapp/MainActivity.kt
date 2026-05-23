package com.infoapp.infoapp

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "infoapp/app_launcher"
    private val preferencesName = "infoapp_modules"
    private val selectedAppsKey = "selected_apps"
    private val descriptionPrefix = "description_"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> result.success(getInstalledApps())
                "getSavedApps" -> result.success(getSavedApps())
                "getAppDescriptions" -> result.success(getAppDescriptions())
                "saveApps" -> {
                    val packages = call.arguments as? List<*>
                    saveApps(packages.orEmpty().filterIsInstance<String>())
                    result.success(null)
                }
                "saveAppDescription" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val packageName = arguments?.get("packageName") as? String
                    val description = arguments?.get("description") as? String

                    if (packageName == null || description == null) {
                        result.error("invalid_arguments", "Datos de descripcion invalidos.", null)
                    } else {
                        saveAppDescription(packageName, description)
                        result.success(null)
                    }
                }
                "launchApp" -> {
                    val packageName = call.arguments as? String
                    result.success(packageName?.let(::launchApp) ?: false)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val packageManager = packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }

        return activities
            .filter { it.activityInfo.packageName != packageName }
            .map { resolveInfo ->
                val appName = resolveInfo.loadLabel(packageManager).toString()
                val icon = resolveInfo.loadIcon(packageManager)
                mapOf(
                    "packageName" to resolveInfo.activityInfo.packageName,
                    "name" to appName,
                    "icon" to drawableToBase64(icon)
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["name"]?.lowercase(Locale.getDefault()) }
    }

    private fun getSavedApps(): List<String> {
        val preferences = getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        return preferences.getStringSet(selectedAppsKey, emptySet()).orEmpty().toList()
    }

    private fun saveApps(packageNames: List<String>) {
        getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(selectedAppsKey, packageNames.toSet())
            .apply()
    }

    private fun getAppDescriptions(): Map<String, String> {
        val preferences = getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        return preferences.all
            .filterKeys { it.startsWith(descriptionPrefix) }
            .mapKeys { it.key.removePrefix(descriptionPrefix) }
            .mapValues { it.value as? String ?: "" }
            .filterValues { it.isNotBlank() }
    }

    private fun saveAppDescription(packageName: String, description: String) {
        val editor = getSharedPreferences(preferencesName, Context.MODE_PRIVATE).edit()
        val key = "$descriptionPrefix$packageName"

        if (description.isBlank()) {
            editor.remove(key)
        } else {
            editor.putString(key, description.trim())
        }

        editor.apply()
    }

    private fun launchApp(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun drawableToBase64(drawable: Drawable): String {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)

        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
    }
}
