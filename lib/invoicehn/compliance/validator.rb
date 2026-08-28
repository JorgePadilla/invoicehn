# frozen_string_literal: true

require "date"

module Invoicehn
  module Compliance
    # Checks an invoice against the Reglamento del Régimen de Facturación.
    #
    # Every rule cites the article it enforces. The validator reports all
    # failures at once rather than stopping at the first, so an operator fixing
    # a document sees the whole list.
    #
    # Scope: this validates *document content*. It cannot verify that the
    # operator is registered in the Régimen de Facturación (Art. 45), enrolled
    # as autoimpresor (Art. 47), or that the CAI it was handed is genuine —
    # those are obligations the software cannot discharge.
    class Validator
      RULES = [
        :issuer_identification,      # Art. 10 num. 1
        :authorization_present,      # Art. 10 num. 3, 4, 5
        :authorization_current,      # Art. 62
        :correlative_in_range,       # Art. 10 num. 5, 7
        :document_type_is_factura,   # Art. 10 num. 7 lit. c
        :line_items_present,         # Art. 11 num. 1 lit. d, e, f
        :customer_identification,    # Art. 11 num. 1 lit. a, b / num. 2 lit. a
        :consumidor_final_threshold, # Art. 11 num. 2
        :exonerado_documents,        # Art. 10 num. 8 / Art. 11 num. 4
        :foreign_currency_rate,      # Art. 11 closing paragraph
        :mixed_supply_notice         # Art. 11 num. 3
      ].freeze

      attr_reader :invoice, :on

      def initialize(invoice, on: Date.today)
        @invoice = invoice
        @on = on
      end

      def violations
        @violations ||= RULES.flat_map { |rule| Array(send(rule)) }.compact.freeze
      end

      def errors = violations.select(&:error?)
      def warnings = violations.select(&:warning?)
      def valid? = errors.empty?

      private

      def violation(article, requirement, detail = nil, severity: :error)
        Violation.new(article: article, requirement: requirement, detail: detail, severity: severity)
      end

      # Art. 10 num. 1 — "Datos de identificación del emisor".
      def issuer_identification
        if invoice.issuer.nil?
          return violation("Art. 10 num. 1", "Datos de identificación del emisor",
                           "no se configuró el emisor")
        end

        missing = invoice.issuer.missing_fields
        return if missing.empty?

        violation("Art. 10 num. 1", "Datos de identificación del emisor",
                  "faltan: #{missing.join("; ")}")
      end

      # Art. 10 num. 3, 4 and 5 — CAI, fecha límite and rango must appear.
      def authorization_present
        return if invoice.authorization

        violation("Art. 10 num. 3, 4 y 5",
                  "Clave de Autorización de Impresión (CAI), fecha límite de emisión y rango autorizado",
                  "la factura no tiene autorización asociada")
      end

      # Art. 62 — documents lose validity once the authorized period expires.
      def authorization_current
        auth = invoice.authorization
        return if auth.nil?
        return unless auth.expired?(invoice.issue_date)

        violation("Art. 62", "Fecha límite de emisión vigente",
                  "la autorización venció el #{auth.limit_date} y la factura se emitió el #{invoice.issue_date}")
      end

      # Art. 10 num. 5 and 7 — the number must fall inside the authorized range.
      def correlative_in_range
        auth = invoice.authorization
        return if auth.nil?
        return if auth.covers?(invoice.correlative)

        violation("Art. 10 num. 5", "Rango autorizado vigente",
                  "el correlativo #{invoice.correlative} está fuera del rango #{auth.range_label}")
      end

      # Art. 10 num. 7 lit. c — "01 = Factura".
      def document_type_is_factura
        return if invoice.correlative.factura?

        violation("Art. 10 num. 7 lit. c", "Código de tipo de documento 01 para la Factura",
                  "el correlativo declara el tipo #{invoice.correlative.document_type} " \
                  "(#{invoice.correlative.document_type_name})")
      end

      # Art. 11 num. 1 lit. d, e, f — a document with nothing on it describes no
      # transferencia de bienes ni prestación de servicios.
      def line_items_present
        return if invoice.line_items.any?

        violation("Art. 11 num. 1 lit. d, e y f",
                  "Descripción detallada, cantidad de unidades y valor unitario",
                  "la factura no tiene líneas de detalle")
      end

      # Art. 11 num. 1 lit. a and b for taxpayers; num. 2 lit. a for final
      # consumers.
      def customer_identification
        customer = invoice.customer
        return violation("Art. 11", "Datos del cliente", "no se configuró el cliente") if customer.nil?

        if customer.taxpayer? || customer.exonerado?
          return if !customer.name.empty? && customer.rtn

          return violation("Art. 11 num. 1 lit. a y b",
                           "Nombres y Apellidos o Razón Social, y RTN del cliente",
                           "el cliente que sustenta crédito fiscal debe identificarse con nombre y RTN")
        end

        nil
      end

      # Art. 11 num. 2 — above L 10,000.00 the consumidor final's data becomes
      # mandatory: "nombres y apellidos, el tipo y número de documento de
      # identificación en el espacio destinado al RTN".
      def consumidor_final_threshold
        customer = invoice.customer
        return unless customer.is_a?(Customer::ConsumidorFinal)

        # The threshold is a sum *in lempiras*, so a foreign-currency invoice is
        # measured by its Lempira equivalent — otherwise an anonymous sale of
        # US$50,000 would slip past a rule written for L 10,000. A foreign
        # invoice without a rate cannot be converted, but it already fails the
        # Art. 11 closing-paragraph rule, so nothing goes unreported.
        amount = invoice.foreign_currency? ? invoice.total_in_lempiras : invoice.total
        return if amount.nil?
        return unless customer.identification_required?(amount)
        return if customer.identified?

        violation("Art. 11 num. 2",
                  "Datos del consumidor final en ventas superiores a L 10,000.00",
                  "el total (#{invoice.total}#{" ≡ #{amount}" if invoice.foreign_currency?}) " \
                  "excede el umbral y deben consignarse nombres y apellidos junto al tipo y " \
                  "número de documento de identificación")
      end

      # Art. 10 num. 8 and Art. 11 num. 4 — an exonerated purchaser's supporting
      # numbers.
      def exonerado_documents
        customer = invoice.customer
        results = []

        if customer.is_a?(Customer::Exonerado) && !customer.supported?
          results << violation("Art. 10 num. 8 y Art. 11 num. 4",
                               "Orden de Compra Exenta, Constancia del Registro de Exonerados o Registro SAG",
                               "el adquirente exonerado no tiene ninguno de los tres documentos de respaldo")
        end

        # An exonerado line without an exonerado buyer is a contradiction the
        # document would carry on its face.
        exonerado_lines = invoice.line_items.any? { |item| item.treatment.exonerado? }
        if exonerado_lines && !customer.exonerado?
          results << violation("Art. 11 num. 4",
                               "Ventas a Obligados Tributarios Exonerados",
                               "hay líneas con tratamiento exonerado pero el cliente no está registrado como exonerado")
        end

        results
      end

      # Art. 11, closing paragraph: "En ambos casos, cuando el Obligado
      # Tributario emita facturas con otra denominación monetaria, debe indicar
      # la tasa de cambio vigente a la fecha de emisión."
      def foreign_currency_rate
        return unless invoice.foreign_currency?

        rate = invoice.exchange_rate
        if rate.nil?
          return violation("Art. 11 (párrafo final)",
                           "Tasa de cambio vigente a la fecha de emisión",
                           "la factura está en #{invoice.currency} y no indica tasa de cambio")
        end

        unless rate.currency == invoice.currency
          return violation("Art. 11 (párrafo final)",
                           "Tasa de cambio vigente a la fecha de emisión",
                           "la tasa convierte desde #{rate.currency} pero la factura está en #{invoice.currency}")
        end

        return if rate.current_on?(invoice.issue_date)

        violation("Art. 11 (párrafo final)",
                  "Tasa de cambio vigente a la fecha de emisión",
                  "la tasa es del #{rate.date} y la factura se emitió el #{invoice.issue_date}")
      end

      # Art. 11 num. 3 — "Para respaldar el crédito fiscal en los casos que la
      # factura sustente ventas exentas y gravadas, se reconocerán únicamente
      # las ventas gravadas." Not a defect: a notice, so the document can say so
      # and the buyer is not misled about what it supports.
      def mixed_supply_notice
        return unless invoice.summary.mixed_supply?
        return unless invoice.customer.taxpayer?

        violation("Art. 11 num. 3",
                  "Crédito fiscal limitado a las ventas gravadas",
                  "la factura mezcla ventas gravadas y no gravadas; sólo #{invoice.summary.credito_fiscal_base} " \
                  "sustenta crédito fiscal",
                  severity: :warning)
      end
    end
  end
end
