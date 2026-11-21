require File.dirname(__FILE__) + '/../test_helper'
require 'stringio'

class ComputeConnectionTest < Test::Unit::TestCase
  def setup
    connection = stub()
    OpenStack::Authentication.stubs(:init).returns(connection)
  end

  def test_init_connection_no_credentials
    assert_raises(OpenStack::Exception::MissingArgument) do
      conn = OpenStack::Connection.create(:api_key => "AABBCCDD11", :auth_url => "a.b.c")
    end
  end

  def test_init_connection_no_password
    assert_raises(OpenStack::Exception::MissingArgument) do
      conn = OpenStack::Connection.create(:username => "test_account", :auth_url => "a.b.c")
    end
  end

  def test_init_connection_no_auth_url
    assert_raises(OpenStack::Exception::MissingArgument) do
      conn = OpenStack::Connection.create(:username => "test_account", :api_key => "AABBCCDD11")
    end
  end

  def test_init_connection_bad_auth_url
    assert_raises(OpenStack::Exception::InvalidArgument) do
      conn = OpenStack::Connection.create(:username => "test_account", :api_key => "AABBCCDD11", :auth_url => "***")
    end
  end

  def test_init_connection
      conn = OpenStack::Connection.create(:username => "test_account", :api_key => "AABBCCDD11", :auth_url => "https://a.b.c")
      assert_not_nil conn, "Connection.new returned nil."
  end

  def test_csreq_gives_up_after_the_configured_retries
    conn = timing_out_connection
    conn.http["a.b.c"].expects(:request).twice.raises(Net::ReadTimeout)

    assert_raises(OpenStack::Exception::Connection) do
      conn.csreq("HEAD", "a.b.c", "/path", 443, "https")
    end
  end

  def test_put_object_gives_up_after_the_configured_retries
    conn = timing_out_connection
    conn.http["a.b.c"].expects(:request).twice.raises(Net::ReadTimeout)

    assert_raises(OpenStack::Exception::Connection) do
      conn.put_object("a.b.c", "/path", 443, "https", {}, "data")
    end
  end

  def test_set_timeouts_turns_off_net_http_retries
    conn = OpenStack::Connection.create(:username => "test_account", :api_key => "AABBCCDD11", :auth_url => "https://a.b.c", :read_timeout => 30).connection
    http = Net::HTTP.new("a.b.c", 443)

    conn.set_timeouts(http)

    assert_equal 30, http.read_timeout
    assert_equal 0, http.max_retries
  end

  def test_put_object_resends_the_whole_stream_after_a_dropped_connection
    conn = timing_out_connection
    sent = []
    conn.http["a.b.c"].stubs(:request).with do |request|
      sent << request.body_stream.read(1_000)
      raise EOFError if sent.size == 1
      true
    end.returns(stub(:code => "201", :body => ""))

    conn.put_object("a.b.c", "/path", 443, "https", {}, StringIO.new("data"))

    assert_equal ["data", "data"], sent
  end

  def test_put_object_resends_the_whole_stream_after_reauthenticating
    conn = timing_out_connection
    OpenStack::Authentication.stubs(:init)
    sent = []
    conn.http["a.b.c"].stubs(:request).with do |request|
      sent << request.body_stream.read(1_000)
      true
    end.returns(stub(:code => "401", :body => "")).then.returns(stub(:code => "201", :body => ""))

    conn.put_object("a.b.c", "/path", 443, "https", {}, StringIO.new("data"))

    assert_equal ["data", "data"], sent
  end

  private

  def timing_out_connection
    conn = OpenStack::Connection.create(:username => "test_account", :api_key => "AABBCCDD11", :auth_url => "https://a.b.c", :retries => 2).connection
    conn.stubs(:sleep)
    conn.http["a.b.c"] = stub(:started? => false)
    conn
  end
end
