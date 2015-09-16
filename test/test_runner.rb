require 'thread'
require 'test/unit'
require 'event_core'

class TestThread < Test::Unit::TestCase

  def setup
    @loop = EventCore::MainLoop.new
  end

  def teardown
    @loop = nil
  end

  def test_fiber1
    count = 0
    @loop.add_fiber {
      count += 2
      @loop.yield
      count += 3
      @loop.yield
      count += 5
      @loop.add_once { @loop.quit }
    }

    @loop.run

    assert_equal 10, count
  end

  def test_fiber_subtask
    count = 0
    @loop.add_fiber {
      count += 2
      @loop.yield
      count += @loop.yield {|task| task.done(3)}
      @loop.yield
      count += 5
      @loop.add_once { @loop.quit }
    }

    @loop.run

    assert_equal 10, count
  end

  # Here we do a long running blocking task in a thread outside the main loop.
  # We assert that the loops spins a timer while waiting for the blocking thread.
  def test_fiber_subtask_slow
    timer_count = 0
    fiber_count = 0

    @loop.add_timeout(0.1) { timer_count += 1 }

    @loop.add_fiber {
      fiber_count += 2
      @loop.yield
      fiber_count += @loop.yield_from_thread { sleep 3; 11 }
      @loop.yield
      fiber_count += 5
      @loop.add_once { @loop.quit }
    }

    @loop.run

    assert_equal 18, fiber_count
    assert(timer_count > 25)
  end
  
  def test_fiber_many
    num_fibers = 100
    all_datas = []
    (0..num_fibers-1).each do |i|
      fiber_data = []
      all_datas << fiber_data
      @loop.add_fiber {
        fiber_data << (i)
        @loop.yield
        fiber_data << (i * 2)

        # Also test that we can end the fiber with an async yield
        @loop.yield {|task| fiber_data << (i * 3); task.done }
      }
    end
    
    @loop.add_once(1.0) { @loop.quit }
    @loop.run

    assert_equal num_fibers, all_datas.length

    all_datas.each_with_index do |fiber_data, i|
      assert_equal [i, i*2, i*3], fiber_data
    end
  end

  # Asserts that fibers can be created from other threads.
  def test_off_thread_creation
    counter = 0
    @loop.add_once {
      Thread.new {
        @loop.add_fiber {
          counter += 3
          @loop.yield
          counter += 5
          counter += @loop.yield { |task| task.done(7) }
          counter += @loop.yield_from_thread {
            sleep 0.1
            @loop.add_once(0.2) { @loop.quit }
            11
          }
        }
      }
    }

    @loop.run

    assert_equal 26, counter
  end

end