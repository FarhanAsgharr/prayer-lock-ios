#!/usr/bin/env ruby
# frozen_string_literal: true

# Configures Runner.xcodeproj for the Screen Time app-blocking feature.
#
# This does programmatically what a developer would otherwise do by clicking
# through Xcode: it adds the three app-extension targets, sets their build
# settings, wires their entitlements and capabilities, embeds them in the app,
# and attaches the blocking Swift sources and the app's own entitlement to the
# Runner target.
#
# It is idempotent — running it twice does not create duplicate targets — so it
# is safe to re-run after `flutter clean` or a fresh checkout regenerates the
# base project. The iOS deployment README instructs the developer to run it
# once after `pod install`.
#
# Requires only the `xcodeproj` Ruby gem (pure Ruby, no Xcode needed):
#   gem install xcodeproj
#   ruby configure_project.rb

require 'xcodeproj'

PROJECT_PATH = 'Runner.xcodeproj'
APP_TARGET = 'Runner'
APP_BUNDLE_ID = 'com.prayerlock.prayerLock'
APP_GROUP = 'group.com.prayerlock.shared'

# Each extension: on-disk folder, target name, the single Swift source, and the
# bundle-id suffix Apple requires (extension ids must be prefixed by the app's).
EXTENSIONS = [
  {
    name: 'DeviceActivityMonitor',
    source: 'DeviceActivityMonitorExtension.swift',
    frameworks: %w[DeviceActivity ManagedSettings FamilyControls]
  },
  {
    name: 'ShieldConfiguration',
    source: 'ShieldConfigurationExtension.swift',
    frameworks: %w[ManagedSettings ManagedSettingsUI]
  },
  {
    name: 'ShieldAction',
    source: 'ShieldActionExtension.swift',
    frameworks: %w[ManagedSettings ManagedSettingsUI]
  }
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
app_target = project.targets.find { |t| t.name == APP_TARGET }
raise "#{APP_TARGET} target not found" unless app_target

# ---------------------------------------------------------------------------
# 1. Runner target: attach its entitlements and the blocking sources.
# ---------------------------------------------------------------------------

app_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  # Family Controls types are iOS 16+, gated with @available in the code, so the
  # app itself can keep supporting iOS 13.
end

# Add the two blocking Swift files to Runner's compile sources, if not already
# present. Flutter's generated project does not know about files we added.
blocking_group = project.main_group.find_subpath('Runner/Blocking', true)
blocking_group.set_source_tree('SOURCE_ROOT')

['Runner/Blocking/BlockingManager.swift', 'Runner/Blocking/BlockingChannel.swift'].each do |path|
  already = app_target.source_build_phase.files_references.any? { |r| r.real_path.to_s.end_with?(path) }
  next if already

  file_ref = blocking_group.find_file_by_path(File.basename(path)) ||
             blocking_group.new_reference(File.basename(path))
  app_target.add_file_references([file_ref])
  puts "Added #{path} to #{APP_TARGET}"
end

# ---------------------------------------------------------------------------
# 2. Create each extension target.
# ---------------------------------------------------------------------------

created_targets = []

EXTENSIONS.each do |ext|
  name = ext[:name]

  existing = project.targets.find { |t| t.name == name }
  if existing
    puts "Extension target #{name} already exists — updating settings"
    target = existing
  else
    # app_extension product type; deployment target 16.0 (Screen Time minimum).
    target = project.new_target(
      :app_extension,
      name,
      :ios,
      '16.0',
      project.products_group,
      :swift
    )
    puts "Created extension target #{name}"
  end

  # Filesystem group for the extension's files.
  group = project.main_group.find_subpath(name, true)
  group.set_source_tree('SOURCE_ROOT')

  # Attach the Swift source.
  source_path = "#{name}/#{ext[:source]}"
  unless target.source_build_phase.files_references.any? { |r| r.real_path.to_s.end_with?(ext[:source]) }
    ref = group.find_file_by_path(ext[:source]) || group.new_reference(ext[:source])
    target.add_file_references([ref])
    puts "  attached #{source_path}"
  end

  # Link the Screen Time system frameworks the extension imports. Swift would
  # implicitly link most of these, but declaring them explicitly avoids the
  # occasional "no such module" at link time in extension targets.
  ext[:frameworks].each do |framework|
    begin
      target.add_system_framework(framework)
    rescue StandardError => e
      warn "  could not add framework #{framework}: #{e.message}"
    end
  end

  # Build settings.
  target.build_configurations.each do |config|
    bs = config.build_settings
    bs['PRODUCT_BUNDLE_IDENTIFIER'] = "#{APP_BUNDLE_ID}.#{name}"
    bs['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    bs['SWIFT_VERSION'] = '5.0'
    bs['INFOPLIST_FILE'] = "#{name}/Info.plist"
    bs['CODE_SIGN_ENTITLEMENTS'] = "#{name}/#{name}.entitlements"
    bs['CODE_SIGN_STYLE'] = 'Automatic'
    bs['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
    bs['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    bs['GENERATE_INFOPLIST_FILE'] = 'NO'
    bs['SKIP_INSTALL'] = 'YES'
    bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
    bs['TARGETED_DEVICE_FAMILY'] = '1,2'
    # Extensions cannot contain a main() — this is required for app extensions.
    bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    bs['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  end

  created_targets << target
end

# ---------------------------------------------------------------------------
# 3. Embed the extensions in the app and add build dependencies.
# ---------------------------------------------------------------------------

# The "Embed App Extensions" copy-files phase places each .appex into the app's
# PlugIns directory. Without it the extensions build but are never bundled, and
# the Screen Time features silently do nothing.
embed_phase = app_target.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :plug_ins
end

unless embed_phase
  embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end

created_targets.each do |target|
  # Build dependency so the extension is built before the app is assembled.
  app_target.add_dependency(target)

  product_ref = target.product_reference
  already_embedded = embed_phase.files_references.include?(product_ref)
  next if already_embedded

  build_file = embed_phase.add_file_reference(product_ref)
  # RemoveHeadersOnCopy + code-sign on copy is the standard extension embed.
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "Embedded #{target.name} in #{APP_TARGET}"
end

# ---------------------------------------------------------------------------
# 4. Save.
# ---------------------------------------------------------------------------

project.save
puts "\nSaved #{PROJECT_PATH}."
puts "Targets now: #{project.targets.map(&:name).join(', ')}"
