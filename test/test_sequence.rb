# frozen_string_literal: true

require "test_helper"

# Art. 10 num. 7 lit. d — the correlative "deberá iniciarse en uno (00000001)"
# and advances without gaps. Two processes issuing at once must not land on the
# same number or skip one.
class TestSequence < Minitest::Test
  def with_sequence
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      yield Invoicehn::Sequence.new(config), config
    end
  end

  def test_the_first_number_is_one
    with_sequence do |seq|
      assert_equal "000-001-01-00000001", seq.peek("000-001-01").to_s
      assert_equal 0, seq.issued_count("000-001-01")
    end
  end

  def test_peek_does_not_consume
    with_sequence do |seq|
      3.times { assert_equal "000-001-01-00000001", seq.peek("000-001-01").to_s }
      assert_equal 0, seq.issued_count("000-001-01")
    end
  end

  def test_allocation_advances_without_gaps
    with_sequence do |seq|
      numbers = Array.new(5) { seq.allocate("000-001-01").to_s }

      assert_equal %w[
        000-001-01-00000001 000-001-01-00000002 000-001-01-00000003
        000-001-01-00000004 000-001-01-00000005
      ], numbers
      assert_equal 5, seq.issued_count("000-001-01")
    end
  end

  # SAR authorizes a range per emission point and document type, so each
  # identifier runs its own series.
  def test_each_identifier_runs_an_independent_series
    with_sequence do |seq|
      assert_equal "000-001-01-00000001", seq.allocate("000-001-01").to_s
      assert_equal "000-002-01-00000001", seq.allocate("000-002-01").to_s
      assert_equal "003-001-01-00000001", seq.allocate("003-001-01").to_s
      assert_equal "000-001-01-00000002", seq.allocate("000-001-01").to_s
    end
  end

  # The block runs inside the lock: if it raises, the number is not consumed, so
  # a failure cannot burn a correlativo without producing a document.
  def test_a_failing_block_does_not_consume_the_number
    with_sequence do |seq|
      assert_raises(RuntimeError) do
        seq.allocate("000-001-01") { raise "fallo al guardar" }
      end

      assert_equal 0, seq.issued_count("000-001-01")
      assert_equal "000-001-01-00000001", seq.peek("000-001-01").to_s
    end
  end

  def test_the_block_result_is_returned
    with_sequence do |seq|
      result = seq.allocate("000-001-01") { |c| "factura #{c}" }

      assert_equal "factura 000-001-01-00000001", result
      assert_equal 1, seq.issued_count("000-001-01")
    end
  end

  # A successor range that continues the numbering rather than restarting it.
  def test_align_to_moves_the_counter_up_to_a_successor_range
    with_sequence do |seq|
      auth = build_authorization(range_start: "000-001-01-00000501",
                                 range_end: "000-001-01-00001000")
      seq.align_to(auth)

      assert_equal "000-001-01-00000501", seq.peek("000-001-01").to_s
    end
  end

  def test_align_to_never_moves_the_counter_backwards
    with_sequence do |seq|
      10.times { seq.allocate("000-001-01") }
      seq.align_to(build_authorization(range_start: "000-001-01-00000001",
                                       range_end: "000-001-01-00000500"))

      assert_equal 10, seq.issued_count("000-001-01")
    end
  end

  def test_rejects_a_malformed_identifier
    with_sequence do |seq|
      assert_raises(Invoicehn::ValidationError) { seq.peek("000-001") }
    end
  end

  # The reason allocation holds an exclusive lock. Concurrent issuers must
  # produce a contiguous run with no duplicates and no holes.
  def test_concurrent_processes_produce_a_contiguous_run
    skip "fork no disponible en esta plataforma" unless Process.respond_to?(:fork)

    with_sequence do |_seq, config|
      workers = 8
      per_worker = 6
      readers = []

      workers.times do
        reader, writer = IO.pipe
        readers << reader

        Process.fork do
          reader.close
          # A fresh Sequence per process, as separate CLI invocations would have.
          seq = Invoicehn::Sequence.new(config)
          per_worker.times { writer.puts(seq.allocate("000-001-01").to_s) }
          writer.close
          exit!(0)
        end

        writer.close
      end

      Process.waitall
      numbers = readers.flat_map { |r| r.read.split("\n") }.tap { readers.each(&:close) }

      assert_equal workers * per_worker, numbers.size, "se perdieron asignaciones"
      assert_equal numbers.size, numbers.uniq.size, "se asignó el mismo correlativo dos veces"

      sequences = numbers.map { |n| Invoicehn::Correlative.parse(n).sequence }.sort

      assert_equal((1..(workers * per_worker)).to_a, sequences, "la serie tiene huecos")
    end
  end
end
