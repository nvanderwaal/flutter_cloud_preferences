# flutter_cloud_preferences example

A dark-mode switch and a counter stored with `CloudPreferences`. Change them,
delete the app, and install it again: the values come back from iCloud or
Android Auto Backup.

The example has no iCloud entitlement, so on iOS and macOS values stay local
until you add the iCloud capability with your own team. See the
[package README](../README.md#ios-and-macos).
