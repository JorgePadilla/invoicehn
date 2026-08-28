# frozen_string_literal: true

require "test_helper"

# Art. 10 num. 3, 4 and 5 — the CAI, the fecha límite de emisión and the rango
# autorizado, all current. Art. 62 governs expiry.
class TestArt10Authorization < Minitest::Test
  def test_carries_cai_range_and_limit_date
    auth = build_authorization

    assert_equal "ABCD12-345678-9ABCDE-F01234-567890-AB", auth.cai
    assert_equal "000-001-01-00000001 al 000-001-01-00000500", auth.range_label
    assert_equal 500, auth.capacity
  end

  # Art. 4 num. 7 defines the CAI only as "una serie alfanumérica generada
  # electrónicamente". No length or grouping is fixed anywhere in the decree, so
  # any non-empty string SAR issues must be accepted verbatim. Validating
  # against a guessed format would reject real CAIs.
  def test_cai_is_stored_verbatim_whatever_its_shape
    %w[A1B2C3 ABCD12-345678-9ABCDE-F01234-567890-AB
       0123456789ABCDEF0123456789ABCDEF X].each do |cai|
      assert_equal cai, build_authorization(cai: cai).cai
    end
  end

  def test_cai_must_not_be_empty
    assert_raises(Invoicehn::ValidationError) { build_authorization(cai: "") }
    assert_raises(Invoicehn::ValidationError) { build_authorization(cai: "   ") }
  end

  def test_range_bounds_must_share_one_identifier
    error = assert_raises(Invoicehn::ValidationError) do
      build_authorization(range_start: "000-001-01-00000001", range_end: "000-002-01-00000500")
    end
    assert_match(/identificadores distintos/, error.message)
  end

  def test_range_must_not_end_before_it_starts
    assert_raises(Invoicehn::ValidationError) do
      build_authorization(range_start: "000-001-01-00000500", range_end: "000-001-01-00000001")
    end
  end

  def test_covers_only_numbers_inside_the_range
    auth = build_authorization

    assert auth.covers?("000-001-01-00000001")
    assert auth.covers?("000-001-01-00000500")
    refute auth.covers?("000-001-01-00000501")
    refute auth.covers?("000-002-01-00000001") # another emission point
  end

  def test_identifier_reflects_establishment_point_and_type
    auth = build_authorization(range_start: "003-002-01-00000001", range_end: "003-002-01-00000100")

    assert_equal "003-002-01", auth.identifier
    assert_equal "003", auth.establishment
    assert_equal "002", auth.emission_point
    assert_equal "01", auth.document_type
  end

  def test_out_of_range_correlative_is_reported_against_article_10
    invoice = build_invoice(
      correlative: "000-001-01-00000501",
      authorization: build_authorization
    )

    assert_violates "Art. 10 num. 5", invoice
  end

  def test_assert_usable_names_the_failing_condition
    auth = build_authorization

    assert auth.assert_usable!("000-001-01-00000001")

    error = assert_raises(Invoicehn::RangeExhausted) { auth.assert_usable!("000-001-01-00000501") }
    assert_match(/fuera del rango autorizado/, error.message)
  end

  def test_round_trips_through_a_hash
    auth = build_authorization

    assert_equal auth.to_h, Invoicehn::Authorization.from_h(auth.to_h).to_h
  end
end
