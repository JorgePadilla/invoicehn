# frozen_string_literal: true

module Invoicehn
  # Base for every error this library raises.
  class Error < StandardError; end

  # A value does not satisfy the format the law or this library requires.
  class ValidationError < Error; end

  # Arithmetic across mismatched currencies.
  class CurrencyMismatch < Error; end

  # Raised when a document fails one or more compliance rules. Carries the
  # violations so a caller can report every problem at once rather than
  # discovering them one at a time.
  class ComplianceError < Error
    attr_reader :violations

    def initialize(violations)
      @violations = Array(violations)
      super(@violations.join("\n"))
    end
  end

  # The authorization's fecha límite de emisión has passed (Art. 62).
  class AuthorizationExpired < Error; end

  # The next correlative would fall outside the authorized range (Art. 10 num. 5).
  class RangeExhausted < Error; end

  # No authorization on file covers the document being issued.
  class NoAuthorization < Error; end

  # The requested document was not found in the store.
  class DocumentNotFound < Error; end

  # An issued document may not be altered (Art. 41 — correct by annulment).
  class ImmutableDocument < Error; end
end
