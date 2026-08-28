# frozen_string_literal: true

require "test_helper"

# Art. 11 num. 1 lit. j) and num. 2 lit. g) — "Denominación literal de la Moneda
# Nacional Lempira o símbolo (L)".
#
# Art. 11, closing paragraph — "En ambos casos, cuando el Obligado Tributario
# emita facturas con otra denominación monetaria, debe indicar la tasa de cambio
# vigente a la fecha de emisión." The paragraph opens "En ambos casos", so it
# binds both the crédito-fiscal and the consumidor-final invoice.
class TestArt11Currency < Minitest::Test
  def usd_invoice(rate: nil, issue_date: Date.new(2026, 8, 28), **overrides)
    build_invoice(
      currency: "USD",
      issue_date: issue_date,
      exchange_rate: rate,
      line_items: [build_line(unit_price: usd("100.00"))],
      **overrides
    )
  end

  def bch_rate(date: Date.new(2026, 8, 28), rate: "24.6543")
    Invoicehn::ExchangeRate.new(rate: rate, date: date, currency: "USD")
  end

  def test_lempira_invoices_need_no_rate
    invoice = build_invoice

    refute_predicate invoice, :foreign_currency?
    assert_predicate invoice, :compliant?
    assert_equal "L", invoice.total.symbol
  end

  def test_a_foreign_currency_invoice_without_a_rate_is_refused
    invoice = usd_invoice

    assert_predicate invoice, :foreign_currency?
    assert_violates "Art. 11 (párrafo final)", invoice
    assert_raises(Invoicehn::ComplianceError) { invoice.validate! }
  end

  def test_a_rate_dated_the_issue_date_satisfies_the_article
    invoice = usd_invoice(rate: bch_rate)

    refute_violates "Art. 11 (párrafo final)", invoice
    assert_predicate invoice, :compliant?
  end

  # "vigente a la fecha de emisión" — yesterday's rate is not the rate in force
  # on the issue date.
  def test_a_stale_rate_is_refused
    invoice = usd_invoice(rate: bch_rate(date: Date.new(2026, 8, 27)))

    assert_violates "Art. 11 (párrafo final)", invoice
  end

  def test_a_rate_for_the_wrong_currency_is_refused
    rate = Invoicehn::ExchangeRate.new(rate: "1.08", date: Date.new(2026, 8, 28), currency: "HNL")
    invoice = usd_invoice(rate: rate)

    assert_violates "Art. 11 (párrafo final)", invoice
  end

  def test_the_lempira_equivalent_is_computed_when_a_rate_is_present
    invoice = usd_invoice(rate: bch_rate)

    assert_equal usd("115.00"), invoice.total # 100 + 15% ISV
    assert_equal hnl("2835.24"), invoice.total_in_lempiras # 115 × 24.6543 = 2835.2445
  end

  def test_the_lempira_equivalent_is_nil_without_a_rate
    assert_nil usd_invoice.total_in_lempiras
  end

  # The reason SpanishNumerals takes a currency: a USD invoice must not claim to
  # be denominated in lempiras.
  def test_total_in_words_names_the_invoice_currency
    assert_equal "CIENTO QUINCE DÓLARES CON 00/100", usd_invoice(rate: bch_rate).total_in_words
    assert_match(/LEMPIRAS/, build_invoice.total_in_words)
  end

  def test_the_rate_line_names_its_source_and_date
    assert_equal "1 USD = L 24.6543 (Banco Central de Honduras, 2026-08-28)", bch_rate.to_s
  end

  # The norm names no rate source, so the field is free text with the market
  # default filled in.
  def test_the_source_is_configurable
    rate = Invoicehn::ExchangeRate.new(rate: "24.70", date: Date.new(2026, 8, 28),
                                       currency: "USD", source: "Banco Atlántida")

    assert_match(/Banco Atlántida/, rate.to_s)
  end

  def test_a_rate_must_be_positive
    assert_raises(Invoicehn::ValidationError) { bch_rate(rate: "0") }
    assert_raises(Invoicehn::ValidationError) { bch_rate(rate: "-1") }
  end

  def test_currencies_cannot_be_mixed_within_an_invoice
    assert_raises(Invoicehn::CurrencyMismatch) do
      Invoicehn::TaxSummary.new(
        [build_line(unit_price: hnl("10.00")), build_line(unit_price: usd("10.00"))],
        currency: "HNL"
      ).subtotal
    end
  end
end
