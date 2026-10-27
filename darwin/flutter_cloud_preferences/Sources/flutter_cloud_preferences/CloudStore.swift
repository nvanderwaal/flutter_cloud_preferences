import Foundation

/// The local store, mirrored to iCloud key-value storage.
///
/// UserDefaults holds the values and is the source of truth. Every write is
/// copied to `NSUbiquitousKeyValueStore`. iCloud values are only read back on a
/// fresh install (when the local store has never been opened), and then only
/// fill keys the app has not written or removed since. With live sync on, every
/// external change is applied instead.
///
/// Local-only keys live in a [LocalStore] that is never mirrored to iCloud or
/// included in device backups.
///
/// Values are stored as property list types: String, NSNumber (bool, int and
/// double keep their type), [String] and Data.
final class CloudStore {
  static let valuesKey = "flutter_cloud_preferences.values"
  static let openedKey = "flutter_cloud_preferences.opened"
  static let restorePendingKey = "flutter_cloud_preferences.restorePending"
  static let touchedKeysKey = "flutter_cloud_preferences.touchedKeys"

  private let defaults: UserDefaults
  private let cloud: NSUbiquitousKeyValueStore
  private let notificationCenter: NotificationCenter
  private let local: LocalStore
  private var values: [String: Any] = [:]
  private var localOnlyKeys: Set<String> = []
  private var liveSync = false
  // On a fresh install iCloud may deliver its data after start-up, or after
  // the app was closed. Until it arrives, the restore stays pending, also
  // across launches, and the keys the app writes or removes are remembered:
  // the restore skips them, and they are written to iCloud again once it
  // arrives, because iCloud discards writes made before its first download.
  private var restorePending = false
  private var touchedKeys: Set<String> = []
  private var observer: NSObjectProtocol?

  /// Called on the main thread with changes made outside the app.
  var onChange: ((StoreChange) -> Void)?

  init(
    defaults: UserDefaults = .standard,
    cloud: NSUbiquitousKeyValueStore = .default,
    notificationCenter: NotificationCenter = .default,
    local: LocalStore = LocalStore()
  ) {
    self.defaults = defaults
    self.cloud = cloud
    self.notificationCenter = notificationCenter
    self.local = local
  }

  deinit {
    if let observer = observer {
      notificationCenter.removeObserver(observer)
    }
  }

