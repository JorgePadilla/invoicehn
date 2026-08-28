# frozen_string_literal: true

module Invoicehn
  module Renderers
    # Renders the Factura as a PDF.
    #
    # The legends are the same constants the text renderer uses, so the two
    # outputs cannot drift apart on the wording the decree fixes.
    #
    # Art. 38 forbids issuing fiscal documents on thermal paper and requires the
    # information to be legible and permanent — a PDF printed on ordinary paper
    # satisfies that; the operator remains responsible for the medium.
    class Pdf
      # Loaded lazily so the rest of the library works without prawn installed.
      #
      # LoadError also covers Gem::ConflictError, which is what actually surfaces
      # when prawn's ttfunk dependency pins bigdecimal and a newer bigdecimal has
      # already been activated — a conflict rather than a missing file.
      def self.available?
        require "prawn"
        require "prawn/table"
        true
      rescue LoadError
        false
      end

      # Prawn's built-in AFM fonts encode as Windows-1252. That covers every
      # accented character Spanish needs, but a name or description carrying
      # anything outside it would raise mid-render — so text is transcoded with
      # a replacement rather than allowed to abort a fiscal document.
      def self.encode(text)
        text.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?")
            .encode("UTF-8")
      end

      MARGIN = 36
      TITLE_SIZE = 16
      BODY_SIZE = 9

      attr_reader :invoice, :copy

      def initialize(invoice, copy: :original)
        @invoice = invoice
        @copy = copy
      end

      def render_file(path)
        document.render_file(path)
        path
      end

      def render = document.render

      private

      # Shorthand for the Windows-1252 transcode every string on the page goes
      # through.
      def e(text) = self.class.encode(text)

      def document
        unless self.class.available?
          raise Error, "se requiere la gema «prawn» para generar PDF: gem install prawn prawn-table"
        end

        Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)

        pdf = Prawn::Document.new(page_size: "LETTER", margin: MARGIN)
        pdf.font_size BODY_SIZE

        issuer_section(pdf)
        document_section(pdf)
        customer_section(pdf)
        line_items_section(pdf)
        totals_section(pdf)
        footer_section(pdf)

        pdf
      end

      # Art. 10 num. 1.
      def issuer_section(pdf)
        issuer = @invoice.issuer
        pdf.text e(issuer.trade_name.upcase), size: 14, align: :center, style: :bold
        pdf.text e(issuer.legal_name), align: :center
        pdf.text e("RTN: #{issuer.rtn.formatted}"), align: :center
        pdf.text e("Casa matriz: #{issuer.headquarters_address}"), align: :center
        pdf.text e("Establecimiento: #{issuer.branch_address}"), align: :center if issuer.branch?
        pdf.text e("Tel.: #{issuer.phone}   Correo: #{issuer.email}"), align: :center
        pdf.move_down 8
        pdf.stroke_horizontal_rule
        pdf.move_down 8
      end

      # Art. 10 num. 2, 3, 4, 5 and 7.
      def document_section(pdf)
        auth = @invoice.authorization
        pdf.text e(Text::DOCUMENT_NAME), size: TITLE_SIZE, align: :center, style: :bold

        pdf.text e(Text::ANNULLED_LEGEND), size: TITLE_SIZE, align: :center, style: :bold if @invoice.annulled?

        pdf.move_down 6
        pdf.text e("No.: <b>#{@invoice.correlative}</b>"), inline_format: true
        pdf.text e("Fecha de emisión: #{@invoice.issue_date}")
        pdf.move_down 4
        pdf.text e("CAI: #{auth.cai}")
        pdf.text e("Rango autorizado: #{auth.range_label}")
        pdf.text e("Fecha límite de emisión: #{auth.limit_date}")
        pdf.move_down 8
        pdf.stroke_horizontal_rule
        pdf.move_down 8
      end

      # Art. 11 num. 1 lit. a) b), num. 2 lit. a), Art. 10 num. 8.
      def customer_section(pdf)
        customer = @invoice.customer

        if customer.is_a?(Customer::ConsumidorFinal)
          pdf.text e("Cliente: #{customer.display_name}")
          pdf.text e("Identificación: #{customer.identification_line}")
        else
          pdf.text e("Cliente: #{customer.name}")
          pdf.text e("RTN: #{customer.rtn.formatted}")
        end

        if customer.is_a?(Customer::Exonerado)
          customer.supporting_documents.each { |label, value| pdf.text e("#{label}: #{value}") }
        end

        pdf.move_down 8
      end

      # Art. 11 num. 1 lit. d) e) f) and l).
      def line_items_section(pdf)
        header = ["Descripción", "Cant.", "V. unitario", "Descuento", "Tratamiento", "Valor"].map { |h| e(h) }
        rows = @invoice.line_items.map do |item|
          [
            e(item.description),
            item.quantity.frac.zero? ? item.quantity.to_i.to_s : item.quantity.to_s("F"),
            item.unit_price.to_fixed,
            item.discount.to_fixed,
            e(item.treatment.label),
            item.taxable_base.to_fixed
          ]
        end

        pdf.table([header] + rows, width: pdf.bounds.width, header: true) do |t|
          t.cells.size = BODY_SIZE
          t.cells.padding = [3, 4, 3, 4]
          t.row(0).font_style = :bold
          t.row(0).background_color = "EEEEEE"
          t.columns(1..3).align = :right
          t.column(5).align = :right
        end

        pdf.move_down 8
      end

      # Art. 11 num. 1 lit. g) h) i) j) k) l); Art. 10 num. 10.
      def totals_section(pdf)
        summary = @invoice.summary
        rows = []

        rows += summary.untaxed_buckets.map do |b|
          [e("Importe #{b.treatment.label.downcase}:"), e(b.base.to_s)]
        end
        rows += summary.taxed_buckets.map do |b|
          [e("Importe gravado #{b.treatment.rate_percent}%:"), e(b.base.to_s)]
        end

        rows << [e("Subtotal:"), e(summary.gross.to_s)]
        # Art. 10 num. 10 — part of the required format, printed whether or not
        # a discount was granted.
        rows << [e("Descuentos y rebajas otorgados:"), e(summary.discount.to_s)]

        rows += summary.taxed_buckets.map do |b|
          [e("ISV #{b.treatment.rate_percent}%:"), e(b.isv.to_s)]
        end

        rows << [e("TOTAL:"), e(@invoice.total.to_s)]

        pdf.table(rows, position: :right, width: pdf.bounds.width * 0.55) do |t|
          t.cells.size = BODY_SIZE
          t.cells.borders = []
          t.cells.padding = [2, 4, 2, 4]
          t.column(1).align = :right
          t.row(-1).font_style = :bold
          t.row(-1).borders = [:top]
        end

        pdf.move_down 8
        pdf.text e(@invoice.total_in_words), style: :italic

        if @invoice.foreign_currency?
          pdf.move_down 4
          pdf.text e("Tasa de cambio a la fecha de emisión: #{@invoice.exchange_rate}")
          equivalent = @invoice.total_in_lempiras
          pdf.text e("Equivalente en Lempiras: #{equivalent}") if equivalent
        end

        pdf.move_down 8
      end

      def footer_section(pdf)
        if @invoice.summary.mixed_supply?
          pdf.text e("Esta factura sustenta crédito fiscal únicamente por las ventas gravadas: " \
                     "#{@invoice.summary.credito_fiscal_base} (Art. 11 num. 3)."), size: 8
          pdf.move_down 4
        end

        if @invoice.annulled?
          pdf.text e("#{Text::ANNULLED_LEGEND} el #{@invoice.annulled_at}: #{@invoice.annulment_reason}"),
                   style: :bold
          pdf.move_down 4
        end

        pdf.text e(@invoice.notes), size: 8 unless @invoice.notes.empty?

        pdf.move_down 6
        pdf.stroke_horizontal_rule
        pdf.move_down 4
        # Art. 10 num. 6.
        pdf.text e(Text::COPIES.fetch(@copy, Text::COPY_ORIGINAL)), align: :center, style: :bold
      end
    end
  end
end
