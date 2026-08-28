# frozen_string_literal: true

module Invoicehn
  # The purchaser. Art. 11 distinguishes three situations, and which fields are
  # mandatory depends on which one applies — so each is a separate class rather
  # than a flag on one.
  #
  #   Taxpayer       — num. 1: a buyer who needs the invoice to support crédito
  #                    fiscal. Name and RTN are both required.
  #   ConsumidorFinal— num. 2: name and identification, or the legend
  #                    "CONSUMIDOR FINAL". Above L 10,000.00 the client's data
  #                    becomes mandatory.
  #   Exonerado      — num. 4 with Art. 10 num. 8: a buyer holding an
  #                    exoneration, which brings its own supporting numbers.
  class Customer
    CONSUMIDOR_FINAL_LEGEND = "CONSUMIDOR FINAL"

    # Art. 11 num. 2: "Cuando la venta de bienes o prestación de servicios se
    # realice al Consumidor Final y excediera la suma de diez mil Lempiras
    # (L 10,000.00), debe consignarse obligatoriamente los datos del cliente".
    #
    # The reforms moved the power to change this figure to the Secretaría de
    # Finanzas, so it is a constant here and not a guess at a future value.
    IDENTIFICATION_THRESHOLD = Money.new("10000.00", "HNL")

    attr_reader :name

    def initialize(name:)
      @name = name.to_s.strip
    end

    def consumidor_final? = false
    def exonerado? = false
    def taxpayer? = false
    def rtn = nil

    # What goes in the space reserved for the RTN on the printed document.
    def identification_line = rtn&.formatted.to_s

    def to_h = { "kind" => kind, "name" => @name }

    def self.from_h(hash)
      case hash["kind"]
      when "taxpayer" then Taxpayer.from_h(hash)
      when "consumidor_final" then ConsumidorFinal.from_h(hash)
      when "exonerado" then Exonerado.from_h(hash)
      else
        raise ValidationError, "tipo de cliente desconocido: #{hash["kind"].inspect}"
      end
    end

    # A buyer supporting crédito fiscal — Art. 11 num. 1 lit. a) and b).
    class Taxpayer < Customer
      attr_reader :rtn

      def initialize(name:, rtn:)
        super(name: name)
        @rtn = rtn.is_a?(Rtn) ? rtn : Rtn.new(rtn)
        freeze
      end

      def kind = "taxpayer"
      def taxpayer? = true

      def to_h = super.merge("rtn" => @rtn.to_s)

      def self.from_h(hash) = new(name: hash["name"], rtn: hash["rtn"])

      def to_s = "#{@name} (RTN #{@rtn.formatted})"
    end

    # Art. 11 num. 2 lit. a) — "Nombres y Apellidos, Número de identificación o
    # consignar la leyenda 'CONSUMIDOR FINAL'".
    class ConsumidorFinal < Customer
      attr_reader :identification_type, :identification_number

      # @param name [String, nil] omit for an anonymous sale, which prints the
      #   legend instead.
      # @param identification_type [String, nil] e.g. "DNI", "Pasaporte".
      def initialize(name: nil, identification_type: nil, identification_number: nil)
        super(name: name)
        @identification_type = identification_type.to_s.strip
        @identification_number = identification_number.to_s.strip
        freeze
      end

      def kind = "consumidor_final"
      def consumidor_final? = true

      def identified? = !@name.empty? && !@identification_number.empty?

      # Above the threshold Art. 11 requires "nombres y apellidos, el tipo y
      # número de documento de identificación en el espacio destinado al RTN".
      #
      # @param total [Money] must be in lempiras: the article states the
      #   threshold as a sum in lempiras, so a foreign-currency invoice is
      #   measured by its converted equivalent. The caller does the conversion.
      def identification_required?(total)
        unless total.currency == "HNL"
          raise CurrencyMismatch,
                "el umbral del Art. 11 num. 2 se mide en lempiras; se recibió #{total.currency}"
        end

        total > IDENTIFICATION_THRESHOLD
      end

      def display_name = @name.empty? ? CONSUMIDOR_FINAL_LEGEND : @name

      def identification_line
        return CONSUMIDOR_FINAL_LEGEND unless identified?

        [@identification_type, @identification_number].reject(&:empty?).join(" ")
      end

      def to_h
        super.merge(
          "identification_type" => @identification_type,
          "identification_number" => @identification_number
        )
      end

      def self.from_h(hash)
        new(
          name: hash["name"],
          identification_type: hash["identification_type"],
          identification_number: hash["identification_number"]
        )
      end

      def to_s = identified? ? "#{@name} (#{identification_line})" : CONSUMIDOR_FINAL_LEGEND
    end

    # Art. 11 num. 4 with Art. 10 num. 8 — an exonerated purchaser. At least one
    # of the three supporting numbers must be present:
    #   a) Número correlativo de la Orden de Compra Exenta
    #   b) Número correlativo de la Constancia del Registro de Exonerados
    #   c) Número identificativo del Registro de la Secretaría de Estado en el
    #      Despacho de Agricultura y Ganadería
    class Exonerado < Customer
      attr_reader :rtn, :purchase_order, :exoneration_registry, :sag_registry

      def initialize(name:, rtn:, purchase_order: nil, exoneration_registry: nil, sag_registry: nil)
        super(name: name)
        @rtn = rtn.is_a?(Rtn) ? rtn : Rtn.new(rtn)
        @purchase_order = purchase_order.to_s.strip
        @exoneration_registry = exoneration_registry.to_s.strip
        @sag_registry = sag_registry.to_s.strip
        freeze
      end

      def kind = "exonerado"
      def exonerado? = true

      def supporting_documents
        {
          "Orden de Compra Exenta" => @purchase_order,
          "Constancia del Registro de Exonerados" => @exoneration_registry,
          "Registro SAG" => @sag_registry
        }.reject { |_label, value| value.empty? }
      end

      # "según corresponda" — the article accepts whichever of the three applies
      # to the buyer, so one is enough, but none is not.
      def supported? = supporting_documents.any?

      def to_h
        super.merge(
          "rtn" => @rtn.to_s,
          "purchase_order" => @purchase_order,
          "exoneration_registry" => @exoneration_registry,
          "sag_registry" => @sag_registry
        )
      end

      def self.from_h(hash)
        new(
          name: hash["name"],
          rtn: hash["rtn"],
          purchase_order: hash["purchase_order"],
          exoneration_registry: hash["exoneration_registry"],
          sag_registry: hash["sag_registry"]
        )
      end

      def to_s = "#{@name} (RTN #{@rtn.formatted}, exonerado)"
    end
  end
end
