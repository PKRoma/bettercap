# encoding: UTF-8
=begin

BETTERCAP

Author : Simone 'evilsocket' Margaritelli
Email  : evilsocket@gmail.com
Blog   : http://www.evilsocket.net/

This project is released under the GPL 3 license.

=end
require 'rubydns'

module BetterCap
module Network
module Servers

# Class to wrap RubyDNS::RuleBasedServer and add some utility methods.
class DnsWrapper < RubyDNS::RuleBasedServer
  # Instantiate a server with a block.
  def initialize(options = {}, &block)
    super(options,&block)
    @rules = options[:rules]
  end
  # Give a name and a record type, try to match a rule and use it for processing the given arguments.
  def process(name, resource_class, transaction)
    Logger.debug "[#{'DNS'.green}] Received #{resource_class.name} request for #{name} ..."
    super
  end
end

# Simple DNS server class used for DNS spoofing.
class DNSD
  # Use upstream DNS for name resolution.
  UPSTREAM = RubyDNS::Resolver.new([[:udp, "8.8.8.8", 53], [:tcp, "8.8.8.8", 53]])

  # Initialize the DNS server with the specified +address+ and tcp/udp +port+.
  # The server will use the +hosts+ dictionary composed by 'regexp -> ip' entries
  # to do custom DNS spoofing/resolution.
  def initialize( hosts, address = '0.0.0.0', port = 5300 )
    @port    = port
    @address = address
    @server  = nil
    @rules   = []
    @thread  = nil
    @ifaces  = [
      [:udp, address, port],
      [:tcp, address, port]
    ]

    Logger.warn "Empty hosts file for DNS server." if hosts.empty?

    hosts.each do |exp,addr|
      block = Proc.new do |transaction|
        Logger.info "[#{transaction.options[:peer]} > #{'DNS'.green}] Received request for '#{transaction.question.to_s.yellow}', sending spoofed reply #{addr.yellow} ..."
        transaction.respond!(addr)
      end

      @rules << RubyDNS::RuleBasedServer::Rule.new( [ exp, Resolv::DNS::Resource::IN::A ], block )
    end
  end

  # Start the server.
  def start
    Logger.info "[#{'DNS'.green}] Starting on #{@address}:#{@port} ( #{@rules.size} redirection rule#{if @rules.size > 1 then 's' else '' end} ) ..."

    @thread = Thread.new {
      RubyDNS::run_server(:listen => @ifaces, :asynchronous => true, :server_class => DnsWrapper, :rules => @rules ) do
        # Suppress RubyDNS logging.
        @logger.level = ::Logger::ERROR
        # Default DNS handler
        otherwise do |transaction|
          transaction.passthrough!(UPSTREAM)
        end
      end
    }
  end

  # Stop the server.
  def stop
    Logger.info "Stopping DNS server ..."
    begin
      @thread.kill
    rescue; end
  end

  # Parse hosts from +filename+.
  def self.parse_hosts( filename )
    raise BetterCap::Error, "File '#{filename}' does not exist." unless File.exist?(filename)

    hosts = {}
    File.open(filename).each_with_index do |line,lineno|
      line = line.strip
      # skip empty lines and comments
      next if line.empty? or line[0] == '#'
      if line =~ /^([^\s]+)\s+(.+)$/
        address    = $1
        expression = $2

        if address == 'local'
          address = Context.get.ifconfig[:ip_saddr].to_s
        end

        raise BetterCap::Error, "Invalid IPv4 address '#{address}' on line #{lineno + 1} of '#{filename}'." unless Network.is_ip?(address)

        hosts[ Regexp.new(expression) ] = address
      end
    end

    hosts
  end
end

end
end
end
