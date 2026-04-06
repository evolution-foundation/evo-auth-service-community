module Mail
  class ResendProvider
    class DeliveryError < StandardError; end

    def initialize(_settings); end

    def deliver!(mail)
      api_key = GlobalConfigService.load('RESEND_API_SECRET', nil) ||
                GlobalConfigService.load('RESEND_API_KEY', nil)

      raise DeliveryError, "Resend API key not configured" if api_key.blank?

      Resend.api_key = api_key

      Resend::Emails.send(
        from: mail.header[:from].to_s,
        to: mail.header[:to].to_s,
        subject: mail.header[:subject].to_s,
        html: mail.decoded,
        text: sanitize_html(mail.decoded)
      )
    rescue Resend::Error => e
      raise DeliveryError, "Failed to send email: #{e.message}"
    rescue StandardError => e
      raise DeliveryError, "An error occurred while sending email: #{e.message}"
    end

    private

    def sanitize_html(html)
      sanitized = ActionView::Base.full_sanitizer.sanitize(html)
      # NOTE: Remove more than two consecutive newlines
      sanitized.lines.map(&:strip).join("\n").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
