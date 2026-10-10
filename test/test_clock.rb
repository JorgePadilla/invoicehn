# frozen_string_literal: true

require "test_helper"

# Honduras is UTC-6 all year. A host whose process runs in UTC reads
# Date.today six hours early: from 18:00 in Tegucigalpa it is already
# "tomorrow", which would stamp the wrong fecha de emisión (Art. 11 num. 1
# lit. c) and expire an authorization before its fecha límite (Art. 62).
# Every default date therefore comes from one configurable clock.
class TestClock < Minitest::Test
  def teardown
    Invoicehn.reset_settings!
  end

  def root = File.expand_path("..", __dir__)

  # Structural, like test_no_float: nothing in lib/ may read the process date
  # directly. The only exception is the clock's own default.
  def test_no_direct_date_today_in_lib
    Dir.glob(File.join(root, "lib", "**", "*.rb")).each do |path|
      next if path.end_with?("lib/invoicehn/settings.rb")

      File.read(path).each_line.with_index(1) do |line, number|
        next if line.strip.start_with?("#")

        refute_match(/\bDate\.today\b/, line,
                     "#{path.delete_prefix(root)}:#{number} lee Date.today; use Invoicehn.today")
      end
    end
  end

  def test_defaults_to_the_process_date
    assert_equal Date.today, Invoicehn.today
  end

  def test_configured_clock_is_used
    Invoicehn.configure { |c| c.today = -> { Date.new(2026, 3, 15) } }

    assert_equal Date.new(2026, 3, 15), Invoicehn.today
  end

  def test_rejects_a_clock_that_is_not_callable
    assert_raises(ArgumentError) { Invoicehn.configure { |c| c.today = Date.new(2026, 1, 1) } }
  end

  # A Time or a DateTime would carry an hour and a zone into a field the law
  # defines as a date.
  def test_rejects_a_clock_that_returns_something_other_than_a_date
    Invoicehn.configure { |c| c.today = -> { Time.now } }

    assert_raises(Invoicehn::Error) { Invoicehn.today }
  end

  def test_invoice_issue_date_defaults_to_the_clock
    Invoicehn.configure { |c| c.today = -> { Date.new(2026, 3, 15) } }

    assert_equal Date.new(2026, 3, 15),
                 build_invoice(authorization: build_authorization(limit_date: Date.new(2026, 12, 31))).issue_date
  end

  # The fecha límite is judged against Honduran today, not the server's.
  def test_authorization_expiry_follows_the_clock
    auth = build_authorization(limit_date: Date.new(2026, 6, 30))

    Invoicehn.configure { |c| c.today = -> { Date.new(2026, 6, 30) } }

    refute_predicate auth, :expired?

    Invoicehn.configure { |c| c.today = -> { Date.new(2026, 7, 1) } }

    assert_predicate auth, :expired?
  end

  def test_issuance_stamps_the_clock_date
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      store.add_authorization(build_authorization(limit_date: Date.new(2026, 12, 31)))
      Invoicehn.configure { |c| c.today = -> { Date.new(2026, 3, 15) } }

      invoice = Invoicehn::Issuance.new(config: config, store: store)
                                   .issue(customer: Invoicehn::Customer::ConsumidorFinal.new,
                                          line_items: [build_line])

      assert_equal Date.new(2026, 3, 15), invoice.issue_date
    end
  end
end
