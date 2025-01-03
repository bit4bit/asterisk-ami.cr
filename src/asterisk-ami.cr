require "socket"
require "uuid"

class Asterisk
  alias Header = Hash(String, String)

  class Action
    getter :action_id

    def initialize(@action : String, @action_id : String, @header = Header.new, @variables = Header.new)
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
    @message = Header.new
    @fields : Hash(String, Bool)

    getter :message

    def initialize(@message : Header, @fields : Hash(String, Bool))
    end

    def has?(field)
      @fields[field]?
    end

    def get(key : String)
      @message.fetch(key, nil)
    end

    def self.from(raw : String) : Event
      header = Header.new
      fields = Hash(String, Bool).new

      raw.split(/(\r\n|\n)/, limit: nil, remove_empty: true)
        .reject { |v| v =~ /\r\n|\n/ }
        .each { |v|
          fields[v] = true
          elems = v.split(/: /, limit: 2)
          case elems.size
          when 1
            header[elems[0]] = ""
          when 2
            header[elems[0]] = elems[1]
          end
        }

      Event.new(message: header, fields: fields)
    end
  end

  class Ami::Inbound
    def initialize(@host : String, @port : Int32, @username : String, @secret : String)
    end

    private def conn
      @socket.not_nil!
    end

    def connect(timeout : Time::Span = 5.seconds, read_timeout : Time::Span = 1.minutes)
      # TODO: how to close connection if server restart the port?
      @socket = TCPSocket.new(@host, @port, connect_timeout: timeout, blocking: false)

      if !conn.gets.not_nil!.includes?("Asterisk")
        puts "error not asterisk"
        return false
      end
      conn.read_timeout = read_timeout
      conn.write_timeout = 1.seconds

      action = Asterisk::Action.new(
        "Login",
        UUID.v4.hexstring,
        Hash{"Username" => @username,
             "Secret"   => @secret,
             "AuthType" => "plain",
             "Events"   => "on"}).as_s
      send(action)

      read_next_pdu().get("Response") == "Success"
    end

    def close
      conn.close
    end

    def events
      Channel(Event).new(1024*16)
    end

    alias EventReply = Channel(Asterisk::Event)
    @wait_for_reply = Hash(String, EventReply).new

    def pull_events
      loop do
        pdu = read_next_pdu()

        @wait_for_reply.each do |key, reply|
          if pdu.has?(key)
            reply.send(pdu)
            @wait_for_reply.delete(key)
          end
        end

        yield pdu
      end
    end

    def request(action, timeout = 5.seconds) : Event
      send(action.as_s)
      wait_for_event_key("ActionID", action.action_id, timeout)
    end

    private def wait_for_event_key(key, value, timeout)
      reply = EventReply.new
      @wait_for_reply["#{key}: #{value}"] = reply
      select
      when r = reply.receive
        r
      when timeout timeout
        raise "timeout"
      end
    end

    private def send(action : String)
      conn.write(action.encode("utf-8"))
    end

    private def read_next_pdu
      raw = ""
      issue_on_close = 0
      loop do
        conn.each_line(chomp: true) do |line|
          break if line == ""
          raw += line + "\n"
        end

        # MACHETE: force to close connection
        issue_on_close += 1
        if issue_on_close > 1024
          conn.close
          break
        end

        break if raw.size > 0
      end

      Asterisk::Event.from(raw)
    end
  end
end
