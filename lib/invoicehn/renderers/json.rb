# frozen_string_literal: true

require "json"

module Invoicehn
  module Renderers
    # Machine-readable form of the document.
    #
    # This serves Art. 53 num. 5 — "El Sistema debe tener la capacidad de
    # generación de archivos tipo texto para su almacenamiento y traslado hacia
    # la Administración Tributaria a través de servicios web o intercambio de
    # protocolo" — and is the shape a future electronic-emission module (Art. 54,
    # CAEE) would build its payload from.
    #
    # Every monetary figure is a string. A JSON number would invite the reader
    # to parse it as a float, and Ley del ISV Art. 9 makes a mis-rounded charge
    # an offence.
    class Json
      attr_reader :invoice

      def initialize(invoice, pretty: true)
        @invoice = invoice
        @pretty = pretty
      end

      def render
        @pretty ? JSON.pretty_generate(payload) : JSON.generate(payload)
      end
      alias to_s render

      def payload = @invoice.to_h

      # A batch export, for handing a period's documents to SAR or to an
      # accounting system.
      def self.export(invoices, pretty: true)
        payload = {
          "generated_at" => Time.now.utc.iso8601,
          "count" => invoices.size,
          "documents" => invoices.map(&:to_h)
        }
        pretty ? JSON.pretty_generate(payload) : JSON.generate(payload)
      end

      # Flat, one row per document — the shape a spreadsheet or an accounting
      # import expects.
      def self.export_csv(invoices)
        headers = %w[
          correlativo fecha estado cai cliente rtn_cliente moneda
          subtotal descuentos isv total
        ]

        rows = invoices.map do |inv|
          [
            inv.correlative.to_s,
            inv.issue_date.iso8601,
            inv.status,
            inv.authorization.cai,
            inv.customer.to_s,
            inv.customer.rtn&.to_s,
            inv.currency,
            inv.subtotal.to_fixed,
            inv.discount.to_fixed,
            inv.isv_total.to_fixed,
            inv.total.to_fixed
          ]
        end

        ([headers] + rows).map { |row| row.map { |cell| quote_csv(cell) }.join(",") }.join("\n")
      end

      def self.quote_csv(value)
        value = value.to_s
        value.match?(/[",\n]/) ? "\"#{value.gsub('"', '""')}\"" : value
      end
    end
  end
end
