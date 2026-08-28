# frozen_string_literal: true

module Invoicehn
  # Renders an amount as Spanish words for the "importe total en números y
  # letras" of Art. 11 num. 1 lit. k).
  #
  # The currency name is a parameter, not a constant: a USD invoice must read
  # DÓLARES. Hard-coding LEMPIRAS would make the document misstate its own
  # amount.
  module SpanishNumerals
    UNITS = %w[
      CERO UNO DOS TRES CUATRO CINCO SEIS SIETE OCHO NUEVE DIEZ
      ONCE DOCE TRECE CATORCE QUINCE DIECISÉIS DIECISIETE DIECIOCHO DIECINUEVE
    ].freeze

    TENS = {
      20 => "VEINTE", 30 => "TREINTA", 40 => "CUARENTA", 50 => "CINCUENTA",
      60 => "SESENTA", 70 => "SETENTA", 80 => "OCHENTA", 90 => "NOVENTA"
    }.freeze

    # 21-29 contract into a single word and carry an accent on 22, 23 and 26.
    TWENTIES = {
      21 => "VEINTIUNO", 22 => "VEINTIDÓS", 23 => "VEINTITRÉS", 24 => "VEINTICUATRO",
      25 => "VEINTICINCO", 26 => "VEINTISÉIS", 27 => "VEINTISIETE", 28 => "VEINTIOCHO",
      29 => "VEINTINUEVE"
    }.freeze

    HUNDREDS = {
      100 => "CIENTO", 200 => "DOSCIENTOS", 300 => "TRESCIENTOS", 400 => "CUATROCIENTOS",
      500 => "QUINIENTOS", 600 => "SEISCIENTOS", 700 => "SETECIENTOS",
      800 => "OCHOCIENTOS", 900 => "NOVECIENTOS"
    }.freeze

    MAX = 999_999_999_999

    module_function

    # Money -> "MIL DOSCIENTOS TREINTA Y CUATRO LEMPIRAS CON 56/100"
    def money_to_words(money)
      rounded = money.round_statutory.amount
      negative = rounded.negative?
      integer, cents = rounded.abs.to_s("F").split(".")
      integer = integer.to_i
      cents = cents.to_s.ljust(2, "0")[0, 2]

      noun = integer == 1 ? singular_of(money.currency) : plural_of(money.currency)

      # "uno" apocopates directly before the noun: un lempira, veintiún
      # lempiras, ciento un dólares. Appending the raw cardinal would print
      # "UNO LEMPIRA", which is not Spanish — and this is the line an accountant
      # reads aloud.
      words = "#{apocopate(integer_to_words(integer))} #{noun} CON #{cents}/100"
      negative ? "MENOS #{words}" : words
    end

    def singular_of(currency) = Money::CURRENCIES.fetch(currency.to_s.upcase)[:singular]
    def plural_of(currency)   = Money::CURRENCIES.fetch(currency.to_s.upcase)[:plural]

    # Cardinal in the masculine form, which is what both LEMPIRA and DÓLAR take.
    def integer_to_words(number)
      number = Integer(number)
      raise ValidationError, "número negativo" if number.negative?
      raise ValidationError, "número fuera de rango: #{number}" if number > MAX

      return UNITS[0] if number.zero?

      millions, remainder = number.divmod(1_000_000)
      parts = []
      parts << millions_phrase(millions) if millions.positive?
      parts << below_million(remainder) if remainder.positive?
      parts.join(" ")
    end

    def millions_phrase(millions)
      # "UN MILLÓN", not "UNO MILLÓN" — uno apocopates before a noun.
      return "UN MILLÓN" if millions == 1

      "#{apocopate(below_million(millions))} MILLONES"
    end

    def below_million(number)
      thousands, remainder = number.divmod(1_000)
      parts = []

      if thousands.positive?
        # 1000 is "MIL", never "UN MIL".
        parts << (thousands == 1 ? "MIL" : "#{apocopate(below_thousand(thousands))} MIL")
      end
      parts << below_thousand(remainder) if remainder.positive?
      parts.join(" ")
    end

    def below_thousand(number)
      return "" if number.zero?
      return "CIEN" if number == 100

      hundreds = (number / 100) * 100
      remainder = number % 100
      parts = []
      parts << HUNDREDS[hundreds] if hundreds.positive?
      parts << below_hundred(remainder) if remainder.positive?
      parts.join(" ")
    end

    def below_hundred(number)
      return "" if number.zero?
      return UNITS[number] if number < 20
      return TWENTIES[number] if TWENTIES.key?(number)

      tens = (number / 10) * 10
      unit = number % 10
      unit.zero? ? TENS[tens] : "#{TENS[tens]} Y #{UNITS[unit]}"
    end

    # "UNO" becomes "UN" directly before a noun — MIL, MILLONES, or the currency
    # name: veintiún mil, un lempira, ciento un dólares.
    def apocopate(phrase)
      phrase
        .sub(/\bVEINTIUNO\z/, "VEINTIÚN")
        .sub(/\bUNO\z/, "UN")
    end
  end
end
