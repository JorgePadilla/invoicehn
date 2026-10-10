# frozen_string_literal: true

require "invoicehn" unless defined?(Invoicehn::Issuance)
require "invoicehn/testing"

module Invoicehn
  # Minitest modules a host application includes to run the store, sequence
  # and ledger contracts against its own adapters:
  #
  #   require "invoicehn/test_support/contracts"
  #
  #   class PostgresStoreContractTest < ActiveSupport::TestCase
  #     include Invoicehn::TestSupport::StoreContract
  #
  #     # A store holding a complete issuer and a current authorization for
  #     # contract_identifier ("000-001-01" unless overridden).
  #     def contract_store = Facturacion::InvoicehnStore.new
  #   end
  #
  #   class PostgresSequenceContractTest < ActiveSupport::TestCase
  #     include Invoicehn::TestSupport::SequenceContract
  #     def contract_sequence = Facturacion::InvoicehnSequence.new
  #   end
  #
  #   class LedgerContractTest < ActiveSupport::TestCase
  #     include Invoicehn::TestSupport::LedgerContract
  #     def contract_ledger = Facturacion::InvoicehnLedger.new
  #   end
  #
  #   class IssuanceContractTest < ActiveSupport::TestCase
  #     include Invoicehn::TestSupport::IssuanceContract
  #     def contract_store = Facturacion::InvoicehnStore.new
  #     def contract_sequence = Facturacion::InvoicehnSequence.new
  #     def contract_ledger = Facturacion::InvoicehnLedger.new
  #   end
  #
  # The modules write documents; run them against a test database. They use
  # only Minitest's assertions (assert, assert_equal, assert_raises, ...).
  module TestSupport
    # Fixed sample data, independent of the host's records.
    module Samples
      def contract_identifier = Issuance::DEFAULT_IDENTIFIER

      def contract_sample_issuer
        Issuer.new(rtn: "08011990123456", legal_name: "Contrato, S. de R.L.", trade_name: "Contrato",
                   headquarters_address: "Tegucigalpa, M.D.C.", phone: "2222-3333", email: "contrato@ejemplo.hn")
      end

      def contract_sample_lines
        [LineItem.new(description: "Prueba de contrato", quantity: 2, unit_price: Money.new("50.00"),
                      treatment: :gravado_15)]
      end

      # A document numbered at the last number of `authorization`'s range, so
      # it does not collide with the next number the host would issue.
      def contract_sample_document(authorization:, issuer: contract_sample_issuer, **extra)
        Invoice.new(correlative: authorization.range_end, issuer: issuer,
                    customer: Customer::Taxpayer.new(name: "Cliente de Contrato, S.A.", rtn: "05019005123456"),
                    authorization: authorization, line_items: contract_sample_lines,
                    issue_date: Invoicehn.today, **extra)
      end
    end

    # Requires #contract_store.
    module StoreContract
      include Samples

      def contract_authorization(store = contract_store)
        auth = store.active_authorization(contract_identifier, next_sequence: nil, on: Invoicehn.today)
        assert auth, "contract_store debe tener una autorización vigente para #{contract_identifier}"
        auth
      end

      def test_store_contract_interface
        assert Testing.assert_store_contract(contract_store)
      end

      def test_store_contract_issuer_is_complete
        issuer = contract_store.issuer

        assert_kind_of Issuer, issuer
        assert_empty issuer.missing_fields
      end

      def test_store_contract_active_authorization_covers_the_number
        store = contract_store
        auth = contract_authorization(store)

        first = store.active_authorization(contract_identifier, next_sequence: auth.range_start.sequence,
                                                                on: Invoicehn.today)

        assert_equal auth.to_h, first.to_h
        beyond = auth.range_end.sequence + 1
        covering = store.active_authorization(contract_identifier, next_sequence: beyond, on: Invoicehn.today)

        assert(covering.nil? || covering.covers?(auth.range_end.with_sequence(beyond)),
               "active_authorization devolvió una autorización que no cubre #{beyond}")
        assert_nil store.active_authorization(contract_identifier, next_sequence: auth.range_start.sequence,
                                                                   on: auth.limit_date + 1)
      end

      def test_store_contract_round_trips_save_find_delete
        store = contract_store
        document = contract_sample_document(authorization: contract_authorization(store))

        refute store.exists?(document.correlative)
        store.save_document(document)

        assert store.exists?(document.correlative)
        assert_equal document.to_h, store.find(document.correlative).to_h
        assert_raises(ImmutableDocument) { store.save_document(document) }

        store.delete_document(document)

        refute store.exists?(document.correlative)
        assert_raises(DocumentNotFound) { store.find(document.correlative) }
      end

      # Art. 41 — the annulled form replaces the record; the number stays.
      def test_store_contract_keeps_the_annulled_form
        store = contract_store
        document = contract_sample_document(authorization: contract_authorization(store))
        store.save_document(document)
        store.save_document(document.annul(reason: "Prueba de contrato"))

        found = store.find(document.correlative)

        assert_predicate found, :annulled?
        assert_equal "Prueba de contrato", found.annulment_reason
      ensure
        store&.delete_document(document) if document
      end

      # A note's reference and motivo (Arts. 26 and 28 num. 3-4) must survive
      # the store. Runs only when the store holds an authorization for
      # contract_note_identifier.
      def test_store_contract_keeps_a_notes_reference_and_motivo
        store = contract_store
        auth = store.active_authorization(contract_note_identifier, next_sequence: nil, on: Invoicehn.today)
        skip "sin autorización para #{contract_note_identifier}" unless auth

        reference = DocumentReference.new(correlative: "#{contract_identifier}-00000001", cai: "CAI-CONTRATO",
                                          issue_date: Invoicehn.today)
        note = contract_sample_document(authorization: auth, reference: reference, motivo: "Devolución")
        store.save_document(note)
        found = store.find(note.correlative)

        assert_equal reference, found.reference
        assert_equal "Devolución", found.motivo
        assert_equal note.to_h, found.to_h
      ensure
        store&.delete_document(note) if note
      end

      def contract_note_identifier = "#{contract_identifier.split("-")[0, 2].join("-")}-06"
    end

    # Requires #contract_sequence.
    module SequenceContract
      include Samples

      def contract_other_identifier = "#{contract_identifier.split("-")[0, 2].join("-")}-07"

      def test_sequence_contract_interface
        assert Testing.assert_sequence_contract(contract_sequence)
      end

      def test_sequence_contract_peek_does_not_consume
        sequence = contract_sequence
        before = sequence.issued_count(contract_identifier)

        assert_equal sequence.peek(contract_identifier), sequence.peek(contract_identifier)
        assert_equal before + 1, sequence.peek(contract_identifier).sequence
        assert_equal before, sequence.issued_count(contract_identifier)
      end

      def test_sequence_contract_allocate_yields_the_next_number_and_advances
        sequence = contract_sequence
        expected = sequence.peek(contract_identifier)
        yielded = nil

        result = sequence.allocate(contract_identifier) do |correlative|
          yielded = correlative
          :resultado
        end

        assert_equal expected, yielded
        assert_equal :resultado, result
        assert_equal expected.sequence, sequence.issued_count(contract_identifier)
        assert_equal expected.succ, sequence.peek(contract_identifier)
      end

      # The property Issuance's all-or-nothing guarantee rests on.
      def test_sequence_contract_a_failing_block_consumes_nothing
        sequence = contract_sequence
        before = sequence.issued_count(contract_identifier)

        assert_raises(ArgumentError) { sequence.allocate(contract_identifier) { raise ArgumentError, "fallo" } }
        assert_equal before, sequence.issued_count(contract_identifier)
      end

      # Each identificador del documento runs its own series (Art. 10 num. 7).
      def test_sequence_contract_identifiers_are_independent
        sequence = contract_sequence
        other = sequence.issued_count(contract_other_identifier)
        sequence.allocate(contract_identifier) { |c| c }

        assert_equal other, sequence.issued_count(contract_other_identifier)
      end
    end

    # Requires #contract_ledger.
    module LedgerContract
      include Samples

      def contract_ledger_document
        auth = Authorization.new(cai: "CAI-CONTRATO", range_start: "#{contract_identifier}-00000001",
                                 range_end: "#{contract_identifier}-00000010", limit_date: Invoicehn.today + 30)
        contract_sample_document(authorization: auth)
      end

      def test_ledger_contract_interface
        assert Testing.assert_ledger_contract(contract_ledger)
      end

      def test_ledger_contract_records_issue_and_annulment
        ledger = contract_ledger
        document = contract_ledger_document

        ledger.record(document, event: :emision)
        ledger.record(document.annul(reason: "Prueba de contrato"), event: :anulacion)

        pass
      end
    end

    # Requires #contract_store, #contract_sequence and #contract_ledger,
    # wired to each other. Issues one real Factura.
    module IssuanceContract
      include Samples

      def test_issuance_contract_round_trip_and_rollback
        document = Testing.assert_issuance_round_trip(store: contract_store, sequence: contract_sequence,
                                                      ledger: contract_ledger, identifier: contract_identifier)

        assert_equal contract_identifier, document.correlative.identifier
      end
    end
  end
end
