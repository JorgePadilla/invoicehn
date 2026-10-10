# frozen_string_literal: true

require "test_helper"
require "invoicehn/test_support/contracts"
require "invoicehn/test_support/memory"
require "minitest/mock"

# The contract modules a host includes, run against the two implementations
# the gem ships: the JSON files and the in-memory reference adapters.
module ContractFixtures
  def auth(type)
    Invoicehn::Authorization.new(cai: "CAI-#{type}", range_start: "000-001-#{type}-00000001",
                                 range_end: "000-001-#{type}-00000100", limit_date: Date.today + 90)
  end
end

class TestJsonContracts < Minitest::Test
  include ContractFixtures
  include Invoicehn::TestSupport::StoreContract
  include Invoicehn::TestSupport::SequenceContract
  include Invoicehn::TestSupport::LedgerContract
  include Invoicehn::TestSupport::IssuanceContract

  def setup
    @dir = Dir.mktmpdir("invoicehn-contract")
    @config = Invoicehn::Config.new(home: @dir)
    @store = Invoicehn::Storage::JsonStore.new(@config)
    @store.save_issuer(build_issuer)
    %w[01 06].each { |type| @store.add_authorization(auth(type)) }
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def contract_store = @store
  def contract_sequence = (@contract_sequence ||= Invoicehn::Sequence.new(@config))
  def contract_ledger = (@contract_ledger ||= Invoicehn::Ledger::JsonlLedger.new(@config))
end

class TestMemoryContracts < Minitest::Test
  include ContractFixtures
  include Invoicehn::TestSupport::StoreContract
  include Invoicehn::TestSupport::SequenceContract
  include Invoicehn::TestSupport::LedgerContract
  include Invoicehn::TestSupport::IssuanceContract

  def contract_store
    @contract_store ||= Invoicehn::TestSupport::MemoryStore.new(issuer: build_issuer,
                                                                authorizations: [auth("01"), auth("06")])
  end

  def contract_sequence = (@contract_sequence ||= Invoicehn::TestSupport::MemorySequence.new)
  def contract_ledger = (@contract_ledger ||= Invoicehn::TestSupport::MemoryLedger.new)
end

# A host that injects all three collaborators never touches the file system.
class TestIssuanceWithoutFileSystem < Minitest::Test
  include ContractFixtures

  def test_injected_issuance_creates_no_directory
    Dir.mktmpdir("invoicehn-nofs") do |dir|
      home = File.join(dir, "no-existe")
      previous = ENV.to_h.slice("HOME", "INVOICEHN_HOME")
      ENV["HOME"] = home
      ENV.delete("INVOICEHN_HOME")
      begin
        store = Invoicehn::TestSupport::MemoryStore.new(issuer: build_issuer, authorizations: [auth("01")])
        # Not even the paths are computed: Config is never built.
        Invoicehn::Config.stub(:new, ->(*) { flunk "Issuance construyó un Config" }) do
          issuance = Invoicehn::Issuance.new(store: store, sequence: Invoicehn::TestSupport::MemorySequence.new,
                                             ledger: Invoicehn::TestSupport::MemoryLedger.new)
          issuance.issue(customer: Invoicehn::Customer::ConsumidorFinal.new, line_items: [build_line])
          issuance.health
        end

        refute Dir.exist?(home)
        assert_empty Dir.children(dir)
      ensure
        previous.each { |k, v| ENV[k] = v }
        ENV.delete("INVOICEHN_HOME") unless previous.key?("INVOICEHN_HOME")
      end
    end
  end
end