  /// Opens the store and returns all values. Calling it again only returns
  /// the values.
  func open(liveSync: Bool, localOnlyKeys: Set<String>) -> [String: Any] {
    if observer == nil {
      self.liveSync = liveSync
      self.localOnlyKeys = localOnlyKeys
      values = defaults.dictionary(forKey: CloudStore.valuesKey) ?? [:]
      let isFreshInstall = !defaults.bool(forKey: CloudStore.openedKey)
      defaults.set(true, forKey: CloudStore.openedKey)
      if isFreshInstall {
        defaults.set(true, forKey: CloudStore.restorePendingKey)
      }
      restorePending = defaults.bool(forKey: CloudStore.restorePendingKey)
      touchedKeys = Set(defaults.stringArray(forKey: CloudStore.touchedKeysKey) ?? [])

      moveLocalOnlyValues()

      observer = notificationCenter.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: cloud,
        queue: .main
      ) { [weak self] notification in
        self?.cloudDidChange(notification)
      }
      cloud.synchronize()

      if restorePending {
        // Whatever iCloud already has locally is restored before returning.
        // Anything that arrives later is reported as a restore event.
        let restored = fillMissing(from: cloud.dictionaryRepresentation)
        if !isFreshInstall && !restored.isEmpty {
          // iCloud downloaded its data while the app was closed.
          finishRestore()
        }
      }
      removeLocalOnlyKeysFromCloud()
    }
    return values.merging(local.values) { synced, _ in synced }
  }

  func set(_ value: Any, forKey key: String) {
    if localOnlyKeys.contains(key) {
      local.set(value, forKey: key)
      return
    }
    values[key] = value
    touch([key])
    save()
    cloud.set(value, forKey: key)
  }

  func remove(_ key: String) {
    if localOnlyKeys.contains(key) {
      local.remove(key)
      return
    }
    values.removeValue(forKey: key)
    touch([key])
    save()
    cloud.removeObject(forKey: key)
  }

  func clear() {
    // Only keys this store wrote; other iCloud keys of the app are left alone.
    let keys = Array(values.keys)
    for key in keys {
      cloud.removeObject(forKey: key)
    }
    values.removeAll()
    touch(keys)
    save()
    local.clear()
  }

  private func save() {
    defaults.set(values, forKey: CloudStore.valuesKey)
  }

  private func touch(_ keys: [String]) {
    guard restorePending else { return }
    touchedKeys.formUnion(keys)
    defaults.set(Array(touchedKeys), forKey: CloudStore.touchedKeysKey)
  }

  /// Moves values to the store their key belongs in, after the app changed
  /// which keys are local-only.
  private func moveLocalOnlyValues() {
    // A local store that already exists was created on this device, so a
    // synced value of a newly local-only key was written here and is kept.
    // Otherwise the value may have come from a backup of another device, and
    // is dropped.
    let keepSynced = local.exists
    var changed = false
    for key in localOnlyKeys where values[key] != nil {
      if keepSynced && local.values[key] == nil {
        local.set(values[key]!, forKey: key)
      }
      values.removeValue(forKey: key)
      changed = true
    }
    for (key, value) in local.values where !localOnlyKeys.contains(key) {
      if values[key] == nil {
        values[key] = value
        cloud.set(value, forKey: key)
      }
      local.remove(key)
      changed = true
    }
    if changed {
      save()
    }
    local.create()
  }

  /// Removes local-only keys from iCloud, in case an earlier version of the
  /// app synced them.
  private func removeLocalOnlyKeysFromCloud() {
    for key in localOnlyKeys where cloud.object(forKey: key) != nil {
      cloud.removeObject(forKey: key)
    }
  }

  /// Adds the values of keys the local store does not have and the app has
  /// not touched since installing, and returns the keys that were added.
  @discardableResult
  private func fillMissing(from cloudValues: [String: Any]) -> [String] {
    var added: [String] = []
    for (key, value) in cloudValues
    where values[key] == nil && !touchedKeys.contains(key) && !localOnlyKeys.contains(key)
      && CloudStore.isSupported(value)
    {
      values[key] = value
      added.append(key)
    }
    if !added.isEmpty {
      save()
    }
    return added
  }

  /// Ends the pending restore and writes the keys the app touched while it
  /// was pending to iCloud again.
  private func finishRestore() {
    restorePending = false
    defaults.removeObject(forKey: CloudStore.restorePendingKey)
    for key in touchedKeys {
      if let value = values[key] {
        cloud.set(value, forKey: key)
      } else {
        cloud.removeObject(forKey: key)
      }
    }
    touchedKeys.removeAll()
    defaults.removeObject(forKey: CloudStore.touchedKeysKey)
    removeLocalOnlyKeysFromCloud()
  }

  private func cloudDidChange(_ notification: Notification) {
    let userInfo = notification.userInfo ?? [:]
    let rawReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

    if liveSync {
      // Keys the app touched before the first download keep their local value.
      let keys = changedKeys.filter { !localOnlyKeys.contains($0) && !touchedKeys.contains($0) }
      if restorePending {
        finishRestore()
      }
      applyLiveChange(reason: rawReason, keys: keys)
    } else if restorePending {
      let added = fillMissing(from: cloud.dictionaryRepresentation)
      finishRestore()
      if !added.isEmpty {
        onChange?(
          StoreChange(
            reason: .restored, keys: added,
            values: values.filter { added.contains($0.key) }))
      }
    }
  }

  private func applyLiveChange(reason rawReason: Int?, keys: [String]) {
    guard !keys.isEmpty else { return }
    let reason: StoreChangeReason
    switch rawReason ?? NSUbiquitousKeyValueStoreServerChange {
    case NSUbiquitousKeyValueStoreInitialSyncChange: reason = .initialSync
    case NSUbiquitousKeyValueStoreQuotaViolationChange: reason = .quotaViolation
    case NSUbiquitousKeyValueStoreAccountChange: reason = .accountChange
    default: reason = .serverChange
    }
    var changed: [String: Any] = [:]
    for key in keys {
      if let value = cloud.object(forKey: key), CloudStore.isSupported(value) {
        values[key] = value
        changed[key] = value
      } else {
        values.removeValue(forKey: key)
      }
    }
    save()
    onChange?(StoreChange(reason: reason, keys: keys, values: changed))
  }

  /// Whether [value] is one of the types the Dart side reads.
  static func isSupported(_ value: Any) -> Bool {
    switch value {
    case is String, is NSNumber, is Data: return true
    case let list as [Any]: return list.allSatisfy { $0 is String }
    default: return false
    }
  }
}

/// Values that stay on this device: a property list in Application Support,
/// in a folder excluded from device backups and never mirrored to iCloud.
final class LocalStore {
  private let directory: URL
  private let file: URL
  private(set) var values: [String: Any] = [:]

  init(directory: URL = LocalStore.defaultDirectory) {
    self.directory = directory
    file = directory.appendingPathComponent("local_only.plist")
    if let data = try? Data(contentsOf: file),
      let stored = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    {
      values = stored
    }
  }

  static var defaultDirectory: URL {
    var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    #if os(macOS)
      // Application Support is shared by every app outside the sandbox.
      url.appendPathComponent(Bundle.main.bundleIdentifier ?? "flutter_cloud_preferences")
    #endif
    url.appendPathComponent("flutter_cloud_preferences", isDirectory: true)
    return url
  }

  /// Whether the store was created on this device before.
  var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

  /// Creates the store's file if it does not exist yet.
  func create() {
    if !exists {
      save()
    }
  }

  func set(_ value: Any, forKey key: String) {
    values[key] = value
    save()
  }

  func remove(_ key: String) {
    if values.removeValue(forKey: key) != nil {
      save()
    }
  }

  func clear() {
    values.removeAll()
    save()
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      // Excluding the folder covers the file, which is replaced on every save.
      var excluded = URLResourceValues()
      excluded.isExcludedFromBackup = true
      var folder = directory
      try folder.setResourceValues(excluded)
      let data = try PropertyListSerialization.data(
        fromPropertyList: values, format: .binary, options: 0)
      try data.write(to: file, options: .atomic)
    } catch {
      NSLog("CloudPreferences: could not save local-only values: \(error)")
    }
  }
}
