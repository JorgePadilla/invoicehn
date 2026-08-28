# frozen_string_literal: true

require "thor"
require "json"

module Invoicehn
  module CLI
    # `invoicehn <command>`.
    #
    # Subcommands are scriptable; `invoicehn new` opens the interactive wizard.
    # Both drive the same Invoicehn::Issuance service, so neither can produce a
    # document the other could not.
    class Main < Thor
      class_option :lang, type: :string, aliases: "-l",
                          desc: "Idioma de la interfaz / interface language (es, en)"
      class_option :"data-dir", type: :string,
                                desc: "Directorio de datos (por defecto ~/.invoicehn)"

      def self.exit_on_failure? = true

      desc "setup", "Configura los datos del emisor (Art. 10 num. 1)"
      method_option :rtn, type: :string
      method_option :"legal-name", type: :string
      method_option :"trade-name", type: :string
      method_option :address, type: :string, desc: "Dirección de la casa matriz"
      method_option :branch, type: :string, desc: "Dirección del establecimiento"
      method_option :phone, type: :string
      method_option :email, type: :string
      def setup
        prepare

        # Every Art. 10 num. 1 field supplied on the command line means the
        # profile can be set up unattended; otherwise the wizard asks.
        required = [options[:rtn], options[:"legal-name"], options[:"trade-name"],
                    options[:address], options[:phone], options[:email]]

        if required.all?
          issuer = Issuer.new(
            rtn: options[:rtn], legal_name: options[:"legal-name"],
            trade_name: options[:"trade-name"], headquarters_address: options[:address],
            branch_address: options[:branch], phone: options[:phone], email: options[:email]
          ).validate!

          issuance.store.save_issuer(issuer)
          say Locale.t("setup.saved", path: config.issuer_path), :green
        else
          Wizard.new(issuance, shell).setup
        end
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "auth SUBCOMANDO", "Gestiona las autorizaciones del SAR (CAI, rango, fecha límite)"
      subcommand "auth", Class.new(Thor) {
        class_option :"data-dir", type: :string
        def self.exit_on_failure? = true

        desc "add", "Registra un CAI, su rango autorizado y su fecha límite"
        method_option :cai, type: :string
        method_option :from, type: :string, desc: "Correlativo inicial (NNN-NNN-NN-NNNNNNNN)"
        method_option :to, type: :string, desc: "Correlativo final"
        method_option :limit, type: :string, desc: "Fecha límite de emisión (AAAA-MM-DD)"
        def add
          cli = Main.new([], options)
          if options[:cai] && options[:from] && options[:to] && options[:limit]
            auth = Authorization.new(cai: options[:cai], range_start: options[:from],
                                     range_end: options[:to], limit_date: options[:limit])
            cli.send(:issuance).store.add_authorization(auth)
            cli.send(:issuance).sequence.align_to(auth)
            say Locale.t("auth.saved", range: auth.range_label)
          else
            Wizard.new(cli.send(:issuance), shell).add_authorization
          end
        rescue Invoicehn::Error => e
          warn "Error: #{e.message}"
          exit 1
        end

        desc "list", "Muestra las autorizaciones registradas y su vigencia"
        def list
          cli = Main.new([], options)
          Reporter.new(cli.send(:issuance), shell).authorizations
        end
      }

      desc "new", "Emite una factura con el asistente interactivo"
      def new
        prepare
        Wizard.new(issuance, shell).issue
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "issue", "Emite una factura desde un archivo JSON"
      method_option :file, type: :string, required: true, aliases: "-f",
                           desc: "Archivo JSON con el cliente y las líneas de detalle"
      method_option :identifier, type: :string, default: "000-001-01"
      method_option :print, type: :boolean, default: true, desc: "Muestra la factura al emitirla"
      def issue
        prepare
        data = JSON.parse(File.read(options[:file]))
        invoice = Builder.new(issuance).from_hash(data, identifier: options[:identifier])

        say Locale.t("invoice.issued", correlative: invoice.correlative), :green
        say "\n#{Renderers::Text.new(invoice).render}" if options[:print]
      rescue JSON::ParserError => e
        warn "Archivo JSON inválido: #{e.message}"
        exit 1
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "show CORRELATIVO", "Muestra una factura emitida"
      method_option :format, type: :string, default: "text", enum: %w[text json]
      method_option :copy, type: :string, default: "original", enum: %w[original copia]
      def show(correlative)
        invoice = issuance.store.find(correlative)

        case options[:format]
        when "json" then say Renderers::Json.new(invoice).render
        else say Renderers::Text.new(invoice, copy: options[:copy].to_sym).render
        end
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "list", "Lista las facturas emitidas en orden cronológico"
      method_option :from, type: :string, desc: "Desde (AAAA-MM-DD)"
      method_option :to, type: :string, desc: "Hasta (AAAA-MM-DD)"
      def list
        Reporter.new(issuance, shell).documents(from: parse_date(options[:from]),
                                                to: parse_date(options[:to]))
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "annul CORRELATIVO", "Anula una factura (Art. 41)"
      method_option :reason, type: :string, required: true, aliases: "-r",
                             desc: "Motivo de la anulación"
      def annul(correlative)
        invoice = issuance.annul(correlative, reason: options[:reason])

        say "Factura #{invoice.correlative} anulada.", :yellow
        say "El correlativo queda consumido y no se reutilizará."
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "pdf CORRELATIVO", "Genera el PDF de una factura"
      method_option :output, type: :string, aliases: "-o"
      method_option :copy, type: :string, default: "original", enum: %w[original copia]
      def pdf(correlative)
        invoice = issuance.store.find(correlative)
        path = options[:output] || "#{invoice.correlative}.pdf"
        Renderers::Pdf.new(invoice, copy: options[:copy].to_sym).render_file(path)

        say "PDF generado: #{path}", :green
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "export", "Exporta las facturas en texto para el SAR (Art. 53 num. 5)"
      method_option :from, type: :string
      method_option :to, type: :string
      method_option :format, type: :string, default: "json", enum: %w[json csv]
      method_option :output, type: :string, aliases: "-o"
      def export
        invoices = issuance.store.all(from: parse_date(options[:from]), to: parse_date(options[:to]))

        content = case options[:format]
                  when "csv" then Renderers::Json.export_csv(invoices)
                  else Renderers::Json.export(invoices)
                  end

        if options[:output]
          File.write(options[:output], "#{content}\n")
          say "#{invoices.size} documento(s) exportado(s) a #{options[:output]}", :green
        else
          say content
        end
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "check", "Verifica que se pueda emitir: emisor, autorización y correlativo"
      method_option :identifier, type: :string, default: "000-001-01"
      def check
        Reporter.new(issuance, shell).health(identifier: options[:identifier])
      rescue Invoicehn::Error => e
        abort_with(e)
      end

      desc "version", "Muestra la versión"
      def version
        say "invoicehn #{Invoicehn::VERSION}"
      end

      private

      def config
        @config ||= Config.new(home: options[:"data-dir"])
      end

      def issuance
        Locale.current = options[:lang] if options[:lang]
        @issuance ||= Issuance.new(config: config)
      end

      def prepare
        Locale.current = options[:lang] if options[:lang]
        config.ensure_home!
      end

      def parse_date(value)
        value && Date.parse(value)
      rescue ArgumentError
        raise ValidationError, "fecha inválida: #{value}"
      end

      # Compliance failures list every problem at once, which is more useful
      # than the first one.
      def abort_with(error)
        if error.is_a?(ComplianceError)
          warn Locale.t("errors.compliance")
          error.violations.each { |v| warn "  · #{v}" }
        else
          warn "Error: #{error.message}"
        end
        exit 1
      end
    end
  end
end
