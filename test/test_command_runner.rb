require 'test/unit'
require 'command_runner'

class TestCommandRunner < Test::Unit::TestCase

  def test_shell_echo
    result = CommandRunner.run('echo hello')
    assert_equal "hello\n", result[:out]
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
    result = CommandRunner.run('echo hello && sleep 5', timeout: {2 => 'TERM'})
    assert_equal "hello\n", result[:out]
    assert_equal Signal.list['TERM'], result[:status].termsig
  end

  def test_shell_timeout_before_echo
    result = CommandRunner.run('sleep 5; echo hello', timeout: {2 => 'TERM'})
    assert_equal "", result[:out]
    assert_equal Signal.list['TERM'], result[:status].termsig
  end

  def test_no_shell_timeout_procs_in_order
    proc_callbacks = []

    result = CommandRunner.run(['sleep', '10'], timeout: {
                                   6 => Proc.new { proc_callbacks << 'proc6' },
                                   1 => Proc.new { proc_callbacks << 'proc1' },
                                   3 => Proc.new { proc_callbacks << 'proc3' },
                                   5 => 'KILL',
                                   2 => Proc.new { proc_callbacks << 'proc2' },
                                      })
    assert_equal "", result[:out]
    assert_equal Signal.list['KILL'], result[:status].termsig
    assert_equal ['proc1', 'proc2', 'proc3'], proc_callbacks
  end

  def test_no_shell_raising_action
    proc_callbacks = []

    begin
      CommandRunner.run("echo hello; sleep 10; echo world", timeout: {
                                                              1 => Proc.new { proc_callbacks << 'proc1' },
                                                              3 => Proc.new { proc_callbacks << 'proc3' },
                                                              2 => Proc.new { raise "KillMeNow" },
                                                          })
      fail "Previous command should raise"
    rescue => e
      # Expected
      assert_equal "KillMeNow", e.message
    end
  end

end