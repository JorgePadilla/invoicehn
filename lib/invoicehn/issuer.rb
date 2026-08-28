# frozen_string_literal: true

module Invoicehn
  # The Obligado Tributario emitting the document.
  #
  # Art. 10 num. 1 — "Datos de identificación del emisor":
  #   a) Registro Tributario Nacional (RTN)
  #   b) Nombres y Apellidos, Razón o Denominación Social. "Los Obligados
  #      Tributarios como comerciantes individuales podrán sustituir sus Nombres
  #      y Apellidos por el nombre comercial registrado en el Registro
  #      Tributario Nacional (RTN)"
  #   c) Nombre Comercial
  #   d) Dirección de la casa matriz y del establecimiento donde esté localizado
  #      el punto de emisión
  #   e) Número telefónico
  #   f) Correo Electrónico
  #
  # All six are required by the article, so all six are required here. The
  # printer's data (num. 9) is not modelled: it applies only to pre-printed
  # invoices produced through an imprenta, and this library issues under the
  # autoimpresor modality.
  class Issuer
    attr_reader :rtn, :legal_name, :trade_name, :headquarters_address,
                :branch_address, :phone, :email

    # @param branch_address [String, nil] address of the establishment holding
    #   the emission point. Defaults to the headquarters address, which is the
    #   correct value when issuing from the casa matriz.
    def initialize(rtn:, legal_name:, trade_name:, headquarters_address:, phone:, email:,
                   branch_address: nil)
      @rtn = rtn.is_a?(Rtn) ? rtn : Rtn.new(rtn)
      @legal_name = legal_name.to_s.strip
      @trade_name = trade_name.to_s.strip
      @headquarters_address = headquarters_address.to_s.strip
      branch = branch_address.to_s.strip
      @branch_address = branch.empty? ? @headquarters_address : branch
      @phone = phone.to_s.strip
      @email = email.to_s.strip

      freeze
    end

    # Returns the Art. 10 num. 1 fields that are missing, as human-readable
    # Spanish descriptions. Empty means complete.
    def missing_fields
      {
        "nombre o razón social (Art. 10 num. 1 lit. b)" => @legal_name,
        "nombre comercial (Art. 10 num. 1 lit. c)" => @trade_name,
        "dirección de la casa matriz (Art. 10 num. 1 lit. d)" => @headquarters_address,
        "dirección del establecimiento del punto de emisión (Art. 10 num. 1 lit. d)" => @branch_address,
        "número telefónico (Art. 10 num. 1 lit. e)" => @phone,
        "correo electrónico (Art. 10 num. 1 lit. f)" => @email
      }.select { |_label, value| value.nil? || value.empty? }.keys
    end

    def complete? = missing_fields.empty?

    def validate!
      return self if complete?

      raise ValidationError,
            "faltan datos obligatorios del emisor: #{missing_fields.join("; ")}"
    end

    # True when the emission point is somewhere other than the casa matriz, in
    # which case both addresses must be shown.
    def branch? = @branch_address != @headquarters_address

    def to_h
      {
        "rtn" => @rtn.to_s,
        "legal_name" => @legal_name,
        "trade_name" => @trade_name,
        "headquarters_address" => @headquarters_address,
        "branch_address" => @branch_address,
        "phone" => @phone,
        "email" => @email
      }
    end

    def self.from_h(hash)
      new(
        rtn: hash["rtn"],
        legal_name: hash["legal_name"],
        trade_name: hash["trade_name"],
        headquarters_address: hash["headquarters_address"],
        branch_address: hash["branch_address"],
        phone: hash["phone"],
        email: hash["email"]
      )
    end

    def to_s = "#{@legal_name} (RTN #{@rtn.formatted})"
  end
end
