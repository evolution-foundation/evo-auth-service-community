require 'net/http'
require 'json'

module Mail
  class BmsProvider
    class DeliveryError < StandardError; end

    def initialize(_settings); end

    def deliver!(mail)
      bms_api_key = GlobalConfigService.load('BMS_API_KEY', nil)

      if bms_api_key.blank?
        Rails.logger.info "📧 BMS PROVIDER: No BMS_API_KEY found, falling back to SMTP"
        return deliver_via_smtp!(mail)
      end

      Rails.logger.info "🚀 BMS PROVIDER: Starting email delivery via BMS"

      from_email = extract_email_from_header(mail.header[:from].to_s)
      from_name = extract_name_from_header(mail.header[:from].to_s)
      to_email = extract_email_from_header(mail.header[:to].to_s)
      to_name = extract_name_from_header(mail.header[:to].to_s) || to_email.split('@')[0]

      Rails.logger.info "🚀 BMS PROVIDER: From: #{from_name} <#{from_email}>, To: #{to_name} <#{to_email}>"

      message_id = generate_message_id
      bms_ippool = GlobalConfigService.load('BMS_IPPOOL', 'default')

      payload = {
        contact: {
          email: to_email,
          firstName: to_name
        },
        message: {
          id: message_id,
          title: mail.header[:subject].to_s,
          from: {
            email: from_email,
            firstName: from_name || from_email.split('@')[0]
          },
          ippool: bms_ippool,
          subject: mail.header[:subject].to_s,
          content: mail.decoded
        }
      }

      response = send_via_bms_api(payload, bms_api_key)
      Rails.logger.info "✅ BMS PROVIDER: Email sent successfully!"

      response
    rescue StandardError => e
      Rails.logger.error "❌ BMS PROVIDER: Failed: #{e.message}, falling back to SMTP"
      deliver_via_smtp!(mail)
    end

    private

    def deliver_via_smtp!(mail)
      smtp_settings = ActionMailer::Base.smtp_settings
      smtp = Mail::SMTP.new(smtp_settings)
      smtp.deliver!(mail)
    end

    def send_via_bms_api(payload, bms_api_key)
      uri = URI('https://bms-api.bri.us/services/send-email')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request['api-key'] = bms_api_key
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json

      start_time = Time.current
      response = http.request(request)
      duration = ((Time.current - start_time) * 1000).round(2)

      Rails.logger.info "🌐 BMS API: #{response.code} in #{duration}ms"

      unless response.is_a?(Net::HTTPSuccess)
        raise DeliveryError, "BMS API error: #{response.code} - #{response.body}"
      end

      JSON.parse(response.body)
    end

    def extract_email_from_header(header_value)
      match = header_value.match(/<(.+)>/) || header_value.match(/(\S+@\S+)/)
      match ? match[1] : header_value.strip
    end

    def extract_name_from_header(header_value)
      match = header_value.match(/^([^<]+)</)
      match ? match[1].strip : nil
    end

    def generate_message_id
      timestamp = Time.now.to_i
      random_suffix = rand(10000..99999)
      (timestamp.to_s + random_suffix.to_s).to_i
    end
  end
end
