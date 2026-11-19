package com.example.kyvra_app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val profileChannel = "blossom/profile_store"
    private val readerChannel = "blossom/reader_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, profileChannel)
            .setMethodCallHandler { call, result ->
                val email = call.argument<String>("email")?.trim()?.lowercase()
                if (email.isNullOrEmpty()) {
                    result.error("invalid_email", "An email is required for the local profile key.", null)
                    return@setMethodCallHandler
                }
                val preferences = getSharedPreferences("blossom_profiles", Context.MODE_PRIVATE)
                val key = "profile_$email"
                val trackingKey = "tracking_$email"
                when (call.method) {
                    "loadProfile" -> result.success(preferences.getString(key, null))
                    "saveProfile" -> {
                        val profile = call.argument<String>("profile")
                        if (profile == null) {
                            result.error("invalid_profile", "A profile is required.", null)
                        } else {
                            preferences.edit().putString(key, profile).apply()
                            result.success(null)
                        }
                    }
                    "loadTrackingData" -> result.success(preferences.getString(trackingKey, null))
                    "saveTrackingData" -> {
                        val data = call.argument<String>("data")
                        if (data == null) {
                            result.error("invalid_tracking_data", "Tracking data is required.", null)
                        } else {
                            preferences.edit().putString(trackingKey, data).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, readerChannel)
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences("blossom_reader", Context.MODE_PRIVATE)
                when (call.method) {
                    "loadReader" -> {
                        val id = preferences.getString("id", null)
                        val name = preferences.getString("name", "Kyvra reader")
                        if (id == null) result.success(null)
                        else result.success(mapOf("id" to id, "name" to name))
                    }
                    "saveReader" -> {
                        val id = call.argument<String>("id")
                        val name = call.argument<String>("name")
                        if (id.isNullOrBlank() || name.isNullOrBlank()) {
                            result.error("invalid_reader", "A reader ID and name are required.", null)
                        } else {
                            preferences.edit().putString("id", id).putString("name", name).apply()
                            result.success(null)
                        }
                    }
                    "forgetReader" -> {
                        preferences.edit().clear().apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
