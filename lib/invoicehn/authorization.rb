# frozen_string_literal: true

require "date"

module Invoicehn
  # A SAR authorization: the CAI, the authorized range, and the fecha límite de
  # emisión, granted per emission point and document type (Art. 59).
  #
  # Art. 10 requires the invoice to show num. 3 the CAI, num. 4 the fecha límite
  # de emisión vigente, and num. 5 the rango autorizado vigente.
  #
  # This library consumes these values; it never generates them. Obtaining them
  # is the operator's obligation under Arts. 59-61.
  class Authorization
    attr_reader :cai, :range_start, :range_end, :limit_date

    # @param cai [String] the Clave de Autorización de Impresión, as SAR issued
    #   it. Art. 4 num. 7 defines it only as "una serie alfanumérica generada
    #   electrónicamente" — no length or grouping is fixed anywhere in the
    #   decree and no authoritative layout is published, so it is stored and
    #   printed verbatim. Validating it against a guessed format would reject
    #   real CAIs.
    # @param range_start [String, Correlative] first authorized number
    # @param range_end [String, Correlative] last authorized number
    # @param limit_date [Date, String] fecha límite de emisión
    def initialize(cai:, range_start:, range_end:, limit_date:)
      @cai = cai.to_s.strip
      raise ValidationError, "el CAI es obligatorio (Art. 10 num. 3)" if @cai.empty?

      @range_start = coerce_correlative(range_start, "inicio del rango")
      @range_end   = coerce_correlative(range_end, "fin del rango")
      @limit_date  = coerce_date(limit_date)

      validate_range!
      freeze
    end

    # The (establecimiento, punto de emisión, tipo de documento) triple this
    # authorization covers.
    def identifier = @range_start.identifier

    def document_type = @range_start.document_type
    def establishment = @range_start.establishment
    def emission_point = @range_start.emission_point

    # Art. 62: "Los Comprobantes Fiscales y/o Documentos Complementarios
    # perderán su validez y no podrán ser utilizados cuando se haya vencido el
    # plazo de tiempo autorizado." The fecha límite is the last day on which a
    # document may be issued, so it is still usable on that date itself.
    def expired?(on = Date.today) = on > @limit_date

    def days_remaining(from = Date.today) = (@limit_date - from).to_i

    def covers?(correlative)
      correlative = Correlative.parse(correlative.to_s)
      correlative.identifier == identifier &&
        correlative.sequence >= @range_start.sequence &&
        correlative.sequence <= @range_end.sequence
    end

    # Total documents SAR authorized under this grant.
    def capacity = @range_end.sequence - @range_start.sequence + 1

    # Whether this authorization can still be used to issue the given number.
    def usable?(correlative, on: Date.today)
      !expired?(on) && covers?(correlative)
    end

    # Raises with the specific reason, so the caller can report which of the two
    # conditions failed rather than a generic refusal.
    def assert_usable!(correlative, on: Date.today)
      if expired?(on)
        raise AuthorizationExpired,
              "la fecha límite de emisión (#{@limit_date}) ya venció; " \
              "los documentos pierden validez (Art. 62)"
      end

      unless covers?(correlative)
        raise RangeExhausted,
              "el correlativo #{correlative} está fuera del rango autorizado " \
              "#{@range_start}–#{@range_end} (Art. 10 num. 5)"
      end

      self
    end

    # "000-001-01-00000001 al 000-001-01-00000500" as printed on the document.
    def range_label = "#{@range_start} al #{@range_end}"

    def to_h
      {
        "cai" => @cai,
        "range_start" => @range_start.to_s,
        "range_end" => @range_end.to_s,
        "limit_date" => @limit_date.iso8601
      }
    end

    def self.from_h(hash)
      new(
        cai: hash["cai"],
        range_start: hash["range_start"],
        range_end: hash["range_end"],
        limit_date: hash["limit_date"]
      )
    end

    def to_s = "CAI #{@cai} · #{range_label} · vence #{@limit_date}"

    private

    def coerce_correlative(value, label)
      return value if value.is_a?(Correlative)

      Correlative.parse(value)
    rescue ValidationError => e
      raise ValidationError, "#{label}: #{e.message}"
    end

    def coerce_date(value)
      case value
      when Date then value
      when String then Date.parse(value)
      else
        raise ValidationError, "fecha límite de emisión inválida: #{value.inspect}"
      end
    rescue ArgumentError, TypeError
      raise ValidationError, "fecha límite de emisión inválida: #{value.inspect}"
    end

    def validate_range!
      unless @range_start.identifier == @range_end.identifier
        raise ValidationError,
              "el rango abarca identificadores distintos: " \
              "#{@range_start.identifier} y #{@range_end.identifier}"
      end

      return unless @range_end.sequence < @range_start.sequence

      raise ValidationError,
            "el rango termina (#{@range_end}) antes de comenzar (#{@range_start})"
    end
  end
end
