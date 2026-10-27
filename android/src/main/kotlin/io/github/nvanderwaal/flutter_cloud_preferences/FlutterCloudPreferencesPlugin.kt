package io.github.nvanderwaal.flutter_cloud_preferences

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
  * Connects the Dart API to [CloudStore], and [LocalStore] for local-only keys.
  *
  * Android Auto Backup restores data before the app starts, so the change stream
  * never emits and live sync is not available.
  */
class FlutterCloudPreferencesPlugin : FlutterPlugin, CloudPreferencesHostApi {
    private var store: CloudStore? = null
    private var local: LocalStore? = null
    private var localOnlyKeys: Set<String> = emptySet()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        store = CloudStore(binding.applicationContext)
        local = LocalStore(binding.applicationContext)
        CloudPreferencesHostApi.setUp(binding.binaryMessenger, this)
        WatchChangesStreamHandler.register(binding.binaryMessenger, NoChanges)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        CloudPreferencesHostApi.setUp(binding.binaryMessenger, null)
        store = null
        local = null
    }

    override fun initialize(liveSync: Boolean, localOnlyKeys: List<String>): Map<String, Any> {
        if (liveSync) Log.w(TAG, "liveSync is not supported on Android and is ignored.")
        this.localOnlyKeys = localOnlyKeys.toSet()
        moveLocalOnlyValues()
        return requireStore().getAll() + requireLocal().getAll()
    }

    override fun setValue(key: String, value: Any) {
        val saved = if (key in localOnlyKeys) requireLocal().set(key, value) else requireStore().set(key, value)
        if (!saved) {
            throw FlutterError("unsupported-type", "Unsupported value type for $key.", null)
        }
    }

    override fun remove(key: String) =
        if (key in localOnlyKeys) requireLocal().remove(key) else requireStore().remove(key)

    override fun clear() {
        requireStore().clear()
        requireLocal().clear()
    }

    /**
      * Moves values to the store their key belongs in, after the app changed
      * which keys are local-only.
      */
    private fun moveLocalOnlyValues() {
        val store = requireStore()
        val local = requireLocal()
        // A local store that already exists was created on this device, so a
        // backed-up value of a newly local-only key was written here and is
        // kept. Otherwise the value may have been restored from another device,
        // and is dropped.
        val keepBackedUp = local.exists
        val backedUp = store.getAll()
        for (key in localOnlyKeys) {
            val value = backedUp[key] ?: continue
            if (keepBackedUp && !local.contains(key)) local.set(key, value)
            store.remove(key)
        }
        for ((key, value) in local.getAll()) {
            if (key in localOnlyKeys) continue
            if (key !in backedUp) store.set(key, value)
            local.remove(key)
        }
        local.create()
    }

    private fun requireStore(): CloudStore =
        store ?: throw FlutterError("detached", "The plugin is not attached to an engine.", null)

    private fun requireLocal(): LocalStore =
        local ?: throw FlutterError("detached", "The plugin is not attached to an engine.", null)

    private object NoChanges : WatchChangesStreamHandler()

    private companion object {
        const val TAG = "CloudPreferences"
    }
}
