require "readline"
require "shellwords"
require "warden/client"
require "yajl"

module Warden
  class Repl

    COMMAND_LIST = ['ping', 'create', 'stop', 'destroy', 'spawn', 'link',
                    'run', 'net', 'limit', 'info', 'list','help']

    HELP_MESSAGE =<<-EOT
ping                          - ping warden
create                        - create new container
destroy <handle>              - shutdown container <handle>
stop <handle>                 - stop all processes in <handle>
spawn <handle> cmd            - spawns cmd inside container <handle>, returns #jobid
link <handle> #jobid          - do blocking read on results from #jobid
run <handle>  cmd             - short hand for link(spawn(cmd)) i.e. runs cmd, blocks for result
list                          - list containers
info <handle>                 - show metadata for container <handle>
limit <handle> mem  [<value>] - set or get the memory limit for the container (in bytes)
limit <handle> disk [<value>] - set or get the disk limit for the container (in 1k blocks)
net <handle> #in              - forward port #in on external interface to container <handle>
net <handle> #out <address[/mask][:port]> - allow traffic from the container <handle> to address <address>
help                          - show help message
Please see README.md for more details.
EOT

    def initialize(opts={})
      @warden_socket_path = opts[:warden_socket_path] || "/tmp/warden.sock"
      @client = Warden::Client.new(@warden_socket_path)
      @history_path = opts[:history_path] || File.join(ENV['HOME'], '.warden-history')
    end

    def run
      restore_history

      @client.connect unless @client.connected?

      comp = proc { |s|
        if s[0] == '0'
          container_list.grep( /^#{Regexp.escape(s)}/ )
        else
          COMMAND_LIST.grep( /^#{Regexp.escape(s)}/ )
        end
      }

      Readline.completion_append_character = " "
      Readline.completion_proc = comp

      while line = Readline.readline('warden> ', true)
        if process_line(line)
          save_history
        end
      end
    end

    private

    def container_list
      @client.write(['list'])
      Yajl::Parser.parse(@client.read.inspect)
    end

    def save_history
      marshalled = Yajl::Encoder.encode(Readline::HISTORY.to_a)
      open(@history_path, 'w+') {|f| f.write(marshalled)}
    end

    def restore_history
      return unless File.exists? @history_path
      open(@history_path, 'r') do |file|
        history = Yajl::Parser.parse(file.read)
        history.map {|line| Readline::HISTORY.push line}
      end
    end

    def process_line(line)
      words = Shellwords.shellwords(line)
      return false if words.empty?

      #coalesce shell commands into a single string
      if ['run','spawn'].member? words[0]
        if words.size > 3
          tail = words.slice!(2..-1)
          words.push(tail.join(' '))
        end
      end

      if words[0] == 'help'
        puts HELP_MESSAGE
        return true
      end

      @client.write(words)
      begin
        puts @client.read.inspect
      rescue  => e
        if e.message.match('unknown command')
          puts "#{e.message}, try help for assistance."
        else
          puts e.message
        end
      end

      true
    end

  end
end