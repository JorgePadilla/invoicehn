# frozen_string_literal: true

require "test_helper"

# Ley del ISV Art. 9 makes charging the customer a mis-rounded amount an
# offence — "se considerará como hurto". Binary floating point cannot represent
# a centavo exactly, so Float is banned from every path a fiscal figure travels.
# This test enforces that structurally, not by convention.
class TestNoFloat < Minitest::Test
  MONEY_PATHS = %w[
    lib/invoicehn/money.rb
    lib/invoicehn/tax_treatment.rb
    lib/invoicehn/tax_summary.rb
    lib/invoicehn/line_item.rb
    lib/invoicehn/exchange_rate.rb
    lib/invoicehn/spanish_numerals.rb
  ].freeze

  def root = File.expand_path("..", __dir__)

  # Float appears in these files only inside a `when Float` guard or the error
  # message that rejects it, never in arithmetic.
  def test_no_float_arithmetic_in_the_money_path
    MONEY_PATHS.each do |relative|
      source = File.read(File.join(root, relative))

      source.each_line.with_index(1) do |line, number|
        next if line.strip.start_with?("#")
        next if line.include?("when Float")
        next if line.include?("Float no está permitido")

        refute_match(/\bFloat\b/, line,
                     "#{relative}:#{number} menciona Float fuera de su rechazo: #{line.strip}")
        refute_match(/\.to_f\b/, line,
                     "#{relative}:#{number} usa to_f: #{line.strip}")
      end
    end
  end

  def test_money_refuses_float_input
    assert_raises(Invoicehn::ValidationError) { Invoicehn::Money.new(10.5) }
    assert_raises(Invoicehn::ValidationError) { Invoicehn::Money.new(0.1) }
  end

  def test_line_item_refuses_float_quantity_and_price
    assert_raises(Invoicehn::ValidationError) { build_line(quantity: 2.5) }
    assert_raises(Invoicehn::ValidationError) { build_line(unit_price: 10.5) }
  end

  def test_exchange_rate_refuses_float
    assert_raises(Invoicehn::ValidationError) do
      Invoicehn::ExchangeRate.new(rate: 24.65, date: Date.today)
    end
  end

  # The classic demonstration: 0.1 + 0.2 != 0.3 in binary floating point.
  def test_amounts_that_a_float_would_get_wrong
    total = hnl("0.10") + hnl("0.20")

    assert_equal dec("0.30"), total.amount
    assert_equal "L 0.30", total.to_s
  end

  def test_repeated_addition_does_not_drift
    total = Invoicehn::Money.sum(Array.new(100) { hnl("0.01") })

    assert_equal dec("1.00"), total.amount
  end

  # Serialised amounts are strings, so a JSON reader downstream cannot parse a
  # fiscal figure into a Float.
  def test_serialised_amounts_are_strings
    assert_equal({ "amount" => "1234.56", "currency" => "HNL" }, hnl("1234.56").to_h)
    assert_equal "900.00", hnl("900").to_fixed
    assert_equal "0.00", hnl(0).to_fixed
  end

  # JSON input arrives with Float numbers; the builder must convert through the
  # decimal text form, not the binary value.
  def test_json_floats_are_converted_through_their_text_form
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      store.add_authorization(build_authorization)

      builder = Invoicehn::CLI::Builder.new(Invoicehn::Issuance.new(config: config, store: store))
      invoice = builder.from_hash({
                                    "customer" => { "kind" => "consumidor_final" },
                                    "items" => [{ "description" => "Artículo", "quantity" => 3,
                                                  "unit_price" => 0.1, "treatment" => "exento" }]
                                  })

      assert_equal dec("0.30"), invoice.total.amount
    end
  end
end
