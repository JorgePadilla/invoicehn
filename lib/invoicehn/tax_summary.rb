# frozen_string_literal: true

module Invoicehn
  # The per-rate breakdown an invoice must display.
  #
  # Art. 11 num. 1 requires:
  #   g) "Discriminación de los valores exentos, exonerados y de los gravados
  #      con alícuota cero, cuando corresponda"
  #   h) "Subtotales sujetos a los impuestos discriminados por tarifa o alícuota"
  #   i) "Discriminación de los impuestos por tarifa o alícuota"
  #   l) "Discriminación de los descuentos y rebajas otorgados" (Acuerdo 725-2018)
  #
  # Acuerdo 725-2018 also added Art. 10 num. 10, "Descuentos y rebajas
  # otorgados", to the *format* requirements. That makes the discounts line part
  # of the invoice layout rather than something shown only when a discount
  # exists — so #discount is always available and the renderers always print it,
  # zero or not.
  #
  # ISV is computed on the summed base per rate and rounded once, rather than
  # rounded per line and then summed. The norm does not settle the question —
  # Ley del ISV Art. 9 speaks of the charge "sobre el precio del artículo
  # vendido o servicio prestado", which reads per item, while Art. 11 lit. h/i
  # require the invoice to *display* a subtotal and a tax per rate. Rounding
  # once per rate is what keeps those printed figures consistent: rounding each
  # line and summing can produce a tax total that does not equal the printed
  # rate times the printed subtotal, and that discrepancy is exactly what an
  # auditor would question. The choice is recorded here because it is a reading
  # of an open point, not a settled rule.
  class TaxSummary
    # One row of the breakdown: everything the document must show for a single
    # tax treatment.
    Bucket = Struct.new(:treatment, :gross, :discount, :base, :isv, keyword_init: true) do
      def total = base + isv
      def empty? = gross.zero? && discount.zero?
      def to_s = "#{treatment}: base #{base}, ISV #{isv}"

      def to_h
        {
          "treatment" => treatment.key.to_s,
          "label" => treatment.label,
          "rate" => treatment.rate.to_s("F"),
          "gross" => gross.to_h,
          "discount" => discount.to_h,
          "base" => base.to_h,
          "isv" => isv.to_h
        }
      end
    end

    attr_reader :currency, :buckets

    def initialize(line_items, currency: "HNL")
      @currency = currency
      @buckets = build_buckets(Array(line_items))
      freeze
    end

    # Only the treatments actually present, in the order the law lists them
    # (exento, exonerado, gravado 0%, then the taxed rates).
    def present_buckets = @buckets.reject(&:empty?)

    def bucket_for(treatment)
      key = TaxTreatment.fetch(treatment).key
      @buckets.find { |b| b.treatment.key == key }
    end

    def gross    = sum_of(:gross)
    def discount = sum_of(:discount)

    # The sum of all bases, taxed and untaxed alike — the invoice's subtotal
    # after discounts and before ISV.
    def subtotal = sum_of(:base)

    def isv_total = sum_of(:isv)

    def total = subtotal + isv_total

    # Art. 11 num. 3: "Para respaldar el crédito fiscal en los casos que la
    # factura sustente ventas exentas y gravadas, se reconocerán únicamente las
    # ventas gravadas." This is the portion of the invoice that supports the
    # buyer's crédito fiscal.
    def credito_fiscal_base
      Money.sum(taxed_buckets.map(&:base), currency: @currency)
    end

    def taxed_buckets = present_buckets.select { |b| b.treatment.taxed? }
    def untaxed_buckets = present_buckets.reject { |b| b.treatment.taxed? }

    # True when the invoice mixes taxed and untaxed supplies, which is the
    # condition Art. 11 num. 3 addresses.
    def mixed_supply?
      taxed_buckets.any? && untaxed_buckets.any?
    end

    def to_h
      {
        "currency" => @currency,
        "buckets" => present_buckets.map(&:to_h),
        "gross" => gross.to_h,
        "discount" => discount.to_h,
        "subtotal" => subtotal.to_h,
        "isv_total" => isv_total.to_h,
        "total" => total.to_h
      }
    end

    private

    def build_buckets(line_items)
      TaxTreatment.all.map do |treatment|
        lines = line_items.select { |item| item.treatment == treatment }

        gross    = Money.sum(lines.map(&:gross), currency: @currency).round_statutory
        discount = Money.sum(lines.map(&:discount), currency: @currency).round_statutory

        # Rounded once here, then taxed — so the printed ISV equals the printed
        # rate applied to the printed base.
        base = Money.sum(lines.map(&:taxable_base), currency: @currency).round_statutory
        isv  = (base * treatment.rate).round_statutory

        Bucket.new(treatment: treatment, gross: gross, discount: discount, base: base, isv: isv).freeze
      end.freeze
    end

    def sum_of(field)
      Money.sum(@buckets.map { |b| b.public_send(field) }, currency: @currency)
    end
  end
end
