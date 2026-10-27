#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_cloud_preferences.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_cloud_preferences'
  s.version          = '0.1.0'
  s.summary          = 'Preferences backed up to iCloud key-value storage.'
  s.description      = <<-DESC
Key-value preferences that survive reinstalls and new devices, backed up to iCloud key-value storage.
                       DESC
  s.homepage         = 'https://github.com/nvanderwaal/flutter_cloud_preferences'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nick van der Waal' => 'https://github.com/nvanderwaal' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_cloud_preferences/Sources/flutter_cloud_preferences/**/*.swift'
  s.resource_bundles = {'flutter_cloud_preferences_privacy' => ['flutter_cloud_preferences/Sources/flutter_cloud_preferences/PrivacyInfo.xcprivacy']}

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
