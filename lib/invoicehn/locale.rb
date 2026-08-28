# frozen_string_literal: true

require "yaml"

module Invoicehn
  # Interface strings for the CLI, in Spanish or English.
  #
  # This deliberately covers *only* the interface. The Factura's own legends are
  # legal text fixed by the Reglamento and live as constants in
  # Renderers::Text — an English-locale CLI still issues a Spanish invoice,
  # because the document's wording is not a presentation choice.
  module Locale
    DEFAULT = "es"
    AVAILABLE = %w[es en].freeze
    ENV_VAR = "INVOICEHN_LANG"

    class << self
      def current
        @current ||= detect
      end

      def current=(lang)
        lang = lang.to_s.downcase[0, 2]
        @current = AVAILABLE.include?(lang) ? lang : DEFAULT
      end

      # Looks up a dotted key: t("setup.title"). Interpolation uses %{name}
      # placeholders. A missing key returns the key itself rather than raising —
      # a broken label must never stop an invoice from being issued.
      def t(key, **values)
        string = dig(catalog(current), key) || dig(catalog(DEFAULT), key)
        return key.to_s if string.nil?

        values.empty? ? string : format(string, **values)
      rescue KeyError
        string
      end

      def reset!
        @current = nil
        @catalogs = nil
      end

      private

      # Spanish unless English is asked for explicitly, via INVOICEHN_LANG or
      # --lang. The system LANG is deliberately ignored: the users are Honduran
      # businesses, and someone running an English-locale laptop still wants the
      # Spanish interface next to a Spanish document.
      def detect
        normalize(ENV.fetch(ENV_VAR, DEFAULT))
      end

      def normalize(lang)
        lang = lang.to_s.downcase[0, 2]
        AVAILABLE.include?(lang) ? lang : DEFAULT
      end

      def catalogs
        @catalogs ||= AVAILABLE.to_h do |lang|
          path = File.expand_path("../../config/locales/#{lang}.yml", __dir__)
          data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
          [lang, data[lang] || {}]
        end
      end

      def catalog(lang) = catalogs.fetch(lang, {})

      def dig(hash, key)
        value = key.to_s.split(".").reduce(hash) do |acc, part|
          acc.is_a?(Hash) ? acc[part] : nil
        end
        value.is_a?(String) ? value : nil
      end
    end
  end
end
