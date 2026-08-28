# frozen_string_literal: true

require "bigdecimal"
require "date"

module Invoicehn
  # The exchange rate shown on an invoice denominated in a currency other than
  # the Lempira.
  #
  # Art. 11 closes with a paragraph that governs both invoice types: "En ambos
  # casos, cuando el Obligado Tributario emita facturas con otra denominación
  # monetaria, debe indicar la tasa de cambio vigente a la fecha de emisión."
  #
  # Note what the norm does *not* say. It does not require a computed Lempira
  # equivalent, does not name a rate source, and does not fix the rate's
  # precision — and no further SAR guidance on the point exists. The Banco
  # Central de Honduras daily reference rate is the market default and is what
  # this library names when no source is given, but a bank or negotiated rate is
  # not visibly prohibited, so the source is a free-text field.
  class ExchangeRate
    DEFAULT_SOURCE = "Banco Central de Honduras"

    attr_reader :rate, :date, :source, :currency

    # @param rate [BigDecimal, String, Integer] lempiras per one unit of
    #   +currency+.
    # @param date [Date, String] must equal the invoice's issue date — the
    #   article requires the rate "vigente a la fecha de emisión".
    def initialize(rate:, date:, currency: "USD", source: DEFAULT_SOURCE)
      @rate = coerce_rate(rate)
      @date = coerce_date(date)
      @currency = currency.to_s.upcase
      @source = source.to_s.strip
      @source = DEFAULT_SOURCE if @source.empty?

      raise ValidationError, "la tasa de cambio debe ser mayor que cero" unless @rate.positive?
      raise ValidationError, "moneda no soportada: #{currency}" unless Money.currency?(@currency)

      freeze
    end

    # Whether this rate is the one in effect on the given issue date.
    def current_on?(issue_date) = @date == issue_date

    # The Lempira equivalent of a foreign-currency amount. Not required by the
    # norm, but useful on the face of the document and for the ledger.
    def to_lempiras(money)
      unless money.currency == @currency
        raise CurrencyMismatch,
              "la tasa convierte desde #{@currency}, no desde #{money.currency}"
      end

      Money.new(money.amount * @rate, "HNL").round_statutory
    end

    # "1 USD = L 24.6543 (Banco Central de Honduras, 2026-08-28)"
    def to_s
      "1 #{@currency} = L #{@rate.to_s("F")} (#{@source}, #{@date.iso8601})"
    end

    def to_h
      {
        "rate" => @rate.to_s("F"),
        "date" => @date.iso8601,
        "currency" => @currency,
        "source" => @source
      }
    end

    def self.from_h(hash)
      return nil if hash.nil?

      new(
        rate: hash["rate"],
        date: hash["date"],
        currency: hash["currency"] || "USD",
        source: hash["source"]
      )
    end

    private

    def coerce_rate(value)
      case value
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when String then BigDecimal(value)
      when Float
        raise ValidationError, "Float no está permitido en la tasa de cambio; use BigDecimal o String"
      else
        raise ValidationError, "tasa de cambio no numérica: #{value.inspect}"
      end
    rescue ArgumentError
      raise ValidationError, "tasa de cambio no numérica: #{value.inspect}"
    end

    def coerce_date(value)
      case value
      when Date then value
      when String then Date.parse(value)
      else
        raise ValidationError, "fecha de la tasa de cambio inválida: #{value.inspect}"
      end
    rescue ArgumentError, TypeError
      raise ValidationError, "fecha de la tasa de cambio inválida: #{value.inspect}"
    end
  end
end
