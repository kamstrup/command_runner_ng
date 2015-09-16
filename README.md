Command Runner NG, for Ruby
==============================================
Travis CI Status: ![Travis CI Build Status](https://travis-ci.org/kamstrup/command_runner_ng.svg?branch=master)

Provides advanced, but easy, control for subprocesses and shell commands in Ruby.

Features:

 * Run a command with a set of timeout rules

Examples
--------
The following are equivalent:

```rb
require 'command_runner'

CommandRunner.run('sleep 10', timeout: 5) # Spawns a subshell
CommandRunner.run(['sleep', '10'], timeout: 5) # No subshell in this one and the rest
CommandRunner.run(['sleep', '10'], timeout: {5 => 'KILL'})
CommandRunner.run(['sleep', '10'], timeout: {5 => Proc.new { |pid| Process.kill('KILL', pid)}})
CommandRunner.run(['sleep', '10'], timeout: {
    5 => 'KILL',
    2 => Proc.new {|pid| puts "Sending SIGKILL to PID #{pid} in 3s"}
})
```

Inspecting the output - observe that 'world' never gets printed:
```rb
require 'command_runner'
result = CommandRunner.run('echo hello; sleep 10; echo world', timeout: 3)
puts result
=> {:out=>"hello\n", :status=>#<Process::Status: pid 13205 SIGKILL (signal 9)>}
```

Why?
----
We have used too many subtly broken approaches to handling child processes in many different projects. In particular
wrt timeouts, but also other issues.
There are numerous examples scattered around StackExchange and pastebins that are also subtly broken. This
project tries to collect the pieces and provide a simple Bug Free (TM) API for doing the common tasks that are
not straight forward on the bare Ruby Process API.