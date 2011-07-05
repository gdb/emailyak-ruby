require 'cgi'
require 'set'

require 'rubygems'
require 'json'
require 'openssl'
require 'rest_client'

# A lot of the structure here is borrowed from the Stripe Ruby
# bindings (https://github.com/stripe/stripe-ruby).
module EmailYak
  @@version = '0.0.1'
  @@ssl_bundle_path = File.join(File.dirname(__FILE__), 'data/ca-certificates.crt')
  @@api_key = nil
  @@api_base = 'https://api.emailyak.com/v1'
  @@verify_ssl_certs = true

  module Util
    def self.file_readable(file)
      begin
        File.open(file) { |f| }
      rescue
        false
      else
        true
      end
    end
  end

  class EmailYakError < StandardError; end
  class APIConnectionError < EmailYakError; end
  class APIResponseCodeError < EmailYakError
    attr_reader :rcode, :rbody

    def initialize(message, rcode, rbody)
      super(message)
      @rcody = rcode
      @rbody = rbody
    end
  end

  def self.api_url(url=''); [@@api_base, api_key, 'json', url].join('/'); end
  def self.api_key=(api_key); @@api_key = api_key; end
  def self.api_key; @@api_key; end
  def self.api_base=(api_base); @@api_base = api_base; end
  def self.api_base; @@api_base; end
  def self.verify_ssl_certs=(verify); @@verify_ssl_certs = verify; end
  def self.verify_ssl_certs; @@verify_ssl_certs; end
  def self.version; @@version; end

  module Email
    def self.get_all(params={})
      EmailYak.request(:get, 'get/all/email/', nil, params)
    end
  end
  
  def self.request(method, url, api_key, params=nil, headers={})
    api_key ||= @@api_key
    raise EmailYakError.new('No API key provided.  (HINT: set your API key using "EmailYak.api_key = <API-KEY>".') unless api_key

    if !verify_ssl_certs
      unless @no_verify
        $stderr.puts "WARNING: Running without SSL cert verification.  Execute 'EmailYak.verify_ssl_certs = true' to enable verification."
        @no_verify = true
      end
      ssl_opts = { :verify_ssl => false }
    elsif !Util.file_readable(@@ssl_bundle_path)
      unless @no_bundle
        $stderr.puts "WARNING: Running without SSL cert verification because #{@@ssl_bundle_path} isn't readable"
        @no_bundle = true
      end
      ssl_opts = { :verify_ssl => false }
    else
      ssl_opts = {
        :verify_ssl => OpenSSL::SSL::VERIFY_PEER,
        :ssl_ca_file => @@ssl_bundle_path
      }
    end

    case method.to_s.downcase.to_sym
    when :get, :head, :delete
      # Make params into GET parameters
      headers = { :params => params }.merge(headers)
      payload = nil
    else
      payload = params
    end
    opts = {
      :method => method,
      :url => self.api_url(url),
      :user => api_key,
      :headers => headers,
      :open_timeout => 30,
      :payload => payload,
      :timeout => 80
    }.merge(ssl_opts)

    begin
      response = execute_request(opts)
    rescue SocketError => e
      self.handle_restclient_error(e)
    rescue NoMethodError => e
      # Work around RestClient bug
      if e.message =~ /\WRequestFailed\W/
        e = APIConnectionError.new('Unexpected HTTP response code')
        self.handle_restclient_error(e)
      else
        raise
      end
    rescue RestClient::ExceptionWithResponse => e
      if rcode = e.http_code and rbody = e.http_body
        self.handle_api_error(rcode, rbody)
      else
        self.handle_restclient_error(e)
      end
    rescue RestClient::Exception, Errno::ECONNREFUSED => e
      self.handle_restclient_error(e)
    end

    rbody = response.body
    rcode = response.code
    begin
      resp = JSON.parse(rbody, :symbolize_names => true)
    rescue JSON::ParseError
      raise APIError.new("Invalid response object from API: #{rbody.inspect} (HTTP response code was #{rcode})")
    end

    [resp, api_key]
  end

  private

  def self.execute_request(opts)
    RestClient::Request.execute(opts)
  end

  def self.handle_api_error(rcode, rbody)
    case rcode
    when 402
      raise APIResponseCodeError.new('Invalid JSON/XML. Malformed JSON/XML syntax.', rcode, rbody)
    when 403
      raise APIResponseCodeError.new('Permission denied.', rcode, rbody)
    when 420
      raise APIResponseCodeError.new('Internal Error. There was an error in the system.', rcode, rbody)
    when 421
      raise APIResponseCodeError.new('Input Parameter Error.', rcode, rbody)
    when 423
      raise APIResponseCodeError.new('API key does not exist.', rcode, rbody)
    when 424
      raise APIResponseCodeError.new('Account disabled.', rcode, rbody)
    when 426
      raise APIResponseCodeError.new('Domain has been disabled.', rcode, rbody)
    when 427
      raise APIResponseCodeError.new('The domain is not registered with Email Yak.', rcode, rbody)
    when 428
      raise APIResponseCodeError.new('The requested record is not found.', rcode, rbody)
    when 430
      raise APIResponseCodeError.new('Account not allowed access to requested version of API.', rcode, rbody)
    when 431
      raise APIResponseCodeError.new('Invalid Response Format. In the url, specify ../json/.. or ../xml/..', rcode, rbody)
    when 432
      raise APIResponseCodeError.new('Invalid when 431(Request Format. Needs to be JSON or XML.', rcode, rbody)
    when 503
      raise APIResponseCodeError.new('Service is Temporarily Down. Please stand by.', rcode, rbody)
    else
      raise APIResponseCodeError.new("Unrecognized return code #{rcode}", rcode, rbody)
    end
  end

  def self.handle_restclient_error(e)
    case e
    when RestClient::ServerBrokeConnection, RestClient::RequestTimeout
      message = "Could not connect to EmailYak (#{@@api_base}).  Please check your internet connection and try again."
    when RestClient::SSLCertificateNotVerified
      message = "Could not verify EmailYak's SSL certificate.  Please make sure that your network is not intercepting certificates."
    when SocketError
      message = "Unexpected error communicating when trying to connect to EmailYak.  HINT: You may be seeing this message because your DNS is not working.  To check, try running 'host emailyak.com' from the command line."
    else
      message = "Unexpected error communicating with EmailYak."
    end
    message += "\n\n(Network error: #{e.message})"
    raise APIConnectionError.new(message)
  end
end
