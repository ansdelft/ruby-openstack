require 'rubygems'

module OpenStack

class Connection

    attr_reader   :authuser
    attr_reader   :authtenant
    attr_reader   :authkey
    attr_reader   :auth_method
    attr_accessor :authtoken
    attr_accessor :authok
    attr_accessor :service_host
    attr_accessor :service_path
    attr_accessor :service_port
    attr_accessor :service_scheme
    attr_accessor :quantum_version
    attr_reader   :retries
    attr_reader   :auth_host
    attr_reader   :auth_port
    attr_reader   :auth_scheme
    attr_reader   :auth_path
    attr_reader   :service_name
    attr_reader   :service_type
    attr_reader   :user_domain
    attr_reader   :user_domain_id
    attr_reader   :project_id
    attr_reader   :project_name
    attr_reader   :project_domain_name
    attr_reader   :project_domain_id
    attr_reader   :domain_name
    attr_reader   :domain_id
    attr_reader   :proxy_host
    attr_reader   :proxy_port
    attr_reader   :ca_cert
    attr_reader   :ssl_version
    attr_reader   :region
    attr_reader   :regions_list #e.g. os.connection.regions_list == {"region-a.geo-1" => [ {:service=>"object-store", :versionId=>"1.0"}, {:service=>"identity", :versionId=>"2.0"}], "region-b.geo-1"=>[{:service=>"identity", :versionId=>"2.0"}] }

    attr_reader   :http
    attr_reader   :is_debug
    attr_reader   :endpoint_type

    # Creates and returns a new Connection object, depending on the service_type
    # passed in the options:
    #
    # e.g:
    # os = OpenStack::Connection.create({:username => "herp@derp.com", :api_key=>"password",
    #               :auth_url => "https://region-a.geo-1.identity.cloudsvc.com:35357/v2.0/",
    #               :authtenant=>"herp@derp.com-default-tenant", :service_type=>"object-store")
    #
    # Will return an OpenStack::Swift::Connection object.
    #
    #   options hash:
    #
    #   :username - Your OpenStack username or public key, depending on auth_method. *required*
    #   :auth_method - Type of authentication - 'password', 'key', 'rax-kskey', 'token' - defaults to 'password'.
    #     For auth v3.0 valid options are 'password', 'token', 'password_user_id'
    #   :authtenant_name OR :authtenant_id - Your OpenStack tenant name or id *required*. Defaults to username.
    #     passing :authtenant will default to using that parameter as tenant name.
    #   :api_key - Your OpenStack API key *required* (either private key or password, depending on auth_method)
    #   :auth_url - Configurable auth_url endpoint.
    #   :service_name - (Optional for v2.0 auth only). The optional name of the compute service to use.
    #   :service_type - (Optional for v2.0 auth only). Defaults to "compute"
    #   :user_domain - (Optional for v3.0 auth only). The optional name of the user domain.
    #   :user_domain_id - (Optional for v3.0 auth only). Defaults to "default"
    #   :project_id - (Optional for v3.0 auth only). For authorization scoping
    #   :project_name - (Optional for v3.0 auth only). For authorization scoping
    #   :project_domain_name - (Optional for v3.0 auth only). For authorization scoping
    #   :project_domain_id - (Optional for v3.0 auth only). For authorization scoping
    #   :domain_name - (Optional for v3.0 auth only). For authorization scoping
    #   :domain_id - (Optional for v3.0 auth only). For authorization scoping
    #   :region - (Optional for v2.0 auth only). The specific service region to use. Defaults to first returned region.
    #   :retry_auth - Whether to retry if your auth token expires (defaults to true)
    #   :proxy_host - If you need to connect through a proxy, supply the hostname here
    #   :proxy_port - If you need to connect through a proxy, supply the port here
    #   :ca_cert - path to a CA chain in PEM format
    #   :ssl_version - explicitly set an version (:SSLv3 etc, see  OpenSSL::SSL::SSLContext::METHODS)
    #   :is_debug - Only for development purpose for debug output
    #   :endpoint_type - Type of endpoint. Optional. 'publicURL', 'internalURL', 'adminURL'
    #
    # The options hash is used to create a new OpenStack::Connection object
    # (private constructor) and this is passed to the constructor of OpenStack::Compute::Connection
    # or OpenStack::Swift::Connection (depending on :service_type) where authentication is done using
    # OpenStack::Authentication.
    #
    def self.create(options = {:retry_auth => true})
      #call private constructor and grab instance vars
      connection = new(options)
      case connection.service_type
        when "compute"
          OpenStack::Compute::Connection.new(connection)
        when "object-store"
          OpenStack::Swift::Connection.new(connection)
        when "volume"
          OpenStack::Volume::Connection.new(connection)
        when "image"
          OpenStack::Image::Connection.new(connection)
        when "network"
          OpenStack::Network::Connection.new(connection)
        when "identity"
          OpenStack::Identity::Connection.new(connection)
       else
          raise Exception::InvalidArgument, "Invalid :service_type parameter: #{@service_type}"
      end
    end

    private_class_method :new

    def initialize(options = {:retry_auth => true})
      @retries = options[:retries] || 3
      @authuser = options[:username] || (raise Exception::MissingArgument, "Must supply a :username")
      @authkey = options[:api_key] || (raise Exception::MissingArgument, "Must supply an :api_key")
      @auth_url = options[:auth_url] || (raise Exception::MissingArgument, "Must supply an :auth_url")
      @authtenant = (options[:authtenant_id])? {:type => "tenantId", :value=>options[:authtenant_id]} : {:type=>"tenantName", :value=>(options[:authtenant_name] || options[:authtenant] || @authuser)}
      @auth_method = options[:auth_method] || "password"
      @service_name = options[:service_name] || nil
      @service_type = options[:service_type] || "compute"
      @user_domain_id = options[:user_domain_id] || "default"
      @user_domain = options[:user_domain] || nil
      @project_id = options[:project_id] || nil
      @project_name = options[:project_name] || nil
      @project_domain_name = options[:project_domain_name] || nil
      @project_domain_id = options[:project_domain_id] || nil
      @domain_name = options[:domain_name] || nil
      @domain_id = options[:domain_id] || nil
      @region = options[:region] || @region = nil
      @regions_list = {} # this is populated during authentication - from the returned service catalogue
      @is_debug = options[:is_debug]
      auth_uri=nil
      begin
        auth_uri=URI.parse(@auth_url)
      rescue Exception => e
        raise Exception::InvalidArgument, "Invalid :auth_url parameter: #{e.message}"
      end
      raise Exception::InvalidArgument, "Invalid :auth_url parameter." if auth_uri.nil? or auth_uri.host.nil?
      @auth_host = auth_uri.host
      @auth_port = auth_uri.port
      @auth_scheme = auth_uri.scheme
      @auth_path = auth_uri.path
      @retry_auth = options[:retry_auth]
      @proxy_host = options[:proxy_host]
      @proxy_port = options[:proxy_port]
      @ca_cert = options[:ca_cert]
      @ssl_version = options[:ssl_version]
      @authok = false
      @http = {}
      @quantum_version = 'v2.0' if @service_type == 'network'
      @endpoint_type = options[:endpoint_type] || "publicURL"
    end

    #specialised from of csreq for PUT object... uses body_stream if possible
    def put_object(server,path,port,scheme,headers = {},data = nil,attempts = 0) # :nodoc:

      tries = @retries
      time = 3

      if data.respond_to? :read
        headers['Transfer-Encoding'] = 'chunked'
        hdrhash = headerprep(headers)
        request = Net::HTTP::Put.new(path,hdrhash)
        chunked = OpenStack::Swift::ChunkedConnectionWrapper.new(data, 65535)
        request.body_stream = chunked
      else
        headers['Content-Length'] = (data.respond_to?(:lstat))? data.lstat.size.to_s : ((data.respond_to?(:size))? data.size.to_s : "0")
        hdrhash = headerprep(headers)
        request = Net::HTTP::Put.new(path,hdrhash)
        request.body = data
      end
      start_http(server,path,port,scheme,hdrhash)
      response = @http[server].request(request)
      if @is_debug
        puts "REQUEST: PUT => #{path}"
        puts data if data
        puts "RESPONSE: #{response.body}"
        puts '----------------------------------------'
      end
      raise OpenStack::Exception::ExpiredAuthToken if response.code == "401"
      response
    rescue Errno::EPIPE, Timeout::Error, Errno::EINVAL, EOFError
      # Server closed the connection, retry
      puts "Can't connect to the server: #{tries} tries to reconnect" if @is_debug
      sleep time += 1
      @http[server].finish if @http[server].started?
      retry unless (tries -= 1) <= 0
      raise OpenStack::Exception::Connection, "Unable to connect to #{server} after #{@retries} retries"

    rescue OpenStack::Exception::ExpiredAuthToken
      raise OpenStack::Exception::Connection, "Authentication token expired and you have requested not to retry" if @retry_auth == false
      OpenStack::Authentication.init(self)
      retry
    end


    # This method actually makes the HTTP REST calls out to the server
    def csreq(method,server,path,port,scheme,headers = {},data = nil,attempts = 0, &block) # :nodoc:
      tries = @retries
      time = 3

      hdrhash = headerprep(headers)
      start_http(server,path,port,scheme,hdrhash)
      request = Net::HTTP.const_get(method.to_s.capitalize).new(path,hdrhash)
      request.body = data
      if block_given?
        response =  @http[server].request(request) do |res|
          res.read_body do |b|
            yield b
          end
        end
      else
        response = @http[server].request(request)
      end
      if @is_debug
        puts "REQUEST: #{method.to_s} => #{scheme}://#{server}#{path}"
        puts data if data
        puts "RESPONSE: #{response.body}"
        puts '----------------------------------------'
      end
      raise OpenStack::Exception::ExpiredAuthToken if response.code == "401"
      response
    rescue Errno::EPIPE, Timeout::Error, Errno::EINVAL, EOFError
      # Server closed the connection, retry
      puts "Can't connect to the server: #{tries} tries to reconnect" if @is_debug
      sleep time += 1
      @http[server].finish if @http[server].started?
      retry unless (tries -= 1) <= 0
      raise OpenStack::Exception::Connection, "Unable to connect to #{server} after #{@retries} retries"
    rescue OpenStack::Exception::ExpiredAuthToken
      raise OpenStack::Exception::Connection, "Authentication token expired and you have requested not to retry" if @retry_auth == false
      OpenStack::Authentication.init(self)
      retry
    end

    # This is a much more sane way to make a http request to the api.
    # Example: res = conn.req('GET', "/servers/#{id}")
    def req(method, path, options = {})
      server   = options[:server]   || @service_host
      port     = options[:port]     || @service_port
      scheme   = options[:scheme]   || @service_scheme
      headers  = options[:headers]  || {'content-type' => 'application/json'}
      data     = options[:data]
      attempts = options[:attempts] || 0
      path = (@service_path.empty? ? "/" : @service_path) + @quantum_version.to_s + path
      res = csreq(method,server,path,port,scheme,headers,data,attempts)
      res.code.match(/^20.$/) ? (return res) : OpenStack::Exception.raise_exception(res)
    end

    private

    # Sets up standard HTTP headers
    def headerprep(headers = {}) # :nodoc:
      default_headers = {}
      default_headers["X-Auth-Token"] = @authtoken if authok
      default_headers["X-Storage-Token"] = @authtoken if authok
      default_headers["Connection"] = "Keep-Alive"
      default_headers["User-Agent"] = "OpenStack Ruby API #{Gem::VERSION}"
      default_headers["Accept"] = "application/json"
      default_headers.merge(headers)
    end

    # Starts (or restarts) the HTTP connection
    def start_http(server,path,port,scheme,headers) # :nodoc:

      tries = @retries
      time = 3

      if (@http[server].nil?)
        begin
          @http[server] = Net::HTTP::Proxy(@proxy_host, @proxy_port).new(server,port)
          if scheme == "https"
            @http[server].use_ssl = true
            @http[server].verify_mode = OpenSSL::SSL::VERIFY_NONE

            # use the ca_cert if were given one, and make sure we verify!
            if ! @ca_cert.nil?
              @http[server].ca_file = @ca_cert
              @http[server].verify_mode = OpenSSL::SSL::VERIFY_PEER
            end

            # explicitly set the SSL version to use
            @http[server].ssl_version= @ssl_version if ! @ssl_version.nil?
          end
          @http[server].start
        rescue
          puts "Can't connect to the server: #{tries} tries to reconnect" if @is_debug
          sleep time += 1
          retry unless (tries -= 1) <= 0
          raise OpenStack::Exception::Connection, "Unable to connect to #{server}"
        end
      end
    end

  end #end class Connection

  #============================
  # OpenStack::Authentication
  #============================

  class Authentication

    # Performs an authentication to the OpenStack auth server.
    # If it succeeds, it sets the service_host, service_path, service_port,
    # service_scheme, authtoken, and authok variables on the connection.
    # If it fails, it raises an exception.

    def self.init(conn)
      if conn.auth_path =~ /.*v3\/?$/
        AuthV30.new(conn)
      elsif conn.auth_path =~ /.*v2.0\/?$/
        AuthV20.new(conn)
      else
        AuthV10.new(conn)
      end
    end
  end

  private

  class AuthV10
    def initialize(connection)
      tries = connection.retries
      time = 3

      hdrhash = { "X-Auth-User" => connection.authuser, "X-Auth-Key" => connection.authkey }
      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.auth_host, connection.auth_port)
        if connection.auth_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE

          # use the ca_cert if were given one, and make sure to verify!
          if !connection.ca_cert.nil?
            server.ca_file = connection.ca_cert
            server.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          # explicitly set the SSL version to use
          server.ssl_version = connection.ssl_version if !connection.ssl_version.nil?
        end
        server.start
      rescue
        puts "Can't connect to the server: #{tries} tries  to reconnect" if connection.is_debug
        sleep time += 1
        retry unless (tries -= 1) <= 0
        raise OpenStack::Exception::Connection, "Unable to connect to #{server}"
      end

      response = server.get(connection.auth_path, hdrhash)

      if (response.code =~ /^20./)
        connection.authtoken = response["x-auth-token"]
        case connection.service_type
        when "compute"
          uri = URI.parse(response["x-server-management-url"])
        when "object-store"
          uri = URI.parse(response["x-storage-url"])
        end
        raise OpenStack::Exception::Authentication, "Unexpected Response from  #{connection.auth_host} - couldn't get service URLs: \"x-server-management-url\" is: #{response["x-server-management-url"]} and \"x-storage-url\" is: #{response["x-storage-url"]}"  if (uri.host.nil? || uri.host=="")
        connection.service_host = uri.host
        connection.service_path = uri.path
        connection.service_port = uri.port
        connection.service_scheme = uri.scheme
        connection.authok = true
      else
        connection.authok = false
        raise OpenStack::Exception::Authentication, "Authentication failed with response code #{response.code}"
      end
      server.finish
    end
  end

  class AuthV20
    attr_reader :uri
    attr_reader :version
    def initialize(connection)

      tries = connection.retries
      time = 3

      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.auth_host, connection.auth_port)
        if connection.auth_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE

          # use the ca_cert if were given one, and make sure we verify!
          if !connection.ca_cert.nil?
            server.ca_file = connection.ca_cert
            server.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          # explicitly set the SSL version to use
          server.ssl_version = connection.ssl_version if !connection.ssl_version.nil?
        end
        server.start
      rescue
        puts "Can't connect to the server: #{tries} tries  to reconnect" if connection.is_debug
        sleep time += 1
        retry unless (tries -= 1) <= 0
        raise OpenStack::Exception::Connection, "Unable to connect to  #{server}"
      end

      @uri = String.new

      case connection.auth_method
      when "password"
        auth_data = JSON.generate({ "auth" =>  { "passwordCredentials" => { "username" => connection.authuser, "password" => connection.authkey }, connection.authtenant[:type] => connection.authtenant[:value]}})
      when "rax-kskey"
        auth_data = JSON.generate({"auth" => {"RAX-KSKEY:apiKeyCredentials" => {"username" => connection.authuser, "apiKey" => connection.authkey}}})
      when "key"
        auth_data = JSON.generate({"auth" => { "apiAccessKeyCredentials" => {"accessKey" => connection.authuser, "secretKey" => connection.authkey}, connection.authtenant[:type] => connection.authtenant[:value]}})
      else
        raise Exception::InvalidArgument, "Unrecognized auth method #{connection.auth_method}"
      end

      response = server.post(connection.auth_path.chomp("/")+"/tokens", auth_data, {'Content-Type' => 'application/json'})
      if (response.code =~ /^20./)
        resp_data=JSON.parse(response.body)
        connection.authtoken = resp_data['access']['token']['id']
        implemented_services = resp_data["access"]["serviceCatalog"].inject([]){|res, current| res << current["type"] ;res}
        raise OpenStack::Exception::NotImplemented.new("The requested service: \"#{connection.service_type}\" is not present " +
                                                       "in the returned service catalogue.", 501, "#{resp_data["access"]["serviceCatalog"]}") unless implemented_services.include?(connection.service_type)
        resp_data['access']['serviceCatalog'].each do |service|
          service["endpoints"].each do |endpoint|
            connection.regions_list[endpoint["region"]] ||= []
            connection.regions_list[endpoint["region"]] << {:service=>service["type"], :versionId => endpoint["versionId"]}
          end
          if connection.service_name
            check_service_name = connection.service_name
          else
            check_service_name = service['name']
          end
          if service['type'] == connection.service_type and service['name'] == check_service_name
            endpoints = service["endpoints"]
            if connection.region
              endpoints.each do |ep|
                if ep["region"] and ep["region"].upcase == connection.region.upcase
                  @uri = URI.parse(ep[connection.endpoint_type])
                end
              end
            else
              @uri = URI.parse(endpoints[0][connection.endpoint_type])
            end
            if @uri == ""
              raise OpenStack::Exception::Authentication, "No API endpoint for region #{connection.region}"
            else
              if @version #already got one version of endpoints
                current_version = get_version_from_response(service,connection.endpoint_type)
                if @version.to_f > current_version.to_f
                  next
                end
              end
              #grab version to check next time round for multi-version deployments
              @version = get_version_from_response(service,connection.endpoint_type)
              connection.service_host = @uri.host
              connection.service_path = @uri.path
              connection.service_port = @uri.port
              connection.service_scheme = @uri.scheme
              connection.authok = true
            end
          end
        end
      else
        connection.authtoken = false
        raise OpenStack::Exception::Authentication, "Authentication failed with response code #{response.code}"
      end
      server.finish if server.started?
    end

    def get_version_from_response(service,endpoint_type)
      service["endpoints"].first["versionId"] || parse_version_from_endpoint(service["endpoints"].first[endpoint_type])
    end

    #IN  --> https://az-2.region-a.geo-1.compute.hpcloudsvc.com/v1.1/46871569847393
    #OUT --> "1.1"
    def parse_version_from_endpoint(endpoint)
      endpoint.match(/\/v(\d).(\d)/).to_s.sub("/v", "")
    end
  end

  # Implement the Identity Version 3.x API
  # http://developer.openstack.org/api-ref-identity-v3.html
  # This is still experimental, so don't use in production.
  class AuthV30
    attr_reader :uri, :version
    # TODO: Parse the version for an endpoint

    def initialize(connection)
      tries = connection.retries
      time = 3

      begin
        server = Net::HTTP::Proxy(connection.proxy_host, connection.proxy_port).new(connection.auth_host, connection.auth_port)
        if connection.auth_scheme == "https"
          server.use_ssl = true
          server.verify_mode = OpenSSL::SSL::VERIFY_NONE

          # use the ca_cert if were given one, and make sure we verify!
          unless connection.ca_cert.nil?
            server.ca_file = connection.ca_cert
            server.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          # explicitly set the SSL version to use
          server.ssl_version = connection.ssl_version unless connection.ssl_version.nil?
        end
        server.start
      rescue
        puts "Can't connect to the server: #{tries} tries to reconnect" if connection.is_debug
        sleep time += 1
        retry unless (tries -= 1) <= 0
        raise OpenStack::Exception::Connection, "Unable to connect to #{server}"
      end

      # Build Auth JSON
      auth = { "auth" => { "identity" => {} } }

      case connection.auth_method.to_sym
      when :password
        auth["auth"]["identity"]["methods"] = ["password"]
        auth["auth"]["identity"]["password"] = { "user" => { "name" => connection.authuser, "password" => connection.authkey } }
        auth["auth"]["identity"]["password"]["user"]["domain"] = connection.user_domain ? { "name" => connection.user_domain } : { "id" => connection.user_domain_id }
      when :password_user_id
        auth["auth"]["identity"]["methods"] = ["password"]
        auth["auth"]["identity"]["password"] = { "user" => { "id" => connection.authuser, "password" => connection.authkey } }
      when :token
        auth["auth"]["identity"]["methods"] = ["token"]
        auth["auth"]["identity"]["token"] = { "id" => connection.authkey }
      else
        raise Exception::InvalidArgument, "Unrecognized auth method #{connection.auth_method}."
      end

      # handle project authentication scope
      if (connection.project_id || connection.project_name) && (connection.project_domain_name || connection.project_domain_id)
        auth["auth"]["scope"] = { "project" => { "domain" => {} } }
        auth["auth"]["scope"]["project"]["name"] =  connection.project_name if connection.project_name
        auth["auth"]["scope"]["project"]["id"] =  connection.project_id if connection.project_id
        auth["auth"]["scope"]["project"]["domain"]["name"] = connection.project_domain_name if connection.project_domain_name
        auth["auth"]["scope"]["project"]["domain"]["id"] = connection.project_domain_id if connection.project_domain_id
      end

      # handle domain authentication scope
      if connection.domain_name || connection.domain_id
        auth["auth"]["scope"] = { "domain" => {} }
        auth["auth"]["scope"]["domain"]["name"] = connection.domain_name if connection.domain_name
        auth["auth"]["scope"]["domain"]["id"] = connection.domain_id if connection.domain_id
      end

      response = server.post(connection.auth_path.chomp('/') + '/auth/tokens',
                             JSON.generate(auth),
                             {'Content-Type' => 'application/json'})

      # debugging
      if connection.is_debug
        puts "REQUEST: POST => #{connection.auth_path.chomp('/') + '/auth/tokens'}"
        puts "RESPONSE: #{response.body}"
        puts '----------------------------------------'
      end

      if response.code =~ /^20./
        connection.authtoken = response['X-Subject-Token']

        resp_data=JSON.parse(response.body)

        catalog = resp_data["token"]["catalog"]
        unless catalog
          raise OpenStack::Exception::Authentication, "No service catalog returned. Maybe your auth request is unscoped. Please check if your selected user has a default project."
        end

        # Check if the used service is available
        implemented_services = resp_data["token"]["catalog"].map {|service| service['type']}
        raise OpenStack::Exception::NotImplemented.new("The requested service: \"#{connection.service_type}\" is not present " +
                                                       "in the returned service catalogue.", 501, "#{resp_data["access"]["serviceCatalog"]}") unless implemented_services.include?(connection.service_type)
        catalog.each do |service|
          service["endpoints"].each do |endpoint|
            connection.regions_list[endpoint["region"]] ||= []
            connection.regions_list[endpoint["region"]] << {:service=>service["type"], :versionId => endpoint["versionId"]}
          end

          # set use preset service name if set, otherwise ignore.
          if connection.service_name
            check_service_name = connection.service_name
          else
            check_service_name = service['name']
          end

          if service['type'] == connection.service_type and service['name'] == check_service_name
            endpoints = service["endpoints"]

            # filter endpoints by interfacetype
            interface_type = connection.endpoint_type.gsub('URL','')
            endpoints = endpoints.select {|ep| ep['interface'] == interface_type}

            # Select endpoint based on region
            if connection.region
              endpoints.each do |ep|
                if ep["region"] and ep["region"].upcase == connection.region.upcase
                  @uri = URI.parse(ep['url'])
                end
              end
            else
              @uri = URI.parse(endpoints[0]['url'])
            end

            if @uri == ""
              raise OpenStack::Exception::Authentication, "No API endpoint for region #{connection.region}"
            else
              connection.service_host = @uri.host
              connection.service_path = @uri.path
              connection.service_port = @uri.port
              connection.service_scheme = @uri.scheme
              connection.authok = true
            end
          end
        end
      else
        connection.authtoken = false
        raise OpenStack::Exception::Authentication, "Authentication failed with response code #{response.code}"
      end
      server.finish if server.started?
    end
  end


  #============================
  # OpenStack::Exception
  #============================

  class Exception
    class ComputeError < StandardError
      attr_reader :response_body
      attr_reader :response_code

      def initialize(message, code, response_body)
        @response_code=code
        @response_body=response_body
        super(message)
      end
    end

    class ComputeFault                < ComputeError # :nodoc:
    end
    class ServiceUnavailable          < ComputeError # :nodoc:
    end
    class Unauthorized                < ComputeError # :nodoc:
    end
    class BadRequest                  < ComputeError # :nodoc:
    end
    class OverLimit                   < ComputeError # :nodoc:
    end
    class BadMediaType                < ComputeError # :nodoc:
    end
    class BadMethod                   < ComputeError # :nodoc:
    end
    class ItemNotFound                < ComputeError # :nodoc:
    end
    class BuildInProgress             < ComputeError # :nodoc:
    end
    class ServerCapacityUnavailable   < ComputeError # :nodoc:
    end
    class BackupOrResizeInProgress    < ComputeError # :nodoc:
    end
    class ResizeNotAllowed            < ComputeError # :nodoc:
    end
    class NotImplemented              < ComputeError # :nodoc:
    end
    class Other                       < ComputeError # :nodoc:
    end
    class ResourceStateConflict       < ComputeError # :nodoc:
    end
    class QuantumError                < ComputeError # :nodoc:
    end

    # Plus some others that we define here

    class ExpiredAuthToken            < StandardError # :nodoc:
    end
    class MissingArgument             < StandardError # :nodoc:
    end
    class InvalidArgument             < StandardError # :nodoc:
    end
    class TooManyPersonalityItems     < StandardError # :nodoc:
    end
    class PersonalityFilePathTooLong  < StandardError # :nodoc:
    end
    class PersonalityFileTooLarge     < StandardError # :nodoc:
    end
    class Authentication              < StandardError # :nodoc:
    end
    class Connection                  < StandardError # :nodoc:
    end

    # In the event of a non-200 HTTP status code, this method takes the HTTP response, parses
    # the JSON from the body to get more information about the exception, then raises the
    # proper error.  Note that all exceptions are scoped in the OpenStack::Compute::Exception namespace.
    def self.raise_exception(response)
      return if response.code =~ /^20.$/
      begin
        fault = nil
        info = nil
        if response.body.nil? && response.code == "404" #HEAD ops no body returned
          exception_class = self.const_get("ItemNotFound")
          raise exception_class.new("The resource could not be found", "404", "")
        else
          JSON.parse(response.body).each_pair do |key, val|
            fault=key
            info=val
          end
          exception_class = self.const_get(fault[0,1].capitalize+fault[1,fault.length])
          raise exception_class.new((info["message"] || info), response.code, response.body)
        end
      rescue JSON::ParserError => parse_error
        deal_with_faulty_error(response, parse_error)
      rescue NameError
        raise OpenStack::Exception::Other.new("The server returned status #{response.code}", response.code, response.body)
      end
    end

    private

    #e.g. os.delete("non-existant") ==> response.body is:
    # "404 Not Found\n\nThe resource could not be found.\n\n   "
    # which doesn't parse. Deal with such cases here if possible (JSON::ParserError)
    def self.deal_with_faulty_error(response, parse_error)
      case response.code
      when "404"
        klass = self.const_get("ItemNotFound")
        msg = "The resource could not be found"
      when "409"
        klass = self.const_get("ResourceStateConflict")
        msg = "There was a conflict with the state of the resource"
      else
        klass = self.const_get("Other")
        msg = "Oops - not sure what happened: #{parse_error}"
      end
      raise klass.new(msg, response.code.to_s, response.body)
    end
  end
end

