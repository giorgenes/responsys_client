require 'test_helper'
require 'responsys_client'

class ResponsysClientTest < Test::Unit::TestCase 
  def setup
    config = YAML.load_file("test/config.yml")
    @username = config["username"]
    @password = config["password"]
    #@client = SunDawg::ResponsysClient.new(@username, @password, :wiredump_dev => STDOUT)
    @client = SunDawg::ResponsysClient.new(@username, @password)
  end

  def test_client_instantiation
    assert @client
  end

  def test_invalid_login
    error = assert_raise AccountFault do
      SunDawg::ResponsysClient.new("foo", "bar").login
   end
    assert_equal ExceptionCode::INVALID_USER_NAME, error.exception_code
  end

  def test_login
    assert_nothing_raised do
      @client.login
      assert @client.session_id
    end
  end

  def test_list_folders
    results = @client.list_folders
    assert results.size
    results.each do |result|
      assert result.name
    end
  end

  def test_create_folder
    folder_name = "test_folder_#{Time.now.to_i}"
    @client.keep_alive = true
    response = @client.create_folder folder_name
    assert response.result
    results = @client.list_folders
    assert results.map { |i| i.name }.include? folder_name
  end

  def test_save_users
    SunDawg::Responsys::User.add_field :email_address
    SunDawg::Responsys::User.add_field :city
    SunDawg::Responsys::User.add_field :state
    user = SunDawg::Responsys::User.new
    user.email_address = "sundawg.#{Time.now.to_i}@sundawg.net"
    user.city = "San Francisco"
    user.state = "CA"
    response = @client.save_users "Animoto", "Animoto Test", [user] 
    assert response.result
  end
end