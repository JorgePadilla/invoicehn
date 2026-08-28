# frozen_string_literal: true

require "test_helper"

# Ley del Impuesto Sobre Ventas (Decreto-Ley 24), Artículo 9, redactado por
# Decreto 135-94:
#
#   "...resulte una fracción menor de 0.005 de Lempira, deberá reducirse el
#    recargo hasta la cifra de centavos próxima inferior, en cambio, si la
#    fracción citada es igual o mayor de 0.005 de Lempira, entonces podrá
#    subirse el cómputo hasta la cifra de centavos próxima superior. El recargo
#    del impuesto al consumidor fuera de la regla establecida en el párrafo
#    anterior, se considerará como hurto..."
#
# The statute makes mis-rounding an offence, so these cases pin the exact
# boundary rather than trusting a library default.
class TestIsvArt9Rounding < Minitest::Test
  def test_fraction_below_half_centavo_rounds_down
    assert_equal dec("10.00"), hnl("10.004").round_statutory.amount
    assert_equal dec("10.00"), hnl("10.00499").round_statutory.amount
    assert_equal dec("0.00"),  hnl("0.0049").round_statutory.amount
  end

  def test_fraction_exactly_half_centavo_rounds_up
    assert_equal dec("10.01"), hnl("10.005").round_statutory.amount
    assert_equal dec("0.01"),  hnl("0.005").round_statutory.amount
  end

  def test_fraction_above_half_centavo_rounds_up
    assert_equal dec("10.01"), hnl("10.00501").round_statutory.amount
    assert_equal dec("10.01"), hnl("10.006").round_statutory.amount
  end

  # The tie goes away from zero on both sides, so a credit is not quietly
  # shaved in the issuer's favour.
  def test_negative_amounts_round_symmetrically
    assert_equal dec("-10.01"), hnl("-10.005").round_statutory.amount
    assert_equal dec("-10.00"), hnl("-10.004").round_statutory.amount
  end

  def test_already_rounded_amounts_are_unchanged
    assert_equal dec("10.01"), hnl("10.01").round_statutory.amount
    assert_equal dec("0.00"),  hnl(0).round_statutory.amount
  end

  # 15% of 33.37 is 5.0055 — the kind of ordinary line that lands on the tie.
  def test_realistic_isv_computation_at_the_boundary
    isv = hnl("33.37") * dec("0.15")

    assert_equal dec("5.0055"), isv.amount
    assert_equal dec("5.01"), isv.round_statutory.amount
  end

  def test_float_is_refused_outright
    error = assert_raises(Invoicehn::ValidationError) { hnl(10.005) }
    assert_match(/Float no está permitido/, error.message)
  end

  def test_precision_is_retained_until_rounding_is_requested
    # Three lines of 0.334 each: rounding per line then summing gives 1.00,
    # summing then rounding gives 1.00 as well — but the intermediate value
    # must not have been silently truncated along the way.
    line = hnl("0.334")
    total = line + line + line

    assert_equal dec("1.002"), total.amount
    assert_equal dec("1.00"), total.round_statutory.amount
  end
end
