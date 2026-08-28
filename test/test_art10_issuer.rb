# frozen_string_literal: true

require "test_helper"

# Art. 10 num. 1 — "Datos de identificación del emisor": RTN, nombre o razón
# social, nombre comercial, dirección de la casa matriz y del establecimiento
# donde esté localizado el punto de emisión, número telefónico y correo
# electrónico.
class TestArt10Issuer < Minitest::Test
  def test_a_complete_issuer_passes
    issuer = build_issuer

    assert_predicate issuer, :complete?
    assert_empty issuer.missing_fields
    assert_same issuer, issuer.validate!
  end

  def test_rtn_is_required_and_validated
    assert_raises(Invoicehn::ValidationError) { build_issuer(rtn: "") }
    assert_raises(Invoicehn::ValidationError) { build_issuer(rtn: "123") }
  end

  def test_each_remaining_field_is_mandatory
    {
      legal_name: "nombre o razón social",
      trade_name: "nombre comercial",
      headquarters_address: "dirección de la casa matriz",
      phone: "número telefónico",
      email: "correo electrónico"
    }.each do |field, description|
      issuer = build_issuer(field => "")

      refute_predicate issuer, :complete?, "#{field} debería ser obligatorio"
      assert(issuer.missing_fields.any? { |m| m.include?(description) },
             "se esperaba que faltara #{description}, se obtuvo #{issuer.missing_fields.inspect}")
    end
  end

  def test_validate_lists_every_missing_field_at_once
    issuer = build_issuer(legal_name: "", phone: "", email: "")
    error = assert_raises(Invoicehn::ValidationError) { issuer.validate! }

    assert_match(/nombre o razón social/, error.message)
    assert_match(/número telefónico/, error.message)
    assert_match(/correo electrónico/, error.message)
  end

  # "Dirección de la casa matriz y del establecimiento donde esté localizado el
  # punto de emisión" — when issuing from the casa matriz the two coincide.
  def test_branch_address_defaults_to_headquarters
    issuer = build_issuer

    assert_equal issuer.headquarters_address, issuer.branch_address
    refute_predicate issuer, :branch?
  end

  def test_branch_address_is_kept_when_it_differs
    issuer = build_issuer(branch_address: "Barrio Guamilito, San Pedro Sula")

    assert_predicate issuer, :branch?
    assert_equal "Barrio Guamilito, San Pedro Sula", issuer.branch_address
  end

  def test_an_incomplete_issuer_blocks_the_invoice
    invoice = build_invoice(issuer: build_issuer(email: ""))

    assert_violates "Art. 10 num. 1", invoice
    assert_raises(Invoicehn::ComplianceError) { invoice.validate! }
  end

  def test_round_trips_through_a_hash
    issuer = build_issuer(branch_address: "Sucursal Centro")

    assert_equal issuer.to_h, Invoicehn::Issuer.from_h(issuer.to_h).to_h
  end
end
