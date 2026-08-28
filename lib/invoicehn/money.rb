# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"

module Invoicehn
  # An amount of money, held as a BigDecimal at full precision.
  #
  # Rounding to centavos happens only through #round_statutory, which implements
  # Artículo 9 de la Ley del Impuesto Sobre Ventas (redactado por Decreto 135-94):
  #
  #   "Cuando al calcular dicho gravamen, resulte una fracción menor de 0.005 de
  #    Lempira, deberá reducirse el recargo hasta la cifra de centavos próxima
  #    inferior, en cambio, si la fracción citada es igual o mayor de 0.005 de
  #    Lempira, entonces podrá subirse el cómputo hasta la cifra de centavos
  #    próxima superior. El recargo del impuesto al consumidor fuera de la regla
  #    establecida en el párrafo anterior, se considerará como hurto."
  #
  # Charging the customer an amount rounded outside that rule is characterised by
  # the statute as theft, so this is a correctness requirement and not a policy
  # choice. Float never appears in this class or in the tax path; test/test_no_float.rb
  # enforces that.
  class Money
    include Comparable

    SCALE = 2
    CURRENCIES = {
      "HNL" => { symbol: "L", singular: "LEMPIRA", plural: "LEMPIRAS" },
      "USD" => { symbol: "$", singular: "DÓLAR", plural: "DÓLARES" }
    }.freeze

    attr_reader :amount, :currency

    class << self
      def zero(currency = "HNL")
        new(0, currency)
      end

      # Sums a collection, inferring the currency from the members. An empty
      # collection has no currency to infer, so the caller supplies one.
      def sum(monies, currency: "HNL")
        monies = Array(monies)
        return zero(currency) if monies.empty?

        monies.reduce { |acc, m| acc + m }
      end

      def currency?(code)
        CURRENCIES.key?(code.to_s.upcase)
      end
    end

    def initialize(amount, currency = "HNL")
      @currency = currency.to_s.upcase
      raise ValidationError, "moneda no soportada: #{currency}" unless CURRENCIES.key?(@currency)

      @amount = coerce_to_decimal(amount)
      freeze
    end

    # Rounds to centavos under Ley del ISV Art. 9: a fraction of a centavo below
    # 0.005 lempira rounds down, one at or above 0.005 rounds up. That is
    # half-up at the centavo, with the tie going up.
    def round_statutory
      self.class.new(@amount.round(SCALE, BigDecimal::ROUND_HALF_UP), @currency)
    end

    def +(other)
      combine(other) { |a, b| a + b }
    end

    def -(other)
      combine(other) { |a, b| a - b }
    end

    # Scaling by a quantity or a tax rate. The result keeps full precision;
    # call #round_statutory at the point the amount becomes payable.
    def *(other)
      self.class.new(@amount * coerce_to_decimal(other), @currency)
    end

    def /(other)
      divisor = coerce_to_decimal(other)
      raise ZeroDivisionError, "división por cero" if divisor.zero?

      self.class.new(@amount / divisor, @currency)
    end

    def -@
      self.class.new(-@amount, @currency)
    end

    def zero? = @amount.zero?
    def positive? = @amount.positive?
    def negative? = @amount.negative?

    def <=>(other)
      return nil unless other.is_a?(self.class)

      assert_same_currency!(other)
      @amount <=> other.amount
    end

    def ==(other)
      other.is_a?(self.class) && other.currency == @currency && other.amount == @amount
    end
    alias eql? ==

    def hash = [@amount, @currency].hash

    def symbol = CURRENCIES.fetch(@currency)[:symbol]
    def currency_word = CURRENCIES.fetch(@currency)[@amount.abs == 1 ? :singular : :plural]

    # "L 1,234.56" — the symbol satisfies Art. 11 num. 1 lit. j).
    def to_s
      integer, fraction = to_fixed.delete("-").split(".")
      grouped = integer.reverse.scan(/\d{1,3}/).join(",").reverse
      "#{"-" if @amount.negative?}#{symbol} #{grouped}.#{fraction}"
    end

    def inspect = "#<Invoicehn::Money #{self}>"

    # Always two decimals: BigDecimal#to_s("F") would render 900 as "900.0",
    # and a fiscal amount must show both centavo digits.
    def to_fixed
      rounded = @amount.round(SCALE, BigDecimal::ROUND_HALF_UP)
      integer, fraction = rounded.abs.to_s("F").split(".")
      "#{"-" if rounded.negative?}#{integer}.#{fraction.to_s.ljust(SCALE, "0")[0, SCALE]}"
    end

    # Serialised as a string so no downstream JSON parser can turn it into a Float.
    def to_h
      { "amount" => to_fixed, "currency" => @currency }
    end

    def self.from_h(hash)
      new(hash["amount"] || hash[:amount], hash["currency"] || hash[:currency] || "HNL")
    end

    private

    def combine(other)
      assert_same_currency!(other)
      self.class.new(yield(@amount, other.amount), @currency)
    end

    def assert_same_currency!(other)
      return if other.currency == @currency

      raise CurrencyMismatch, "no se pueden combinar #{@currency} y #{other.currency}"
    end

    # Accepts Integer, BigDecimal, Rational, or a numeric String. Float is
    # rejected outright: admitting it here would let binary rounding error into
    # a figure the statute makes criminal to get wrong.
    def coerce_to_decimal(value)
      case value
      when BigDecimal then value
      when Integer    then BigDecimal(value)
      when Rational   then BigDecimal(value, 20)
      when Money      then value.amount
      when String
        begin
          BigDecimal(value)
        rescue ArgumentError
          raise ValidationError, "importe no numérico: #{value.inspect}"
        end
      when Float
        raise ValidationError,
              "Float no está permitido en importes (Ley del ISV Art. 9); " \
              "use BigDecimal, Integer o String, p. ej. \"#{value}\""
      else
        raise ValidationError, "importe no numérico: #{value.inspect}"
      end
    end
  end
end
