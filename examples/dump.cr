require "option_parser"
require "uri"
require "uuid"
require "json"
require "../src/asterisk-ami"

connection_uri = nil

OptionParser.parse do |parser|
  parser.on("-u URI", "--uri URI", "example: asterisk://demo:demo@localhost:5038/") { |val| connection_uri = URI.parse(val) }
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

events = Channel(Asterisk::Event).new(1024*16)
spawn name: "asterisk events reader" do
  conn.pull_events do |event|
    events.send(event)
  end
rescue ex
  STDERR.puts ex.inspect_with_backtrace
  exit 1
end

# example action and wait for response
puts conn.request(Asterisk::Action.new(
  "Ping",
  UUID.v4.hexstring
)
).inspect

loop do
  event = events.receive
  if event.get("Event") == "Shutdown"
    STDERR.puts "asterisk shutdown"
    exit 1
  end

  puts event.message.to_json
end
