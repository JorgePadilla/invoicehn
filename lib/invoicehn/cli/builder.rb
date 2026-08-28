# frozen_string_literal: true

module Invoicehn
  module CLI
    # Turns a plain hash — from a JSON file or the wizard — into an issued
    # invoice. Shared by the scriptable and interactive paths so both go through
    # exactly the same construction and validation.
    class Builder
      attr_reader :issuance

      def initialize(issuance)
        @issuance = issuance
      end

      def from_hash(data, identifier: "000-001-01")
        currency = (data["currency"] || "HNL").to_s.upcase

        @issuance.issue(
          identifier: identifier,
          customer: build_customer(data["customer"] || {}),
          line_items: Array(data["items"] || data["line_items"]).map { |i| build_line(i, currency) },
          currency: currency,
          exchange_rate: build_rate(data["exchange_rate"], currency),
          notes: data["notes"]
        )
      end

      def build_customer(data)
        kind = (data["kind"] || data["tipo"] || "consumidor_final").to_s

        case kind
        when "taxpayer", "obligado_tributario"
          Customer::Taxpayer.new(name: data["name"], rtn: data["rtn"])
        when "exonerado"
          Customer::Exonerado.new(
            name: data["name"], rtn: data["rtn"],
            purchase_order: data["purchase_order"],
            exoneration_registry: data["exoneration_registry"],
            sag_registry: data["sag_registry"]
          )
        else
          Customer::ConsumidorFinal.new(
            name: data["name"],
            identification_type: data["identification_type"],
            identification_number: data["identification_number"]
          )
        end
      end

      def build_line(data, currency)
        discount = data["discount"] || data["descuento"]

        LineItem.new(
          description: data["description"] || data["descripcion"],
          quantity: to_decimal(data["quantity"] || data["cantidad"] || 1),
          unit_price: Money.new(to_decimal(data["unit_price"] || data["precio"]), currency),
          discount: discount && Money.new(to_decimal(discount), currency),
          treatment: data["treatment"] || data["tratamiento"] || :gravado_15
        )
      end

      def build_rate(data, currency)
        return nil if data.nil?
        return ExchangeRate.from_h(data) if data.is_a?(Hash)

        ExchangeRate.new(rate: to_decimal(data), date: Date.today, currency: currency)
      end

      private

      # JSON numbers arrive as Float, which must never reach a fiscal figure —
      # so they are converted through their decimal text form, not their binary
      # value.
      def to_decimal(value)
        case value
        when BigDecimal then value
        when Integer then BigDecimal(value)
        when Float then BigDecimal(value.to_s)
        when String then BigDecimal(value)
        when nil then raise ValidationError, "falta un importe o cantidad en el archivo"
        else raise ValidationError, "valor no numérico: #{value.inspect}"
        end
      rescue ArgumentError
        raise ValidationError, "valor no numérico: #{value.inspect}"
      end
    end
  end
end
