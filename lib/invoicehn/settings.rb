# frozen_string_literal: true

require "date"

module Invoicehn
  # Process-wide settings, set once at boot with Invoicehn.configure.
  #
  # Not to be confused with Invoicehn::Config, which is where the bundled JSON
  # store keeps its files.
  #
  # == The clock
  #
  # Every date this library defaults — the fecha de emisión (Art. 10 num. 7 /
  # Art. 11 num. 1 lit. c), the day an authorization is checked against its
  # fecha límite (Art. 62), the day of an annulment (Art. 41) — comes from
  # Invoicehn.today. The default is Date.today, which reads the *process* time
  # zone. A server running in UTC is six hours ahead of Honduras (UTC-6, no
  # daylight saving), so between 18:00 and midnight in Tegucigalpa it would
  # stamp tomorrow's date on the document and could even treat an
  # authorization as expired a few hours early.
  #
  # A Rails host should point the clock at its configured zone:
  #
  #   # config/application.rb: config.time_zone = "America/Tegucigalpa"
  #   Invoicehn.configure { |c| c.today = -> { Date.current } }
  class Settings
    DEFAULT_TODAY = -> { Date.today }

    attr_reader :today

    def initialize
      @today = DEFAULT_TODAY
    end

    # @param provider [#call] returns the current Date in Honduras.
    def today=(provider)
      unless provider.respond_to?(:call)
        raise ArgumentError, "today debe responder a #call (p. ej. -> { Date.current })"
      end

      @today = provider
    end
  end
end
