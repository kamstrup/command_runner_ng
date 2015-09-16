Command Runner NG, for Ruby
==============================================
Travis CI Status: ![Travis CI Build Status](https://travis-ci.org/kamstrup/command_runner_ng.svg?branch=master)

Provides advanced, but easy, control for subprocesses and shell commands. 

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
    2 = Proc.new {|pid| puts "PID #{pid} getting SIGKILL in 3s"}
})
```