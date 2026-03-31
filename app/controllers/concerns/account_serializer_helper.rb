module AccountSerializerHelper
  def account_data
    RuntimeConfig.account || {}
  end
end
