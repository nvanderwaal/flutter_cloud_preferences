package io.github.nvanderwaal.flutter_cloud_preferences

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import org.json.JSONArray

/**
  * Stores values in a dedicated SharedPreferences file, which Android Auto Backup
  * includes by default and restores before the app first starts after an install.
  *
  * SharedPreferences has no double, list or byte type and cannot tell a stored
  * string from an encoded one, so every string is stored with a type prefix:
  * `s:` string, `d:` double, `l:` JSON array of strings, `b:` Base64 bytes.
  * Bools are stored as booleans and ints as longs.
  */
class CloudStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    fun getAll(): Map<String, Any> =
        prefs.all.mapNotNull { (key, value) -> decode(value)?.let { key to it } }.toMap()

    /** Returns false when [value] has an unsupported type. */
    fun set(key: String, value: Any): Boolean {
        val editor = prefs.edit()
        when (value) {
            is Boolean -> editor.putBoolean(key, value)
            is Int -> editor.putLong(key, value.toLong())
            is Long -> editor.putLong(key, value)
            else -> editor.putString(key, encode(value) ?: return false)
        }
        return editor.commit()
    }

    fun remove(key: String) {
        prefs.edit().remove(key).commit()
    }

    fun clear() {
        prefs.edit().clear().commit()
    }

    companion object {
        /** The file name to include in custom backup rules, without `.xml`. */
        const val FILE_NAME = "flutter_cloud_preferences"

        private const val STRING = "s:"
        private const val DOUBLE = "d:"
        private const val LIST = "l:"
        private const val BYTES = "b:"

        fun encode(value: Any): String? =
            when (value) {
                is String -> STRING + value
                is Double -> DOUBLE + value.toString()
                is ByteArray -> BYTES + Base64.encodeToString(value, Base64.NO_WRAP)
                is List<*> ->
                    if (value.all { it is String }) LIST + JSONArray(value).toString() else null
                else -> null
            }

        fun decode(value: Any?): Any? =
            when (value) {
                is Boolean, is Long -> value
                is Int -> value.toLong()
                is String ->
                    when {
                        value.startsWith(STRING) -> value.substring(STRING.length)
                        value.startsWith(DOUBLE) -> value.substring(DOUBLE.length).toDoubleOrNull()
                        value.startsWith(BYTES) -> Base64.decode(value.substring(BYTES.length), Base64.NO_WRAP)
                        value.startsWith(LIST) -> {
                            val array = JSONArray(value.substring(LIST.length))
                            List(array.length()) { array.getString(it) }
                        }
                        else -> null
                    }
                else -> null
            }
    }
}
