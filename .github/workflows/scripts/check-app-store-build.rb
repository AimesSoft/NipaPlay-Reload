#!/usr/bin/env ruby

require "fastlane_core/build_watcher"
require "spaceship"

api_key_path, bundle_id, app_version, build_number = ARGV

if [api_key_path, bundle_id, app_version, build_number].any? { |value| value.nil? || value.empty? }
  warn "usage: check-app-store-build.rb API_KEY_JSON BUNDLE_ID APP_VERSION BUILD_NUMBER"
  exit 2
end

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from(filepath: api_key_path)
app = Spaceship::ConnectAPI::App.find(bundle_id)

unless app
  warn "App Store Connect app not found for bundle ID #{bundle_id}"
  exit 2
end

platform = Spaceship::ConnectAPI::Platform::IOS
builds = Spaceship::ConnectAPI::Build.all(
  app_id: app.id,
  version: app_version,
  build_number: build_number,
  platform: platform
)

if builds.empty?
  puts "Build #{app_version} (#{build_number}) is not uploaded yet."
  exit 10
end

puts "Build #{app_version} (#{build_number}) already exists; waiting for processing to finish."
build = FastlaneCore::BuildWatcher.wait_for_build_processing_to_be_complete(
  app_id: app.id,
  platform: platform,
  app_version: app_version,
  build_version: build_number,
  poll_interval: 15,
  timeout_duration: 3600,
  return_spaceship_testflight_build: false
)

unless build.processing_state == Spaceship::ConnectAPI::Build::ProcessingState::VALID
  warn "Build processing finished with state #{build.processing_state}, not VALID."
  exit 2
end

puts "Build #{app_version} (#{build_number}) is valid and can be reused."
