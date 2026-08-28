# frozen_string_literal: true

require "date"

module Invoicehn
  # Issues a Factura: picks the authorization, allocates the correlativo,
  # validates against the Reglamento, persists, and posts to the ledger.
  #
  # The whole sequence happens inside the allocator's lock, so a document is
  # either fully recorded or its number was never consumed. Nothing here can
  # produce a number without a document behind it.
  class Issuance
    attr_reader :store, :sequence, :ledger

    def initialize(config: Config.new, store: nil, sequence: nil, ledger: nil)
      @config   = config
      @store    = store || Storage::JsonStore.new(config)
      @sequence = sequence || Sequence.new(config)
      @ledger   = ledger || Ledger::JsonlLedger.new(config)
    end

    # @param identifier [String] "NNN-NNN-NN", the establecimiento / punto de
    #   emisión / tipo de documento triple. Defaults to the casa matriz's first
    #   emission point issuing a Factura.
    # @param issue_date [Date] pinned to today by default. Art. 43 obliges
    #   chronological custody, and a ledger whose numbering disagrees with its
    #   dates is the first thing an audit questions — so backdating is not
    #   offered through the CLI.
    def issue(customer:, line_items:, identifier: "000-001-01", currency: "HNL",
              exchange_rate: nil, notes: nil, issue_date: Date.today)
      issuer = @store.issuer
      raise NoAuthorization, "no se ha configurado el emisor; ejecute «invoicehn setup»" if issuer.nil?

      @sequence.allocate(identifier) do |correlative|
        authorization = pick_authorization(identifier, correlative, issue_date)

        invoice = Invoice.new(
          correlative: correlative,
          issuer: issuer,
          customer: customer,
          authorization: authorization,
          line_items: line_items,
          issue_date: issue_date,
          currency: currency,
          exchange_rate: exchange_rate,
          notes: notes
        )

        invoice.validate!(on: issue_date)
        @store.save_document(invoice)
        @ledger.record(invoice, event: :emision)
        invoice
      end
    end

    # Art. 41 — annulment. The correlativo stays consumed; the sequence never
    # goes backwards.
    def annul(correlative, reason:, on: Date.today)
      invoice = @store.find(correlative)
      annulled = invoice.annul(reason: reason, on: on)

      @store.save_document(annulled)
      @ledger.record(annulled, event: :anulacion)
      annulled
    end

    # What `invoicehn check` reports: whether issuing is possible right now, and
    # what is about to go wrong.
    def health(identifier: "000-001-01", on: Date.today)
      issuer = @store.issuer
      next_correlative = @sequence.peek(identifier)
      authorizations = @store.authorizations_for(identifier)
      active = @store.active_authorization(identifier, next_sequence: next_correlative.sequence, on: on)

      {
        identifier: identifier,
        issuer_configured: !issuer.nil?,
        issuer_complete: issuer&.complete? || false,
        issuer_missing: issuer&.missing_fields || [],
        authorizations: authorizations.size,
        active_authorization: active,
        next_correlative: next_correlative,
        issued: @sequence.issued_count(identifier),
        remaining: active ? (active.range_end.sequence - next_correlative.sequence + 1) : 0,
        days_remaining: active&.days_remaining(on),
        # Art. 42 — expired authorizations holding unused documents must be
        # reported to SAR within the first 10 business days of the next month.
        lapsed_with_unused: lapsed_with_unused(identifier, on: on),
        ready: !issuer.nil? && issuer.complete? && !active.nil?
      }
    end

    private

    def pick_authorization(identifier, correlative, on)
      authorization = @store.active_authorization(identifier, next_sequence: correlative.sequence, on: on)

      if authorization.nil?
        on_file = @store.authorizations_for(identifier)
        raise NoAuthorization, <<~MSG.strip if on_file.empty?
          no hay autorización registrada para #{identifier}; regístrela con «invoicehn auth add»
          (el CAI, el rango y la fecha límite los otorga el SAR, Arts. 59-61)
        MSG

        raise NoAuthorization, <<~MSG.strip
          ninguna autorización vigente cubre el correlativo #{correlative};
          las registradas están vencidas o agotadas. Solicite una nueva al SAR.
        MSG
      end

      authorization.assert_usable!(correlative, on: on)
      authorization
    end

    # Authorizations past their fecha límite that still had numbers left.
    def lapsed_with_unused(identifier, on:)
      issued = @sequence.issued_count(identifier)

      @store.authorizations_for(identifier).select do |auth|
        auth.expired?(on) && issued < auth.range_end.sequence
      end
    end
  end
end
