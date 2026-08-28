# frozen_string_literal: true

require "test_helper"

# Art. 53 num. 5 — "El Sistema debe tener la capacidad de generación de archivos
# tipo texto para su almacenamiento y traslado hacia la Administración
# Tributaria a través de servicios web o intercambio de protocolo."
class TestArt53Export < Minitest::Test
  def invoice = build_invoice

  def test_json_carries_every_required_field
    payload = JSON.parse(Invoicehn::Renderers::Json.new(invoice).render)

    assert_equal "000-001-01-00000001", payload["correlative"]
    assert_equal "Factura", payload["document_name"]
    assert_equal "emitida", payload["status"]
    assert payload["issuer"]
    assert payload["customer"]
    assert payload["authorization"]
    assert payload["line_items"]
    assert payload["totals"]
    assert payload["total_in_words"]
  end

  def test_the_authorization_travels_with_the_document
    payload = JSON.parse(Invoicehn::Renderers::Json.new(invoice).render)

    assert_equal build_authorization.cai, payload["authorization"]["cai"]
    assert_equal "2026-08-28", payload["issue_date"] if invoice.issue_date == Date.new(2026, 8, 28)
  end

  # A JSON number would invite the reader to parse a fiscal figure as a float.
  def test_amounts_are_strings_throughout
    payload = JSON.parse(Invoicehn::Renderers::Json.new(invoice).render)

    assert_kind_of String, payload["totals"]["total"]["amount"]
    assert_kind_of String, payload["totals"]["isv_total"]["amount"]
    assert_kind_of String, payload["line_items"].first["unit_price"]["amount"]
  end

  def test_a_document_round_trips_through_json
    original = invoice
    reloaded = Invoicehn::Invoice.from_h(JSON.parse(Invoicehn::Renderers::Json.new(original).render))

    assert_equal original.correlative, reloaded.correlative
    assert_equal original.total, reloaded.total
    assert_equal original.subtotal, reloaded.subtotal
    assert_equal original.isv_total, reloaded.isv_total
    assert_equal original.total_in_words, reloaded.total_in_words
  end

  def test_batch_export_wraps_the_documents
    payload = JSON.parse(Invoicehn::Renderers::Json.export([invoice, invoice]))

    assert_equal 2, payload["count"]
    assert_equal 2, payload["documents"].size
    assert payload["generated_at"]
  end

  def test_csv_export_has_a_header_and_one_row_per_document
    csv = Invoicehn::Renderers::Json.export_csv([invoice])
    lines = csv.lines(chomp: true)

    assert_equal 2, lines.size
    assert_equal "correlativo,fecha,estado,cai,cliente,rtn_cliente,moneda,subtotal,descuentos,isv,total",
                 lines.first
    assert lines.last.start_with?("000-001-01-00000001,")
  end

  # A razón social containing a comma must not break the column layout.
  def test_csv_quotes_fields_containing_commas
    named = build_invoice(
      customer: Invoicehn::Customer::Taxpayer.new(name: "Ejemplo, S. de R.L.", rtn: "05019005123456")
    )
    csv = Invoicehn::Renderers::Json.export_csv([named])

    assert_includes csv, '"Ejemplo, S. de R.L. (RTN 0501-9005-123456)"'
    assert_equal 2, csv.lines.size
  end

  def test_csv_amounts_carry_two_decimals
    csv = Invoicehn::Renderers::Json.export_csv([invoice])
    fields = csv.lines(chomp: true).last.split(",")

    assert_match(/\A\d+\.\d{2}\z/, fields[-1])
    assert_match(/\A\d+\.\d{2}\z/, fields[-2])
  end

  def test_an_empty_export_still_produces_a_header
    assert_equal 1, Invoicehn::Renderers::Json.export_csv([]).lines.size
    assert_equal 0, JSON.parse(Invoicehn::Renderers::Json.export([]))["count"]
  end
end
