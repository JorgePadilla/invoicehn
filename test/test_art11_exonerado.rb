# frozen_string_literal: true

require "test_helper"

# Art. 10 num. 8 — "Datos del Adquirente Exonerado": Orden de Compra Exenta,
# Constancia del Registro de Exonerados, Registro de la Secretaría de
# Agricultura y Ganadería.
#
# Art. 11 num. 4 — "Cuando la venta de bienes y/o prestación de servicios se
# realicen a Obligados Tributarios Exonerados se debe consignar el Número
# correlativo de la Orden de Compra Exenta, Número correlativo de la Constancia
# del Registro de Exonerados o, el Número identificativo del Registro Único de
# Personas Naturales del Sector Agroindustrial, según corresponda."
class TestArt11Exonerado < Minitest::Test
  E = Invoicehn::Customer::Exonerado

  def exonerado(**overrides)
    E.new(name: "Fundación Ejemplo", rtn: "08019995123456", **overrides)
  end

  def exonerado_invoice(customer: exonerado(purchase_order: "OCE-2026-0042"))
    build_invoice(customer: customer, line_items: [build_line(treatment: :exonerado)])
  end

  # "según corresponda" — whichever of the three applies to the buyer, so any
  # one of them suffices.
  def test_any_one_supporting_document_suffices
    assert_predicate exonerado(purchase_order: "OCE-2026-0042"), :supported?
    assert_predicate exonerado(exoneration_registry: "CRE-8891"), :supported?
    assert_predicate exonerado(sag_registry: "SAG-4410"), :supported?
  end

  def test_none_at_all_is_refused
    customer = exonerado

    refute_predicate customer, :supported?
    assert_violates "Art. 10 num. 8 y Art. 11 num. 4", exonerado_invoice(customer: customer)
  end

  def test_supporting_documents_are_listed_for_display
    customer = exonerado(purchase_order: "OCE-2026-0042", sag_registry: "SAG-4410")

    assert_equal({ "Orden de Compra Exenta" => "OCE-2026-0042", "Registro SAG" => "SAG-4410" },
                 customer.supporting_documents)
  end

  def test_a_supported_exonerado_invoice_is_compliant
    assert_predicate exonerado_invoice, :compliant?
  end

  def test_exonerado_lines_carry_no_isv
    invoice = exonerado_invoice

    assert_equal hnl("1000.00"), invoice.subtotal
    assert_equal hnl("0.00"), invoice.isv_total
  end

  # An exonerado line on an invoice to a buyer who is not registered as
  # exonerated is a contradiction the document would carry on its face.
  def test_exonerado_lines_require_an_exonerado_buyer
    invoice = build_invoice(
      customer: Invoicehn::Customer::ConsumidorFinal.new,
      line_items: [build_line(treatment: :exonerado)]
    )

    assert_violates "Art. 11 num. 4", invoice
  end

  def test_an_exonerado_buyer_needs_a_name_and_rtn
    assert_raises(Invoicehn::ValidationError) { exonerado(rtn: "bad") }
    assert_violates "Art. 11 num. 1 lit. a y b",
                    exonerado_invoice(customer: exonerado(name: "", purchase_order: "OCE-1"))
  end

  def test_round_trips_through_a_hash
    customer = exonerado(purchase_order: "OCE-2026-0042", exoneration_registry: "CRE-8891")

    assert_equal customer.to_h, Invoicehn::Customer.from_h(customer.to_h).to_h
  end
end
