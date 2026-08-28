# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "invoicehn"
require "invoicehn/cli"
require "minitest/autorun"
require "tmpdir"

module Invoicehn
  # Shared helpers for the suite.
  module TestHelpers
    def hnl(amount) = Invoicehn::Money.new(amount, "HNL")
    def usd(amount) = Invoicehn::Money.new(amount, "USD")

    def dec(value) = BigDecimal(value.to_s)

    # Runs the block with the data directory pointed at a throwaway path, so
    # tests never touch the operator's real ledger.
    def with_temp_home
      Dir.mktmpdir("invoicehn-test") do |dir|
        previous = ENV.fetch("INVOICEHN_HOME", nil)
        ENV["INVOICEHN_HOME"] = dir
        begin
          yield dir
        ensure
          ENV["INVOICEHN_HOME"] = previous
        end
      end
    end

    # A complete Art. 10 num. 1 issuer.
    def build_issuer(**overrides)
      Invoicehn::Issuer.new(
        rtn: "08011990123456",
        legal_name: "Comercial Ejemplo, S. de R.L.",
        trade_name: "Ejemplo",
        headquarters_address: "Col. Palmira, Tegucigalpa, M.D.C.",
        phone: "2222-3333",
        email: "facturacion@ejemplo.hn", **overrides
      )
    end

    def build_authorization(**overrides)
      Invoicehn::Authorization.new(
        cai: "ABCD12-345678-9ABCDE-F01234-567890-AB",
        range_start: "000-001-01-00000001",
        range_end: "000-001-01-00000500",
        limit_date: Date.today + 180, **overrides
      )
    end

    def build_line(**overrides)
      Invoicehn::LineItem.new(
        description: "Servicio de consultoría",
        quantity: 1,
        unit_price: hnl("1000.00"),
        treatment: :gravado_15, **overrides
      )
    end

    def build_invoice(**overrides)
      Invoicehn::Invoice.new(
        correlative: "000-001-01-00000001",
        issuer: build_issuer,
        customer: Invoicehn::Customer::ConsumidorFinal.new,
        authorization: build_authorization,
        line_items: [build_line], **overrides
      )
    end

    # The articles cited by the violations an invoice produces.
    def violation_articles(invoice, on: Date.today)
      invoice.violations(on: on).map(&:article)
    end

    def assert_violates(article, invoice, on: Date.today)
      articles = violation_articles(invoice, on: on)
      assert_includes articles, article,
                      "se esperaba una violación de #{article}; se obtuvo #{articles.inspect}"
    end

    def refute_violates(article, invoice, on: Date.today)
      refute_includes violation_articles(invoice, on: on), article
    end
  end
end

Minitest::Test.include(Invoicehn::TestHelpers)
