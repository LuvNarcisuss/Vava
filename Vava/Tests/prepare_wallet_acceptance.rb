require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'
require 'tmpdir'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
simulator, resolution = Open3.capture2('python3', File.join(__dir__, 'qa_simulator.py'))
abort 'Unable to resolve Vava QA.' unless resolution.success?
destination = Dir.mktmpdir('vava-wallet-swift-')
bundle = "com.vava.walletacceptance.swift#{SecureRandom.hex(4)}"
%w[App Assets Configuration PrivacyInfo.xcprivacy].each do |name|
  File.symlink(File.join(root, name), File.join(destination, name))
end
File.symlink(File.join(__dir__, 'qa_simulator.py'), File.join(destination, 'qa_simulator.py'))
FileUtils.cp_r(File.join(root, 'Vava.xcodeproj'), destination)
path = File.join(destination, 'Vava.xcodeproj')
project = Xcodeproj::Project.open(path)
app = project.targets.find { |target| target.name == 'Vava' }
info = Xcodeproj::Plist.read_from_path(File.join(root, 'App/Info.plist'))
info['CFBundleDisplayName'] = 'Vava Wallet Test'
Xcodeproj::Plist.write_to_path(info, File.join(destination, 'AcceptanceInfo.plist'))
Xcodeproj::Plist.write_to_path({ 'get-task-allow' => true }, File.join(destination, 'Acceptance.entitlements'))
app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle
  config.build_settings['ENABLE_TESTABILITY'] = 'YES'
  config.build_settings['INFOPLIST_FILE'] = 'AcceptanceInfo.plist'
  if config.name == 'Debug'
    config.build_settings['CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]'] = 'Acceptance.entitlements'
  end
end
tests = project.new_target(:unit_test_bundle, 'VavaWalletTests', :ios, '17.0')
tests.add_dependency(app)
tests.source_build_phase.add_file_reference(project.main_group.new_file(File.join(root, 'Tests/StoreKitTransactionRecorder.swift')))
source = project.main_group.new_file(File.join(root, 'Tests/WalletStoreKitTests.swift'))
tests.source_build_phase.add_file_reference(source)
fixture = project.main_group.new_file(File.join(root, 'Configuration/VavaCoins.storekit'))
tests.resources_build_phase.add_file_reference(fixture)
tests.build_configurations.each do |config|
  config.base_configuration_reference = app.build_configurations.find { |item| item.name == config.name }.base_configuration_reference
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{bundle}.tests",
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/Vava.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Vava',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'TARGETED_DEVICE_FAMILY' => '1',
    'SUPPORTS_MACCATALYST' => 'NO',
    'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
    'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'],
    'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)', '$(PLATFORM_DIR)/Developer/Library/Frameworks']
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.test_action.build_configuration = 'Debug'
scheme.test_action.should_use_launch_scheme_args_env = true
scheme.launch_action.build_configuration = 'Debug'
scheme.launch_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new([
  { key: 'VAVA_LOCAL_STOREKIT', value: '1', enabled: true }
])
scheme.save_as(path, 'VavaWalletAcceptance', true)
metadata = { 'directory' => destination, 'bundle' => bundle,
             'simulator' => simulator.strip }
File.write(File.join(destination, 'acceptance.json'), JSON.pretty_generate(metadata))
puts JSON.generate(metadata)
