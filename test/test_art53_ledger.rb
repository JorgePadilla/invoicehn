# frozen_string_literal: true

require "test_helper"

# Art. 53 num. 1 — "El sistema de facturación debe estar integrado al menos a un
# sistema contable o de inventarios."
# Art. 53 num. 3 — "El software debe garantizar la persistencia y disponibilidad
# inmediata de la información actual e histórica de las transacciones."
# Art. 53 num. 5 — "El Sistema debe tener la capacidad de generación de archivos
# tipo texto para su almacenamiento y traslado hacia la Administración
# Tributaria."
class TestArt53Ledger < Minitest::Test
  def with_issuance
    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      store.add_authorization(build_authorization)
      ledger = Invoicehn::Ledger::JsonlLedger.new(config)
      yield Invoicehn::Issuance.new(config: config, store: store, ledger: ledger), store, ledger
    end
  end

  def consumer = Invoicehn::Customer::ConsumidorFinal.new

  def test_every_issuance_is_posted_to_the_ledger
    with_issuance do |issuance, _store, ledger|
      3.times { issuance.issue(customer: consumer, line_items: [build_line]) }

      entries = ledger.entries

      assert_equal 3, entries.size
      assert(entries.all? { |e| e["event"] == "emision" })
      assert_equal(%w[000-001-01-00000001 000-001-01-00000002 000-001-01-00000003],
                   entries.map { |e| e["correlative"] })
    end
  end

  def test_annulments_are_posted_too
    with_issuance do |issuance, _store, ledger|
      invoice = issuance.issue(customer: consumer, line_items: [build_line])
      issuance.annul(invoice.correlative, reason: "Error")

      events = ledger.entries.map { |e| e["event"] }

      assert_equal %w[emision anulacion], events
    end
  end

  # The ledger is a record, not a working file: entries accumulate and are never
  # rewritten, so the history stays intact.
  def test_the_ledger_is_append_only
    with_issuance do |issuance, _store, ledger|
      issuance.issue(customer: consumer, line_items: [build_line])
      first = File.read(ledger.path)

      issuance.issue(customer: consumer, line_items: [build_line])
      second = File.read(ledger.path)

      assert second.start_with?(first), "una entrada anterior fue reescrita"
      assert_equal 2, second.lines.size
    end
  end

  # Art. 53 num. 5 — plain text, one JSON object per line, readable without this
  # library.
  def test_entries_are_plain_text_lines
    with_issuance do |issuance, _store, ledger|
      issuance.issue(customer: consumer, line_items: [build_line])

      line = File.readlines(ledger.path).first

      assert_equal 1, File.readlines(ledger.path).size
      parsed = JSON.parse(line)
      assert_equal "000-001-01-00000001", parsed["correlative"]
    end
  end

  def test_entries_carry_the_figures_an_audit_needs
    with_issuance do |issuance, _store, ledger|
      issuance.issue(customer: consumer,
                     line_items: [build_line(unit_price: hnl("1000.00"), discount: hnl("100.00"))])

      entry = ledger.entries.first

      assert_equal "900.00", entry["subtotal"]
      assert_equal "100.00", entry["discount"]
      assert_equal "135.00", entry["isv"]
      assert_equal "1035.00", entry["total"]
      assert_equal build_authorization.cai, entry["cai"]
    end
  end

  # Money crosses the ledger as a string, so no JSON parser downstream can turn
  # a fiscal figure into a Float.
  def test_amounts_are_serialised_as_strings
    with_issuance do |issuance, _store, ledger|
      issuance.issue(customer: consumer, line_items: [build_line])

      entry = ledger.entries.first

      %w[subtotal discount isv total].each do |field|
        assert_kind_of String, entry[field], "#{field} debería ser texto, no un número"
      end
    end
  end

  def test_entries_can_be_filtered_by_date
    with_issuance do |issuance, _store, ledger|
      issuance.issue(customer: consumer, line_items: [build_line])

      assert_equal 1, ledger.entries(from: Date.today, to: Date.today).size
      assert_empty ledger.entries(from: Date.today + 1)
    end
  end

  # Art. 53 num. 1 is satisfied by an interface, so real accounting software can
  # replace the built-in book.
  def test_a_custom_ledger_can_be_substituted
    recorder = Class.new(Invoicehn::Ledger) do
      attr_reader :posted

      def initialize
        super
        @posted = []
      end

      def record(invoice, event: :emision)
        @posted << [invoice.correlative.to_s, event]
        invoice
      end

      def entries(**) = @posted
    end.new

    with_temp_home do |dir|
      config = Invoicehn::Config.new(home: dir)
      config.ensure_home!
      store = Invoicehn::Storage::JsonStore.new(config)
      store.save_issuer(build_issuer)
      store.add_authorization(build_authorization)

      Invoicehn::Issuance.new(config: config, store: store, ledger: recorder)
                         .issue(customer: consumer, line_items: [build_line])

      assert_equal [["000-001-01-00000001", :emision]], recorder.posted
    end
  end

  # Art. 53 num. 3 — historical information stays immediately available.
  def test_documents_are_retrievable_in_chronological_order
    with_issuance do |issuance, store|
      3.times { issuance.issue(customer: consumer, line_items: [build_line]) }

      assert_equal(%w[000-001-01-00000001 000-001-01-00000002 000-001-01-00000003],
                   store.all.map { |i| i.correlative.to_s })
    end
  end
end
