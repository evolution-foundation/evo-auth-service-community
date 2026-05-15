# frozen_string_literal: true

module Avatarable
  extend ActiveSupport::Concern
  include Rails.application.routes.url_helpers

  included do
    has_one_attached :avatar
    validate :acceptable_avatar, if: -> { avatar.changed? }
    after_save :fetch_avatar_from_gravatar
  end

  # Signed URL TTL for cloud storage avatars. Short-lived to limit exposure if the
  # URL leaks via logs, screenshots or cached API responses — frontend should
  # re-fetch the user payload to refresh the URL when it expires.
  AVATAR_URL_TTL = 1.hour

  def avatar_url
    return nil unless avatar.attached?

    if avatar.service.class.name == 'ActiveStorage::Service::DiskService'
      base_url = Rails.application.config.app_url.to_s.chomp('/')
      path = Rails.application.routes.url_helpers.rails_service_blob_proxy_path(avatar.signed_id, avatar.filename)
      "#{base_url}#{path}"
    else
      avatar.blob.url(expires_in: AVATAR_URL_TTL)
    end
  rescue StandardError => e
    Rails.logger.error("[Avatarable] Avatar URL generation failed for #{self.class.name}##{id}: #{e.class} - #{e.message}")
    nil
  end

  def fetch_avatar_from_gravatar
    return unless saved_changes.key?(:email)
    return if email.blank?

    # Incase avatar_url is supplied, we don't want to fetch avatar from gravatar
    # So we will wait for it to be processed
    # Avatar::AvatarFromGravatarJob.set(wait: 30.seconds).perform_later(self, email)
    # TODO: Implement avatar job when needed
    Rails.logger.info "Avatar fetch from Gravatar skipped for #{email}"
  end

  def acceptable_avatar
    return unless avatar.attached?

    errors.add(:avatar, 'is too big') if avatar.byte_size > 15.megabytes

    acceptable_types = ['image/jpeg', 'image/png', 'image/gif'].freeze
    errors.add(:avatar, 'filetype not supported') unless acceptable_types.include?(avatar.content_type)
  end
end
