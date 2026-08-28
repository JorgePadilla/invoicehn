# frozen_string_literal: true

require "bigdecimal"

module Invoicehn
  # How a line is treated for Impuesto Sobre Ventas.
  #
  # Art. 11 num. 1 lit. g) requires "Discriminación de los valores exentos,
  # exonerados y de los gravados con alícuota cero", and lit. h) and i) require
  # subtotals and taxes broken out "por tarifa o alícuota". Three of these
  # categories yield no tax but must still be told apart on the face of the
  # document, so the treatment is modelled as an identity rather than as a bare
  # rate.
  #
  # Rates come from Decreto 278-2013 Art. 16 (La Gaceta 33,316, in force
  # 1 January 2014), which reformed Art. 6 of the Ley del Impuesto Sobre Ventas:
  # a general rate of 15% and 18% on "las bebidas alcohólicas, cerveza y
  # cigarrillos al igual que los boletos aéreos de clase ejecutiva".
  class TaxTreatment
    include Comparable

    attr_reader :key, :rate, :label

    def initialize(key, rate, label, order)
      @key = key.to_sym
      @rate = rate
      @label = label
      @order = order
      freeze
    end

    # No tax applies — the good or service is outside the tax's reach
    # (Ley del ISV Art. 15).
    EXENTO = new(:exento, BigDecimal("0"), "Exento", 0)

    # Taxable in principle, but the purchaser holds an exoneration. Art. 10
    # num. 8 and Art. 11 num. 4 require the exoneration's supporting numbers on
    # the invoice.
    EXONERADO = new(:exonerado, BigDecimal("0"), "Exonerado", 1)

    # Taxed at zero. Art. 12: "En caso de exportaciones con mercancías gravadas,
    # por concepto del Impuesto Sobre Ventas, los Obligados Tributarios deben
    # extender la Factura con tasa cero."
    GRAVADO_0 = new(:gravado_0, BigDecimal("0"), "Gravado 0%", 2)

    # The general rate.
    GRAVADO_15 = new(:gravado_15, BigDecimal("0.15"), "Gravado 15%", 3)

    # The special rate. Which goods fall here is ambiguously drafted across
    # sources — the decree names only "clase ejecutiva" for air tickets while
    # the Art. 6 enumeration it amends adds "otros productos elaborados de
    # tabaco". Deciding whether a given product qualifies is the operator's
    # call; this library only computes once that call is made.
    GRAVADO_18 = new(:gravado_18, BigDecimal("0.18"), "Gravado 18%", 4)

    ALL = {
      exento: EXENTO,
      exonerado: EXONERADO,
      gravado_0: GRAVADO_0,
      gravado_15: GRAVADO_15,
      gravado_18: GRAVADO_18
    }.freeze

    GENERAL_RATE = BigDecimal("0.15")
    SPECIAL_RATE = BigDecimal("0.18")

    class << self
      def fetch(key)
        return key if key.is_a?(TaxTreatment)

        ALL.fetch(key.to_s.to_sym) do
          raise ValidationError,
                "tratamiento fiscal desconocido: #{key.inspect} (válidos: #{ALL.keys.join(", ")})"
        end
      end

      def all = ALL.values

      # The categories that must be shown separately even though they carry no
      # tax (Art. 11 num. 1 lit. g).
      def untaxed = [EXENTO, EXONERADO, GRAVADO_0]

      def taxed = [GRAVADO_15, GRAVADO_18]
    end

    def taxed? = @rate.positive?
    def untaxed? = !taxed?
    def exonerado? = @key == :exonerado
    def exento? = @key == :exento

    # 15% renders as "15%", not "15.0%".
    def rate_percent = (@rate * 100).to_i

    def to_s = @label
    def to_sym = @key
    def inspect = "#<Invoicehn::TaxTreatment #{@key}>"

    def <=>(other) = other.is_a?(self.class) ? @order <=> other.instance_variable_get(:@order) : nil

    def ==(other) = other.is_a?(self.class) && other.key == @key
    alias eql? ==

    def hash = @key.hash

    # The five categories above are the complete set the law recognises; a
    # sixth cannot be invented at runtime.
    private_class_method :new
  end
end
