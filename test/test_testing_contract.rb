# frozen_string_literal: true

require "test_helper"
require "invoicehn/testing"

# Invoicehn::Testing is what a host application runs against its own
# store/sequence/ledger adapters. It is proven here against the bundled
# implementations, and against broken ones it must catch.
class TestTestingContract < Minitest::Test
  T = Invoicehn::Testing

  def with_setup
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      store.add_authorization(build_authorization)
      yield config, store, Invoicehn::Sequence.new(config), Invoicehn::Ledger::JsonlLedger.new(config)
    end
  end

  def test_bundled_implementations_satisfy_the_interfaces
    with_setup do |_config, store, sequence, ledger|
      assert T.assert_store_contract(store)
      assert T.assert_sequence_contract(sequence)
      assert T.assert_ledger_contract(ledger)
    end
  end

  def test_bundled_implementations_pass_the_round_trip
    with_setup do |_config, store, sequence, ledger|
      document = T.assert_issuance_round_trip(store: store, sequence: sequence, ledger: ledger)

      assert_equal "000-001-01-00000001", document.correlative.to_s
    end
  end

  # A 0.1.0-era store lacks delete_document.
  def test_missing_method_is_reported
    store = Object.new
    def store.issuer = nil

    error = assert_raises(T::ContractError) { T.assert_store_contract(store) }

    assert_includes error.message, "#delete_document"
    assert_includes error.message, "#active_authorization"
  end

  def test_wrong_keywords_are_reported
    store = Invoicehn::Storage::JsonStore.new(Invoicehn::Config.new(home: Dir.tmpdir))
    def store.active_authorization(identifier) = identifier

    error = assert_raises(T::ContractError) { T.assert_store_contract(store) }

    assert_includes error.message, "next_sequence:"
  end

  def test_a_store_that_cannot_delete_fails_the_round_trip
    with_setup do |_config, store, sequence, ledger|
      def store.delete_document(document) = document

      error = assert_raises(T::ContractError) do
        T.assert_issuance_round_trip(store: store, sequence: sequence, ledger: ledger)
      end

      assert_includes error.message, "quedó guardado"
    end
  end

  # A sequence that commits the counter before running the block.
  class EagerSequence < Invoicehn::Sequence
    def allocate(identifier)
      correlative = peek(identifier)
      align_to(Invoicehn::Authorization.new(cai: "x", range_start: correlative.succ, range_end: correlative.succ,
                                            limit_date: Date.today))
      yield correlative
    end
  end

  def test_a_sequence_that_advances_on_failure_fails_the_round_trip
    with_setup do |config, store, _sequence, ledger|
      error = assert_raises(T::ContractError) do
        T.assert_issuance_round_trip(store: store, sequence: EagerSequence.new(config), ledger: ledger)
      end

      assert_includes error.message, "el contador avanzó"
    end
  end
end
