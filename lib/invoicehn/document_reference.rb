# frozen_string_literal: true

require "date"

module Invoicehn
  # The document a Nota de Crédito or Nota de Débito applies to.
  #
  # Art. 26 num. 3 (Nota de Crédito) and Art. 28 num. 3 (Nota de Débito)
  # require, at the moment of issue, the "Datos del Comprobante Fiscal que da
  # lugar a la Nota":
  #
  #   a) Clave de Autorización de Impresión (CAI)
  #   b) Número correlativo del Comprobante Fiscal al que le está aplicando la
  #      Nota
  #   c) Fecha de emisión del Comprobante Fiscal al que le está aplicando la
  #      Nota
  #
  # These are exactly the three fields here, all mandatory. The CAI is the one
  # printed on the original document — not the note's own CAI.
  class DocumentReference
    attr_reader :correlative, :cai, :issue_date

    # @param correlative [String, Correlative] the original document's number
    # @param cai [String] the CAI printed on the original document
    # @param issue_date [Date, String] the original document's fecha de emisión
    def initialize(correlative:, cai:, issue_date:)
      @correlative = correlative.is_a?(Correlative) ? correlative : Correlative.parse(correlative)
      @cai = cai.to_s.strip
      if @cai.empty?
        raise ValidationError, "el CAI del documento de referencia es obligatorio (Arts. 26 y 28 num. 3 lit. a)"
      end

      @issue_date = coerce_date(issue_date)
      freeze
    end

    # Builds the reference from a document this library issued, so the three
    # fields are copied rather than retyped.
    def self.from_document(document)
      new(correlative: document.correlative, cai: document.authorization.cai, issue_date: document.issue_date)
    end

    def self.from_h(hash)
      return nil if hash.nil?

      new(correlative: hash["correlative"], cai: hash["cai"], issue_date: hash["issue_date"])
    end

    def document_type = @correlative.document_type
    def document_type_name = @correlative.document_type_name

    def to_h
      {
        "correlative" => @correlative.to_s,
        "document_type" => document_type,
        "cai" => @cai,
        "issue_date" => @issue_date.iso8601
      }
    end

    def ==(other)
      other.is_a?(self.class) && other.to_h == to_h
    end
    alias eql? ==

    def hash = to_h.hash

    def to_s = "#{document_type_name} #{@correlative} · CAI #{@cai} · #{@issue_date}"

    private

    def coerce_date(value)
      case value
      when Date then value
      when String then Date.parse(value)
      else
        raise ValidationError, "fecha de emisión del documento de referencia inválida: #{value.inspect}"
      end
    rescue ArgumentError, TypeError
      raise ValidationError, "fecha de emisión del documento de referencia inválida: #{value.inspect}"
    end
  end
end
