# frozen_string_literal: true

require "date"

module Invoicehn
  # Issues a Factura, Nota de Crédito or Nota de Débito: picks the
  # authorization, allocates the correlativo, validates against the
  # Reglamento, persists, and posts to the ledger.
  #
  # The whole sequence happens inside the allocator's block, so a document is
  # either fully recorded or its number was never consumed. Nothing here can
  # produce a number without a document behind it, and a failure part-way
  # leaves nothing behind: if the ledger refuses the entry, the document just
  # saved is deleted again before the counter would have advanced.
  #
  # The store, sequence and ledger are duck-typed collaborators; the README
  # lists the exact methods each must answer, and Invoicehn::Testing checks
  # an implementation against that list.
  class Issuance
    DEFAULT_IDENTIFIER = "000-001-01"
    CREDIT_NOTE_IDENTIFIER = "000-001-06"
    DEBIT_NOTE_IDENTIFIER = "000-001-07"

    attr_reader :store, :sequence, :ledger

    def initialize(config: Config.new, store: nil, sequence: nil, ledger: nil)
      @config   = config
      @store    = store || Storage::JsonStore.new(config)
      @sequence = sequence || Sequence.new(config)
      @ledger   = ledger || Ledger::JsonlLedger.new(config)
    end

    # @param identifier [String] "NNN-NNN-NN", the establecimiento / punto de
    #   emisión / tipo de documento triple. Its last group decides the kind of
    #   document: 01 Factura, 06 Nota de Crédito, 07 Nota de Débito. Each
    #   identifier has its own counter and its own SAR authorization (Art. 59:
    #   "La autorización será por punto de emisión y por tipo de documento").
    # @param issue_date [Date] pinned to today by default. Art. 43 obliges
    #   chronological custody, and a ledger whose numbering disagrees with its
    #   dates is the first thing an audit questions — so backdating is not
    #   offered through the CLI.
    # @param reference [DocumentReference, String, Correlative, nil] notes
    #   only: the document the note applies to. A correlative is looked up in
    #   the store and its CAI and date copied; a DocumentReference is used as
    #   given (for documents issued outside this store) and, if the store does
    #   hold that document, checked against it.
    # @param motivo [String, nil] notes only: "Motivo de la emisión del
    #   documento" (Arts. 26 and 28 num. 4).
    def issue(customer:, line_items:, identifier: DEFAULT_IDENTIFIER, currency: "HNL",
              exchange_rate: nil, notes: nil, issue_date: Invoicehn.today,
              reference: nil, motivo: nil)
      issuer = @store.issuer
      raise NoAuthorization, "no se ha configurado el emisor; ejecute «invoicehn setup»" if issuer.nil?

      reference = resolve_reference(reference, customer)

      @sequence.allocate(identifier) do |correlative|
        authorization = pick_authorization(identifier, correlative, issue_date)

        document = Invoice.new(
          correlative: correlative,
          issuer: issuer,
          customer: customer,
          authorization: authorization,
          line_items: line_items,
          issue_date: issue_date,
          currency: currency,
          exchange_rate: exchange_rate,
          notes: notes,
          reference: reference,
          motivo: motivo
        )

        document.validate!(on: issue_date)
        persist(document)
      end
    end

    # A Nota de Crédito (tipo 06, Arts. 25-26): returns, discounts granted after
    # the sale, or the reversal of an operation (Art. 4 num. 32).
    def issue_credit_note(reference:, motivo:, customer:, line_items:,
                          identifier: CREDIT_NOTE_IDENTIFIER, **options)
      assert_type!(identifier, Correlative::NOTA_DE_CREDITO)
      issue(customer: customer, line_items: line_items, identifier: identifier,
            reference: reference, motivo: motivo, **options)
    end

    # A Nota de Débito (tipo 07, Arts. 27-28): an adjustment charged on top of
    # a Comprobante Fiscal already issued (Art. 4 num. 31).
    def issue_debit_note(reference:, motivo:, customer:, line_items:,
                         identifier: DEBIT_NOTE_IDENTIFIER, **options)
      assert_type!(identifier, Correlative::NOTA_DE_DEBITO)
      issue(customer: customer, line_items: line_items, identifier: identifier,
            reference: reference, motivo: motivo, **options)
    end

    # Art. 41 — annulment. The correlativo stays consumed; the sequence never
    # goes backwards.
    # Works the same for a Factura and for a note.
    def annul(correlative, reason:, on: Invoicehn.today)
      invoice = @store.find(correlative)
      annulled = invoice.annul(reason: reason, on: on)

      @store.save_document(annulled)
      @ledger.record(annulled, event: :anulacion)
      annulled
    end

    # What `invoicehn check` reports: whether issuing is possible right now, and
    # what is about to go wrong.
    def health(identifier: DEFAULT_IDENTIFIER, on: Invoicehn.today)
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
        remaining: active ? [active.range_end.sequence - next_correlative.sequence + 1, 0].max : 0,
        days_remaining: active&.days_remaining(on),
        # Art. 42 — expired authorizations holding unused documents must be
        # reported to SAR within the first 10 business days of the next month.
        lapsed_with_unused: lapsed_with_unused(identifier, on: on),
        ready: !issuer.nil? && issuer.complete? && !active.nil?
      }
    end

    private

    # Saves, then posts to the ledger. If posting fails — for any reason,
    # including an interrupt — the document is deleted again, so the store
    # never holds a number the counter has not consumed. Without this a
    # failing ledger left the document on disk and the counter behind it, and
    # every later issue for that identifier failed with ImmutableDocument.
    def persist(document)
      @store.save_document(document)
      recorded = false
      begin
        @ledger.record(document, event: :emision)
        recorded = true
      ensure
        @store.delete_document(document) unless recorded
      end
      document
    end

    def assert_type!(identifier, type)
      return if identifier.to_s.split("-")[2] == type

      raise ValidationError,
            "el identificador #{identifier} no corresponde a #{Correlative::DOCUMENT_TYPES.fetch(type)} " \
            "(tipo #{type})"
    end

    # Turns what the caller passed into a DocumentReference, cross-checking it
    # against the original when the store holds it.
    def resolve_reference(reference, customer)
      return nil if reference.nil?

      if reference.is_a?(DocumentReference)
        original = @store.exists?(reference.correlative) ? @store.find(reference.correlative) : nil
        check_reference_matches!(reference, original) if original
      else
        original = @store.find(reference)
        reference = DocumentReference.from_document(original)
      end

      check_original!(original, customer) if original
      reference
    end

    def check_reference_matches!(reference, original)
      stored = DocumentReference.from_document(original)
      return if stored == reference

      raise ValidationError,
            "los datos del documento de referencia no coinciden con #{original.correlative} " \
            "registrado (CAI #{stored.cai}, fecha #{stored.issue_date})"
    end

    # Not article text but consistency: a note adjusts the operation of the
    # document it points at, so that document must still stand and belong to
    # the same acquirer.
    def check_original!(original, customer)
      if original.annulled?
        raise ValidationError, "#{original.correlative} está ANULADA (Art. 41); no se le puede aplicar una nota"
      end

      return unless original.customer.rtn && customer.rtn
      return if original.customer.rtn == customer.rtn

      raise ValidationError,
            "el adquirente de la nota (RTN #{customer.rtn.formatted}) no es el de " \
            "#{original.correlative} (RTN #{original.customer.rtn.formatted})"
    end

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
