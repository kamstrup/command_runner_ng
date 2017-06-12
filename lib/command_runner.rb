module CommandRunner

  MAX_TIME = Time.new(2**63 - 1)

  DEFAULT_OPTIONS = {:err=>[:child, :out]}

  # Like IO.popen(), but block until the child completes.
  #
  # For convenience allows you to pass > 1 string args without a boxing array,
  # to execute a command with arguments without a subshell. See examples below.
  #
  # Takes an optional timeout parameter. If timeout is a
  # number the child will be killed after that many seconds
  # if it haven't completed. Alternatively it can be a Hash
  # of timeouts to actions. Each action can be a string or integer
  # specifying the signal to send, or a Proc to execute. The Proc
  # will be called with the child PID as argument.
  #
  # These examples are equivalent:
  #   run('sleep 10', timeout: 5) # With a subshell
  #   run('sleep', '10', timeout: 5) # Without subshell. Convenience API to avoid array boxing as below
  #   run(['sleep', '10'], timeout: 5) # No subshell in this one and the rest
  #   run(['sleep', '10'], timeout: {5 => 'KILL'})
  #   run(['sleep', '10'], timeout: {5 => Proc.new { |pid| Process.kill('KILL', pid)}})
  #   run(['sleep', '10'], timeout: {
  #             5 => 'KILL',
  #             2 => Proc.new {|pid| puts "PID #{pid} geting SIGKILL in 3s"}
  #   })
  #
  # Takes an optional environment parameter (a Hash). The environment is
  # populated with the keys/values of this parameter.
  #
  # Returns a Hash with :out, :pid,  and :status. :out is a string with stdout
  # and stderr merged, and :status is a Process::Status. The :pid field is the
  # the PID the child process had when it ran.
  #
  # As a special case - if an action Proc raises an exception, the child
  # will be killed with SIGKILL, cleaned up, and the exception rethrown
  # to the caller of run.
  #
  # By default stderr in the child is merged into its stdout. You can do any kind
  # of advanced stream mapping by overriding the default options hash. The options are passed to Kernel.spawn.
  # See https://ruby-doc.org/core-2.2.3/Kernel.html#method-i-spawn for details.
  #
  # Fx. redirecting stderr to /dev/null would look like:
  #    run('ls', 'nosuchfile', options: {:err => "/dev/null"})
  #
  # For simple case of splitting stderr into a buffer separate from stdout you can pass
  # the argument split_stderr: true. This will make an :err entry available in the result.
  #
  # All Kernel.spawn features, like setting umasks, process group, and are supported through the options hash.
  #
  # Debugging: To help debugging your app you can set the debug_log parameter. It can be any old object responding
  # to :puts. Fx. $stderr, $stdout, or the write end of an IO.pipe. CommandRunnerNG will put some info about
  # all process start, stop, and timeouts here. To enable debug logging for all commands call
  # CommandRunner.set_debug_log!($stderr) (or with some other object responding to :puts).
  #
  def self.run(*args, timeout: nil, environment: {}, debug_log: nil, split_stderr: false, options: DEFAULT_OPTIONS)
    if debug_log.nil?
      debug_log = @@global_debug_log
    end

    # If args is an array of strings, allow that as a shorthand for [arg1, arg2, arg3]
    if args.length > 1 && args.all? {|arg| arg.is_a? String}
      args = [args]
    end

    # This could be tweakable through vararg opts
    tick = 0.1

    now = Time.now

    # Build deadline_sequence. A list of deadlines and corresponding actions to take
    if timeout
      if timeout.is_a? Numeric
        deadline_sequence = [{:deadline => now + timeout, :action => 'KILL'}]
      elsif timeout.is_a? Hash
        deadline_sequence = timeout.collect do |t, action|
          unless action.is_a? Integer or action.is_a? String or action.is_a? Proc
              raise "Unsupported action type '#{action.class}'. Must be Integer, String, or Proc"
          end
          unless t.is_a? Numeric
            raise "Unsupported timeout value '#{t}'. Must be a Numeric"
          end
          {:deadline => now + t, :action => action}
        end.sort! { |a, b| a[:deadline] <=> b[:deadline]}
      else
        raise "Unsupported type for timeout paramter: #{timeout.class}"
      end
    else
      deadline_sequence = [{:deadline => MAX_TIME, :action => 0}]
    end

    if split_stderr
      err_r, err_w = IO.pipe
      errbuf = ""
      options = options.merge({:err => err_w})
    end

    # Spawn child, merging stderr into stdout
    io = IO.popen(environment, *args, options)
    debug_log.puts("CommandRunnerNG spawn: args=#{args}, timeout=#{timeout}, options: #{options}, PID: #{io.pid}") if debug_log.respond_to?(:puts)
    data = ""

    err_w.close if split_stderr

    # Run through all deadlines until command completes.
    # We could merge this block into the selecting block above,
    # but splitting like this saves us a Process.wait syscall per iteration.
    eof = false
    deadline_sequence.each do |point|
      while Time.now < point[:deadline]
        if Process.wait(io.pid, Process::WNOHANG)
          read_nonblock_safe!(io, data, tick)
          read_nonblock_safe!(err_r, errbuf, 0) if split_stderr
          result = {:out => data, :status => $?, pid: io.pid}
          if split_stderr
            result[:err] = errbuf
            err_r.close
          end
          debug_log.puts("CommandRunnerNG exit: PID: #{io.pid}, code: #{result[:status].exitstatus}") if debug_log.respond_to?(:puts)
          io.close
          return result
        elsif !eof
          eof = read_nonblock_safe!(io, data, tick)
          read_nonblock_safe!(err_r, errbuf, 0) if split_stderr
        end
      end

      # Deadline for this point reached. Fire the action.
      action = point[:action]
      debug_log.puts("CommandRunnerNG timeout: PID: #{io.pid}, action: #{action}") if debug_log.respond_to?(:puts)
      if action.is_a? String or action.is_a? Integer
        Process.kill(action, io.pid)
      elsif action.is_a? Proc
        begin
          action.call(io.pid)
        rescue => e
          # If the action block throws and error, clean up and rethrow
          begin
            Process.kill('KILL', io.pid)
          rescue
            # process already dead
          end
          Process.wait(io.pid)
          io.close
          raise e
        end
      else
        # Given the assertions when building the deadline_sequence this should never be reached
        raise "Internal error in CommandRunnerNG. Child may be left unattended!"
      end
    end

    # Either we didn't have a deadline, or none of the deadlines killed off the child.
    loop do
      dead = read_nonblock_safe!(io, data, tick)
      read_nonblock_safe!(err_r, errbuf, 0) if split_stderr
      break if dead
    end
    Process.wait(io.pid)

    result = {:out => data, :status => $?, pid: io.pid}
    if split_stderr
      result[:err] = errbuf
      err_r.close
    end

    debug_log.puts("CommandRunnerNG exit: PID: #{io.pid}, code: #{result[:status].exitstatus}") if debug_log.respond_to?(:puts)

    io.close

    result
  end

  # Create a helper instance to launch a command with a given configuration.
  # Invoke the command with the run() method. The configuration given to create()
  # can be overriden on each invocation of run().
  #
  # The run() method of the helper instance must be invoked with a
  #
  # Examples:
  # git = CommandRunner.create(['sudo', 'git'], timeout: 10, allowed_sub_commands: [:commit, :pull, :push])
  # git.run(:pull, 'origin', 'master')
  # git.run(:pull, 'origin', 'master', timeout: 2) # override default timeout of 10
  # git.run(:status) # will raise an error because :status is not in list of allowed commands
  def self.create(*args, timeout: nil, environment: {}, allowed_sub_commands: [], debug_log: nil, split_stderr: false, options: DEFAULT_OPTIONS)
    CommandInstance.new(args, timeout, environment, allowed_sub_commands, debug_log, split_stderr, options)
  end

  # Log all command line invocations to a logger object responding to :puts. Set to nil to disable.
  # Setting the :debug_log keyword argument on individual invocations of CommandRunner.run() overrides this value.
  def self.set_debug_log!(logger)
    if logger.respond_to?(:puts) || logger.nil?
      @@global_debug_log = logger
    else
      raise ArgumentError.new("Logger '#{logger}' not responding to :puts")
    end
  end

  private

  # Set to an object that respond to :puts to enable global debug logging for all
  @@global_debug_log = nil

  class CommandInstance

    def initialize(default_args, default_timeout, default_environment, allowed_sub_commands, debug_log, split_stderr, options)
      unless default_args.first.is_a? Array
        raise "First argument must be an array of command line args. Found #{default_args}"
      end

      @default_args = default_args
      @default_timeout = default_timeout
      @default_environment = default_environment
      @allowed_sub_commands = allowed_sub_commands
      @debug_log = debug_log
      @split_stderr = split_stderr
      @options = options
    end

    def run(*args, timeout: nil, environment: {})
      args_list = *args

      if !args_list.nil? && !args_list.empty? && args_list.first.is_a?(Array)
        if args_list.length > 1
          raise "Unsupported args list length: #{args_list.length}"
        else
          args_list = args_list.first
        end
      end

      # Check sub command if needed
      if !args_list.nil? && !args_list.empty? &&
          !@allowed_sub_commands.empty? && !@allowed_sub_commands.include?(args_list.first)
        raise "Illegal sub command '#{args_list.first}'. Expected #{allowed_sub_commands} (#{allowed_sub_commands.include?(args_list.first)})"
      end

      full_args = @default_args.dup
      full_args[0] += args_list.map {|arg| arg.to_s }
      CommandRunner.run(*full_args,
                        timeout: (timeout || @default_timeout),
                        environment: @default_environment.merge(environment),
                        debug_log: @debug_log,
                        split_stderr: @split_stderr,
                        options: @options)
    end

  end

  # Read data async, appending to data_out,
  # returning true on EOF, false otherwise
  def self.read_nonblock_safe!(io, data_out, tick)
    IO.select([io], nil, nil, tick)
    begin
      # Read all available data until EAGAIN or EOF
      loop do
        data_out << io.read_nonblock(4096)
      end
    rescue IO::WaitReadable
      # Ignore: tick time reached without io
      return false
    rescue EOFError
      # Child closed stdout (probably dead, but not necessarily)
      return true
    end
  end

end
