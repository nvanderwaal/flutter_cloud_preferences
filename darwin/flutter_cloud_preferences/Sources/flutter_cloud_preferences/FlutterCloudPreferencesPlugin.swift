#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Connects the Dart API to [CloudStore].
public class FlutterCloudPreferencesPlugin: NSObject, FlutterPlugin, CloudPreferencesHostApi {
  private let store = CloudStore()
  private let changes = ChangesStreamHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let plugin = FlutterCloudPreferencesPlugin()
    plugin.store.onChange = { [weak plugin] change in plugin?.changes.send(change) }
    CloudPreferencesHostApiSetup.setUp(binaryMessenger: messenger, api: plugin)
    WatchChangesStreamHandler.register(with: messenger, streamHandler: plugin.changes)
  }

  func initialize(liveSync: Bool, localOnlyKeys: [String]) throws -> [String: Any] {
    return ValueCoding.toDart(store.open(liveSync: liveSync, localOnlyKeys: Set(localOnlyKeys)))
  }

  func setValue(key: String, value: Any) throws {
    guard let stored = ValueCoding.fromDart(value) else {
      throw PigeonError(
        code: "unsupported-type", message: "Unsupported value type for \(key).", details: nil)
    }
    store.set(stored, forKey: key)
  }

  func remove(key: String) throws {
    store.remove(key)
  }

  func clear() throws {
    store.clear()
  }
}

/// Delivers store changes to Dart, keeping those sent before Dart listens.
private final class ChangesStreamHandler: WatchChangesStreamHandler {
  private var sink: PigeonEventSink<StoreChange>?
  private var pending: [StoreChange] = []

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<StoreChange>) {
    self.sink = sink
    pending.forEach(sink.success)
    pending.removeAll()
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func send(_ change: StoreChange) {
    var change = change
    change.values = ValueCoding.toDart(change.values)
    if let sink = sink {
      sink.success(change)
    } else {
      pending.append(change)
    }
  }
}

/// Converts between platform channel values and property list values.
///
/// The only difference is bytes: `FlutterStandardTypedData` on the channel,
/// `Data` in storage.
enum ValueCoding {
  static func fromDart(_ value: Any) -> Any? {
    switch value {
    case let bytes as FlutterStandardTypedData: return bytes.data
    case let list as [Any]: return list.allSatisfy { $0 is String } ? list : nil
    case is String, is NSNumber: return value
    default: return nil
    }
  }

  static func toDart(_ values: [String: Any]) -> [String: Any] {
    return values.mapValues { value in
      if let data = value as? Data {
        return FlutterStandardTypedData(bytes: data)
      }
      return value
    }
  }
}
