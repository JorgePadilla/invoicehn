# frozen_string_literal: true

require "json"
require "fileutils"
require "date"

module Invoicehn
  module Storage
    # Append-only store for issued documents, plus the issuer profile and the
    # authorizations on file.
    #
    # An issued document is never rewritten in place. The one exception is
    # annulment (Art. 41), which replaces the record with its annulled form —
    # the correlative stays consumed either way, which is what keeps the series
    # auditable.
    class JsonStore
      attr_reader :config

      def initialize(config = Config.new)
        @config = config
      end

      # --- issuer -------------------------------------------------------

      def issuer
        data = read_json(@config.issuer_path)
        data && Issuer.from_h(data)
      end

      def save_issuer(issuer)
        write_json(@config.issuer_path, issuer.to_h)
        issuer
      end

      # --- authorizations ------------------------------------------------

      def authorizations
        Array(read_json(@config.authorizations_path)).map { |h| Authorization.from_h(h) }
      end

      # One identifier accumulates authorizations over time: a range is
      # exhausted, SAR grants a successor, and the old one stays on file as part
      # of the record.
      def add_authorization(authorization)
        existing = authorizations
        duplicate = existing.find do |a|
          a.cai == authorization.cai && a.range_start == authorization.range_start
        end
        raise ValidationError, "esa autorización ya está registrada" if duplicate

        write_json(@config.authorizations_path, (existing + [authorization]).map(&:to_h))
        authorization
      end

      def authorizations_for(identifier)
        authorizations.select { |a| a.identifier == identifier }
      end

      # The authorization that should be used next for an identifier: still
      # current, and with room left in its range.
      def active_authorization(identifier, next_sequence: nil, on: Date.today)
        candidates = authorizations_for(identifier).reject { |a| a.expired?(on) }
        return nil if candidates.empty?

        if next_sequence
          covering = candidates.select { |a| a.covers?(sequence_to_correlative(identifier, next_sequence)) }
          return covering.min_by { |a| a.range_start.sequence } if covering.any?
        end

        candidates.min_by { |a| a.range_start.sequence }
      end

      # --- documents -----------------------------------------------------

      def save_document(invoice)
        path = @config.document_path(invoice.correlative, invoice.issue_date)
        FileUtils.mkdir_p(File.dirname(path))

        if File.exist?(path) && !invoice.annulled?
          raise ImmutableDocument,
                "la factura #{invoice.correlative} ya está registrada y no puede modificarse (Art. 41)"
        end

        write_json(path, invoice.to_h)
        invoice
      end

      def find(correlative)
        correlative = Correlative.parse(correlative.to_s)
        path = Dir.glob(File.join(@config.documents_dir, "*", "*", "#{correlative}.json")).first
        raise DocumentNotFound, "no existe la factura #{correlative}" unless path

        Invoice.from_h(read_json(path))
      end

      def exists?(correlative)
        Dir.glob(File.join(@config.documents_dir, "*", "*", "#{correlative}.json")).any?
      end

      # Documents in chronological order, which is the order Art. 43 requires
      # them to be kept in.
      def all(from: nil, to: nil)
        Dir.glob(File.join(@config.documents_dir, "*", "*", "*.json"))
           .map { |path| Invoice.from_h(read_json(path)) }
           .select { |inv| within?(inv.issue_date, from, to) }
           .sort_by { |inv| [inv.issue_date, inv.correlative.to_s] }
      end

      # --- settings ------------------------------------------------------

      def settings = read_json(@config.settings_path) || {}

      def save_settings(hash)
        write_json(@config.settings_path, settings.merge(hash))
      end

      private

      def sequence_to_correlative(identifier, sequence)
        establishment, emission_point, document_type = identifier.split("-")
        Correlative.new(establishment: establishment, emission_point: emission_point,
                        document_type: document_type, sequence: sequence)
      end

      def within?(date, from, to)
        return false if from && date < from
        return false if to && date > to

        true
      end

      def read_json(path)
        return nil unless File.exist?(path)

        content = File.read(path)
        return nil if content.strip.empty?

        JSON.parse(content)
      rescue JSON::ParserError => e
        raise Error, "archivo dañado en #{path}: #{e.message}"
      end

      # Written to a temporary file and renamed, so an interrupted write cannot
      # leave a half-written fiscal record behind.
      def write_json(path, data)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp#{Process.pid}"
        File.write(tmp, "#{JSON.pretty_generate(data)}\n")
        File.rename(tmp, path)
        data
      end
    end
  end
end
