# frozen_string_literal: true

module Invoicehn
  module Renderers
    # Renders a Factura, Nota de Crédito or Nota de Débito as plain text for
    # the terminal or a printer.
    #
    # Every legend here is legal text fixed by the Reglamento, not interface
    # copy, so it lives as a constant rather than in the i18n catalog: an
    # English-locale CLI must never leak English onto a fiscal document.
    class Text
      WIDTH = 78

      # Art. 10 num. 2 — "Denominación del documento: 'Factura'".
      DOCUMENT_NAME = "FACTURA"

      # Art. 25 num. 2 — "Nota de Crédito"; Art. 27 num. 2 — "Nota de Débito".
      TITLES = {
        Correlative::FACTURA => DOCUMENT_NAME,
        Correlative::NOTA_DE_CREDITO => "NOTA DE CRÉDITO",
        Correlative::NOTA_DE_DEBITO => "NOTA DE DÉBITO"
      }.freeze

      # Art. 10 num. 6 — "Destino de los ejemplares de la factura".
      COPY_ORIGINAL = "Original: Cliente"
      COPY_ISSUER   = "Copia: Obligado tributario emisor"

      # Art. 25 num. 7 and Art. 27 num. 7 word the issuer's copy differently:
      # "Copia: Obligado Tributario".
      COPY_ISSUER_NOTE = "Copia: Obligado Tributario"

      # Art. 26 num. 3 — the block that identifies the original document.
      REFERENCE_HEADING = "Documento al que se aplica la nota"

      # Art. 26 num. 7 — "Apellidos, Nombres, Tarjeta de Identidad o documento
      # de identificación, y firma de la persona que recibe la Nota de
      # Crédito." Filled in by hand when the note is delivered.
      RECEIVER_FIELDS = ["Recibido por (nombres y apellidos)", "Identidad o documento de identificación",
                         "Firma"].freeze

      def self.title_for(invoice) = TITLES.fetch(invoice.document_type, invoice.document_name.upcase)

      def self.copy_legend(invoice, copy)
        return COPY_ORIGINAL unless copy == :copia

        invoice.factura? ? COPY_ISSUER : COPY_ISSUER_NOTE
      end

      # [label, value] pairs printed for a note's reference and motivo.
      def self.reference_lines(invoice)
        reference = invoice.reference
        return [] unless invoice.note? && reference

        [
          ["#{reference.document_type_name} No.", reference.correlative.to_s],
          ["CAI", reference.cai],
          ["Fecha de emisión", reference.issue_date.to_s]
        ]
      end

      # Art. 41 — "consignando en los mismos la leyenda 'ANULADA'".
      ANNULLED_LEGEND = "ANULADA"

      COPIES = { original: COPY_ORIGINAL, copia: COPY_ISSUER }.freeze

      DESCRIPTION_WIDTH = 30
      ROW_TEMPLATE = "%-#{DESCRIPTION_WIDTH}s %8s %12s %11s %13s".freeze

      attr_reader :invoice, :copy

      # @param copy [Symbol] :original or :copia — Art. 5 requires documents to
      #   be generated "en original y copia".
      def initialize(invoice, copy: :original, width: WIDTH)
        @invoice = invoice
        @copy = copy
        @width = width
      end

      def render
        sections = [
          issuer_block,
          document_block,
          customer_block,
          reference_block,
          line_items_block,
          totals_block,
          footer_block
        ].compact

        "#{sections.join("\n")}\n"
      end
      alias to_s render

      private

      def rule(char = "─") = char * @width

      def centre(text) = text.to_s.center(@width).rstrip

      # Label on the left, value on the right, dot-filled between.
      def pair(label, value)
        value = value.to_s
        space = @width - label.length - value.length
        space = 1 if space < 1
        "#{label}#{" " * space}#{value}"
      end

      def wrap(text, indent: 0)
        limit = @width - indent
        text.to_s.scan(/\S.{0,#{limit - 1}}(?:\s|$)/).map { |l| "#{" " * indent}#{l.strip}" }
      end

      # Art. 10 num. 1 — datos de identificación del emisor.
      def issuer_block
        issuer = @invoice.issuer
        lines = [rule("═")]
        lines << centre(issuer.trade_name.upcase)
        lines << centre(issuer.legal_name)
        lines << centre("RTN: #{issuer.rtn.formatted}")
        lines += wrap("Casa matriz: #{issuer.headquarters_address}").map { |l| centre(l) }
        lines += wrap("Establecimiento: #{issuer.branch_address}").map { |l| centre(l) } if issuer.branch?
        lines << centre("Tel.: #{issuer.phone}   Correo: #{issuer.email}")
        lines << rule("═")
        lines.join("\n")
      end

      # Art. 10 num. 2, 3, 4, 5, 6 and 7.
      def document_block
        auth = @invoice.authorization
        lines = []
        lines << centre(self.class.title_for(@invoice))
        lines << centre(ANNULLED_LEGEND) if @invoice.annulled?
        lines << ""
        lines << pair("No.: #{@invoice.correlative}", "Fecha de emisión: #{@invoice.issue_date}")
        lines << ""
        lines += wrap("CAI: #{auth.cai}")
        lines << "Rango autorizado: #{auth.range_label}"
        lines << "Fecha límite de emisión: #{auth.limit_date}"
        lines << rule
        lines.join("\n")
      end

      # Art. 11 num. 1 lit. a) and b), or num. 2 lit. a).
      def customer_block
        customer = @invoice.customer
        lines = []

        if customer.is_a?(Customer::ConsumidorFinal)
          lines << pair("Cliente: #{customer.display_name}", customer.identification_line)
        else
          lines << "Cliente: #{customer.name}"
          lines << "RTN: #{customer.rtn.formatted}"
        end

        # Art. 10 num. 8 / Art. 11 num. 4 — datos del adquirente exonerado.
        if customer.is_a?(Customer::Exonerado)
          customer.supporting_documents.each { |label, value| lines << "#{label}: #{value}" }
        end

        lines << rule
        lines.join("\n")
      end

      # Art. 26 num. 3 and 4; Art. 28 num. 3 and 4.
      def reference_block
        return nil unless @invoice.note?

        lines = [REFERENCE_HEADING]
        lines += self.class.reference_lines(@invoice).map { |label, value| "  #{label}: #{value}" }
        lines += wrap("Motivo: #{@invoice.motivo}")
        lines << rule
        lines.join("\n")
      end

      # Art. 11 num. 1 lit. d), e), f) and l).
      def line_items_block
        lines = [header_row, rule("·")]

        @invoice.line_items.each do |item|
          lines += item_rows(item)
        end

        lines << rule
        lines.join("\n")
      end

      # Header and detail rows share one template, so the columns cannot drift
      # apart.
      def header_row
        row("Descripción", "Cant.", "V. unitario", "Descuento", "Valor")
      end

      def row(*cells) = format(ROW_TEMPLATE, *cells)

      def item_rows(item)
        # Art. 11 requires the description to be "detallada", so a long one
        # continues on its own lines instead of being truncated — and it breaks
        # between words, not mid-word.
        head, *rest = wrap_words(item.description, DESCRIPTION_WIDTH)

        rows = [row(head,
                    trim_quantity(item.quantity),
                    item.unit_price.to_fixed,
                    item.discount.to_fixed,
                    item.taxable_base.to_fixed)]

        rows += rest.map { |line| "  #{line}" }
        rows << "  (#{item.treatment.label})"
        rows
      end

      def wrap_words(text, limit)
        words = text.to_s.split
        return [""] if words.empty?

        words.each_with_object([+""]) do |word, lines|
          if lines.last.empty?
            lines[-1] = word.length > limit ? word[0, limit] : word
          elsif lines.last.length + 1 + word.length <= limit
            lines[-1] = "#{lines.last} #{word}"
          else
            lines << word
          end
        end
      end

      def trim_quantity(quantity)
        whole = quantity.frac.zero?
        whole ? quantity.to_i.to_s : quantity.to_s("F")
      end

      # Art. 11 num. 1 lit. g), h), i), j), k) and l); Art. 10 num. 10.
      def totals_block
        summary = @invoice.summary
        lines = []

        # lit. g) — the untaxed categories, each shown separately.
        lines += summary.untaxed_buckets.map do |bucket|
          pair("Importe #{bucket.treatment.label.downcase}:", bucket.base.to_s)
        end

        # lit. h) — subtotals by rate.
        lines += summary.taxed_buckets.map do |bucket|
          pair("Importe gravado #{bucket.treatment.rate_percent}%:", bucket.base.to_s)
        end

        lines << pair("Subtotal:", summary.gross.to_s)

        # Art. 10 num. 10 and Art. 11 num. 1 lit. l) — the discounts line is
        # part of the required format, so it is printed whether or not a
        # discount was granted.
        lines << pair("Descuentos y rebajas otorgados:", summary.discount.to_s)

        # lit. i) — taxes by rate.
        lines += summary.taxed_buckets.map do |bucket|
          pair("ISV #{bucket.treatment.rate_percent}%:", bucket.isv.to_s)
        end

        lines << rule("·")
        lines << pair("TOTAL:", @invoice.total.to_s)
        lines << ""

        # lit. k) — the total in words.
        lines += wrap(@invoice.total_in_words)

        # Art. 11, closing paragraph — the rate in force on the issue date.
        if @invoice.foreign_currency?
          lines << ""
          lines << "Tasa de cambio a la fecha de emisión: #{@invoice.exchange_rate}"
          equivalent = @invoice.total_in_lempiras
          lines << pair("Equivalente en Lempiras:", equivalent.to_s) if equivalent
        end

        lines << rule
        lines.join("\n")
      end

      def footer_block
        lines = []

        # Art. 11 num. 3 — where the invoice mixes exempt and taxed sales, only
        # the taxed sales support crédito fiscal. Saying so on the document
        # keeps the buyer from over-claiming.
        if @invoice.factura? && @invoice.summary.mixed_supply?
          lines += wrap("Esta factura sustenta crédito fiscal únicamente por las ventas gravadas: " \
                        "#{@invoice.summary.credito_fiscal_base} (Art. 11 num. 3).")
          lines << ""
        end

        if @invoice.annulled?
          lines += wrap("#{ANNULLED_LEGEND} el #{@invoice.annulled_at}: #{@invoice.annulment_reason}")
          lines << ""
        end

        lines += wrap(@invoice.notes) unless @invoice.notes.empty?

        # Art. 26 num. 7.
        if @invoice.credit_note?
          RECEIVER_FIELDS.each { |label| lines << "#{label}: #{"_" * [@width - label.length - 2, 10].max}" }
          lines << ""
        end

        # Art. 10 num. 6; Arts. 25 and 27 num. 7.
        lines << centre(self.class.copy_legend(@invoice, @copy))
        lines << rule("═")
        lines.join("\n")
      end
    end
  end
end
