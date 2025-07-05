require "option_parser"
require "uri"
require "uuid"
require "json"
require "../src/asterisk-ami"

connection_uri = nil
action = "Ping"

OptionParser.parse do |parser|
  parser.on("-u URI", "--uri URI", "example: asterisk://demo:demo@localhost:5038/") { |val| connection_uri = URI.parse(val) }
  parser.on("-a ACTION", "--action ACTION") { |val| action = val }
  parser.on("-h", "--help", "help") do
    puts parser
    exit
  end
end

conn = Asterisk::Ami::Inbound.new(
  connection_uri.not_nil!.host.not_nil!,
  connection_uri.not_nil!.port.not_nil!,
  connection_uri.not_nil!.user.not_nil!,
  connection_uri.not_nil!.password.not_nil!)
if !conn.connect(1.second)
  raise "fails authenticate to #{connection_uri}"
end

spawn do
  conn.pull_events do |ev|
  end
end

# example action and wait for response
resp = conn.request(
  Asterisk::Action.new(
    action,
    UUID.v4.hexstring
  )
)
puts "ACTION RESPONSE: #{resp.inspect}"

conn.close
