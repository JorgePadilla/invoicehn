# frozen_string_literal: true

require "test_helper"

# Art. 11 num. 1 lit. k) — "Importe total en números y letras".
class TestSpanishNumerals < Minitest::Test
  N = Invoicehn::SpanishNumerals

  def test_units_and_teens
    assert_equal "CERO", N.integer_to_words(0)
    assert_equal "UNO", N.integer_to_words(1)
    assert_equal "QUINCE", N.integer_to_words(15)
    assert_equal "DIECISÉIS", N.integer_to_words(16)
    assert_equal "DIECINUEVE", N.integer_to_words(19)
  end

  def test_twenties_contract_into_one_word
    assert_equal "VEINTE", N.integer_to_words(20)
    assert_equal "VEINTIUNO", N.integer_to_words(21)
    assert_equal "VEINTIDÓS", N.integer_to_words(22)
    assert_equal "VEINTISÉIS", N.integer_to_words(26)
  end

  def test_tens_above_thirty_take_y
    assert_equal "TREINTA", N.integer_to_words(30)
    assert_equal "TREINTA Y UNO", N.integer_to_words(31)
    assert_equal "NOVENTA Y NUEVE", N.integer_to_words(99)
  end

  def test_cien_versus_ciento
    assert_equal "CIEN", N.integer_to_words(100)
    assert_equal "CIENTO UNO", N.integer_to_words(101)
    assert_equal "CIENTO CINCUENTA", N.integer_to_words(150)
    assert_equal "QUINIENTOS", N.integer_to_words(500)
    assert_equal "NOVECIENTOS NOVENTA Y NUEVE", N.integer_to_words(999)
  end

  def test_thousands
    # 1000 is MIL, never UN MIL.
    assert_equal "MIL", N.integer_to_words(1_000)
    assert_equal "MIL UNO", N.integer_to_words(1_001)
    assert_equal "MIL DOSCIENTOS TREINTA Y CUATRO", N.integer_to_words(1_234)
    assert_equal "DOS MIL", N.integer_to_words(2_000)
    assert_equal "NOVECIENTOS NOVENTA Y NUEVE MIL NOVECIENTOS NOVENTA Y NUEVE",
                 N.integer_to_words(999_999)
  end

  # "uno" apocopates to "un" before MIL and MILLONES.
  def test_apocope_before_mil_and_millones
    assert_equal "VEINTIÚN MIL", N.integer_to_words(21_000)
    assert_equal "TREINTA Y UN MIL", N.integer_to_words(31_000)
    assert_equal "UN MILLÓN", N.integer_to_words(1_000_000)
    assert_equal "VEINTIÚN MILLONES", N.integer_to_words(21_000_000)
  end

  def test_millions
    assert_equal "DOS MILLONES", N.integer_to_words(2_000_000)
    assert_equal "UN MILLÓN DOSCIENTOS TREINTA Y CUATRO MIL QUINIENTOS SESENTA Y SIETE",
                 N.integer_to_words(1_234_567)
  end

  def test_money_renders_currency_and_cents
    assert_equal "MIL DOSCIENTOS TREINTA Y CUATRO LEMPIRAS CON 56/100",
                 N.money_to_words(hnl("1234.56"))
  end

  # The reason the renderer takes a currency at all: a USD invoice must not
  # claim to be denominated in lempiras.
  def test_usd_reads_dolares
    assert_equal "MIL DOSCIENTOS TREINTA Y CUATRO DÓLARES CON 56/100",
                 N.money_to_words(usd("1234.56"))
  end

  # Spanish apocopates "uno" directly before the noun: un lempira, not uno
  # lempira. This is the line an accountant reads aloud, so the grammar has to
  # be right.
  def test_singular_currency_for_exactly_one
    assert_equal "UN LEMPIRA CON 00/100", N.money_to_words(hnl(1))
    assert_equal "UN DÓLAR CON 00/100", N.money_to_words(usd(1))
  end

  def test_apocope_before_the_currency_noun
    assert_equal "VEINTIÚN LEMPIRAS CON 00/100", N.money_to_words(hnl(21))
    assert_equal "TREINTA Y UN LEMPIRAS CON 00/100", N.money_to_words(hnl(31))
    assert_equal "CIENTO UN DÓLARES CON 00/100", N.money_to_words(usd(101))
    assert_equal "MIL UN LEMPIRAS CON 50/100", N.money_to_words(hnl("1001.50"))
  end

  # Only a trailing "uno" apocopates; numbers not ending in one are untouched.
  def test_other_numbers_keep_their_full_form
    assert_equal "CIEN LEMPIRAS CON 00/100", N.money_to_words(hnl(100))
    assert_equal "VEINTIDÓS LEMPIRAS CON 00/100", N.money_to_words(hnl(22))
    assert_equal "MIL LEMPIRAS CON 00/100", N.money_to_words(hnl(1000))
  end

  def test_zero_and_cents_only
    assert_equal "CERO LEMPIRAS CON 00/100", N.money_to_words(hnl(0))
    assert_equal "CERO LEMPIRAS CON 50/100", N.money_to_words(hnl("0.50"))
  end

  # The words must agree with the printed figure, so they are produced from the
  # statutorily rounded amount rather than the raw one.
  def test_words_use_the_statutorily_rounded_amount
    assert_equal "DIEZ LEMPIRAS CON 01/100", N.money_to_words(hnl("10.005"))
    assert_equal "DIEZ LEMPIRAS CON 00/100", N.money_to_words(hnl("10.004"))
  end

  def test_cents_are_zero_padded
    assert_equal "CINCO LEMPIRAS CON 05/100", N.money_to_words(hnl("5.05"))
  end

  def test_rejects_out_of_range
    assert_raises(Invoicehn::ValidationError) { N.integer_to_words(-1) }
    assert_raises(Invoicehn::ValidationError) { N.integer_to_words(10**13) }
  end
end
