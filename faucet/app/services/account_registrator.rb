class AccountRegistrator
  def initialize(user, logger)
    @user = user
    @logger = logger
  end

  def register(account_name, account_key, owner_key, referrer)
    @result = {account_name: account_name}

    @account = @user.bts_accounts.where(name: account_name).first
    if @account
      @result[:error] = "Account '#{account_name}' is already registered"
      return @result
    end

    if @user.bts_accounts.count >= APPCONFIG.registrations_limit
      @result[:error] = 'We cannot register this account - you ran out of your free account registrations.'
      return @result
    end

    begin
      account_key.start_with?('DVS') ? register_dvs(account_name, account_key, owner_key) : register_bts(account_name, account_key, owner_key)
      @user.bts_accounts.create(name: account_name, key: account_key, referrer: referrer)
    rescue BitShares::API::Rpc::Error => ex
      @result[:error] = ex.to_s
      @logger.error("!!! Error. Cannot register account #{account_name} - #{ex.to_s}")
    rescue Errno::ECONNREFUSED => e
      @logger.error("!!! Error. No rpc connection to BitShares toolkit - (#{ex.to_s})")
      if Rails.env.development?
        @user.bts_accounts.create(name: account_name, key: account_key, owner_key: owner_key, referrer: referrer)
      else
        @result[:error] = "No rpc connection to BitShares toolkit"
      end
    end
    @result
  end

  private

  def register_bts(account_name, account_key, owner_key)
    BitShares::API::Wallet.add_contact(account_key)
    #account = BitShares::API::Wallet.get_account(account_name)
    account = {}
    account['id'] = 0
    account['public_data'] = nil
    account['name'] = account_name
    account['active_key_history'] = [["2015-04-28T22:01:23", account_key]]
    account["registration_date"] = "1970-01-01T00:00:00"
    account["last_child_key_index"] = 0
    account["block_production_enabled"] = false
    account["custom_data"] = {}
    account['owner_key'] = owner_key if owner_key
    account['meta_data'] = {'type' => 'public_account', 'data' => ''}
    BitShares::API.rpc.request('request_register_account', [account])
  end

  def register_dvs(account_name, account_key, owner_key)
    dvs_rpc_instance = BitShares::API::Rpc.new(APPCONFIG.dvs_rpc_port, APPCONFIG.dvs_rpc_user, APPCONFIG.dvs_rpc_password, logger: Rails.logger, instance_name: 'dvsrpc')
    dvs_rpc_instance.request('wallet_add_contact_account', [account_name, account_key])
    account = dvs_rpc_instance.request('wallet_get_account', [account_name])
    account['owner_key'] = owner_key if owner_key
    account['meta_data'] = {'type' => 'public_account', 'data' => ''}
    dvs_rpc_instance.request('request_register_account', [account])
  end

end
