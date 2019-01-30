Command Runner NG, for Ruby
==============================================
Travis CI Status: ![Travis CI Build Status](https://travis-ci.org/kamstrup/command_runner_ng.svg?branch=master)

Provides advanced, but easy, control for subprocesses and shell commands in Ruby.

Features:

 * Run a command with a set of timeout rules

Usage
-----
Add the following to your Gemfile:
```rb
gem 'command_runner_ng'
```


Examples
--------
The following are equivalent:

```rb
require 'command_runner'

CommandRunner.run('sleep 10', timeout: 5) # Spawns a subshell
CommandRunner.run('sleep', '10', timeout: 5) # No subshell. Convenience API to avoid array boxing like next line:
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

If you need to run the same command again and again, or the same command with a variation of sub-commands
you can use the ```create``` method:
```rb
git = CommandRunner.create(['sudo', 'git'], timeout: 10, allowed_sub_commands: [:commit, :pull, :push])
git.run(:pull, 'origin', 'master')
git.run([:pull, 'origin', 'master'])
git.run(:pull, 'origin', 'master', timeout: 2) # override default timeout of 10
git.run(:status) # will raise an error because :status is not in list of allowed commands 
```

Redirection and Stderr Handling
-----------
By default stderr is merged into stdout. You can have it split out by passing `split_stderr: true`
to the runner. Eg:
```rb
CommandRunner.run(['ls', '/nosuchdir'], split_stderr: true) # => {out: '', err: 'ls: No such file or directory' ... }
```

If you just want to silence stderr you can override all standard Kernel.spawn options:
```rb
CommandRunner.run(['ls', '/nosuchdir'], options: {err: '/dev/null})
```

Encoding
-----------
If you need to ensure safely encoded output - you can force UTF-8 encoding by passing the :safe symbol. Eg:
```rb
require 'command_runner'
result = CommandRunner.run('echo hellò', encoding: :safe) # => {out: 'hellò\n'}
```

By default we don't apply any encoding changed to the output.

Debugging and Logging
---------
If you need insight to what commands you're running you can pass CommandRunner an object responding to ```:puts```
such as $stdout, $stderr, the writing end of an IO.pipe, or a file opened for writing. CommandRunnerNG will
log start, stop, and timeouts. Eg:

```rb
require 'command_runner'

CommandRunner.run('ls /tmp', debug_log: $stdout)
# Outputs:
# CommandRunnerNG spawn: args=["ls /tmp"], timeout=, options: {:err=>[:child, :out]}, PID: 10973
# CommandRunnerNG exit: PID: 10973, code: 0

my_log = File.open('log.txt, 'a')
CommandRunner.run('ls /tmp', debug_log: my_log) # Log appended to a file
```

Or you can enable debug logging for all command line invocations like this:
```rb
CommandRunner.set_debug_log!($stderr)
```


Why?
----
We have used too many subtly broken approaches to handling child processes in many different projects. In particular
wrt timeouts, but also other issues.
There are numerous examples scattered around StackExchange and pastebins that are also subtly broken. This
project tries to collect the pieces and provide a simple Bug Free (TM) API for doing the common tasks that are
not straight forward on the bare Ruby Process API.
