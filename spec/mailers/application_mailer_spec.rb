# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationMailer do
  let(:user) { double('User', email: 'test@example.com', name: 'Test User') }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    Rails.cache.clear
  end

  describe 'dynamic mail settings loading' do
    context 'when MAILER_TYPE is smtp and SMTP_ADDRESS is configured' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('smtp')
        allow(GlobalConfigService).to receive(:load).with('SMTP_ADDRESS', anything).and_return('smtp.example.com')
        allow(GlobalConfigService).to receive(:load).with('SMTP_PORT', anything).and_return('587')
        allow(GlobalConfigService).to receive(:load).with('SMTP_USERNAME', anything).and_return('user@example.com')
        allow(GlobalConfigService).to receive(:load).with('SMTP_PASSWORD_SECRET', anything).and_return('secret')
        allow(GlobalConfigService).to receive(:load).with('SMTP_ENABLE_STARTTLS_AUTO', anything).and_return('true')
        allow(GlobalConfigService).to receive(:load).with('SMTP_AUTHENTICATION', anything).and_return('login')
        allow(GlobalConfigService).to receive(:load).with('SMTP_DOMAIN', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('SMTP_OPENSSL_VERIFY_MODE', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'sets delivery method to smtp on the message' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method).to be_a(Mail::SMTP)
      end

      it 'configures smtp address from DB' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method.settings[:address]).to eq('smtp.example.com')
      end

      it 'configures smtp port from DB' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method.settings[:port]).to eq(587)
      end

      it 'configures smtp credentials from DB' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method.settings[:user_name]).to eq('user@example.com')
        expect(mail.delivery_method.settings[:password]).to eq('secret')
      end
    end

    context 'when SMTP_AUTHENTICATION is set but the username is absent (EVO-2146)' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('smtp')
        allow(GlobalConfigService).to receive(:load).with('SMTP_ADDRESS', anything).and_return('mailpit')
        allow(GlobalConfigService).to receive(:load).with('SMTP_PORT', anything).and_return('587')
        allow(GlobalConfigService).to receive(:load).with('SMTP_USERNAME', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('SMTP_PASSWORD_SECRET', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('SMTP_ENABLE_STARTTLS_AUTO', anything).and_return('false')
        # the installation_configs seed ships 'login' by default — the real-world scenario
        allow(GlobalConfigService).to receive(:load).with('SMTP_AUTHENTICATION', anything).and_return('login')
        allow(GlobalConfigService).to receive(:load).with('SMTP_DOMAIN', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('SMTP_OPENSSL_VERIFY_MODE', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'does NOT request SMTP-AUTH (the mail gem would raise client-side and no email would ever leave)' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method.settings[:authentication]).to be_nil
        expect(mail.delivery_method.settings[:address]).to eq('mailpit')
      end

      it 'also strips an :authentication INHERITED from the static boot settings' do
        original = ApplicationMailer.smtp_settings
        ApplicationMailer.smtp_settings = (original || {}).merge(authentication: :login)

        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method.settings[:authentication]).to be_nil
      ensure
        ApplicationMailer.smtp_settings = original
      end
    end

    context 'when MAILER_TYPE is smtp but SMTP_ADDRESS is absent' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('smtp')
        allow(GlobalConfigService).to receive(:load).with('SMTP_ADDRESS', anything).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/SMTP_ADDRESS not configured/).at_least(:once)
        UserMailer.two_factor_authentication_code(user, '123456').message
      end

      it 'does not apply smtp as dynamic delivery method' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method).not_to be_a(Mail::SMTP)
      end
    end

    context 'when MAILER_TYPE is bms with a valid BMS_API_SECRET' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('bms')
        allow(GlobalConfigService).to receive(:load).with('BMS_API_SECRET', nil).and_return('bms-key-123')
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'sets delivery method to bms on the message' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method).to be_a(Mail::BmsProvider)
      end
    end

    context 'when MAILER_TYPE is bms but BMS_API_SECRET is absent' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('bms')
        allow(GlobalConfigService).to receive(:load).with('BMS_API_SECRET', nil).and_return(nil)
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'does not set bms as delivery method' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method).not_to be_a(Mail::BmsProvider)
      end
    end

    context 'when MAILER_TYPE is resend with a valid RESEND_API_SECRET' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('resend')
        allow(GlobalConfigService).to receive(:load).with('RESEND_API_SECRET', anything).and_return('re_key_123')
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'sets delivery method to resend on the message' do
        mail = UserMailer.two_factor_authentication_code(user, '123456').message
        expect(mail.delivery_method).to be_a(Mail::ResendProvider)
      end
    end

    context 'when the resolved delivery method is not registered in delivery_methods' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('bms')
        allow(GlobalConfigService).to receive(:load).with('BMS_API_SECRET', nil).and_return('bms-key')
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
        allow(ApplicationMailer).to receive(:delivery_methods).and_wrap_original { |m| m.call.except(:bms) }
        allow_any_instance_of(Mail::Message).to receive(:delivery_method).with(anything, anything).and_return(nil)
      end

      it 'logs a warning about the unregistered delivery method' do
        expect(Rails.logger).to receive(:warn).with(/unregistered delivery method/).at_least(:once)
        UserMailer.two_factor_authentication_code(user, '123456').message
      end
    end

    context 'when GlobalConfigService raises an error' do
      before do
        allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_raise(StandardError, 'DB unavailable')
        allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('noreply@example.com')
      end

      it 'logs a warning and does not raise' do
        expect(Rails.logger).to receive(:warn).with(/Failed to load dynamic mail settings/).at_least(:once)
        expect { UserMailer.two_factor_authentication_code(user, '123456').message }.not_to raise_error
      end
    end
  end

  describe 'sender email' do
    before do
      allow(GlobalConfigService).to receive(:load).with('MAILER_TYPE', 'smtp').and_return('smtp')
      allow(GlobalConfigService).to receive(:load).with('SMTP_ADDRESS', anything).and_return(nil)
      allow(GlobalConfigService).to receive(:load).with('MAILER_SENDER_EMAIL', anything).and_return('custom@example.com')
    end

    it 'uses MAILER_SENDER_EMAIL from GlobalConfigService as the default from' do
      mail = UserMailer.two_factor_authentication_code(user, '123456').message
      expect(mail.from).to include('custom@example.com')
    end
  end
end
