# frozen_string_literal: true

require "bigdecimal"

module Invoicehn
  # One line of the invoice.
  #
  # Art. 11 num. 1 requires per line: lit. d) "Descripción detallada del bien
  # vendido o del servicio prestado", lit. e) "Cantidad de unidades de bienes
  # vendidos", lit. f) "Valor unitario del bien vendido o del servicio
  # prestado", and — added by Acuerdo 725-2018 — lit. l) "Discriminación de los
  # descuentos y rebajas otorgados".
  #
  # The discount reduces the taxable base. Ley del ISV Art. 3 closes the
  # base-imponible article with: "No forman parte de la base gravable los
  # descuentos efectivos que consten en la factura o documento equivalente,
  # siempre que resulten normales según la costumbre comercial." Showing a
  # discount while taxing the gross value would overcharge the customer the very
  # tax that Art. 9 calls hurto to mis-collect.
  class LineItem
    attr_reader :description, :quantity, :unit_price, :discount, :treatment

    # @param discount [Money, nil] absolute amount taken off this line's gross
    #   value, expressed in the invoice's currency.
    def initialize(description:, quantity:, unit_price:, treatment:, discount: nil)
      @description = description.to_s.strip
      @quantity    = coerce_quantity(quantity)
      @unit_price  = coerce_money(unit_price, "valor unitario")
      @treatment   = TaxTreatment.fetch(treatment)
      @discount    = discount.nil? ? Money.zero(@unit_price.currency) : coerce_money(discount, "descuento")

      validate!
      freeze
    end

    def currency = @unit_price.currency

    # Quantity times unit price, before any discount.
    def gross = @unit_price * @quantity

    def discounted? = @discount.positive?

    # The amount that enters the taxable base for this line's rate.
    def taxable_base = gross - @discount

    # The tax this line contributes on its own. The invoice does not sum these:
    # it rounds once per rate on the summed base, so that the printed ISV equals
    # the printed rate times the printed subtotal. This is offered for line-level
    # display and reconciliation only.
    def isv = (taxable_base * @treatment.rate).round_statutory

    def total = taxable_base + isv

    def to_h
      {
        "description" => @description,
        "quantity" => @quantity.to_s("F"),
        "unit_price" => @unit_price.to_h,
        "discount" => @discount.to_h,
        "treatment" => @treatment.key.to_s
      }
    end

    def self.from_h(hash)
      new(
        description: hash["description"],
        quantity: BigDecimal(hash["quantity"]),
        unit_price: Money.from_h(hash["unit_price"]),
        discount: Money.from_h(hash["discount"]),
        treatment: hash["treatment"]
      )
    end

    def to_s
      "#{@quantity.to_s("F")} × #{@unit_price} #{@description} (#{@treatment})"
    end

    private

    def validate!
      if @description.empty?
        raise ValidationError,
              "la descripción del bien o servicio es obligatoria (Art. 11 num. 1 lit. d)"
      end
      raise ValidationError, "la cantidad debe ser mayor que cero (Art. 11 num. 1 lit. e)" unless @quantity.positive?
      raise ValidationError, "el valor unitario no puede ser negativo (Art. 11 num. 1 lit. f)" if @unit_price.negative?
      raise ValidationError, "el descuento no puede ser negativo" if @discount.negative?

      if @discount.currency != @unit_price.currency
        raise CurrencyMismatch, "el descuento está en #{@discount.currency} y el precio en #{@unit_price.currency}"
      end

      return unless @discount > gross

      raise ValidationError,
            "el descuento (#{@discount}) excede el valor de la línea (#{gross})"
    end

    def coerce_quantity(value)
      case value
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when Rational then BigDecimal(value, 20)
      when String then BigDecimal(value)
      when Float
        raise ValidationError, "Float no está permitido en cantidades; use BigDecimal, Integer o String"
      else
        raise ValidationError, "cantidad no numérica: #{value.inspect}"
      end
    rescue ArgumentError
      raise ValidationError, "cantidad no numérica: #{value.inspect}"
    end

    def coerce_money(value, label)
      return value if value.is_a?(Money)

      raise ValidationError, "#{label} debe ser un Invoicehn::Money, se recibió #{value.class}"
    end
  end
end
