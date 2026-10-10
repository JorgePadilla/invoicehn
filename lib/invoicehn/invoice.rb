# frozen_string_literal: true

require "date"

module Invoicehn
  # A Factura (Comprobante Fiscal, tipo 01), or one of the two Documentos
  # Complementarios that adjust it: the Nota de Crédito (tipo 06) and the Nota
  # de Débito (tipo 07). The type is the one the correlative declares (Art. 10
  # num. 7 lit. c; Arts. 25 and 27 num. 5 lit. c).
  #
  # The three share their content: issuer, CAI, rango, fecha límite,
  # correlative, customer, detail lines, ISV by rate and total in words. A note
  # adds what Arts. 26 and 28 require at the moment of issue: the data of the
  # document it applies to (`reference`, a DocumentReference) and the reason
  # for issuing it (`motivo`). A Factura carries neither.
  #
  # An issued invoice is immutable. Art. 41 provides the only correction: "En el
  # caso de emisión de Comprobantes Fiscales y/o Documentos Complementarios con
  # errores, estos deben ser anulados, consignando en los mismos la leyenda
  # 'ANULADA'." Annulment returns a new object; it does not mutate the record,
  # and the correlative it consumed is never reused.
  class Invoice
    DOCUMENT_NAME = "Factura" # Art. 10 num. 2

    STATUS_ISSUED = "emitida"
    STATUS_ANNULLED = "anulada"

    attr_reader :correlative, :issuer, :customer, :authorization, :line_items,
                :issue_date, :currency, :exchange_rate, :status,
                :annulment_reason, :annulled_at, :notes, :reference, :motivo

    def initialize(correlative:, issuer:, customer:, authorization:, line_items:,
                   issue_date: nil, currency: "HNL", exchange_rate: nil,
                   status: STATUS_ISSUED, annulment_reason: nil, annulled_at: nil,
                   notes: nil, reference: nil, motivo: nil)
      @correlative   = correlative.is_a?(Correlative) ? correlative : Correlative.parse(correlative)
      @issuer        = issuer
      @customer      = customer
      @authorization = authorization
      @line_items    = Array(line_items).freeze
      @issue_date    = coerce_date(issue_date || Invoicehn.today)
      @currency      = currency.to_s.upcase
      @exchange_rate = exchange_rate
      @status        = status
      @annulment_reason = annulment_reason
      @annulled_at   = annulled_at && coerce_date(annulled_at)
      @notes         = notes.to_s.strip
      @reference     = coerce_reference(reference)
      @motivo        = motivo.to_s.strip

      if !note? && (@reference || !@motivo.empty?)
        raise ValidationError,
              "sólo las notas de crédito y de débito llevan documento de referencia y motivo " \
              "(Arts. 26 y 28 num. 3 y 4); #{@correlative} es #{document_name}"
      end

      @summary = TaxSummary.new(@line_items, currency: @currency)
      freeze
    end

    # The per-rate breakdown required by Art. 11 num. 1 lit. g) h) i) and l).
    attr_reader :summary

    def subtotal  = @summary.subtotal
    def discount  = @summary.discount
    def isv_total = @summary.isv_total
    def total     = @summary.total

    # Art. 11 num. 1 lit. k) — "Importe total en números y letras". Always
    # rendered: required for a crédito-fiscal invoice and permitted for a
    # consumidor final, so there is one path rather than a conditional.
    def total_in_words = SpanishNumerals.money_to_words(total)

    def foreign_currency? = @currency != "HNL"

    def document_type = @correlative.document_type

    # "Factura", "Nota de Crédito" or "Nota de Débito" — the denominación each
    # article fixes (Art. 10 num. 2, Art. 25 num. 2, Art. 27 num. 2).
    def document_name = @correlative.document_type_name

    def factura? = @correlative.factura?
    def credit_note? = @correlative.credit_note?
    def debit_note? = @correlative.debit_note?
    def note? = @correlative.note?

    # The Lempira equivalent of the total. Not required by the norm, which asks
    # only for the rate, but shown when a rate is present and used to measure
    # the Art. 11 num. 2 threshold, which the article states in lempiras.
    #
    # Returns nil rather than raising when no usable rate is on file: a missing
    # or mismatched rate is already reported by the Art. 11 closing-paragraph
    # rule, and a query used during validation must not blow up the validator.
    def total_in_lempiras
      return total unless foreign_currency?
      return nil if @exchange_rate.nil? || @exchange_rate.currency != @currency

      @exchange_rate.to_lempiras(total)
    end

    def annulled? = @status == STATUS_ANNULLED
    def issued? = @status == STATUS_ISSUED

    # Art. 41. Returns a new invoice carrying the ANULADA legend; the original
    # object is untouched and the correlative stays consumed.
    def annul(reason:, on: Invoicehn.today)
      raise ImmutableDocument, "#{document_name} #{@correlative} ya está anulada" if annulled?

      reason = reason.to_s.strip
      raise ValidationError, "debe indicarse el motivo de la anulación" if reason.empty?

      with(status: STATUS_ANNULLED, annulment_reason: reason, annulled_at: coerce_date(on))
    end

    # Raises on errors only. Warnings (Art. 11 num. 3's mixed-supply notice) are
    # information the document should carry, not grounds to refuse it.
    def validate!(on: Invoicehn.today)
      errors = Compliance::Validator.new(self, on: on).errors
      raise ComplianceError, errors if errors.any?

      self
    end

    def compliant?(on: Invoicehn.today) = Compliance::Validator.new(self, on: on).valid?

    def violations(on: Invoicehn.today) = Compliance::Validator.new(self, on: on).violations
    def warnings(on: Invoicehn.today) = Compliance::Validator.new(self, on: on).warnings

    def to_h
      {
        "correlative" => @correlative.to_s,
        "document_name" => document_name,
        "document_type" => document_type,
        "status" => @status,
        "issue_date" => @issue_date.iso8601,
        "currency" => @currency,
        "issuer" => @issuer.to_h,
        "customer" => @customer.to_h,
        "authorization" => @authorization.to_h,
        "line_items" => @line_items.map(&:to_h),
        "exchange_rate" => @exchange_rate&.to_h,
        "totals" => @summary.to_h,
        "total_in_words" => total_in_words,
        "annulment_reason" => @annulment_reason,
        "annulled_at" => @annulled_at&.iso8601,
        "notes" => @notes,
        "reference" => @reference&.to_h,
        "motivo" => (@motivo unless @motivo.empty?)
      }.compact
    end

    def self.from_h(hash)
      new(
        correlative: hash["correlative"],
        issuer: Issuer.from_h(hash["issuer"]),
        customer: Customer.from_h(hash["customer"]),
        authorization: Authorization.from_h(hash["authorization"]),
        line_items: Array(hash["line_items"]).map { |h| LineItem.from_h(h) },
        issue_date: hash["issue_date"],
        currency: hash["currency"],
        exchange_rate: ExchangeRate.from_h(hash["exchange_rate"]),
        status: hash["status"] || STATUS_ISSUED,
        annulment_reason: hash["annulment_reason"],
        annulled_at: hash["annulled_at"],
        notes: hash["notes"],
        reference: DocumentReference.from_h(hash["reference"]),
        motivo: hash["motivo"]
      )
    end

    def to_s
      "#{document_name} #{@correlative} · #{@issue_date} · #{total}#{" · ANULADA" if annulled?}"
    end

    private

    def with(**changes)
      self.class.new(
        correlative: @correlative, issuer: @issuer, customer: @customer,
        authorization: @authorization, line_items: @line_items,
        issue_date: @issue_date, currency: @currency, exchange_rate: @exchange_rate,
        status: @status, annulment_reason: @annulment_reason,
        annulled_at: @annulled_at, notes: @notes, reference: @reference,
        motivo: @motivo, **changes
      )
    end

    def coerce_reference(value)
      case value
      when nil, DocumentReference then value
      when Hash then DocumentReference.from_h(value.transform_keys(&:to_s))
      else
        raise ValidationError,
              "el documento de referencia debe ser un Invoicehn::DocumentReference: #{value.inspect}"
      end
    end

    def coerce_date(value)
      case value
      when Date then value
      when String then Date.parse(value)
      else
        raise ValidationError, "fecha inválida: #{value.inspect}"
      end
    rescue ArgumentError, TypeError
      raise ValidationError, "fecha inválida: #{value.inspect}"
    end
  end
end
