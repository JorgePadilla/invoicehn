# frozen_string_literal: true

module Invoicehn
  # The 16-digit document number of Art. 10 num. 7: NNN-NNN-NN-NNNNNNNN.
  #
  #   a) first 3 digits  — establecimiento; the casa matriz is assigned 000
  #   b) next 3 digits   — punto de emisión
  #   c) next 2 digits   — tipo de documento (01 = Factura)
  #   d) last 8 digits   — sequence, starting at 00000001 and restarting after
  #                        99999999
  #
  # The first three groups together are the "identificador del documento".
  class Correlative
    include Comparable

    SEQUENCE_MIN = 1
    SEQUENCE_MAX = 99_999_999
    PATTERN = /\A(\d{3})-(\d{3})-(\d{2})-(\d{8})\z/

    # Codes verified in the decree. 09 is deliberately absent: it was not
    # confirmed in the text, and guessing a fiscal document code is not worth
    # the risk.
    DOCUMENT_TYPES = {
      "01" => "Factura",
      "02" => "Factura Prevalorada",
      "03" => "Ticket",
      "04" => "Recibo por Honorarios Profesionales",
      "05" => "Boleta de Compra",
      "06" => "Constancia de Donación",
      "07" => "Nota de Crédito",
      "08" => "Nota de Débito",
      "10" => "Comprobante de Retención"
    }.freeze

    FACTURA = "01"

    attr_reader :establishment, :emission_point, :document_type, :sequence

    class << self
      def parse(value)
        match = PATTERN.match(value.to_s.strip)
        raise ValidationError, "correlativo inválido: #{value.inspect} (se espera NNN-NNN-NN-NNNNNNNN)" unless match

        new(
          establishment: match[1],
          emission_point: match[2],
          document_type: match[3],
          sequence: match[4].to_i
        )
      end

      def valid?(value)
        parse(value)
        true
      rescue ValidationError
        false
      end
    end

    def initialize(establishment:, emission_point:, document_type:, sequence:)
      @establishment  = pad(establishment, 3, "establecimiento")
      @emission_point = pad(emission_point, 3, "punto de emisión")
      @document_type  = pad(document_type, 2, "tipo de documento")
      @sequence       = Integer(sequence)

      unless DOCUMENT_TYPES.key?(@document_type)
        raise ValidationError,
              "tipo de documento no reconocido: #{@document_type} " \
              "(válidos: #{DOCUMENT_TYPES.keys.join(", ")})"
      end

      unless @sequence.between?(SEQUENCE_MIN, SEQUENCE_MAX)
        raise ValidationError,
              "correlativo fuera de rango: #{@sequence} " \
              "(debe estar entre #{SEQUENCE_MIN} y #{SEQUENCE_MAX})"
      end

      freeze
    end

    # The (establecimiento, punto de emisión, tipo de documento) triple. SAR
    # authorizes a CAI and range per emission point and document type, so this
    # is the key a sequence is allocated against.
    def identifier
      "#{@establishment}-#{@emission_point}-#{@document_type}"
    end

    def document_type_name = DOCUMENT_TYPES.fetch(@document_type)
    def factura? = @document_type == FACTURA

    def succ
      raise RangeExhausted, "el correlativo #{self} es el último de la serie" if last?

      with_sequence(@sequence + 1)
    end
    alias next succ

    def last? = @sequence == SEQUENCE_MAX

    def with_sequence(value)
      self.class.new(
        establishment: @establishment,
        emission_point: @emission_point,
        document_type: @document_type,
        sequence: value
      )
    end

    def to_s
      "#{@establishment}-#{@emission_point}-#{@document_type}-#{format("%08d", @sequence)}"
    end

    def inspect = "#<Invoicehn::Correlative #{self}>"

    # Ordering is only meaningful inside one identifier — two different emission
    # points run independent sequences.
    def <=>(other)
      return nil unless other.is_a?(self.class)
      return nil unless identifier == other.identifier

      @sequence <=> other.sequence
    end

    def ==(other)
      other.is_a?(self.class) && other.to_s == to_s
    end
    alias eql? ==

    def hash = to_s.hash

    private

    def pad(value, width, label)
      digits = value.to_s.strip
      digits = format("%0#{width}d", digits.to_i) if digits.match?(/\A\d+\z/) && digits.length < width

      unless digits.match?(/\A\d{#{width}}\z/)
        raise ValidationError, "#{label} inválido: #{value.inspect} (se esperan #{width} dígitos)"
      end

      digits
    end
  end
end
