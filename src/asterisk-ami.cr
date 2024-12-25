require "socket"
require "uuid"

class Asterisk
  alias Header = Hash(String, String)

  class Action
    def initialize(@action : String, @action_id : String, @header : Header, @variables = Header.new())
    end

    def as_s
      String::Builder.build do |msg|
        msg << "Action: #{@action}\n"
        msg << "ActionId: #{@action_id}\n"
        @header.each do |key, value|
          msg << "#{key}: #{value}\n"
        end
        @variables.each do |key, value|
          msg << "Variable: #{key}=#{value}\n"
        end
        msg << "\n"
      end
    end
  end
  
  class Event
    @message = Header.new()

    getter :message
    
    def initialize(@message : Header)
    end

    def get(key : String)
      @message[key]
    end

    def self.from(raw : String) : Event
      header = Header.new()

      raw.split(/(\r\n|\n)/, limit: nil, remove_empty: true)
        .reject {|v| v =~ /\r\n|\n/ }
        .each { |v|
        elems = v.split(/: /, limit: 2)
        case elems.size
        when 1
          header[elems[0]] = ""
        when 2
          header[elems[0]] = elems[1]
        end
      }

      Event.new(message: header)
    end
  end

  class Ami::Inbound
    def initialize(@host : String, @port : Int32, @username : String, @secret : String)
    end

    private def conn
      @socket.not_nil!
    end

    def connect(timeout : Time::Span = 5.seconds)
      # TODO: how to close connection if server restart the port?
      @socket = TCPSocket.new(@host, @port, connect_timeout: timeout, blocking: false)

      if !conn.gets.not_nil!.includes?("Asterisk")
        puts "error not asterisk"
        return false
      end
      conn.read_timeout = 30.seconds
      conn.write_timeout = 1.seconds

      action = Asterisk::Action.new(
                    "Login",
                    UUID.v4().hexstring,
                    Hash{"Username" => @username,
                         "Secret" => @secret,
                         "AuthType" => "plain",
                         "Events" => "on"}).as_s
      send(action)

      read_next_pdu().get("Response") == "Success"
    end
    
    def events
      Channel(Event).new(1024*16)
    end

    def pull_events
      loop do
        yield read_next_pdu()
      end
    end

    private def send(action)
      conn.write(action.encode("utf-8"))
    end

    private def read_next_pdu()
      message = Header.new()
      loop do
        conn.each_line(chomp: true) do |line|
          break if line == ""
          key, value = line.split(": ", 2)
          message[key] = value.strip
        end
        break if message.size > 0
      end

      Asterisk::Event.new(message: message)
    end
  end
end
