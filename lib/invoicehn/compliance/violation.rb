# frozen_string_literal: true

module Invoicehn
  module Compliance
    # One failed legal requirement, carrying the article it comes from so the
    # operator can look it up rather than trust the library's paraphrase.
    class Violation
      SEVERITIES = %i[error warning].freeze

      attr_reader :article, :requirement, :detail, :severity

      def initialize(article:, requirement:, detail: nil, severity: :error)
        raise ArgumentError, "severidad desconocida: #{severity.inspect}" unless SEVERITIES.include?(severity)

        @article = article
        @requirement = requirement
        @detail = detail
        @severity = severity
        freeze
      end

      def error? = @severity == :error
      def warning? = @severity == :warning

      def to_s
        base = "#{@article}: #{@requirement}"
        @detail ? "#{base} — #{@detail}" : base
      end

      def to_h
        {
          "article" => @article,
          "requirement" => @requirement,
          "detail" => @detail,
          "severity" => @severity.to_s
        }.compact
      end

      def inspect = "#<Invoicehn::Compliance::Violation #{self}>"
    end
  end
end
