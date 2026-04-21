#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'SprayWall.xcodeproj')

if File.exist?(PROJECT_PATH)
  FileUtils.rm_rf(PROJECT_PATH)
end

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2640'
project.root_object.attributes['LastUpgradeCheck'] = '2640'

ios_app_target = project.new_target(:application, 'SprayWall', :ios, '17.0')
mac_app_target = project.new_target(:application, 'SprayWall-macOS', :osx, '14.0')
test_target = project.new_target(:unit_test_bundle, 'SprayWallTests', :ios, '17.0')
test_target.add_dependency(ios_app_target)

def configure_target(target, bundle_id:, product_name:, platform:, deployment_target:)
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
    config.build_settings['PRODUCT_NAME'] = product_name
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'

    if platform == :ios
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
      config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    elsif platform == :osx
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = deployment_target
    end

    if target.symbol_type == :application && platform == :ios
      config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
      config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
      config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
      config.build_settings['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
      config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
      config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
      config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
    elsif target.symbol_type == :application && platform == :osx
      config.build_settings['SUPPORTED_PLATFORMS'] = 'macosx'
    else
      config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
      config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
      config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/SprayWall.app/SprayWall'
      config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'
    end
  end
end

configure_target(
  ios_app_target,
  bundle_id: 'com.spraywall.app',
  product_name: 'SprayWall',
  platform: :ios,
  deployment_target: '17.0'
)
configure_target(
  mac_app_target,
  bundle_id: 'com.spraywall.app.macos',
  product_name: 'SprayWall-macOS',
  platform: :osx,
  deployment_target: '14.0'
)
configure_target(
  test_target,
  bundle_id: 'com.spraywall.app.tests',
  product_name: 'SprayWallTests',
  platform: :ios,
  deployment_target: '17.0'
)

main_group = project.main_group
sources_group = main_group.find_subpath('Sources', true)
sources_group.set_source_tree('<group>')

tests_group = main_group.find_subpath('Tests', true)
tests_group.set_source_tree('<group>')

main_source_files = Dir.glob(File.join(ROOT, 'Sources/SprayWall/**/*.swift')).sort
main_source_files.each do |path|
  rel = path.sub("#{ROOT}/", '')
  ref = main_group.files.find { |item| item.path == rel } || main_group.new_file(rel)
  ios_app_target.add_file_references([ref])
  mac_app_target.add_file_references([ref])
end

test_source_files = Dir.glob(File.join(ROOT, 'Tests/SprayWallTests/**/*.swift')).sort
test_source_files.each do |path|
  rel = path.sub("#{ROOT}/", '')
  ref = main_group.new_file(rel)
  test_target.add_file_references([ref])
end

[
  ios_app_target,
  mac_app_target
].each do |target|
  target.build_phases.each do |phase|
    next unless phase.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
    phase.files.each do |file|
      phase.remove_build_file(file)
    end
  end
end

resources_root = File.join(ROOT, 'Resources')
if Dir.exist?(resources_root)
  Dir.glob(File.join(resources_root, '**/*')).sort.each do |path|
    next if File.directory?(path)

    rel = path.sub("#{ROOT}/", '')
    ref = main_group.files.find { |item| item.path == rel } || main_group.new_file(rel)
    ios_app_target.add_resources([ref])
    mac_app_target.add_resources([ref])
  end
end

project.recreate_user_schemes
project.save
puts "Generated #{PROJECT_PATH}"
