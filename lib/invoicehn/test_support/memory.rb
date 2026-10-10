# frozen_string_literal: true

require "monitor"
require "invoicehn" unless defined?(Invoicehn::Issuance)

module Invoicehn
  module TestSupport
    # In-memory store, sequence and ledger. They exist for tests, and as the
    # shortest complete example of the contract a host adapter (Postgres,
    # say) has to meet — each method here is one the README lists. They hold
    # nothing across processes and must never back real fiscal documents.

    # The store: issuer, authorizations and documents.
    class MemoryStore
      attr_reader :documents, :issuer

      def initialize(issuer: nil, authorizations: [])
        @issuer = issuer
        @authorizations = authorizations.dup
        @documents = {}
      end

      def save_issuer(issuer)
        @issuer = issuer
      end

      def add_authorization(authorization)
        @authorizations << authorization
        authorization
      end

      def authorizations_for(identifier) = @authorizations.select { |a| a.identifier == identifier }

      # Unexpired, and — when next_sequence is given — covering that number.
      def active_authorization(identifier, next_sequence: nil, on: Invoicehn.today)
        candidates = authorizations_for(identifier).reject { |a| a.expired?(on) }
        if next_sequence
          correlative = Correlative.parse(format("%<id>s-%<n>08d", id: identifier, n: next_sequence))
          candidates = candidates.select { |a| a.covers?(correlative) }
        end
        candidates.min_by { |a| a.range_start.sequence }
      end

      # An issued document is immutable; only its annulled form may replace it
      # (Art. 41).
      def save_document(document)
        key = document.correlative.to_s
        if @documents.key?(key) && !document.annulled?
          raise ImmutableDocument, "el documento #{key} ya está registrado y no puede modificarse (Art. 41)"
        end

        @documents[key] = document.to_h
        document
      end

      def delete_document(document)
        @documents.delete(document.correlative.to_s)
        document
      end

      def find(correlative)
        hash = @documents[correlative.to_s]
        raise DocumentNotFound, "no existe el documento #{correlative}" unless hash

        Invoice.from_h(hash)
      end

      def exists?(correlative) = @documents.key?(correlative.to_s)
    end

    # The counter per identifier. The block runs inside the lock and the
    # counter advances only after it returns — the property that keeps a
    # failed issue from burning a number.
    class MemorySequence
      def initialize
        @counters = Hash.new(0)
        @lock = Monitor.new
      end

      def peek(identifier) = @lock.synchronize { build(identifier, @counters[identifier] + 1) }

      def issued_count(identifier) = @lock.synchronize { @counters[identifier] }

      def allocate(identifier)
        @lock.synchronize do
          correlative = build(identifier, @counters[identifier] + 1)
          result = block_given? ? yield(correlative) : correlative
          @counters[identifier] = correlative.sequence
          result
        end
      end

      private

      def build(identifier, sequence) = Correlative.parse(format("%<id>s-%<n>08d", id: identifier, n: sequence))
    end

    # Keeps the entries it is handed.
    class MemoryLedger
      attr_reader :records

      def initialize
        @records = []
      end

      def record(document, event: :emision)
        @records << [event, document.correlative.to_s]
        document
      end
    end
  end
end
