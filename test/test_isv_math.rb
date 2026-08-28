# frozen_string_literal: true

require "test_helper"

# Art. 11 num. 1 lit. g) h) i) — discrimination of exempt, exonerated and
# zero-rated values; subtotals by rate; taxes by rate.
class TestIsvMath < Minitest::Test
  def line(treatment, quantity: 1, unit_price: "100.00", discount: nil)
    Invoicehn::LineItem.new(
      description: "Artículo #{treatment}",
      quantity: quantity,
      unit_price: hnl(unit_price),
      discount: discount && hnl(discount),
      treatment: treatment
    )
  end

  def summary(*lines) = Invoicehn::TaxSummary.new(lines)

  # Decreto 278-2013 Art. 16: general rate 15%.
  def test_general_rate_is_fifteen_percent
    assert_equal dec("0.15"), Invoicehn::TaxTreatment::GRAVADO_15.rate
    assert_equal hnl("15.00"), summary(line(:gravado_15)).isv_total
  end

  # Decreto 278-2013 Art. 16: 18% on alcoholic drinks, beer, cigarettes and
  # executive-class air tickets.
  def test_special_rate_is_eighteen_percent
    assert_equal dec("0.18"), Invoicehn::TaxTreatment::GRAVADO_18.rate
    assert_equal hnl("18.00"), summary(line(:gravado_18)).isv_total
  end

  # Art. 12 — exports of taxed merchandise are invoiced at zero rate.
  def test_exports_are_zero_rated
    s = summary(line(:gravado_0))

    assert_equal hnl("100.00"), s.subtotal
    assert_equal hnl("0.00"), s.isv_total
  end

  def test_exempt_and_exonerated_carry_no_tax
    s = summary(line(:exento), line(:exonerado))

    assert_equal hnl("200.00"), s.subtotal
    assert_equal hnl("0.00"), s.isv_total
  end

  # The three untaxed categories all yield zero tax but must remain
  # distinguishable on the document.
  def test_untaxed_categories_stay_separate
    s = summary(line(:exento), line(:exonerado), line(:gravado_0))

    assert_equal 3, s.present_buckets.size
    assert_equal(%i[exento exonerado gravado_0], s.present_buckets.map { |b| b.treatment.key })
    s.present_buckets.each { |b| assert_equal hnl("100.00"), b.base }
  end

  def test_buckets_appear_in_the_order_the_law_lists_them
    s = summary(line(:gravado_18), line(:exento), line(:gravado_15), line(:exonerado), line(:gravado_0))

    assert_equal(%i[exento exonerado gravado_0 gravado_15 gravado_18],
                 s.present_buckets.map { |b| b.treatment.key })
  end

  def test_empty_buckets_are_omitted
    s = summary(line(:gravado_15))

    assert_equal([:gravado_15], s.present_buckets.map { |b| b.treatment.key })
  end

  def test_mixed_rates_are_taxed_independently
    s = summary(line(:gravado_15), line(:gravado_18), line(:exento))

    assert_equal hnl("15.00"), s.bucket_for(:gravado_15).isv
    assert_equal hnl("18.00"), s.bucket_for(:gravado_18).isv
    assert_equal hnl("0.00"), s.bucket_for(:exento).isv
    assert_equal hnl("33.00"), s.isv_total
    assert_equal hnl("300.00"), s.subtotal
    assert_equal hnl("333.00"), s.total
  end

  # The printed ISV must equal the printed rate applied to the printed base.
  # Rounding each line and summing would break that; rounding once per rate
  # preserves it.
  def test_printed_isv_equals_rate_times_printed_subtotal
    # Three lines of 33.37: each 15% is 5.0055, which would round to 5.01 per
    # line and sum to 15.03. The base sums to 100.11, whose 15% is 15.0165 and
    # rounds to 15.02.
    s = summary(line(:gravado_15, unit_price: "33.37"),
                line(:gravado_15, unit_price: "33.37"),
                line(:gravado_15, unit_price: "33.37"))

    assert_equal hnl("100.11"), s.subtotal
    assert_equal hnl("15.02"), s.isv_total

    expected = (s.subtotal * dec("0.15")).round_statutory

    assert_equal expected, s.isv_total
  end

  def test_quantities_multiply
    s = summary(line(:gravado_15, quantity: 7, unit_price: "12.50"))

    assert_equal hnl("87.50"), s.subtotal
    assert_equal hnl("13.13"), s.isv_total # 13.125 rounds up at the tie
  end

  def test_fractional_quantities
    s = summary(line(:gravado_15, quantity: "2.5", unit_price: "10.00"))

    assert_equal hnl("25.00"), s.subtotal
  end

  def test_empty_invoice_totals_to_zero
    s = summary

    assert_equal hnl(0), s.subtotal
    assert_equal hnl(0), s.isv_total
    assert_empty s.present_buckets
  end

  # Art. 11 num. 3 — where an invoice carries both exempt and taxed sales, only
  # the taxed sales support crédito fiscal.
  def test_credito_fiscal_base_counts_only_taxed_supplies
    s = summary(line(:gravado_15), line(:gravado_18), line(:exento), line(:exonerado))

    assert_predicate s, :mixed_supply?
    assert_equal hnl("200.00"), s.credito_fiscal_base
  end

  def test_wholly_taxed_invoice_is_not_mixed_supply
    refute_predicate summary(line(:gravado_15), line(:gravado_18)), :mixed_supply?
  end

  def test_wholly_untaxed_invoice_is_not_mixed_supply
    s = summary(line(:exento))

    refute_predicate s, :mixed_supply?
    assert_equal hnl(0), s.credito_fiscal_base
  end

  def test_unknown_treatment_is_refused
    assert_raises(Invoicehn::ValidationError) { line(:gravado_12) }
  end

  def test_treatments_cannot_be_invented_at_runtime
    assert_raises(NoMethodError) { Invoicehn::TaxTreatment.new(:gravado_25, dec("0.25"), "25%", 9) }
  end
end
