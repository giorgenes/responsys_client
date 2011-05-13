require 'rubygems'
gem 'soap4r'
require 'stub/defaultDriver.rb'
require 'stub/defaultMappingRegistry.rb'
require 'member'

module SunDawg
  class ResponsysClient

    MAX_MEMBERS = 200

    class TooManyMembersError < StandardError
    end

    class ResponsysTimeoutError < StandardError
    end

    class MethodsNotSupportedError < StandardError
    end

    class InconsistentPermissionStatusError < StandardError
    end

    attr_reader :session_id
    attr_accessor :keep_alive

    def initialize(username, password, options = {})
      @username = username
      @password = password
      @keep_alive = options[:keepalive] || false
      @responsys_client = ResponsysWS.new options[:endpoint]
      @responsys_client.wiredump_dev = options[:wiredump_dev] if options[:wiredump_dev]
      @timeout = options[:timeout] || 10 
    end 

    def login
      with_application_error do
        login_request = Login.new
        login_request.username = @username
        login_request.password = @password
        response = @responsys_client.login login_request
        @session_id = response.result.sessionId
        assign_session
      end
    end

    def assign_session
      session_header_request = SessionHeader.new
      session_header_request.sessionId = @session_id
      @responsys_client.headerhandler.add session_header_request
    end
    
    def logout
      begin
        logout_request = Logout.new
        @responsys_client.logout logout_request
      ensure
        @session_id = nil 
      end
    end

    def list_folders
      with_session do
        @responsys_client.listFolders ListFolders.new 
      end
    end

    def create_folder(folder_name)
      with_session do
        create_folder_request = CreateFolder.new
        create_folder_request.folderName = folder_name
        @responsys_client.createFolder create_folder_request
      end
    end

    def list_folder_objects(folder_name, folder_type)
      with_session do
        request = ListFolderObjects.new
        request.folderName = folder_name
        request.type = folder_type
        @responsys_client.listFolderObjects request
      end
    end

    def create_list(folder_name, object_name, description, fields)
      with_session do
        request = CreateList.new
        request.list = InteractObject.new(folder_name, object_name)
        request.description = description
        request.fields = fields.collect { |f| Field.new(f[:name], f[:type], f[:custom], f[:key]) }
        @responsys_client.createList request
      end
    end


    def save_members(folder_name, list_name, members, merge_rules, permission_status = PermissionStatus::OPTIN) 
      #raise MethodsNotSupportedError unless SunDawg::Responsys::Member.fields.include?(:email_address_) && SunDawg::Responsys::Member.fields.include?(:email_permission_status)
      raise TooManyMembersError if members.size > MAX_MEMBERS
      #raise InconsistentPermissionStatusError if members.reject { |i| i.email_permission_status != permission_status }.size != members.size

      with_session do
        list_merge_rule = ListMergeRule.new
        list_merge_rule.insertOnNoMatch = true
        list_merge_rule.updateOnMatch = UpdateOnMatch::REPLACE_ALL
        list_merge_rule.matchColumnName1 = merge_rules[:match_col1]
	list_merge_rule.matchColumnName2 = merge_rules[:match_col2]
	list_merge_rule.matchColumnName3 = merge_rules[:match_col3]
        list_merge_rule.defaultPermissionStatus = permission_status
	list_merge_rule.matchOperator = merge_rules[:operator]
        record_data = RecordData.new
        record_data.fieldNames = SunDawg::Responsys::Member.responsys_fields
        record_data.records = []
        members.each do |member|
          record = ResponsysRecord.new
          record = member.values
          record_data.records << record
        end
        interact_object = InteractObject.new
        interact_object.folderName = folder_name
        interact_object.objectName = list_name
        merge_list_members = MergeListMembers.new
        merge_list_members.list = interact_object
        merge_list_members.recordData = record_data
        merge_list_members.mergeRule = list_merge_rule
        @responsys_client.mergeListMembers merge_list_members
      end
    end

    def launch_campaign(folder_name, campaign_name)
      with_session do
        launch_campaign = LaunchCampaign.new
        interact_object = InteractObject.new
        interact_object.folderName = folder_name 
        interact_object.objectName = campaign_name 
        launch_campaign.campaign = interact_object
        @responsys_client.launchCampaign launch_campaign
      end
    end

    def trigger_campaign(folder_name, campaign_name, email, options = {})
      # Responsys requires something in the optional data for SOAP bindings to work
      options[:foo] = :bar if options.size == 0

      with_session do
        trigger_campaign_message = TriggerCampaignMessage.new
        recipient = Recipient.new
        recipient.emailAddress = email
        recipient_data = RecipientData.new
        recipient_data.optionalData = []
        recipient_data.recipient = recipient
        options.each_pair do |k, v|
          optional_data = OptionalData.new
          optional_data.name = k 
          optional_data.value = v 
          recipient_data.optionalData << optional_data
        end
        interact_object = InteractObject.new
        interact_object.folderName = folder_name
        interact_object.objectName = campaign_name
        trigger_campaign_message.campaign = interact_object
        trigger_campaign_message.recipientData = recipient_data
        @responsys_client.triggerCampaignMessage trigger_campaign_message
      end
    end

    def with_timeout
      Timeout::timeout(@timeout, ResponsysTimeoutError) do
        yield
      end
    end

    def with_session
      begin
        with_timeout do
          login if @session_id.nil?
        end
        with_application_error do
          with_timeout do
            yield
          end
        end
      ensure
        with_timeout do
          logout unless @keep_alive 
        end
      end
    end

    protected

    # Attempts to find the actual service error within SOAP:::FaultError and raise that instead
    def with_application_error
      begin
        yield
      rescue SOAP::FaultError => e
        inner_e = e.detail[e.faultstring.data]
        raise inner_e if inner_e
        raise e
      end
    end
  end
end
