# frozen_string_literal: true

require "test_helper"

# Notas de Crédito (Arts. 25-26) and Notas de Débito (Arts. 27-28), as they
# read in the consolidated text of the Acuerdo 481-2017.
#
# Art. 26 / 28 — "REQUISITOS A SER COMPLETADOS AL MOMENTO DE LA EMISIÓN":
#   1. Nombres y Apellidos, Razón o Denominación Social del adquirente.
#   2. Número de Registro Tributario Nacional (RTN) del adquirente.
#   3. Datos del Comprobante Fiscal que da lugar a la Nota: a) CAI,
#      b) número correlativo, c) fecha de emisión.
#   4. Motivo de la emisión del documento.
class TestArt2528Notas < Minitest::Test
  RTN_CLIENTE = "05019005123456"

  def teardown
    Invoicehn.reset_settings!
  end

  def cliente(rtn: RTN_CLIENTE) = Invoicehn::Customer::Taxpayer.new(name: "Distribuidora del Norte, S.A.", rtn: rtn)

  def referencia(**overrides)
    Invoicehn::DocumentReference.new(
      correlative: "000-001-01-00000042",
      cai: "ABCD12-345678-9ABCDE-F01234-567890-AB",
      issue_date: Date.today - 10, **overrides
    )
  end

  def nota_auth(type)
    build_authorization(range_start: "000-001-#{type}-00000001", range_end: "000-001-#{type}-00000100",
                        cai: "NOTA#{type}-CAI-0001")
  end

  def build_note(type: "06", **overrides)
    Invoicehn::Invoice.new(
      correlative: "000-001-#{type}-00000001",
      issuer: build_issuer,
      customer: cliente,
      authorization: nota_auth(type),
      line_items: [build_line],
      reference: referencia,
      motivo: "Devolución de mercadería", **overrides
    )
  end

  # --- the value object -----------------------------------------------------

  def test_reference_carries_the_three_fields_and_is_frozen
    ref = referencia

    assert_equal "000-001-01-00000042", ref.correlative.to_s
    assert_equal "ABCD12-345678-9ABCDE-F01234-567890-AB", ref.cai
    assert_equal Date.today - 10, ref.issue_date
    assert_predicate ref, :frozen?
    assert_equal ref, Invoicehn::DocumentReference.from_h(ref.to_h)
  end

  def test_reference_requires_the_cai
    assert_raises(Invoicehn::ValidationError) { referencia(cai: " ") }
  end

  def test_reference_from_an_issued_document_copies_its_fields
    factura = build_invoice
    ref = Invoicehn::DocumentReference.from_document(factura)

    assert_equal factura.correlative, ref.correlative
    assert_equal factura.authorization.cai, ref.cai
    assert_equal factura.issue_date, ref.issue_date
  end

  # --- validation -----------------------------------------------------------

  def test_a_complete_credit_note_is_compliant
    note = build_note

    assert_predicate note, :credit_note?
    assert_equal "Nota de Crédito", note.document_name
    assert_empty note.violations
  end

  def test_a_complete_debit_note_is_compliant
    note = build_note(type: "07", motivo: "Intereses por mora")

    assert_predicate note, :debit_note?
    assert_equal "Nota de Débito", note.document_name
    assert_empty note.violations
  end

  def test_art26_num3_reference_is_required
    assert_violates "Art. 26 num. 3", build_note(reference: nil)
    assert_violates "Art. 28 num. 3", build_note(type: "07", reference: nil)
  end

  def test_art26_num4_motivo_is_required
    assert_violates "Art. 26 num. 4", build_note(motivo: "  ")
    assert_violates "Art. 28 num. 4", build_note(type: "07", motivo: nil)
  end

  # No CONSUMIDOR FINAL alternative in Arts. 26 and 28 num. 1-2.
  def test_notes_require_the_acquirers_rtn
    consumer = Invoicehn::Customer::ConsumidorFinal.new(name: "Juan Pérez", identification_type: "DNI",
                                                        identification_number: "0801199012345")

    assert_violates "Art. 26 num. 1 y 2", build_note(customer: consumer)
    assert_violates "Art. 28 num. 1 y 2", build_note(type: "07", customer: consumer)
  end

  # Art. 4 num. 32 and Art. 26 num. 3 lit. b) — the Nota de Crédito applies
  # to a Comprobante Fiscal (Art. 6).
  def test_credit_note_must_refer_to_a_comprobante_fiscal
    on_a_note = build_note(reference: referencia(correlative: "000-001-07-00000003"))

    assert_violates "Art. 26 num. 3", on_a_note
    refute_violates "Art. 26 num. 3", build_note(reference: referencia(correlative: "000-001-10-00000003"))
  end

  # Art. 28 num. 3 lit. b) — "del Comprobante Fiscal o el documento".
  def test_debit_note_may_refer_to_another_document
    refute_violates "Art. 28 num. 3", build_note(type: "07", reference: referencia(correlative: "000-001-06-00000003"))
  end

  def test_reference_cannot_postdate_the_note
    assert_violates "Art. 4 num. 32", build_note(reference: referencia(issue_date: Date.today + 1))
    assert_violates "Art. 4 num. 31", build_note(type: "07", reference: referencia(issue_date: Date.today + 1))
    refute_violates "Art. 4 num. 32", build_note(reference: referencia(issue_date: Date.today))
  end

  def test_a_note_cannot_refer_to_itself
    assert_violates "Art. 28 num. 3", build_note(type: "07", reference: referencia(correlative: "000-001-07-00000001"))
  end

  # Art. 26 num. 9 / Art. 28 num. 8 — Moneda Nacional Lempira; the foreign
  # currency allowance of Art. 11 speaks of facturas only.
  def test_notes_are_issued_in_lempiras
    rate = Invoicehn::ExchangeRate.new(rate: "24.6543", date: Date.today, currency: "USD")
    note = build_note(currency: "USD", exchange_rate: rate,
                      line_items: [build_line(unit_price: usd("10.00"))])

    assert_violates "Art. 26 num. 9", note
  end

  def test_a_factura_does_not_take_a_reference_or_motivo
    assert_raises(Invoicehn::ValidationError) { build_invoice(reference: referencia) }
    assert_raises(Invoicehn::ValidationError) { build_invoice(motivo: "x") }
  end

  def test_other_document_types_are_not_issued
    invoice = build_invoice(correlative: "000-001-08-00000001",
                            authorization: nota_auth("08"))

    assert_violates "Art. 10 num. 7 lit. c", invoice
  end

  # Art. 11 num. 2 (the L 10,000.00 threshold) and Art. 11 num. 3 (mixed
  # supply) are Factura rules.
  def test_factura_rules_do_not_leak_onto_notes
    mixed = build_note(line_items: [build_line, build_line(treatment: :exento)])

    refute_violates "Art. 11 num. 3", mixed
  end

  def test_serialisation_round_trips_reference_and_motivo
    note = build_note
    copy = Invoicehn::Invoice.from_h(JSON.parse(JSON.generate(note.to_h)))

    assert_equal note.reference, copy.reference
    assert_equal "Devolución de mercadería", copy.motivo
    assert_equal "06", note.to_h["document_type"]
    assert_equal "Nota de Crédito", note.to_h["document_name"]
  end

  # A Factura's serialised form is what 0.1.0 wrote, plus the type.
  def test_factura_serialisation_has_no_note_fields
    hash = build_invoice.to_h

    refute hash.key?("reference")
    refute hash.key?("motivo")
    assert_equal "Factura", hash["document_name"]
  end

  def test_annulment_keeps_the_reference
    annulled = build_note.annul(reason: "Error en el monto")

    assert_predicate annulled, :annulled?
    assert_equal referencia, annulled.reference
    assert_equal "Devolución de mercadería", annulled.motivo
  end

  # --- rendering ------------------------------------------------------------

  def text(note, copy: :original) = Invoicehn::Renderers::Text.new(note, copy: copy).render

  # Art. 25 num. 2 / Art. 27 num. 2 — denominación del documento.
  def test_text_titles
    assert_includes text(build_note), "NOTA DE CRÉDITO"
    assert_includes text(build_note(type: "07")), "NOTA DE DÉBITO"
    refute_includes text(build_note), "FACTURA"
  end

  def test_text_shows_reference_and_motivo
    out = text(build_note)

    assert_includes out, "Factura No.: 000-001-01-00000042"
    assert_includes out, "CAI: ABCD12-345678-9ABCDE-F01234-567890-AB"
    assert_includes out, "Fecha de emisión: #{Date.today - 10}"
    assert_includes out, "Motivo: Devolución de mercadería"
    assert_includes out, "CAI: NOTA06-CAI-0001"
  end

  # Art. 26 num. 7 — only the Nota de Crédito asks for the receiver.
  def test_receiver_fields_on_credit_notes_only
    assert_includes text(build_note), "Recibido por (nombres y apellidos):"
    assert_includes text(build_note), "Firma:"
    refute_includes text(build_note(type: "07")), "Recibido por"
    refute_includes text(build_invoice), "Recibido por"
  end

  # Arts. 25 and 27 num. 7 b) — "Copia: Obligado Tributario".
  def test_copy_legend_follows_the_note_articles
    assert_includes text(build_note, copy: :copia), "Copia: Obligado Tributario"
    refute_includes text(build_note, copy: :copia), "emisor"
    assert_includes text(build_note), "Original: Cliente"
  end
end
