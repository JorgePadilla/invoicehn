# frozen_string_literal: true

require "test_helper"

# Art. 11 num. 2 — sales to consumidores finales, and the L 10,000.00 threshold
# above which the client's data becomes mandatory.
class TestArt11ConsumidorFinal < Minitest::Test
  CF = Invoicehn::Customer::ConsumidorFinal

  def invoice_totalling(amount, customer: CF.new)
    # 15% ISV, so the pre-tax price that produces the wanted total.
    base = Invoicehn::Money.new(amount, "HNL") / dec("1.15")
    build_invoice(customer: customer, line_items: [build_line(unit_price: base)])
  end

  # "Nombres y Apellidos, Número de identificación o consignar la leyenda
  # 'CONSUMIDOR FINAL'".
  def test_anonymous_sale_prints_the_legend
    customer = CF.new

    assert_equal "CONSUMIDOR FINAL", customer.identification_line
    assert_equal "CONSUMIDOR FINAL", customer.display_name
    refute_predicate customer, :identified?
  end

  def test_a_named_consumer_prints_their_identification
    customer = CF.new(name: "María López", identification_type: "DNI",
                      identification_number: "0801-1990-12345")

    assert_predicate customer, :identified?
    assert_equal "María López", customer.display_name
    assert_equal "DNI 0801-1990-12345", customer.identification_line
  end

  def test_an_anonymous_sale_below_the_threshold_is_compliant
    invoice = invoice_totalling("5000.00")

    assert_operator invoice.total, :<, CF::IDENTIFICATION_THRESHOLD
    assert_predicate invoice, :compliant?
  end

  # The threshold is L 10,000.00 exactly, and the article says "excediera" — so
  # a sale of exactly ten thousand does not yet require the data.
  def test_exactly_ten_thousand_does_not_require_identification
    customer = CF.new

    refute customer.identification_required?(hnl("10000.00"))
    assert customer.identification_required?(hnl("10000.01"))
  end

  def test_above_the_threshold_an_anonymous_sale_is_refused
    invoice = invoice_totalling("15000.00")

    assert_operator invoice.total, :>, CF::IDENTIFICATION_THRESHOLD
    assert_violates "Art. 11 num. 2", invoice
    assert_raises(Invoicehn::ComplianceError) { invoice.validate! }
  end

  def test_above_the_threshold_an_identified_sale_passes
    customer = CF.new(name: "María López", identification_type: "DNI",
                      identification_number: "0801-1990-12345")
    invoice = invoice_totalling("15000.00", customer: customer)

    refute_violates "Art. 11 num. 2", invoice
    assert_predicate invoice, :compliant?
  end

  # A name with no document number is not "el tipo y número de documento de
  # identificación", so it does not satisfy the article.
  def test_a_name_without_a_document_number_is_not_enough
    customer = CF.new(name: "María López")
    invoice = invoice_totalling("15000.00", customer: customer)

    assert_violates "Art. 11 num. 2", invoice
  end

  def test_the_threshold_matches_the_article
    assert_equal hnl("10000.00"), CF::IDENTIFICATION_THRESHOLD
  end

  # The article states the threshold as a sum in lempiras — "excediera la suma
  # de diez mil Lempiras" — so a foreign-currency sale is measured by its
  # Lempira equivalent. Without this, an anonymous US$50,000 sale would slip
  # past a rule written for L 10,000.
  def usd_invoice(unit_price, customer: CF.new)
    build_invoice(
      customer: customer,
      currency: "USD",
      issue_date: Date.new(2026, 8, 28),
      exchange_rate: Invoicehn::ExchangeRate.new(rate: "24.6543", date: Date.new(2026, 8, 28)),
      line_items: [build_line(unit_price: usd(unit_price), treatment: :exento)]
    )
  end

  def test_a_usd_sale_above_the_lempira_equivalent_requires_identification
    invoice = usd_invoice("50000.00")

    assert_operator invoice.total_in_lempiras, :>, CF::IDENTIFICATION_THRESHOLD
    assert_violates "Art. 11 num. 2", invoice
    assert_raises(Invoicehn::ComplianceError) { invoice.validate! }
  end

  def test_a_usd_sale_below_the_lempira_equivalent_stays_anonymous
    # US$100 ≈ L 2,465.43, well under the threshold.
    invoice = usd_invoice("100.00")

    assert_operator invoice.total_in_lempiras, :<, CF::IDENTIFICATION_THRESHOLD
    refute_violates "Art. 11 num. 2", invoice
    assert_predicate invoice, :compliant?
  end

  def test_an_identified_usd_sale_above_the_threshold_passes
    customer = CF.new(name: "María López", identification_type: "DNI",
                      identification_number: "0801-1990-12345")

    refute_violates "Art. 11 num. 2", usd_invoice("50000.00", customer: customer)
  end

  # The threshold is measured in lempiras, so the predicate refuses any other
  # currency rather than silently comparing incomparable amounts.
  def test_the_predicate_refuses_a_non_lempira_amount
    assert_raises(Invoicehn::CurrencyMismatch) { CF.new.identification_required?(usd("50000.00")) }
  end

  def test_round_trips_through_a_hash
    customer = CF.new(name: "María López", identification_type: "DNI",
                      identification_number: "0801-1990-12345")

    assert_equal customer.to_h, Invoicehn::Customer.from_h(customer.to_h).to_h
  end
end
