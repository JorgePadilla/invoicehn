# frozen_string_literal: true

require "test_helper"

# Art. 11 num. 1 lit. l) and num. 2 lit. j), added by Acuerdo 725-2018 —
# "Discriminación de los descuentos y rebajas otorgados".
#
# These cases assert the base arithmetic, not merely that a discount is
# displayed. Ley del ISV Art. 3: "No forman parte de la base gravable los
# descuentos efectivos que consten en la factura o documento equivalente,
# siempre que resulten normales según la costumbre comercial." Displaying a
# discount while taxing the gross value would overcharge the customer tax.
class TestArt11Discounts < Minitest::Test
  def line(discount: nil, treatment: :gravado_15, quantity: 1, unit_price: "100.00")
    Invoicehn::LineItem.new(
      description: "Artículo",
      quantity: quantity,
      unit_price: hnl(unit_price),
      discount: discount && hnl(discount),
      treatment: treatment
    )
  end

  def test_discount_reduces_the_taxable_base
    item = line(discount: "20.00")

    assert_equal hnl("100.00"), item.gross
    assert_equal hnl("20.00"), item.discount
    assert_equal hnl("80.00"), item.taxable_base
  end

  # The point of the test: 15% of 80, not 15% of 100.
  def test_isv_is_computed_on_the_discounted_base
    s = Invoicehn::TaxSummary.new([line(discount: "20.00")])

    assert_equal hnl("80.00"), s.subtotal
    assert_equal hnl("12.00"), s.isv_total
    refute_equal hnl("15.00"), s.isv_total
  end

  def test_discount_is_tracked_separately_for_display
    s = Invoicehn::TaxSummary.new([line(discount: "20.00")])
    bucket = s.bucket_for(:gravado_15)

    assert_equal hnl("100.00"), bucket.gross
    assert_equal hnl("20.00"), bucket.discount
    assert_equal hnl("80.00"), bucket.base
    assert_equal hnl("20.00"), s.discount
  end

  def test_discounts_are_attributed_to_their_own_rate
    s = Invoicehn::TaxSummary.new([
                                    line(discount: "20.00", treatment: :gravado_15),
                                    line(discount: "50.00", treatment: :gravado_18)
                                  ])

    assert_equal hnl("20.00"), s.bucket_for(:gravado_15).discount
    assert_equal hnl("50.00"), s.bucket_for(:gravado_18).discount
    assert_equal hnl("12.00"), s.bucket_for(:gravado_15).isv  # 15% of 80
    assert_equal hnl("9.00"),  s.bucket_for(:gravado_18).isv  # 18% of 50
    assert_equal hnl("70.00"), s.discount
  end

  def test_discount_on_an_untaxed_line_reduces_the_subtotal_only
    s = Invoicehn::TaxSummary.new([line(discount: "20.00", treatment: :exento)])

    assert_equal hnl("80.00"), s.subtotal
    assert_equal hnl("0.00"), s.isv_total
  end

  def test_discount_applies_after_quantity
    item = line(quantity: 4, unit_price: "25.00", discount: "10.00")

    assert_equal hnl("100.00"), item.gross
    assert_equal hnl("90.00"), item.taxable_base
  end

  def test_absent_discount_is_zero_not_nil
    item = line

    assert_equal hnl("0.00"), item.discount
    refute_predicate item, :discounted?
    assert_equal item.gross, item.taxable_base
  end

  def test_full_discount_leaves_no_base
    s = Invoicehn::TaxSummary.new([line(discount: "100.00")])

    assert_equal hnl("0.00"), s.subtotal
    assert_equal hnl("0.00"), s.isv_total
  end

  def test_discount_exceeding_the_line_is_refused
    error = assert_raises(Invoicehn::ValidationError) { line(discount: "100.01") }
    assert_match(/excede el valor de la línea/, error.message)
  end

  def test_negative_discount_is_refused
    assert_raises(Invoicehn::ValidationError) { line(discount: "-5.00") }
  end

  def test_discount_currency_must_match
    assert_raises(Invoicehn::CurrencyMismatch) do
      Invoicehn::LineItem.new(
        description: "Artículo", quantity: 1, unit_price: hnl("100.00"),
        discount: usd("10.00"), treatment: :gravado_15
      )
    end
  end
end
