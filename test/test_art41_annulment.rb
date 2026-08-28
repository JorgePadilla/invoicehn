# frozen_string_literal: true

require "test_helper"

# Art. 41 — "En el caso de emisión de Comprobantes Fiscales y/o Documentos
# Complementarios con errores, estos deben ser anulados, consignando en los
# mismos la leyenda 'ANULADA' de forma manuscrita, impresa o con sello."
#
# Art. 43 — documents must be kept ordered and chronological, which is only
# possible if the series never reuses or skips a number.
class TestArt41Annulment < Minitest::Test
  def setup_issuance
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      store.add_authorization(build_authorization)
      yield Invoicehn::Issuance.new(config: config, store: store), store
    end
  end

  def test_annulment_marks_the_document
    invoice = build_invoice
    annulled = invoice.annul(reason: "Error en la descripción del servicio")

    assert_predicate annulled, :annulled?
    assert_equal "anulada", annulled.status
    assert_equal "Error en la descripción del servicio", annulled.annulment_reason
    assert_equal Date.today, annulled.annulled_at
  end

  # Annulment returns a new object; the original is untouched.
  def test_the_original_is_not_mutated
    invoice = build_invoice
    invoice.annul(reason: "Error")

    assert_predicate invoice, :issued?
    refute_predicate invoice, :annulled?
  end

  def test_the_correlative_survives_annulment
    invoice = build_invoice
    annulled = invoice.annul(reason: "Error")

    assert_equal invoice.correlative, annulled.correlative
  end

  def test_a_reason_is_required
    assert_raises(Invoicehn::ValidationError) { build_invoice.annul(reason: "") }
    assert_raises(Invoicehn::ValidationError) { build_invoice.annul(reason: "   ") }
  end

  def test_annulling_twice_is_refused
    annulled = build_invoice.annul(reason: "Error")

    assert_raises(Invoicehn::ImmutableDocument) { annulled.annul(reason: "Otra vez") }
  end

  # The point of Art. 41 read with Art. 43: correcting a document must not
  # recycle its number.
  def test_the_number_is_not_reissued_after_annulment
    setup_issuance do |issuance|
      first = issuance.issue(customer: Invoicehn::Customer::ConsumidorFinal.new,
                             line_items: [build_line])

      assert_equal "000-001-01-00000001", first.correlative.to_s

      issuance.annul(first.correlative, reason: "Error en la descripción")

      second = issuance.issue(customer: Invoicehn::Customer::ConsumidorFinal.new,
                              line_items: [build_line])

      assert_equal "000-001-01-00000002", second.correlative.to_s
    end
  end

  def test_the_annulled_document_is_what_is_stored
    setup_issuance do |issuance, store|
      invoice = issuance.issue(customer: Invoicehn::Customer::ConsumidorFinal.new,
                               line_items: [build_line])
      issuance.annul(invoice.correlative, reason: "Cliente devolvió el bien")

      reloaded = store.find(invoice.correlative)

      assert_predicate reloaded, :annulled?
      assert_equal "Cliente devolvió el bien", reloaded.annulment_reason
    end
  end

  # An issued document may not be quietly overwritten — the only route to
  # changing the record is annulment.
  def test_reissuing_over_an_existing_document_is_refused
    setup_issuance do |issuance, store|
      invoice = issuance.issue(customer: Invoicehn::Customer::ConsumidorFinal.new,
                               line_items: [build_line])

      assert_raises(Invoicehn::ImmutableDocument) { store.save_document(invoice) }
    end
  end

  def test_annulment_round_trips_through_a_hash
    annulled = build_invoice.annul(reason: "Error")
    reloaded = Invoicehn::Invoice.from_h(annulled.to_h)

    assert_predicate reloaded, :annulled?
    assert_equal "Error", reloaded.annulment_reason
  end
end
