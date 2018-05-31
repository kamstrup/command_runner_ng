require 'test/unit'
require 'command_runner'

class TestCommandRunner < Test::Unit::TestCase

  def test_ls_no_args
    ls = CommandRunner.create(['ls'])
    result = ls.run

    assert_equal 0, result[:status].exitstatus
    assert result[:out].include? "LICENSE.txt"
  end


  def test_ls_with_args
    ls = CommandRunner.create(['ls', '-lort'], allowed_sub_commands: ['/tmp', 'test'])

    # Without boxing args
    result = ls.run('test')
    assert_equal 0, result[:status].exitstatus
    assert result[:out].include? "test_command_runner_create.rb"

    # With boxed arg
    result = ls.run(['test'])
    assert_equal 0, result[:status].exitstatus
    assert result[:out].include? "test_command_runner_create.rb"

    result = ls.run('/tmp')
    assert_equal 0, result[:status].exitstatus

    begin
      result = ls.run('lib')
      raise "Listing lib should not be allowed"
    rescue => e
      # good. lib is not in allowed_sub_commands
    end
  end

  def test_ls_with_symbl_sub_cmd
    ls = CommandRunner.create(['ls', '-lort'], allowed_sub_commands: [:test, :lib])

    result = ls.run(:test)
    assert_equal 0, result[:status].exitstatus
    assert result[:out].include? "test_command_runner_create.rb"

    result = ls.run(:lib)
    assert_equal 0, result[:status].exitstatus

    begin
      result = ls.run('test')
      raise "Listing 'test' should should require symbol, not string"
    rescue => e
      # good. 'test' string not allowed, only :test
    end
  end

  def test_with_defaults
    slep = CommandRunner.create(['sleep'], timeout: 3)

    start_time = Time.now
    result = slep.run(10)
    assert (Time.now - start_time) < 4 && (Time.now - start_time) > 2
    assert_equal 9, result[:status].termsig

    start_time = Time.now
    result = slep.run(10, timeout: 1)
    assert (Time.now - start_time) < 2
    assert_equal 9, result[:status].termsig
  end

  def test_env
    bash = CommandRunner.create(['ruby', '-e'], environment: {'TEHVAL' => 'world'})

    result = bash.run('puts "hello " + ENV["TEHVAL"]')
    assert_equal "hello world\n", result[:out]
    assert_equal 0, result[:status].exitstatus


    result = bash.run('puts "hello " + ENV["TEHVAL"]', environment: {'TEHVAL' => 'mundo'})
    assert_equal 0, result[:status].exitstatus
    assert_equal "hello mundo\n", result[:out]
  end

  def test_debug_log
    rd, wr = IO.pipe
    ls = CommandRunner.create(['ls'], debug_log: wr)

    result = ls.run('test')
    wr.close
    assert_equal "CommandRunnerNG spawn: args=[[\"ls\", \"test\"]], timeout=, encoding=, options: {:err=>[:child, :out]}, PID: #{result[:pid]}\nCommandRunnerNG exit: PID: #{result[:pid]}, code: 0\n", rd.read
  ensure
    rd.close
  end

  def test_split_stderr
    rb = CommandRunner.create(['ruby', '-e'], split_stderr: true)
    result = rb.run('puts "OUT"; $stderr.puts "ERR"')

    assert_equal "OUT\n", result[:out]
    assert_equal "ERR\n", result[:err]
  end
end