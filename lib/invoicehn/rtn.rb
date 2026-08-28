# frozen_string_literal: true

module Invoicehn
  # Registro Tributario Nacional — 14 digits, for both personas naturales and
  # personas jurídicas.
  #
  # Validation is deliberately limited to length and digits. There is no
  # publicly documented check digit for the Honduran RTN: the word "dígito"
  # appears nowhere in the Código Tributario (Decreto 170-2016), Acuerdo
  # 481-2017 requires the RTN on invoices without ever specifying its structure,
  # and SAR publishes no algorithm. Porting a mod-11 scheme by analogy from the
  # Chilean RUT or Mexican RFC would reject valid Honduran RTNs, so this class
  # does not attempt it. Verify a real RTN against SAR's consulta, not
  # arithmetic.
  #
  # Note also that primary sources disagree on how a natural person's RTN is
  # derived — Código Tributario Art. 66 num. 3 says it *is* the RNP number,
  # while SAR states it is the 13-digit DNI plus one digit. Nothing here assumes
  # either, and nothing here assumes RTN and DNI are interchangeable.
  class Rtn
    LENGTH = 14
    PATTERN = /\A\d{#{LENGTH}}\z/

    attr_reader :digits

    class << self
      def parse(value)
        new(value)
      rescue ValidationError
        nil
      end

      def valid?(value)
        normalize(value).match?(PATTERN)
      end

      # Dashes and spaces are a display convention with no basis in any norm,
      # so they are accepted on input and discarded.
      def normalize(value)
        value.to_s.gsub(/[\s-]/, "")
      end
    end

    def initialize(value)
      @digits = self.class.normalize(value)

      unless @digits.match?(PATTERN)
        raise ValidationError,
              "RTN inválido: se esperan #{LENGTH} dígitos, se recibió #{@digits.inspect}"
      end

      freeze
    end

    # "0801-1990-123456" — the 4-4-6 grouping is customary, not prescribed.
    def formatted
      "#{@digits[0, 4]}-#{@digits[4, 4]}-#{@digits[8, 6]}"
    end

    def to_s = @digits
    def inspect = "#<Invoicehn::Rtn #{formatted}>"

    def ==(other)
      other.is_a?(self.class) && other.digits == @digits
    end
    alias eql? ==

    def hash = @digits.hash
  end
end
