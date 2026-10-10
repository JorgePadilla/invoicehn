# frozen_string_literal: true

require "test_helper"
require "pdf-reader"
require "stringio"

# The PDF must carry the same legally required content as the text renderer:
# Art. 10 num. 2-7 (denominación, CAI, fecha límite, rango, destino,
# correlativo), Art. 11 (customer, totals, total in words) and, for the notes,
# Arts. 26 and 28 num. 3-4 (reference and motivo).
class TestRendererPdf < Minitest::Test
  RTN_CLIENTE = "05019005123456"

  # prawn is a runtime dependency, so a missing prawn is a failure here, not
  # a reason to skip.
  def setup
    assert_predicate Invoicehn::Renderers::Pdf, :available?
  end

  # pdf-reader lays text out by position; collapsing runs of spaces keeps the
  # assertions about content, not about column alignment.
  def pdf_text(document, copy: :original)
    data = Invoicehn::Renderers::Pdf.new(document, copy: copy).render
    PDF::Reader.new(StringIO.new(data)).pages.map(&:text).join("\n").gsub(/[ \t]+/, " ")
  end

  def taxpayer = Invoicehn::Customer::Taxpayer.new(name: "Distribuidora del Norte, S.A.", rtn: RTN_CLIENTE)

  def note(type)
    Invoicehn::Invoice.new(
      correlative: "000-001-#{type}-00000007",
      issuer: build_issuer,
      customer: taxpayer,
      authorization: build_authorization(range_start: "000-001-#{type}-00000001",
                                         range_end: "000-001-#{type}-00000100", cai: "CAI-NOTA-#{type}"),
      line_items: [build_line],
      reference: Invoicehn::DocumentReference.new(correlative: "000-001-01-00000042", cai: "CAI-FACTURA-01",
                                                  issue_date: Date.new(2026, 9, 1)),
      motivo: "Devolución parcial de mercadería"
    )
  end

  def test_factura_carries_the_article_10_fields
    invoice = build_invoice
    auth = invoice.authorization
    text = pdf_text(invoice)

    assert_includes text, "FACTURA"
    assert_includes text, "CAI: #{auth.cai}"
    assert_includes text, "Rango autorizado: #{auth.range_label}"
    assert_includes text, "Fecha límite de emisión: #{auth.limit_date}"
    assert_includes text, "No.: 000-001-01-00000001"
    assert_includes text, "Fecha de emisión: #{invoice.issue_date}"
    assert_includes text, "RTN: 0801-1990-123456"
    assert_includes text, "Original: Cliente"
  end

  def test_consumidor_final_legend
    assert_includes pdf_text(build_invoice), "CONSUMIDOR FINAL"
  end

  def test_taxpayer_rtn
    assert_includes pdf_text(build_invoice(customer: taxpayer)), "RTN: 0501-9005-123456"
  end

  def test_totals_and_total_in_words
    invoice = build_invoice
    text = pdf_text(invoice)

    assert_includes text, "Descuentos y rebajas otorgados:"
    assert_includes text, "ISV 15%:"
    assert_includes text, "L 150.00"
    assert_includes text, "L 1,150.00"
    assert_includes text, invoice.total_in_words
  end

  def test_copy_legend
    assert_includes pdf_text(build_invoice, copy: :copia), "Copia: Obligado tributario emisor"
  end

  def test_annulled_legend
    assert_includes pdf_text(build_invoice.annul(reason: "Error en la cantidad")), "ANULADA"
  end

  def test_credit_note
    text = pdf_text(note("06"))

    assert_includes text, "NOTA DE CRÉDITO"
    refute_includes text, "FACTURA\n"
    assert_includes text, "No.: 000-001-06-00000007"
    assert_includes text, "CAI: CAI-NOTA-06"
    assert_includes text, "Factura No.: 000-001-01-00000042"
    assert_includes text, "CAI: CAI-FACTURA-01"
    assert_includes text, "Fecha de emisión: 2026-09-01"
    assert_includes text, "Motivo: Devolución parcial de mercadería"
    assert_includes text, "RTN: 0501-9005-123456"
    assert_includes text, "Recibido por (nombres y apellidos):"
    assert_includes text, "MIL CIENTO CINCUENTA LEMPIRAS CON 00/100"
  end

  def test_debit_note
    text = pdf_text(note("07"), copy: :copia)

    assert_includes text, "NOTA DE DÉBITO"
    assert_includes text, "Factura No.: 000-001-01-00000042"
    assert_includes text, "Motivo: Devolución parcial de mercadería"
    assert_includes text, "Copia: Obligado Tributario"
    refute_includes text, "Recibido por"
  end
end
