# frozen_string_literal: true

require "test_helper"

# Art. 10 num. 7 — "Número correlativo de la Factura. Constará de dieciséis (16)
# dígitos (NNN-NNN-NN-NNNNNNNN)".
class TestArt10Correlative < Minitest::Test
  C = Invoicehn::Correlative

  def factura(sequence: 1, establishment: "000", emission_point: "001")
    C.new(establishment: establishment, emission_point: emission_point,
          document_type: "01", sequence: sequence)
  end

  def test_renders_sixteen_digits_in_four_groups
    assert_equal "000-001-01-00000001", factura.to_s
    assert_equal 16, factura.to_s.delete("-").length
  end

  # "para la casa matriz el sistema asignará el código 000"
  def test_casa_matriz_is_establishment_000
    assert_equal "000", factura.establishment
  end

  def test_parses_a_well_formed_number
    correlative = C.parse("003-002-01-00012345")

    assert_equal "003", correlative.establishment
    assert_equal "002", correlative.emission_point
    assert_equal "01", correlative.document_type
    assert_equal 12_345, correlative.sequence
  end

  def test_round_trips_through_parse
    assert_equal "007-042-01-00099999", C.parse("007-042-01-00099999").to_s
  end

  def test_rejects_malformed_input
    ["", "000-001-01", "000-001-01-1", "0000-001-01-00000001",
     "000-001-01-000000001", "abc-001-01-00000001", "000/001/01/00000001"].each do |bad|
      assert_raises(Invoicehn::ValidationError, "debió rechazar #{bad.inspect}") { C.parse(bad) }
    end
  end

  # "01 = Factura"
  def test_document_type_01_is_factura
    assert_predicate factura, :factura?
    assert_equal "Factura", factura.document_type_name
  end

  def test_known_document_type_codes
    expected = {
      "01" => "Factura", "02" => "Factura Prevalorada", "03" => "Ticket",
      "04" => "Recibo por Honorarios Profesionales", "05" => "Boleta de Compra",
      "06" => "Constancia de Donación", "07" => "Nota de Crédito",
      "08" => "Nota de Débito", "10" => "Comprobante de Retención"
    }

    assert_equal expected, C::DOCUMENT_TYPES
  end

  # 09 was never confirmed in the decree, so it must not be accepted.
  def test_unconfirmed_document_type_09_is_rejected
    assert_raises(Invoicehn::ValidationError) { C.parse("000-001-09-00000001") }
  end

  # "la numeración correlativa ... deberá iniciarse en uno (00000001)"
  def test_sequence_starts_at_one
    assert_equal "000-001-01-00000001", factura(sequence: 1).to_s
    assert_raises(Invoicehn::ValidationError) { factura(sequence: 0) }
  end

  def test_sequence_advances
    assert_equal "000-001-01-00000002", factura(sequence: 1).succ.to_s
    assert_equal "000-001-01-00010000", factura(sequence: 9_999).succ.to_s
  end

  # "Una vez completados los ocho dígitos (99999999), se reiniciará la
  # numeración correlativa." Restarting is the allocator's decision against a
  # fresh authorization, so the value object refuses to wrap silently.
  def test_sequence_upper_bound
    last = factura(sequence: 99_999_999)

    assert_predicate last, :last?
    assert_equal "000-001-01-99999999", last.to_s
    assert_raises(Invoicehn::RangeExhausted) { last.succ }
    assert_raises(Invoicehn::ValidationError) { factura(sequence: 100_000_000) }
  end

  # "Los primeros tres grupos de dígitos, se denominan identificador del
  # documento ... ya que identifica el establecimiento, punto de emisión y tipo
  # de documento."
  def test_identifier_is_the_first_three_groups
    assert_equal "000-001-01", factura.identifier
    assert_equal "003-002-01", C.parse("003-002-01-00012345").identifier
  end

  def test_ordering_within_one_identifier
    assert_operator factura(sequence: 1), :<, factura(sequence: 2)
    assert_equal factura(sequence: 5), C.parse("000-001-01-00000005")
  end

  # Two emission points run independent sequences, so their numbers are not
  # comparable.
  def test_numbers_from_different_emission_points_are_not_ordered
    assert_nil factura(sequence: 1, emission_point: "001") <=> factura(sequence: 2, emission_point: "002")
  end

  def test_accepts_short_numeric_components_and_pads_them
    assert_equal "000-001-01-00000001",
                 C.new(establishment: 0, emission_point: 1, document_type: 1, sequence: 1).to_s
  end
end
