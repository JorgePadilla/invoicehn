# frozen_string_literal: true

require "tty-prompt"

module Invoicehn
  module CLI
    # The interactive path: `invoicehn setup`, `invoicehn auth add` and
    # `invoicehn new`.
    #
    # The wizard collects input and hands it to the same Issuance service the
    # scriptable commands use, so it cannot produce a document the compliance
    # rules would not accept. Nothing is written until the operator confirms —
    # an abandoned wizard consumes no correlativo.
    class Wizard
      def initialize(issuance, shell = nil, prompt: nil)
        @issuance = issuance
        @shell = shell
        @prompt = prompt || TTY::Prompt.new(interrupt: :exit)
      end

      # Art. 10 num. 1 — datos de identificación del emisor.
      def setup
        header Locale.t("setup.title")
        say Locale.t("setup.intro")
        say ""

        existing = @issuance.store.issuer

        issuer = Issuer.new(
          rtn: ask_rtn(Locale.t("setup.rtn"), default: existing&.rtn&.to_s),
          legal_name: ask(Locale.t("setup.legal_name"), default: existing&.legal_name),
          trade_name: ask(Locale.t("setup.trade_name"), default: existing&.trade_name),
          headquarters_address: ask(Locale.t("setup.headquarters"),
                                    default: existing&.headquarters_address),
          branch_address: @prompt.ask(Locale.t("setup.branch"),
                                      default: existing&.branch? ? existing.branch_address : nil),
          phone: ask(Locale.t("setup.phone"), default: existing&.phone),
          email: ask(Locale.t("setup.email"), default: existing&.email)
        )

        issuer.validate!
        @issuance.store.save_issuer(issuer)
        say Locale.t("setup.saved", path: @issuance.store.config.issuer_path), :green
        issuer
      end

      # Arts. 59-61 — the values SAR grants, transcribed from the authorization
      # document. Nothing here is generated.
      def add_authorization
        header Locale.t("auth.title")
        say Locale.t("auth.intro")
        say ""

        cai = ask(Locale.t("auth.cai"))
        establishment = ask(Locale.t("auth.establishment"), default: "000")
        emission_point = ask(Locale.t("auth.emission_point"), default: "001")

        range_start = Correlative.new(establishment: establishment, emission_point: emission_point,
                                      document_type: Correlative::FACTURA,
                                      sequence: ask(Locale.t("auth.range_start"), default: "1").to_i)
        range_end = range_start.with_sequence(ask(Locale.t("auth.range_end")).to_i)

        authorization = Authorization.new(
          cai: cai, range_start: range_start, range_end: range_end,
          limit_date: ask(Locale.t("auth.limit_date"))
        )

        @issuance.store.add_authorization(authorization)
        @issuance.sequence.align_to(authorization)

        say Locale.t("auth.saved", range: authorization.range_label), :green
        say "Documentos autorizados: #{authorization.capacity}"
        authorization
      end

      def issue
        customer = ask_customer
        currency = @prompt.select(Locale.t("invoice.currency"), %w[HNL USD], default: "HNL")
        line_items = ask_line_items(currency)

        if line_items.empty?
          say Locale.t("invoice.cancelled"), :yellow
          return nil
        end

        exchange_rate = currency == "HNL" ? nil : ask_exchange_rate(currency)
        notes = @prompt.ask(Locale.t("invoice.notes"))

        preview = preview_invoice(customer, line_items, currency, exchange_rate, notes)
        say ""
        say preview

        unless @prompt.yes?(Locale.t("invoice.confirm"))
          say Locale.t("invoice.cancelled"), :yellow
          return nil
        end

        invoice = @issuance.issue(customer: customer, line_items: line_items,
                                  currency: currency, exchange_rate: exchange_rate, notes: notes)

        say ""
        say Locale.t("invoice.issued", correlative: invoice.correlative), :green
        say ""
        say Renderers::Text.new(invoice).render
        invoice
      end

      private

      def say(message, color = nil)
        color ? @prompt.say(message, color: color) : @prompt.say(message)
      end

      def header(text)
        say ""
        say text
        say "─" * text.length
      end

      def ask(question, default: nil)
        options = { required: true }
        options[:default] = default if default && !default.to_s.empty?
        @prompt.ask(question, **options)
      end

      def ask_rtn(question, default: nil)
        loop do
          value = ask(question, default: default)
          return value if Rtn.valid?(value)

          say "RTN inválido: se esperan 14 dígitos.", :red
        end
      end

      # Art. 11 distinguishes three cases, and which fields are mandatory
      # depends on which one applies.
      def ask_customer
        kinds = {
          Locale.t("invoice.kind_consumidor_final") => :consumidor_final,
          Locale.t("invoice.kind_taxpayer") => :taxpayer,
          Locale.t("invoice.kind_exonerado") => :exonerado
        }

        case @prompt.select(Locale.t("invoice.customer_kind"), kinds)
        when :taxpayer
          Customer::Taxpayer.new(
            name: ask(Locale.t("invoice.customer_name")),
            rtn: ask_rtn(Locale.t("invoice.customer_rtn"))
          )
        when :exonerado
          Customer::Exonerado.new(
            name: ask(Locale.t("invoice.customer_name")),
            rtn: ask_rtn(Locale.t("invoice.customer_rtn")),
            purchase_order: @prompt.ask(Locale.t("invoice.purchase_order")),
            exoneration_registry: @prompt.ask(Locale.t("invoice.exoneration_registry")),
            sag_registry: @prompt.ask(Locale.t("invoice.sag_registry"))
          )
        else
          ask_consumidor_final
        end
      end

      # Art. 11 num. 2 — the client's data is only mandatory above L 10,000.00,
      # but it may always be recorded, so it is offered rather than forced.
      def ask_consumidor_final
        name = @prompt.ask(Locale.t("invoice.customer_name"))
        return Customer::ConsumidorFinal.new if name.nil? || name.strip.empty?

        Customer::ConsumidorFinal.new(
          name: name,
          identification_type: @prompt.ask(Locale.t("invoice.id_type"), default: "DNI"),
          identification_number: @prompt.ask(Locale.t("invoice.id_number"))
        )
      end

      def ask_line_items(currency)
        items = []

        loop do
          items << ask_line(currency)
          break unless @prompt.yes?(Locale.t("invoice.add_line"), default: false)
        end

        items
      end

      def ask_line(currency)
        treatments = TaxTreatment.all.to_h { |t| [t.label, t.key] }

        LineItem.new(
          description: ask(Locale.t("invoice.description")),
          quantity: BigDecimal(ask(Locale.t("invoice.quantity"), default: "1")),
          unit_price: Money.new(ask(Locale.t("invoice.unit_price")), currency),
          discount: Money.new(@prompt.ask(Locale.t("invoice.discount"), default: "0"), currency),
          treatment: @prompt.select(Locale.t("invoice.treatment"), treatments, default: 4)
        )
      rescue ArgumentError, ValidationError => e
        say "Dato inválido: #{e.message}", :red
        retry
      end

      # Art. 11, closing paragraph — the rate in force on the issue date.
      def ask_exchange_rate(currency)
        ExchangeRate.new(
          rate: ask(Locale.t("invoice.exchange_rate")),
          date: Date.today,
          currency: currency,
          source: @prompt.ask(Locale.t("invoice.exchange_source"),
                              default: ExchangeRate::DEFAULT_SOURCE)
        )
      end

      # Rendered against the number that *would* be allocated, without consuming
      # it — so an operator who declines has not burned a correlativo.
      def preview_invoice(customer, line_items, currency, exchange_rate, notes)
        identifier = "000-001-01"
        correlative = @issuance.sequence.peek(identifier)
        authorization = @issuance.store.active_authorization(
          identifier, next_sequence: correlative.sequence
        )

        raise NoAuthorization, "no hay autorización vigente para #{identifier}" if authorization.nil?

        invoice = Invoice.new(
          correlative: correlative, issuer: @issuance.store.issuer, customer: customer,
          authorization: authorization, line_items: line_items, currency: currency,
          exchange_rate: exchange_rate, notes: notes
        )

        Renderers::Text.new(invoice).render
      end
    end
  end
end
