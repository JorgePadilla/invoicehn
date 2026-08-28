# frozen_string_literal: true

module Invoicehn
  module CLI
    # Terminal reports: authorization status, the document list, and the
    # pre-flight check.
    class Reporter
      def initialize(issuance, shell = Thor::Base.shell.new)
        @issuance = issuance
        @shell = shell
      end

      def authorizations
        list = @issuance.store.authorizations

        return say(Locale.t("auth.none"), :yellow) if list.empty?

        say Locale.t("auth.list_header"), :bold
        rows = list.map do |auth|
          issued = @issuance.sequence.issued_count(auth.identifier)
          remaining = [auth.range_end.sequence - [issued, auth.range_start.sequence - 1].max, 0].max
          status = auth.expired? ? "VENCIDA" : "vigente"

          [auth.cai, auth.range_label, auth.limit_date.to_s, status, remaining.to_s]
        end

        table(%w[CAI Rango Vence Estado Disponibles], rows)
      end

      def documents(from: nil, to: nil)
        invoices = @issuance.store.all(from: from, to: to)

        return say("No hay facturas emitidas en ese período.", :yellow) if invoices.empty?

        rows = invoices.map do |inv|
          [
            inv.correlative.to_s,
            inv.issue_date.to_s,
            truncate(inv.customer.to_s, 28),
            inv.total.to_s,
            inv.annulled? ? "ANULADA" : ""
          ]
        end

        table(%w[Correlativo Fecha Cliente Total Estado], rows)
        say "\n#{invoices.size} documento(s). " \
            "Total emitido: #{sum_of(invoices.reject(&:annulled?))}"
      end

      def health(identifier: "000-001-01")
        status = @issuance.health(identifier: identifier)

        say Locale.t("check.title"), :bold
        say ""

        if !status[:issuer_configured]
          say "  ✗ #{Locale.t("check.issuer_absent")}", :red
        elsif !status[:issuer_complete]
          say "  ✗ #{Locale.t("check.issuer_missing", fields: status[:issuer_missing].join("; "))}", :red
        else
          say "  ✓ #{Locale.t("check.issuer_ok")}", :green
        end

        if status[:active_authorization]
          auth = status[:active_authorization]
          say "  ✓ #{Locale.t("check.auth_active", cai: auth.cai)}", :green
          say "    #{Locale.t("check.next", correlative: status[:next_correlative])}"
          say "    #{Locale.t("check.remaining", count: status[:remaining])}",
              status[:remaining] < 25 ? :yellow : nil
          say "    #{Locale.t("check.days", days: status[:days_remaining])}",
              status[:days_remaining] < 30 ? :yellow : nil
        else
          say "  ✗ #{Locale.t("check.auth_absent", identifier: identifier)}", :red
        end

        # Art. 42 — expired authorizations holding unused documents must be
        # reported to SAR within the first 10 business days of the next month.
        if status[:lapsed_with_unused].any?
          say ""
          say Locale.t("check.lapsed", count: status[:lapsed_with_unused].size), :yellow
        end

        say ""
        if status[:ready]
          say Locale.t("check.ready"), :green
        else
          say Locale.t("check.not_ready"), :red
        end
      end

      private

      def say(message, color = nil) = @shell.say(message, color)

      def sum_of(invoices)
        return Money.zero if invoices.empty?

        Money.sum(invoices.map(&:total), currency: invoices.first.currency)
      end

      def truncate(text, limit)
        text.length > limit ? "#{text[0, limit - 1]}…" : text
      end

      # Rows are right-stripped because Thor's #say omits the trailing newline
      # when a line ends in whitespace, which would run padded rows together.
      def table(headers, rows)
        widths = headers.each_with_index.map do |header, i|
          [header.length, *rows.map { |r| r[i].to_s.length }].max
        end

        row_line = lambda do |cells|
          widths.each_with_index.map { |w, i| cells[i].to_s.ljust(w) }.join("  ").rstrip
        end

        say row_line.call(headers), :bold
        say widths.map { |w| "─" * w }.join("  ")
        rows.each { |row| say row_line.call(row) }
      end
    end
  end
end
