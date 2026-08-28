# frozen_string_literal: true

require "test_helper"

# Art. 62 — "La Administración Tributaria autorizará la impresión y vigencia de
# los Comprobantes Fiscales ... por un plazo máximo de un (1) año. Los
# Comprobantes Fiscales ... perderán su validez y no podrán ser utilizados
# cuando se haya vencido el plazo de tiempo autorizado."
class TestArt62Expiry < Minitest::Test
  def auth_expiring(date) = build_authorization(limit_date: date)

  def test_not_expired_before_the_limit_date
    auth = auth_expiring(Date.new(2026, 12, 31))

    refute auth.expired?(Date.new(2026, 12, 30))
  end

  # The fecha límite is the last day on which a document may be issued, so a
  # document issued on that date itself is still valid.
  def test_the_limit_date_itself_is_still_usable
    auth = auth_expiring(Date.new(2026, 12, 31))

    refute auth.expired?(Date.new(2026, 12, 31))
    assert auth.assert_usable!("000-001-01-00000001", on: Date.new(2026, 12, 31))
  end

  def test_expired_the_day_after
    auth = auth_expiring(Date.new(2026, 12, 31))

    assert auth.expired?(Date.new(2027, 1, 1))
  end

  def test_issuing_past_the_limit_date_is_refused
    auth = auth_expiring(Date.new(2026, 12, 31))

    error = assert_raises(Invoicehn::AuthorizationExpired) do
      auth.assert_usable!("000-001-01-00000001", on: Date.new(2027, 1, 1))
    end
    assert_match(/fecha límite de emisión/, error.message)
  end

  def test_an_invoice_dated_after_expiry_is_not_compliant
    invoice = build_invoice(
      authorization: auth_expiring(Date.new(2026, 12, 31)),
      issue_date: Date.new(2027, 1, 1)
    )

    assert_violates "Art. 62", invoice
    refute_predicate invoice, :compliant?
    assert_raises(Invoicehn::ComplianceError) { invoice.validate! }
  end

  def test_an_invoice_dated_on_the_limit_date_is_compliant
    invoice = build_invoice(
      authorization: auth_expiring(Date.new(2026, 12, 31)),
      issue_date: Date.new(2026, 12, 31)
    )

    refute_violates "Art. 62", invoice
    assert_predicate invoice, :compliant?
  end

  def test_days_remaining_counts_down_to_the_limit
    auth = auth_expiring(Date.new(2026, 12, 31))

    assert_equal 30, auth.days_remaining(Date.new(2026, 12, 1))
    assert_equal 0, auth.days_remaining(Date.new(2026, 12, 31))
    assert_equal(-1, auth.days_remaining(Date.new(2027, 1, 1)))
  end
end
