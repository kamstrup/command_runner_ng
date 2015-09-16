module CommandRunner

  MAX_TIME = Time.new(2**63 -1)

  # Like IO.popen(), but block until the child completes.
  # Takes an optional timeout parameter. If timeout is a
  # number the child will be killed after that many seconds
  # if it haven't completed. Alternatively it can be a Hash
  # of timeouts to actions. Each action can be a string or integer
  # specifying the signal to send, or a Proc to execute. The Proc
  # will be called with the child PID as argument.
  # These examples are equivalent:
  #   run('sleep 10', timeout: 5) # With a subshell
  #   run(['sleep', '10'], timeout: 5) # No subshell in this one and the rest
  #   run(['sleep', '10'], timeout: {5 => 'KILL'})
  #   run(['sleep', '10'], timeout: {5 => Proc.new { |pid| Process.kill('KILL', pid)}})
  #   run(['sleep', '10'], timeout: {
  #             5 => 'KILL',
  #             2 => Proc.new {|pid| puts "PID #{pid} getting SIGKILL in 3s"}
  #   })
  #
  # Returns a Hash with :out and :status. :out is a string with stdout
  # and stderr merged, and :status is a Process::Status.
  #
  # As a special case - if an action Proc raises an exception, the child
  # will be killed with SIGKILL, cleaned up, and the exception rethrown
  # to the caller of run.
  #
  def self.run(*args, timeout: nil)
    # These could be tweakable through vararg opts
    tick = 0.1
    bufsize = 4096

    now = Time.now

    # Build deadline_sequence. A list of deadlines and corresponding actions to take
    if timeout
      if timeout.is_a? Numeric
        deadline_sequence = [{deadline: now + timeout, action: 'KILL'}]
      elsif timeout.is_a? Hash
        deadline_sequence = timeout.collect do |t, action|
          unless action.is_a? Integer or action.is_a? String or action.is_a? Proc
              raise "Unsupported action type '#{action.class}'. Must be Integer, String, or Proc"
          end
          unless t.is_a? Numeric
            raise "Unsupported timeout value '#{t}'. Must be a Numeric"
          end
          {deadline: now + t, action: action}
        end.sort! { |a, b| a[:deadline] <=> b[:deadline]}
      else
        raise "Unsupported type for timeout paramter: #{timeout.class}"
      end
    else
      deadline_sequence = [{deadline: MAX_TIME, action: 0}]
    end

    # Spawn child, merging stderr into stdout
    io = IO.popen(*args, :err=>[:child, :out])
    data = ""

    # Wait until stdout closes
    while Time.now < deadline_sequence.first[:deadline] do
      IO.select([io], nil, nil, tick)
      begin
        data << io.read_nonblock(bufsize)
      rescue IO::WaitReadable
        # Ignore: tick time reached without io
      rescue EOFError
        # Child closed stdout (probably dead, but not necessarily)
        break
      end
    end

    # Run through all deadlines until command completes
    deadline_sequence.each do |point|
      while Time.now < point[:deadline]
        if Process.wait(io.pid, Process::WNOHANG)
          result = {out: data, status: $?}
          io.close
          return result
        else
          sleep tick
        end
      end

      # Deadline for this point reached. Fire the action.
      action = point[:action]
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

    # Either we didn't have a deadline, or none of the deadlines killed of the child.
    Process.wait(io.pid)
    result = {out: data, status: $?}
    io.close

    result
  end

end
