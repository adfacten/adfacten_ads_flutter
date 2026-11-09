# CocoaPods integration, used when the app has Swift Package Manager turned off.
#
# AdfactenAds is not on the CocoaPods trunk, and a podspec cannot depend on a git pod. So this
# podspec downloads the prebuilt XCFramework from the Adfacten CDN (checksum verified) into
# ios/Frameworks the first time `pod install` evaluates it, and vendors it.
require 'digest'
require 'fileutils'

adfacten_sdk_version = '1.0.2'
adfacten_sdk_sha256 = 'a7ce159e07b4146aa2925d9c7be76dfcda2dc4a80bd9ec4ffcef24531bc9ce7d'
adfacten_sdk_url = "https://cdn.adfacten.com/ios/AdfactenAds-#{adfacten_sdk_version}.xcframework.zip"

frameworks_dir = File.join(File.dirname(File.expand_path(__FILE__)), 'Frameworks')
xcframework = File.join(frameworks_dir, 'AdfactenAds.xcframework')
stamp = File.join(frameworks_dir, '.version')

unless File.exist?(File.join(xcframework, 'Info.plist')) && File.exist?(stamp) &&
       File.read(stamp).strip == adfacten_sdk_version
  FileUtils.rm_rf(frameworks_dir)
  FileUtils.mkdir_p(frameworks_dir)
  zip = File.join(frameworks_dir, 'AdfactenAds.xcframework.zip')
  unless system('curl', '-fsSL', '--retry', '3', '-o', zip, adfacten_sdk_url)
    raise "adfacten_ads: could not download #{adfacten_sdk_url}"
  end
  actual = Digest::SHA256.file(zip).hexdigest
  unless actual == adfacten_sdk_sha256
    FileUtils.rm_rf(frameworks_dir)
    raise "adfacten_ads: checksum mismatch for #{adfacten_sdk_url} (got #{actual})"
  end
  raise 'adfacten_ads: could not unzip the XCFramework' unless system('unzip', '-q', '-o', zip, '-d', frameworks_dir)
  FileUtils.rm_f(zip)
  File.write(stamp, adfacten_sdk_version)
end

Pod::Spec.new do |s|
  s.name             = 'adfacten_ads'
  s.version          = '1.0.1'
  s.summary          = 'Adfacten Ads for Flutter: banner, interstitial, rewarded, native and app-open ads.'
  s.homepage         = 'https://developers.adfacten.com/mobile-sdk-en'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Adfacten' => 'destek@adfacten.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'adfacten_ads/Sources/adfacten_ads/**/*.swift'
  s.vendored_frameworks = 'Frameworks/AdfactenAds.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.frameworks = 'UIKit', 'WebKit', 'AVFoundation', 'StoreKit', 'AdSupport', 'AppTrackingTransparency', 'Network', 'SwiftUI'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
