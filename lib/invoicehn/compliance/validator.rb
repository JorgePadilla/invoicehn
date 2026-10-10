# frozen_string_literal: true

require "date"

module Invoicehn
  module Compliance
    # Checks a Factura, Nota de Crédito or Nota de Débito against the
    # Reglamento del Régimen de Facturación.
    #
    # The Factura's content is Arts. 10 and 11; the Nota de Crédito's is
    # Arts. 25 and 26; the Nota de Débito's, Arts. 27 and 28. Rules specific to
    # one kind say so and return nothing for the others.
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
        :document_type_supported,    # Art. 10 num. 7 lit. c; Arts. 25, 27 num. 5 lit. c
        :line_items_present,         # Art. 11 num. 1 lit. d, e, f; Art. 26 num. 10; Art. 28 num. 7, 9
        :customer_identification,    # Art. 11 num. 1 lit. a, b / num. 2 lit. a; Arts. 26, 28 num. 1, 2
        :consumidor_final_threshold, # Art. 11 num. 2
        :exonerado_documents,        # Art. 10 num. 8 / Art. 11 num. 4
        :foreign_currency_rate,      # Art. 11 closing paragraph
        :note_currency,              # Art. 26 num. 9; Art. 28 num. 8
        :note_reference,             # Arts. 26, 28 num. 3; Art. 4 num. 31, 32
        :note_motivo,                # Arts. 26, 28 num. 4
        :mixed_supply_notice         # Art. 11 num. 3
      ].freeze

      # The document types this library issues.
      SUPPORTED_TYPES = [Correlative::FACTURA, Correlative::NOTA_DE_CREDITO, Correlative::NOTA_DE_DEBITO].freeze

      attr_reader :invoice, :on

      def initialize(invoice, on: Invoicehn.today)
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

      # Art. 10 num. 7 lit. c — "01 = Factura"; Art. 25 num. 5 lit. c — "06 =
      # Nota de Crédito"; Art. 27 num. 5 lit. c — "07 = Nota de Débito". The
      # other types have contents of their own that this library does not
      # model.
      def document_type_supported
        return if SUPPORTED_TYPES.include?(invoice.correlative.document_type)

        violation("Art. 10 num. 7 lit. c", "Código de tipo de documento 01, 06 o 07",
                  "el correlativo declara el tipo #{invoice.correlative.document_type} " \
                  "(#{invoice.correlative.document_type_name}), que esta biblioteca no emite")
      end

      # Art. 11 num. 1 lit. d, e, f — a document with nothing on it describes no
      # transferencia de bienes ni prestación de servicios.
      #
      # A Nota de Crédito must state the "Unidades del bien vendido o servicio
      # prestado" (Art. 26 num. 10); a Nota de Débito, the "Descripción
      # detallada" and the units (Art. 28 num. 7 and 9).
      def line_items_present
        return if invoice.line_items.any?

        article = by_type("Art. 11 num. 1 lit. d, e y f", "Art. 26 num. 10", "Art. 28 num. 7 y 9")
        violation(article, "Descripción detallada, cantidad de unidades y valor unitario",
                  "el documento no tiene líneas de detalle")
      end

      # Art. 11 num. 1 lit. a and b for taxpayers; num. 2 lit. a for final
      # consumers.
      #
      # For the notes, Art. 26 num. 1-2 and Art. 28 num. 1-2 require
      # "Nombres y Apellidos, Razón o Denominación Social del adquirente" and
      # "Número de Registro Tributario Nacional (RTN) del adquirente", with no
      # CONSUMIDOR FINAL alternative like the one Art. 11 num. 2 gives the
      # Factura. A note to an acquirer without an RTN is therefore refused.
      def customer_identification
        customer = invoice.customer
        return violation("Art. 11", "Datos del cliente", "no se configuró el cliente") if customer.nil?
        return note_customer_identification(customer) if invoice.note?

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
        return unless invoice.factura?
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

        # Art. 10 num. 8 is a requirement of the Factura's format; Arts. 25 and
        # 27 have no counterpart.
        if invoice.factura? && customer.is_a?(Customer::Exonerado) && !customer.supported?
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
        return unless invoice.factura?
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
        return unless invoice.factura?
        return unless invoice.summary.mixed_supply?
        return unless invoice.customer.taxpayer?

        violation("Art. 11 num. 3",
                  "Crédito fiscal limitado a las ventas gravadas",
                  "la factura mezcla ventas gravadas y no gravadas; sólo #{invoice.summary.credito_fiscal_base} " \
                  "sustenta crédito fiscal",
                  severity: :warning)
      end

      # Art. 26 num. 9 and Art. 28 num. 8 — "Denominación literal de la Moneda
      # Nacional Lempira o símbolo (L)". The permission to use "otra
      # denominación monetaria" with the exchange rate is in Art. 11's closing
      # paragraph, and it speaks of "facturas" only; the notes' articles have
      # no such paragraph. A note is therefore issued in lempiras.
      def note_currency
        return unless invoice.note?
        return unless invoice.foreign_currency?

        violation(by_type(nil, "Art. 26 num. 9", "Art. 28 num. 8"),
                  "Denominación literal de la Moneda Nacional Lempira o símbolo (L)",
                  "la nota está en #{invoice.currency}; las notas se emiten en lempiras")
      end

      # Art. 26 num. 3 and Art. 28 num. 3 — "Datos del Comprobante Fiscal que
      # da lugar a la Nota": CAI, número correlativo and fecha de emisión.
      def note_reference
        return unless invoice.note?

        reference = invoice.reference
        article = by_type(nil, "Art. 26 num. 3", "Art. 28 num. 3")
        requirement = "Datos del Comprobante Fiscal que da lugar a la Nota (CAI, correlativo y fecha de emisión)"
        return violation(article, requirement, "la nota no indica el documento al que se aplica") if reference.nil?

        [
          reference_type_violation(reference, article, requirement),
          reference_self_violation(reference, article, requirement),
          reference_date_violation(reference)
        ].compact
      end

      # Art. 26 num. 4 and Art. 28 num. 4 — "Motivo de la emisión del
      # documento".
      def note_motivo
        return unless invoice.note?
        return unless invoice.motivo.empty?

        violation(by_type(nil, "Art. 26 num. 4", "Art. 28 num. 4"),
                  "Motivo de la emisión del documento", "la nota no indica el motivo")
      end

      def note_customer_identification(customer)
        return if !customer.name.empty? && customer.rtn

        violation(by_type(nil, "Art. 26 num. 1 y 2", "Art. 28 num. 1 y 2"),
                  "Nombres y Apellidos o Razón Social, y RTN del adquirente",
                  "la nota debe identificar al adquirente con nombre y RTN; " \
                  "el Reglamento no admite CONSUMIDOR FINAL en las notas")
      end

      # Art. 4 num. 32 defines the Nota de Crédito as "vinculado a un
      # Comprobante Fiscal", and Art. 26 num. 3 lit. b) asks for the
      # "Comprobante Fiscal al que le está aplicando la Nota" — so it must
      # point at one of the Art. 6 types. Art. 28 num. 3 lit. b) widens the
      # Nota de Débito to "el Comprobante Fiscal o el documento al que le está
      # aplicando la Nota", so any recognised document type is accepted there.
      def reference_type_violation(reference, article, requirement)
        return unless invoice.credit_note?
        return if reference.correlative.comprobante_fiscal?

        violation(article, requirement,
                  "#{reference.correlative} es #{reference.document_type_name}, " \
                  "que no es un Comprobante Fiscal (Art. 6)")
      end

      def reference_self_violation(reference, article, requirement)
        return unless reference.correlative == invoice.correlative

        violation(article, requirement, "la nota no puede aplicarse a sí misma")
      end

      # Art. 4 num. 32: the Nota de Crédito records adjustments "efectuados con
      # posterioridad a la emisión del correspondiente Comprobante Fiscal"; a
      # Nota de Débito (num. 31) is likewise "vinculado a un Comprobante Fiscal"
      # that must already exist. A reference dated after the note is a typo or
      # a forgery.
      def reference_date_violation(reference)
        return unless reference.issue_date > invoice.issue_date

        violation(by_type(nil, "Art. 4 num. 32", "Art. 4 num. 31"),
                  "La nota es posterior al documento que la origina",
                  "el documento de referencia es del #{reference.issue_date} " \
                  "y la nota se emitió el #{invoice.issue_date}")
      end

      def by_type(factura, credit, debit)
        return credit if invoice.credit_note?
        return debit if invoice.debit_note?

        factura
      end
    end
  end
end
