require 'json'
require 'open3'
require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
output, status = Open3.capture2(RbConfig.ruby, File.join(__dir__, 'prepare_wallet_acceptance.rb'))
abort 'Unable to prepare isolated harness.' unless status.success?
metadata = JSON.parse(output)
destination = metadata.fetch('directory')
FileUtils.rm(File.join(destination, 'App'))
FileUtils.cp_r(File.join(root, 'App'), destination)
entry = File.join(destination, 'App/Core/VavaApplication.swift')
source = File.read(entry)
abort 'Unexpected application entry point.' unless source.include?('@main @MainActor final class VavaApplication')
File.write(entry, source.sub('@main @MainActor final class VavaApplication', '@MainActor final class VavaApplication'))
project_path = File.join(destination, 'Vava.xcodeproj')
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == 'Vava' }
app.source_build_phase.add_file_reference(project.main_group.new_file(File.join(root, 'Tests/SafetyTestHost.swift')))
ui = project.new_target(:ui_test_bundle, 'VavaSafetyUITests', :ios, '17.0')
ui.add_dependency(app)
ui.source_build_phase.add_file_reference(project.main_group.new_file(File.join(root, 'Tests/SafetyUITests.swift')))
ui.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => metadata.fetch('bundle') + '.safetyui',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0',
    'TEST_TARGET_NAME' => 'Vava', 'TARGETED_DEVICE_FAMILY' => '1',
    'SUPPORTS_MACCATALYST' => 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
    'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD' => 'NO'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(ui)
scheme.set_launch_target(app)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project_path, 'VavaSafetyAcceptance', true)
puts JSON.generate(metadata)
