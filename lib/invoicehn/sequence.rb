# frozen_string_literal: true

require "json"
require "fileutils"

module Invoicehn
  # Allocates correlativos, gap-free and without reuse.
  #
  # Art. 10 num. 7 lit. d: "Los ocho dígitos restantes, corresponderán a la
  # numeración correlativa de la Factura que deberá iniciarse en uno
  # (00000001)."
  #
  # Counters are keyed by the (establecimiento, punto de emisión, tipo de
  # documento) triple — the "identificador del documento" — because SAR
  # authorizes a range per emission point and document type (Art. 59), and each
  # such series advances independently.
  #
  # Allocation and persistence happen inside one exclusive file lock, so two
  # processes issuing at the same moment cannot land on the same number or skip
  # one.
  class Sequence
    attr_reader :config

    def initialize(config = Config.new)
      @config = config
    end

    # The number that would be issued next, without consuming it.
    def peek(identifier)
      with_lock(shared: true) do
        counters = read_counters
        build(identifier, (counters[identifier] || 0) + 1)
      end
    end

    def issued_count(identifier)
      with_lock(shared: true) { read_counters[identifier] || 0 }
    end

    # Consumes and returns the next correlativo. The block, if given, runs
    # inside the lock and receives the allocated number — pass the persistence
    # step in so allocation and recording are one atomic step and a crash cannot
    # burn a number without producing a document.
    def allocate(identifier)
      with_lock do
        counters = read_counters
        correlative = build(identifier, (counters[identifier] || 0) + 1)

        result = block_given? ? yield(correlative) : correlative

        counters[identifier] = correlative.sequence
        write_counters(counters)

        result
      end
    end

    # Aligns the counter with an authorization that does not start at 1 — a
    # successor range continuing the numbering, for instance.
    def align_to(authorization)
      with_lock do
        counters = read_counters
        current = counters[authorization.identifier] || 0
        floor = authorization.range_start.sequence - 1

        if current < floor
          counters[authorization.identifier] = floor
          write_counters(counters)
        end

        counters[authorization.identifier]
      end
    end

    def counters = with_lock(shared: true) { read_counters }

    private

    def build(identifier, sequence)
      establishment, emission_point, document_type = identifier.to_s.split("-")

      unless establishment && emission_point && document_type
        raise ValidationError,
              "identificador inválido: #{identifier.inspect} (se espera NNN-NNN-NN)"
      end

      Correlative.new(establishment: establishment, emission_point: emission_point,
                      document_type: document_type, sequence: sequence)
    end

    def read_counters
      path = @config.sequences_path
      return {} unless File.exist?(path)

      content = File.read(path)
      return {} if content.strip.empty?

      JSON.parse(content)
    rescue JSON::ParserError => e
      raise Error, "contador de correlativos dañado en #{path}: #{e.message}"
    end

    def write_counters(counters)
      path = @config.sequences_path
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp#{Process.pid}"
      File.write(tmp, "#{JSON.pretty_generate(counters)}\n")
      File.rename(tmp, path)
    end

    # flock on a dedicated lock file. The lock file is never truncated, so
    # holding it costs nothing and it survives as long as the data directory.
    def with_lock(shared: false)
      FileUtils.mkdir_p(File.dirname(@config.lock_path))

      File.open(@config.lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(shared ? File::LOCK_SH : File::LOCK_EX)
        begin
          yield
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end
  end
end
