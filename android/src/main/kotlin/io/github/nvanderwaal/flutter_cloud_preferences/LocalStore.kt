package io.github.nvanderwaal.flutter_cloud_preferences

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
  * Values that stay on this device: a JSON file in `noBackupFilesDir`, which
  * Auto Backup and device-to-device transfer always skip.
  *
  * Values are encoded like in [CloudStore]: bools and longs as JSON values,
  * everything else as a type-prefixed string.
  */
class LocalStore(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, FILE_NAME))

    /** Whether the store was created on this device before. */
    val exists: Boolean = file.baseFile.exists()

    private val json: JSONObject = load()

    fun getAll(): Map<String, Any> =
        json.keys().asSequence().mapNotNull { key -> CloudStore.decode(json.get(key))?.let { key to it } }.toMap()

    fun contains(key: String): Boolean = json.has(key)

    /** Returns false when [value] has an unsupported type. */
    fun set(key: String, value: Any): Boolean {
        val encoded: Any =
            when (value) {
                is Boolean, is Long -> value
                is Int -> value.toLong()
                else -> CloudStore.encode(value) ?: return false
            }
        json.put(key, encoded)
        return save()
    }

    fun remove(key: String) {
        if (json.remove(key) != null) save()
    }

    fun clear() {
        json.keys().asSequence().toList().forEach { json.remove(it) }
        save()
    }

    /** Creates the store's file if it does not exist yet. */
    fun create() {
        if (!file.baseFile.exists()) save()
    }

    private fun load(): JSONObject =
        try {
            if (file.baseFile.exists()) JSONObject(String(file.readFully(), Charsets.UTF_8)) else JSONObject()
        } catch (e: Exception) {
            Log.w(TAG, "Could not read local-only values.", e)
            JSONObject()
        }

    private fun save(): Boolean {
        val out = try {
            file.startWrite()
        } catch (e: IOException) {
            Log.w(TAG, "Could not save local-only values.", e)
            return false
        }
        return try {
            out.write(json.toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(out)
            true
        } catch (e: IOException) {
            file.failWrite(out)
            Log.w(TAG, "Could not save local-only values.", e)
            false
        }
    }

    private companion object {
        const val FILE_NAME = "flutter_cloud_preferences_local_only.json"
        const val TAG = "CloudPreferences"
    }
}
