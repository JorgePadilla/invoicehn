# frozen_string_literal: true

require "test_helper"

# The rendered document is what the customer receives and what an inspector
# reads, so these cases assert that every field Arts. 10 and 11 require actually
# reaches the page. A regression that silently drops a legally required field
# fails here.
class TestRendererText < Minitest::Test
  def render(invoice = full_invoice, **options)
    Invoicehn::Renderers::Text.new(invoice, **options).render
  end

  def full_invoice(**overrides)
    build_invoice(
      correlative: "000-001-01-00000042",
      issue_date: Date.new(2026, 8, 28),
      customer: Invoicehn::Customer::Taxpayer.new(
        name: "Distribuidora del Norte, S.A.", rtn: "05019005123456"
      ),
      line_items: [
        build_line(description: "Cemento gris bolsa 42.5 kg", quantity: 20,
                   unit_price: hnl("235.00"), treatment: :gravado_15,
                   discount: hnl("200.00")),
        build_line(description: "Cerveza nacional caja 24 unidades", quantity: 3,
                   unit_price: hnl("480.00"), treatment: :gravado_18),
        build_line(description: "Medicamento esencial", quantity: 10,
                   unit_price: hnl("12.50"), treatment: :exento)
      ], **overrides
    )
  end

  # --- Art. 10, requisitos del formato --------------------------------

  # num. 1 — datos de identificación del emisor.
  def test_shows_every_issuer_field
    output = render

    assert_includes output, "EJEMPLO" # nombre comercial, en mayúsculas
    assert_includes output, "Comercial Ejemplo, S. de R.L."
    assert_includes output, "0801-1990-123456"
    assert_includes output, "Col. Palmira"
    assert_includes output, "2222-3333"
    assert_includes output, "facturacion@ejemplo.hn"
  end

  def test_shows_the_branch_address_when_it_differs
    invoice = full_invoice(issuer: build_issuer(branch_address: "Barrio Guamilito, San Pedro Sula"))

    assert_includes render(invoice), "Barrio Guamilito"
  end

  # num. 2 — "Denominación del documento: 'Factura'".
  def test_names_the_document_factura
    assert_includes render, "FACTURA"
  end

  # num. 3, 4 and 5 — CAI, fecha límite and rango, all current.
  def test_shows_cai_range_and_limit_date
    output = render

    assert_includes output, "CAI: ABCD12-345678-9ABCDE-F01234-567890-AB"
    assert_includes output, "Rango autorizado: 000-001-01-00000001 al 000-001-01-00000500"
    assert_includes output, "Fecha límite de emisión:"
  end

  # num. 6 — destino de los ejemplares.
  def test_shows_the_copy_destination
    assert_includes render, "Original: Cliente"
    assert_includes render(copy: :copia), "Copia: Obligado tributario emisor"
  end

  # num. 7 — the 16-digit correlative.
  def test_shows_the_correlative
    assert_includes render, "000-001-01-00000042"
  end

  # num. 10, added by Acuerdo 725-2018 — "Descuentos y rebajas otorgados". This
  # is a *format* requirement, so the line belongs on the document whether or
  # not a discount was granted.
  def test_always_shows_the_discounts_line
    assert_includes render, "Descuentos y rebajas otorgados:"

    without_discount = full_invoice(line_items: [build_line])

    assert_includes render(without_discount), "Descuentos y rebajas otorgados:"
    assert_includes render(without_discount), "L 0.00"
  end

  # --- Art. 11, requisitos al momento de la emisión --------------------

  # num. 1 lit. a) and b).
  def test_shows_the_client_name_and_rtn
    output = render

    assert_includes output, "Distribuidora del Norte, S.A."
    assert_includes output, "0501-9005-123456"
  end

  # num. 1 lit. c).
  def test_shows_the_issue_date
    assert_includes render, "2026-08-28"
  end

  # num. 1 lit. d), e) and f).
  def test_shows_description_quantity_and_unit_value
    output = render

    assert_includes output, "Cemento gris bolsa 42.5 kg"
    assert_includes output, "235.00"
    assert_includes output, "20"
  end

  def test_long_descriptions_are_wrapped_not_truncated
    invoice = full_invoice(
      line_items: [build_line(description: "Servicio de mantenimiento preventivo de equipo industrial")]
    )
    output = render(invoice)

    assert_includes output, "Servicio de mantenimiento"
    assert_includes output, "industrial"
  end

  # num. 1 lit. g) — exempt, exonerated and zero-rated values shown separately.
  def test_discriminates_untaxed_values
    assert_includes render, "Importe exento:"
  end

  # num. 1 lit. h) — subtotals by rate.
  def test_shows_subtotals_by_rate
    output = render

    assert_includes output, "Importe gravado 15%:"
    assert_includes output, "Importe gravado 18%:"
  end

  # num. 1 lit. i) — taxes by rate.
  def test_shows_taxes_by_rate
    output = render

    assert_includes output, "ISV 15%:"
    assert_includes output, "ISV 18%:"
    assert_includes output, "L 675.00"   # 15% of 4,500.00
    assert_includes output, "L 259.20"   # 18% of 1,440.00
  end

  # num. 1 lit. j) — "Denominación literal de la Moneda Nacional Lempira o
  # símbolo (L)".
  def test_shows_the_currency_symbol
    assert_match(/L [\d,]+\.\d{2}/, render)
  end

  # num. 1 lit. k) — "Importe total en números y letras".
  def test_shows_the_total_in_numbers_and_words
    output = render

    assert_includes output, "TOTAL:"
    assert_includes output, "L 6,999.20"
    assert_includes output, "SEIS MIL NOVECIENTOS NOVENTA Y NUEVE LEMPIRAS CON 20/100"
  end

  # num. 2 lit. a) — the legend for an anonymous final consumer.
  def test_shows_the_consumidor_final_legend
    invoice = full_invoice(customer: Invoicehn::Customer::ConsumidorFinal.new)

    assert_includes render(invoice), "CONSUMIDOR FINAL"
  end

  # Art. 10 num. 8 / Art. 11 num. 4 — datos del adquirente exonerado.
  def test_shows_the_exonerated_purchasers_documents
    invoice = full_invoice(
      customer: Invoicehn::Customer::Exonerado.new(
        name: "Fundación Ejemplo", rtn: "08019995123456",
        purchase_order: "OCE-2026-0042", sag_registry: "SAG-4410"
      ),
      line_items: [build_line(treatment: :exonerado)]
    )
    output = render(invoice)

    assert_includes output, "Orden de Compra Exenta: OCE-2026-0042"
    assert_includes output, "Registro SAG: SAG-4410"
  end

  # num. 3 — only taxed sales support crédito fiscal, so a mixed invoice says so.
  def test_notes_the_credito_fiscal_limit_on_a_mixed_invoice
    output = render

    assert_includes output, "crédito fiscal únicamente por las ventas gravadas"
    assert_includes output, "Art. 11 num. 3"
  end

  # Closing paragraph — the rate in force on the issue date.
  def test_shows_the_exchange_rate_on_a_foreign_currency_invoice
    invoice = full_invoice(
      currency: "USD",
      exchange_rate: Invoicehn::ExchangeRate.new(rate: "24.6543", date: Date.new(2026, 8, 28)),
      line_items: [build_line(unit_price: usd("100.00"))]
    )
    output = render(invoice)

    assert_includes output, "Tasa de cambio a la fecha de emisión:"
    assert_includes output, "1 USD = L 24.6543"
    assert_includes output, "Equivalente en Lempiras:"
    assert_includes output, "DÓLARES"
  end

  # --- Art. 41 --------------------------------------------------------

  def test_an_annulled_document_carries_the_legend
    output = render(full_invoice.annul(reason: "Error en la descripción"))

    assert_includes output, "ANULADA"
    assert_includes output, "Error en la descripción"
  end

  def test_a_current_document_does_not_carry_the_legend
    refute_includes render, "ANULADA"
  end

  # --- layout ---------------------------------------------------------

  def test_lines_fit_the_page_width
    render.lines.each do |line|
      assert_operator line.chomp.length, :<=, Invoicehn::Renderers::Text::WIDTH,
                      "línea demasiado larga: #{line.inspect}"
    end
  end

  def test_no_trailing_whitespace
    render.lines.each do |line|
      assert_equal line.chomp, line.chomp.rstrip, "espacio final en: #{line.inspect}"
    end
  end

  # The document's legends are legal text, so they are constants rather than
  # translatable interface copy — an English-locale CLI must never put English
  # on a fiscal document.
  def test_legends_are_fixed_spanish_constants
    assert_equal "FACTURA", Invoicehn::Renderers::Text::DOCUMENT_NAME
    assert_equal "Original: Cliente", Invoicehn::Renderers::Text::COPY_ORIGINAL
    assert_equal "Copia: Obligado tributario emisor", Invoicehn::Renderers::Text::COPY_ISSUER
    assert_equal "ANULADA", Invoicehn::Renderers::Text::ANNULLED_LEGEND
  end
end
