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

    def get(key : String, default = nil)
      @message.fetch(key, default)
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
    alias EventWhileFn = Event -> Bool
    @events_while = Hash(String, EventWhileFn).new
    @events_while_stop = Hash(String, Channel(Bool)).new

    def pull_events(&)
      loop do
        pdu = read_next_pdu()

        @events_while.each do |key, check_fn|
          if !check_fn.call(pdu)
            @events_while_stop[key].send(true)
            @events_while.delete(key)
          end
        end
        yield pdu
      end
    end

    def request(action, timeout = 5.seconds) : Array(Event)
      uid = UUID.v4.hexstring
      as_list = false
      events = [] of Event

      @events_while_stop[uid] = Channel(Bool).new(1)
      @events_while[uid] = event_while_fn do |ev|
        if ev.get("EventList", "").downcase == "start"
          as_list = true
        end

        if as_list && ev.get("ActionID", "") == action.action_id && ev.get("EventList", "").downcase == "complete"
          events << ev
          false
        elsif !as_list && ev.get("ActionID", "") == action.action_id
          events << ev
          false
        elsif ev.get("ActionID", "") == action.action_id
          events << ev
          true
        else
          true
        end
      end

      send(action.as_s)

      wait_events_while(uid, timeout)

      events
    end

    private def event_while_fn(&block : EventWhileFn) : EventWhileFn
      block
    end

    private def wait_events_while(uid, timeout = 5.seconds)
      loop do
        select
        when r = @events_while_stop[uid].receive
          @events_while_stop.delete(uid)
          return
        when timeout timeout
          raise "timeout"
        end
      rescue Channel::ClosedError
        @events_while.delete(uid)
        return
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
