# frozen_string_literal: true

require "json"
require "time"
require "date"
require "fileutils"

module Invoicehn
  # The integration point Art. 53 num. 1 requires.
  #
  # "El sistema de facturación debe estar integrado al menos a un sistema
  # contable o de inventarios." That integration is part of what the operator
  # attests in the Declaración Jurada filed before being authorized as an
  # autoimpresor, so it is a condition of the authorization and not an optional
  # convenience.
  #
  # Subclass and override #record to post into real accounting or inventory
  # software. The default implementation writes an append-only JSONL book, which
  # satisfies the requirement standalone and feeds the Art. 53 num. 5 export.
  class Ledger
    # Called once per issued or annulled document.
    #
    # @param invoice [Invoice]
    # @param event [Symbol] :emision or :anulacion
    def record(invoice, event: :emision)
      raise NotImplementedError, "#{self.class} debe implementar #record"
    end

    # Art. 53 num. 5: "El Sistema debe tener la capacidad de generación de
    # archivos tipo texto para su almacenamiento y traslado hacia la
    # Administración Tributaria a través de servicios web o intercambio de
    # protocolo."
    def entries(from: nil, to: nil)
      raise NotImplementedError, "#{self.class} debe implementar #entries"
    end

    # The default: a plain append-only book on disk.
    class JsonlLedger < Ledger
      attr_reader :path

      def initialize(config = Config.new)
        super()
        @path = config.ledger_path
      end

      def record(invoice, event: :emision)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |f| f.puts(JSON.generate(entry_for(invoice, event))) }
        invoice
      end

      def entries(from: nil, to: nil)
        return [] unless File.exist?(@path)

        File.readlines(@path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
            .select { |e| within?(Date.parse(e["issue_date"]), from, to) }
      end

      private

      def entry_for(invoice, event)
        {
          "recorded_at" => Time.now.utc.iso8601,
          "event" => event.to_s,
          "correlative" => invoice.correlative.to_s,
          "issue_date" => invoice.issue_date.iso8601,
          "cai" => invoice.authorization.cai,
          "customer" => invoice.customer.to_s,
          "customer_rtn" => invoice.customer.rtn&.to_s,
          "currency" => invoice.currency,
          "subtotal" => invoice.subtotal.to_h["amount"],
          "discount" => invoice.discount.to_h["amount"],
          "isv" => invoice.isv_total.to_h["amount"],
          "total" => invoice.total.to_h["amount"],
          "status" => invoice.status
        }
      end

      def within?(date, from, to)
        return false if from && date < from
        return false if to && date > to

        true
      end
    end

    # Fans out to several ledgers, so the built-in book can stay in place while
    # an accounting integration is added alongside it.
    class Multi < Ledger
      attr_reader :ledgers

      def initialize(*ledgers)
        super()
        @ledgers = ledgers.flatten
      end

      def record(invoice, event: :emision)
        @ledgers.each { |l| l.record(invoice, event: event) }
        invoice
      end

      def entries(from: nil, to: nil)
        @ledgers.first&.entries(from: from, to: to) || []
      end
    end
  end
end
