# frozen_string_literal: true

require "test_helper"

# The RTN is required by Art. 10 num. 1 lit. a) for the issuer and Art. 11
# num. 1 lit. b) for the client.
class TestRtn < Minitest::Test
  R = Invoicehn::Rtn

  VALID = "08011990123456"

  def test_accepts_fourteen_digits
    assert_equal VALID, R.new(VALID).to_s
  end

  # Dashes are a display convention, not a norm, so they are accepted and
  # discarded rather than required.
  def test_accepts_and_strips_customary_dashes
    assert_equal VALID, R.new("0801-1990-123456").to_s
    assert_equal VALID, R.new(" 0801 1990 123456 ").to_s
  end

  def test_formats_with_the_customary_grouping
    assert_equal "0801-1990-123456", R.new(VALID).formatted
  end

  def test_rejects_wrong_lengths
    assert_raises(Invoicehn::ValidationError) { R.new("0801199012345") }   # 13, a DNI
    assert_raises(Invoicehn::ValidationError) { R.new("080119901234567") } # 15
    assert_raises(Invoicehn::ValidationError) { R.new("") }
  end

  def test_rejects_non_digits
    assert_raises(Invoicehn::ValidationError) { R.new("0801199012345A") }
    assert_raises(Invoicehn::ValidationError) { R.new("CONSUMIDOR FIN") }
  end

  # No check digit is published for the Honduran RTN, so any 14-digit string
  # must be accepted. A mod-11 scheme borrowed from another country's tax ID
  # would reject valid RTNs — this test documents that as intentional.
  def test_no_check_digit_is_imposed
    assert R.valid?("00000000000000")
    assert R.valid?("99999999999999")
    assert R.valid?("12345678901234")
  end

  def test_parse_returns_nil_instead_of_raising
    assert_nil R.parse("nope")
    assert_equal VALID, R.parse(VALID).to_s
  end

  def test_value_equality
    assert_equal R.new(VALID), R.new("0801-1990-123456")
    refute_equal R.new(VALID), R.new("08011990123457")
    assert_equal 1, [R.new(VALID), R.new("0801-1990-123456")].uniq.size
  end
end
