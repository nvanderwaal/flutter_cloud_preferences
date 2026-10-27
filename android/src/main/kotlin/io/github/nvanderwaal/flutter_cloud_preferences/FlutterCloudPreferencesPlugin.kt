package io.github.nvanderwaal.flutter_cloud_preferences

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
  * Connects the Dart API to [CloudStore].
  *
  * Android Auto Backup restores data before the app starts, so the change stream
  * never emits and live sync is not available.
  */
class FlutterCloudPreferencesPlugin : FlutterPlugin, CloudPreferencesHostApi {
    private var store: CloudStore? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        store = CloudStore(binding.applicationContext)
        CloudPreferencesHostApi.setUp(binding.binaryMessenger, this)
        WatchChangesStreamHandler.register(binding.binaryMessenger, NoChanges)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        CloudPreferencesHostApi.setUp(binding.binaryMessenger, null)
        store = null
    }

    override fun initialize(liveSync: Boolean): Map<String, Any> {
        if (liveSync) Log.w(TAG, "liveSync is not supported on Android and is ignored.")
        return requireStore().getAll()
    }

    override fun setValue(key: String, value: Any) {
        if (!requireStore().set(key, value)) {
            throw FlutterError("unsupported-type", "Unsupported value type for $key.", null)
        }
    }

    override fun remove(key: String) = requireStore().remove(key)

    override fun clear() = requireStore().clear()

    private fun requireStore(): CloudStore =
        store ?: throw FlutterError("detached", "The plugin is not attached to an engine.", null)

    private object NoChanges : WatchChangesStreamHandler()

    private companion object {
        const val TAG = "CloudPreferences"
    }
}
