module AccountSerializerHelper
  # Deprecated: Use AccountSerializer.full instead
  def account_data(account)
    AccountSerializer.full(
      account,
      include_settings: true,
      include_attributes: true,
      include_features: true,
      include_plan: true,
      include_role: true,
      include_counts: true
    )
  end
end
