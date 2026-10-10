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

    # Art. 10 num. 7 lit. c) and its counterparts in every other document type.
    # The codes are the ones in force after Acuerdo 609-2017 (La Gaceta 34,457,
    # 2 Oct 2017), whose Art. 1 rewrote lit. c) of Arts. 15, 17, 20, 23, 25,
    # 27, 29 and 33. Line numbers refer to doc/fuentes/acuerdo_481_2017_consolidado.txt:
    #
    #   01 Factura                              Art. 10 num. 7 c)  (l. 626)
    #   04 Recibo por Honorarios Profesionales  Art. 18 num. 7 c)  (l. 1039) — not reformed
    #   05 Comprobante de Retención             Art. 33 num. 5 c)  (l. 1750)
    #   06 Nota de Crédito                      Art. 25 num. 5 c)  (l. 1345)
    #   07 Nota de Débito                       Art. 27 num. 5 c)  (l. 1438)
    #   08 Guía de Remisión                     Art. 29 num. 4 c)  (l. 1535)
    #   09 Ticket                               Art. 17 num. 4 a)  (l. 969) *
    #   10 Factura Prevalorada                  Art. 15 num. 6 c)  (l. 889)
    #   11 Boleta de Compra                     Art. 20 num. 5 c)  (l. 1122)
    #   12 Constancia de Donación               Art. 23 num. 7 c)  (l. 1259)
    #
    # * Art. 17's closing sentence still reads "El Ticket tendrá como código 03"
    #   (l. 988); 609-2017 changed num. 4 only. The table follows the reformed
    #   numeral. A Ticket's own number is ten digits, not this 16-digit shape.
    #
    # 02 and 03 belonged to the 2017 original (Prevalorada and Ticket) and are
    # assigned to nothing after the reform, so they are rejected. Version 0.1.0
    # shipped the original table; see the CHANGELOG for the migration.
    DOCUMENT_TYPES = {
      "01" => "Factura",
      "04" => "Recibo por Honorarios Profesionales",
      "05" => "Comprobante de Retención",
      "06" => "Nota de Crédito",
      "07" => "Nota de Débito",
      "08" => "Guía de Remisión",
      "09" => "Ticket",
      "10" => "Factura Prevalorada",
      "11" => "Boleta de Compra",
      "12" => "Constancia de Donación"
    }.freeze

    FACTURA = "01"
    NOTA_DE_CREDITO = "06"
    NOTA_DE_DEBITO = "07"

    # Art. 6 — "Son Comprobantes Fiscales": Factura, Factura Prevalorada,
    # Ticket, Recibo por Honorarios Profesionales, Boleta de Compra and
    # Constancia de Donación.
    COMPROBANTES_FISCALES = %w[01 10 09 04 11 12].freeze

    # Art. 7 — "Son Documentos Complementarios": Notas de Crédito, Notas de
    # Débito, Guías de Remisión and Comprobantes de Retención.
    DOCUMENTOS_COMPLEMENTARIOS = %w[06 07 08 05].freeze

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
    def credit_note? = @document_type == NOTA_DE_CREDITO
    def debit_note? = @document_type == NOTA_DE_DEBITO
    def note? = credit_note? || debit_note?
    def comprobante_fiscal? = COMPROBANTES_FISCALES.include?(@document_type)

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
