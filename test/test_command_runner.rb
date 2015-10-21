require 'test/unit'
require 'command_runner'

class TestCommandRunner < Test::Unit::TestCase

  def test_shell_echo
    result = CommandRunner.run('echo hello')
    assert_equal "hello\n", result[:out]
    assert_equal 0, result[:status].exitstatus
  end

  def test_shell_echo_environment_variable
    result = CommandRunner.run('echo hello $MESSAGE', environment: {'MESSAGE' => 'world'})
    assert_equal "hello world\n", result[:out]
    assert_equal 0, result[:status].exitstatus
  end

  def test_no_shell_echo
    result = CommandRunner.run(['echo', 'hello'])
    assert_equal "hello\n", result[:out]
    assert_equal 0, result[:status].exitstatus
  end

  def test_shell_echo_sleep_timeout
    result = CommandRunner.run('echo hello && sleep 5', timeout: 2)
    assert_equal "hello\n", result[:out]
    assert_equal 9, result[:status].termsig
  end

  def test_shell_echo_sleep_timeout_term
    result = CommandRunner.run('echo hello && sleep 5', {:timeout => {2 => 'TERM'}})
    assert_equal "hello\n", result[:out]
    assert_equal Signal.list['TERM'], result[:status].termsig
  end

  def test_shell_timeout_before_echo
    result = CommandRunner.run('sleep 5; echo hello', {:timeout => {2 => 'TERM'}})
    assert_equal "", result[:out]
    assert_equal Signal.list['TERM'], result[:status].termsig
  end

  def test_no_shell_timeout_procs_in_order
    proc_callbacks = []

    result = CommandRunner.run(['sleep', '10'], {:timeout => {
                                   6 => Proc.new { proc_callbacks << 'proc6' },
                                   1 => Proc.new { proc_callbacks << 'proc1' },
                                   3 => Proc.new { proc_callbacks << 'proc3' },
                                   5 => 'KILL',
                                   2 => Proc.new { proc_callbacks << 'proc2' },
                                      }})
    assert_equal "", result[:out]
    assert_equal 9, result[:status].termsig
    assert_equal ['proc1', 'proc2', 'proc3'], proc_callbacks
  end

  def test_no_shell_raising_action
    proc_callbacks = []

    begin
      CommandRunner.run("echo hello; sleep 10; echo world", {:timeout => {
                                                              1 => Proc.new { proc_callbacks << 'proc1' },
                                                              3 => Proc.new { proc_callbacks << 'proc3' },
                                                              2 => Proc.new { raise "KillMeNow" },
                                                          }})
      fail "Previous command should raise"
    rescue => e
      # Expected
      assert_equal "KillMeNow", e.message
    end
  end

  def test_shell_no_stdout_preemption
    result = CommandRunner.run('echo hello; sleep 2; echo world; sleep 2; echo OMG',
      {:timeout => {
          1 => Proc.new {|pid|  },
          3 => 'KILL'
      }})

    assert_equal "hello\nworld\n", result[:out]
    assert_equal 9, result[:status].termsig
  end

  def test_shell_with_background_subshell
    result = CommandRunner.run('echo hello && (sleep 10 && echo world) &',
                               {:timeout => 2})

    assert_equal "hello\n", result[:out]
    assert_equal 0, result[:status].exitstatus
  end

  def test_shell_stdout_to_null
    result = CommandRunner.run('echo hello > /dev/null',
                               {:timeout => 2})

    assert_equal "", result[:out]
    assert_equal 0, result[:status].exitstatus
  end

  def test_shell_stdout_err_to_null
    result = CommandRunner.run('echo hello > /dev/null 2>&1',
                               {:timeout => 2})

    assert_equal "", result[:out]
    assert_equal 0, result[:status].exitstatus
  end

  def test_multi_string_convenience
    result = CommandRunner.run('ls', '-r', 'test')

    assert result[:out].start_with? "test_command_runner_create.rb", "Unexpected output: #{result[:out]}"
    assert_equal 0, result[:status].exitstatus
  end

  # Test disabled as it requires thin.
  # Most perculiar behaviour have been observed when backgrounding thin through a subshell.
  # Note that correct usage would be to daemonize it with -d.
  # The intermidiate shell dies immediately, but stdout is never closed. Presumably thin
  # inherits it, and we never get an EOF in CommandRunnerNG.
  # Requires two files 'config.ru' and 'app.rb' to run (as well as thin and sinatra gems):
  #
  # # config.ru
  # require './app'
  # run HelloWorldApp
  #
  # # app.rb
  # require 'sinatra'
  #
  # class HelloWorldApp < Sinatra::Base
  #  get '/' do
  #    "Hello, world!"
  #  end
  # end
  #
  #def test_thin_background
  #  result = CommandRunner.run('thin start &',
  #                             timeout: 5)
  #
  #  assert_equal 0, result[:status].exitstatus
  #end


end
