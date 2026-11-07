#!/usr/bin/env ruby

# Reuse the imported certificate; never create or revoke a signing identity.
require "spaceship"
require "base64"
require "digest"
require "fileutils"
require "open3"

platform = ARGV.fetch(0, "ios")
abort "usage: ensure-ios-distribution-profile.rb [ios|tvos]" unless %w[ios tvos].include?(platform)
profile_type = platform == "tvos" ? "TVOS_APP_STORE" : "IOS_APP_STORE"

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  key: ENV.fetch("APP_STORE_CONNECT_API_PRIVATE_KEY"),
  in_house: false
)

identities, status = Open3.capture2("security", "find-identity", "-v", "-p", "codesigning")
abort "Cannot read imported signing identities." unless status.success?
fingerprints = identities.scan(/([A-Fa-f0-9]{40}) "(?:Apple|iPhone) Distribution:/).flatten.map(&:upcase)
certificates = Spaceship::ConnectAPI::Certificate.all(filter: { certificateType: "DISTRIBUTION,IOS_DISTRIBUTION" })
certificate = certificates.find do |item|
  item.valid? && fingerprints.include?(Digest::SHA1.hexdigest(Base64.decode64(item.certificate_content)).upcase)
end
abort "The imported distribution identity does not match an active Apple certificate." unless certificate

bundle = Spaceship::ConnectAPI::BundleId.find("com.aimessoft.nipaplay")
abort "NipaPlay bundle ID is missing from the Apple developer account." unless bundle

# Xcode-managed Team Store profiles cannot be used for a manual archive.
# Keep a reusable CI-owned profile bound to the existing certificate instead.
profile_name = platform == "tvos" ? "NipaPlay CI tvOS App Store #{certificate.id}" : "NipaPlay CI App Store #{certificate.id}"
profiles = Spaceship::ConnectAPI::Profile.all(
  filter: { profileType: profile_type }, includes: "bundleId,certificates"
)
profile = profiles.select do |item|
  item.name.start_with?(profile_name) && item.valid? &&
    item.bundle_id&.id == bundle.id && item.certificates.any? { |cert| cert.id == certificate.id }
end.max_by(&:expiration_date)

unless profile
  # Retain expired/invalid profiles; a replacement never revokes other builds.
  name = profiles.any? { |item| item.name == profile_name } ? "#{profile_name} #{Time.now.utc.strftime('%Y%m%d%H%M%S')}" : profile_name
  profile = Spaceship::ConnectAPI::Profile.create(
    name: name, profile_type: profile_type, bundle_id_id: bundle.id,
    certificate_ids: [certificate.id]
  )
end

directory = File.expand_path("~/Library/MobileDevice/Provisioning Profiles")
FileUtils.mkdir_p(directory)
path = File.join(directory, "#{profile.uuid}.mobileprovision")
File.binwrite(path, Base64.decode64(profile.profile_content))
File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |file| file.puts("profile-path=#{path}") }
puts "Installed the CI App Store profile for the existing distribution certificate."
