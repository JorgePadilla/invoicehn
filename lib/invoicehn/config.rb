# frozen_string_literal: true

require "fileutils"

module Invoicehn
  # Where the library keeps the issuer profile, the authorizations, the
  # correlative counters and the issued documents.
  #
  # Art. 43 obliges the operator to keep fiscal documents ordered and
  # chronological for the Código Tributario prescription period, and Art. 53
  # num. 3 requires "la persistencia y disponibilidad inmediata de la
  # información actual e histórica". A directory of plain JSON files satisfies
  # both and stays readable without this library — which matters for records
  # that must outlive the software that wrote them.
  class Config
    DEFAULT_DIRNAME = ".invoicehn"
    ENV_VAR = "INVOICEHN_HOME"

    attr_reader :home

    def initialize(home: nil)
      @home = File.expand_path(home || ENV[ENV_VAR] || File.join(Dir.home, DEFAULT_DIRNAME))
    end

    def issuer_path = File.join(@home, "issuer.json")
    def authorizations_path = File.join(@home, "authorizations.json")
    def sequences_path     = File.join(@home, "sequences.json")
    def settings_path      = File.join(@home, "settings.json")
    def documents_dir      = File.join(@home, "documentos")
    def ledger_path        = File.join(@home, "ledger.jsonl")
    def lock_path          = File.join(@home, "sequence.lock")

    # Issued documents are filed by year and month so the directory stays
    # navigable and mirrors the chronological order Art. 43 asks for.
    def document_path(correlative, issue_date)
      dir = File.join(documents_dir, format("%04d", issue_date.year), format("%02d", issue_date.month))
      File.join(dir, "#{correlative}.json")
    end

    def ensure_home!
      FileUtils.mkdir_p(@home)
      FileUtils.mkdir_p(documents_dir)
      @home
    end

    def initialized? = File.exist?(issuer_path)

    def to_s = @home
  end
end
