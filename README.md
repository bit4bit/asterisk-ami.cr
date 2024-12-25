# asterisk-ami

TODO: Write a description here

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     asterisk-ami:
       github: your-github-user/asterisk-ami
   ```

2. Run `shards install`

## Usage

```crystal
require "asterisk-ami"
```

```crystal
conn = Asterisk::Inbound.new("localhost", 5038, "demo", "demo")
if !conn.connect(1.second)
  raise "fails authenticate to #{host}"
end

events = Channel(Asterisk::Event).new(1024*16)
spawn name: "asterisk events" do
  conn.pull_events do |event|
    events.send(event)
  end
rescue ex
  STDERR.puts ex.inspect_with_backtrace
  exit 1
end

loop do
  event = events.receive
  if event.get("Event") == "Shutdown"
    STDERR.puts "asterisk shutdown"
    exit 1
  end
  yield event.message.to_json
end
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/your-github-user/asterisk-ami/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jovany Leandro G.C](https://github.com/your-github-user) - creator and maintainer