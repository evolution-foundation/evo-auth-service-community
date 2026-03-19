# frozen_string_literal: true

class AccountBuilder
  include CustomExceptions::Account
  pattr_initialize [:account_name, :email!, :confirmed, :user, :user_full_name, :user_password, :locale, :support_email]

  def perform
    if @user.nil?
      validate_email
      validate_user
    end
    ActiveRecord::Base.transaction do
      @account = create_account
      @user = create_and_link_user
    end
    [@user, @account]
  rescue StandardError => e
    Rails.logger.debug e.inspect
    raise e
  end

  private

  def user_full_name
    # the empty string ensures that not-null constraint is not violated
    @user_full_name || ''
  end

  def account_name
    # the empty string ensures that not-null constraint is not violated
    @account_name || ''
  end

  def validate_email
    Account::SignUpEmailValidationService.new(@email).perform
  end

  def validate_user
    if User.exists?(email: @email)
      true
    else
      raise UserErrors.new(errors: I18n.t('errors.signup.user_not_found'))
    end
  end

  def create_account
    account_attributes = {
      name: account_name,
      locale: @locale || I18n.locale
    }
    
    account_attributes[:support_email] = @support_email if @support_email.present?
    
    @account = Account.create!(account_attributes)
    Current.account = @account
    @account
  end

  def create_and_link_user
    @user = @user.present? ? @user : create_user
    if @user
      link_user_to_account(@user, @account)
      @user
    else
      raise UserErrors.new(errors: @user.errors)
    end
  end

  def link_user_to_account(user, account)
    # Create AccountUser with RBAC role
    AccountUser.create_with_role!(
      user: user,
      account: account,
      role_key: 'account_owner',
      inviter: nil # System assignment during account creation
    )
  end

  def create_user
    user = User.from_email(@email)

    if user
      return user
    end
    
    user = User.new(
      email: @email,
      password: user_password,
      password_confirmation: user_password,
      name: user_full_name
    )
    user.confirm if @confirmed
    user.save!
    user
  end
end
