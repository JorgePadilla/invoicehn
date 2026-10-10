# frozen_string_literal: true

require "invoicehn" unless defined?(Invoicehn::Issuance)

module Invoicehn
  # Checks a host application's store, sequence and ledger against the
  # contract Invoicehn::Issuance relies on. Not loaded by `require
  # "invoicehn"`; a host's test suite opts in:
  #
  #   require "invoicehn/testing"
  #
  #   Invoicehn::Testing.assert_store_contract(PostgresStore.new)
  #   Invoicehn::Testing.assert_sequence_contract(PostgresSequence.new)
  #   Invoicehn::Testing.assert_ledger_contract(AccountingLedger.new)
  #   Invoicehn::Testing.assert_issuance_round_trip(store: ..., sequence: ..., ledger: ...)
  #
  # Every check raises Invoicehn::Testing::ContractError listing all the
  # problems it found, and returns the checked object (or, for the round trip,
  # the issued document) otherwise, so it works under minitest, RSpec or a
  # plain script.
  module Testing
    # Raised when an implementation does not satisfy the contract.
    class ContractError < Error; end

    # name => [positional parameters, keyword parameters]
    STORE_CONTRACT = {
      issuer: [0, []],
      authorizations_for: [1, []],
      active_authorization: [1, %i[next_sequence on]],
      save_document: [1, []],
      delete_document: [1, []],
      find: [1, []],
      exists?: [1, []]
    }.freeze

    SEQUENCE_CONTRACT = {
      allocate: [1, []],
      peek: [1, []],
      issued_count: [1, []]
    }.freeze

    LEDGER_CONTRACT = {
      record: [1, %i[event]]
    }.freeze

    # A ledger that refuses every entry, used to prove the rollback.
    class RefusingLedger
      class Refused < StandardError; end

      def record(_document, event: :emision)
        raise Refused, "asiento rechazado a propósito (#{event})"
      end
    end

    class << self
      def assert_store_contract(store) = assert_contract(store, STORE_CONTRACT, "store")
      def assert_sequence_contract(sequence) = assert_contract(sequence, SEQUENCE_CONTRACT, "sequence")
      def assert_ledger_contract(ledger) = assert_contract(ledger, LEDGER_CONTRACT, "ledger")

      # Behavioural check, against a store that already holds a complete
      # issuer and a current authorization for `identifier`. Issues ONE real
      # Factura, so run it against a test database.
      #
      # 1. With a ledger that refuses the entry, issuing must raise and leave
      #    nothing behind: no document at the next number, counter unchanged.
      #    This is what a Postgres adapter gets wrong when allocate advances
      #    the counter outside the block, or delete_document is a no-op.
      # 2. With the real ledger, the document must come back from find equal
      #    to what was issued, and the counter must have advanced by one.
      #
      # @return [Invoice] the document issued in step 2
      def assert_issuance_round_trip(store:, sequence:, ledger:, identifier: Issuance::DEFAULT_IDENTIFIER,
                                     customer: Customer::ConsumidorFinal.new, line_items: nil)
        line_items ||= [LineItem.new(description: "Prueba de contrato", quantity: 1,
                                     unit_price: Money.new("1.00"), treatment: :exento)]
        before = sequence.issued_count(identifier)
        upcoming = sequence.peek(identifier)
        problems = []

        refusing = Issuance.new(store: store, sequence: sequence, ledger: RefusingLedger.new)
        begin
          refusing.issue(customer: customer, line_items: line_items, identifier: identifier)
          problems << "issue no propagó el error del ledger"
        rescue RefusingLedger::Refused
          nil
        end
        problems << "el documento #{upcoming} quedó guardado aunque el ledger lo rechazó" if store.exists?(upcoming)
        if sequence.issued_count(identifier) != before
          problems << "el contador avanzó aunque la emisión falló (allocate debe avanzar sólo si el bloque termina)"
        end
        raise ContractError, problems.join("\n") if problems.any?

        document = Issuance.new(store: store, sequence: sequence, ledger: ledger)
                           .issue(customer: customer, line_items: line_items, identifier: identifier)

        problems << "se emitió #{document.correlative}, se esperaba #{upcoming}" unless document.correlative == upcoming
        problems << "issued_count no avanzó en uno" unless sequence.issued_count(identifier) == before + 1
        problems << "exists? no encuentra #{document.correlative}" unless store.exists?(document.correlative)
        unless store.find(document.correlative).to_h == document.to_h
          problems << "find(#{document.correlative}) no devuelve el documento tal como se emitió"
        end
        raise ContractError, problems.join("\n") if problems.any?

        document
      end

      private

      def assert_contract(object, contract, role)
        problems = contract.flat_map do |name, (positional, keywords)|
          next ["#{role} debe responder a ##{name}"] unless object.respond_to?(name)

          signature_problems(object.method(name), role, name, positional, keywords)
        end
        raise ContractError, problems.join("\n") if problems.any?

        object
      end

      def signature_problems(method, role, name, positional, keywords)
        params = method.parameters
        problems = []

        required = params.count { |type, _| type == :req }
        accepts = params.count { |type, _| %i[req opt].include?(type) }
        rest = params.any? { |type, _| type == :rest }
        unless required <= positional && (rest || accepts >= positional)
          problems << "#{role}##{name} debe aceptar #{positional} argumento(s) posicional(es)"
        end

        keyrest = params.any? { |type, _| type == :keyrest }
        declared = params.filter_map { |type, param| param if %i[key keyreq].include?(type) }
        (keywords - declared).each do |kw|
          problems << "#{role}##{name} debe aceptar la palabra clave #{kw}:" unless keyrest
        end
        problems
      end
    end
  end
end
