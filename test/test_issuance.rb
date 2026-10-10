# frozen_string_literal: true

require "test_helper"

# Issuance of the three document types, the all-or-nothing guarantee, and the
# readiness report.
class TestIssuance < Minitest::Test
  RTN_CLIENTE = "05019005123456"

  # A ledger that refuses every entry — an accounting system that is down.
  class FailingLedger < Invoicehn::Ledger
    def record(_document, event: :emision)
      raise IOError, "contabilidad fuera de línea (#{event})"
    end

    def entries(**) = []
  end

  def cliente(rtn: RTN_CLIENTE) = Invoicehn::Customer::Taxpayer.new(name: "Distribuidora del Norte, S.A.", rtn: rtn)

  def auth(type, last: 100, cai: "CAI-#{type}")
    build_authorization(range_start: "000-001-#{type}-00000001",
                        range_end: format("000-001-%<t>s-%<n>08d", t: type, n: last), cai: cai)
  end

  def with_issuance(ledger: nil, authorizations: [auth("01"), auth("06"), auth("07")])
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      authorizations.each { |a| store.add_authorization(a) }
      ledger ||= Invoicehn::Ledger::JsonlLedger.new(config)
      yield Invoicehn::Issuance.new(config: config, store: store, ledger: ledger), store, config
    end
  end

  def factura(issuance) = issuance.issue(customer: cliente, line_items: [build_line])

  # --- notes ----------------------------------------------------------------

  # Each identifier runs its own counter: Art. 25 / 27 num. 5 lit. d) start
  # the note's numbering at 00000001.
  def test_credit_note_has_its_own_series_and_copies_the_reference
    with_issuance do |issuance, store|
      original = factura(issuance)
      note = issuance.issue_credit_note(reference: original.correlative.to_s, motivo: "Devolución",
                                        customer: cliente, line_items: [build_line(unit_price: hnl("200.00"))])

      assert_equal "000-001-06-00000001", note.correlative.to_s
      assert_equal "CAI-06", note.authorization.cai
      assert_equal original.correlative, note.reference.correlative
      assert_equal "CAI-01", note.reference.cai
      assert_equal original.issue_date, note.reference.issue_date
      assert_equal "000-001-01-00000002", factura(issuance).correlative.to_s
      assert_equal note.to_h, store.find("000-001-06-00000001").to_h
    end
  end

  def test_debit_note
    with_issuance do |issuance|
      original = factura(issuance)
      note = issuance.issue_debit_note(reference: original.correlative, motivo: "Flete adicional",
                                       customer: cliente, line_items: [build_line])

      assert_equal "000-001-07-00000001", note.correlative.to_s
      assert_predicate note, :debit_note?
    end
  end

  # Art. 59 — the authorization is per emission point and document type.
  def test_a_note_needs_its_own_authorization
    with_issuance(authorizations: [auth("01")]) do |issuance|
      original = factura(issuance)

      assert_raises(Invoicehn::NoAuthorization) do
        issuance.issue_credit_note(reference: original.correlative, motivo: "x",
                                   customer: cliente, line_items: [build_line])
      end
    end
  end

  # A document issued before this store existed — by the legacy system — is
  # referenced with the three fields typed in.
  def test_reference_to_a_document_outside_the_store
    with_issuance do |issuance|
      ref = Invoicehn::DocumentReference.new(correlative: "000-001-01-00009999", cai: "CAI-VIEJO",
                                             issue_date: Date.today - 30)
      note = issuance.issue_credit_note(reference: ref, motivo: "Descuento posterior",
                                        customer: cliente, line_items: [build_line])

      assert_equal ref, note.reference
    end
  end

  def test_unknown_correlative_reference_is_refused
    with_issuance do |issuance|
      assert_raises(Invoicehn::DocumentNotFound) do
        issuance.issue_credit_note(reference: "000-001-01-00009999", motivo: "x",
                                   customer: cliente, line_items: [build_line])
      end
    end
  end

  def test_typed_reference_must_match_the_stored_original
    with_issuance do |issuance, _store, config|
      original = factura(issuance)
      wrong = Invoicehn::DocumentReference.new(correlative: original.correlative, cai: "OTRO-CAI",
                                               issue_date: original.issue_date)

      assert_raises(Invoicehn::ValidationError) do
        issuance.issue_credit_note(reference: wrong, motivo: "x", customer: cliente, line_items: [build_line])
      end
      assert_equal 0, Invoicehn::Sequence.new(config).issued_count("000-001-06")
    end
  end

  def test_no_note_on_an_annulled_document
    with_issuance do |issuance|
      original = factura(issuance)
      issuance.annul(original.correlative, reason: "Error")

      assert_raises(Invoicehn::ValidationError) do
        issuance.issue_credit_note(reference: original.correlative, motivo: "x",
                                   customer: cliente, line_items: [build_line])
      end
    end
  end

  def test_note_must_go_to_the_same_acquirer
    with_issuance do |issuance|
      original = factura(issuance)

      assert_raises(Invoicehn::ValidationError) do
        issuance.issue_credit_note(reference: original.correlative, motivo: "x",
                                   customer: cliente(rtn: "08011990123456"), line_items: [build_line])
      end
    end
  end

  def test_note_helpers_refuse_the_wrong_identifier
    with_issuance do |issuance|
      original = factura(issuance)

      assert_raises(Invoicehn::ValidationError) do
        issuance.issue_credit_note(reference: original.correlative, motivo: "x", customer: cliente,
                                   line_items: [build_line], identifier: "000-001-07")
      end
    end
  end

  # A note that fails validation consumes no number.
  def test_a_non_compliant_note_burns_no_number
    with_issuance do |issuance, _store, config|
      original = factura(issuance)

      assert_raises(Invoicehn::ComplianceError) do
        issuance.issue_credit_note(reference: original.correlative, motivo: "",
                                   customer: cliente, line_items: [build_line])
      end
      assert_equal 0, Invoicehn::Sequence.new(config).issued_count("000-001-06")
    end
  end

  # Art. 41 applies to "Comprobantes Fiscales y/o Documentos Complementarios".
  def test_a_note_can_be_annulled
    with_issuance do |issuance, store|
      original = factura(issuance)
      note = issuance.issue_credit_note(reference: original.correlative, motivo: "Devolución",
                                        customer: cliente, line_items: [build_line])
      issuance.annul(note.correlative, reason: "Monto equivocado")

      stored = store.find(note.correlative)

      assert_predicate stored, :annulled?
      assert_equal original.correlative, stored.reference.correlative
      assert_includes Invoicehn::Renderers::Text.new(stored).render, "ANULADA"
    end
  end

  # --- all or nothing -------------------------------------------------------

  # If the ledger refuses the entry, the document must not stay behind: the
  # counter did not advance, and a leftover file at that number made every
  # later issue fail with ImmutableDocument.
  def test_a_failing_ledger_leaves_no_partial_state
    with_issuance(ledger: FailingLedger.new) do |_failing, store, config|
      failing = Invoicehn::Issuance.new(config: config, store: store, ledger: FailingLedger.new)

      assert_raises(IOError) { factura(failing) }
      refute store.exists?("000-001-01-00000001")
      assert_equal 0, Invoicehn::Sequence.new(config).issued_count("000-001-01")
      assert_empty store.all

      healthy = Invoicehn::Issuance.new(config: config, store: store,
                                        ledger: Invoicehn::Ledger::JsonlLedger.new(config))

      assert_equal "000-001-01-00000001", factura(healthy).correlative.to_s
      assert_equal 1, store.all.size
    end
  end

  # --- health ---------------------------------------------------------------

  # An exhausted range whose fecha límite has not passed is not "active": it
  # cannot issue the next number.
  def test_health_with_an_exhausted_range_is_not_ready
    with_issuance(authorizations: [auth("01", last: 2)]) do |issuance|
      2.times { factura(issuance) }

      status = issuance.health

      assert_nil status[:active_authorization]
      assert_equal 0, status[:remaining]
      refute status[:ready]
      assert_raises(Invoicehn::NoAuthorization) { factura(issuance) }
    end
  end

  def test_health_counts_what_is_left
    with_issuance(authorizations: [auth("01", last: 5)]) do |issuance|
      2.times { factura(issuance) }

      status = issuance.health

      assert_equal 3, status[:remaining]
      assert status[:ready]
    end
  end

  def test_health_for_a_note_series
    with_issuance do |issuance|
      status = issuance.health(identifier: "000-001-06")

      assert_equal "000-001-06-00000001", status[:next_correlative].to_s
      assert_equal "CAI-06", status[:active_authorization].cai
    end
  end
end
