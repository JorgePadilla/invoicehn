# frozen_string_literal: true

require "test_helper"
require "open3"

# Exercises the terminal interface as a user would, by running the executable in
# a subprocess against a throwaway data directory.
class TestCli < Minitest::Test
  EXE = File.expand_path("../exe/invoicehn", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  def run_cli(*args, home:)
    Open3.capture3(
      { "INVOICEHN_HOME" => home, "INVOICEHN_LANG" => "es" },
      RbConfig.ruby, "-I#{LIB}", EXE, *args
    )
  end

  def with_configured_cli
    with_temp_home do |home|
      run_cli("setup",
              "--rtn", "08011990123456",
              "--legal-name", "Comercial Ejemplo, S. de R.L.",
              "--trade-name", "Ferretería Ejemplo",
              "--address", "Col. Palmira, Tegucigalpa M.D.C.",
              "--phone", "2222-3333",
              "--email", "facturacion@ejemplo.hn", home: home)

      run_cli("auth", "add",
              "--cai", "ABCD12-345678-9ABCDE-F01234-567890-AB",
              "--from", "000-001-01-00000001",
              "--to", "000-001-01-00000500",
              "--limit", (Date.today + 180).to_s, home: home)

      yield home
    end
  end

  def sale_file(home)
    path = File.join(home, "venta.json")
    File.write(path, JSON.generate(
                       "customer" => { "kind" => "taxpayer", "name" => "Distribuidora del Norte, S.A.",
                                       "rtn" => "05019005123456" },
                       "items" => [{ "description" => "Cemento gris", "quantity" => 20,
                                     "unit_price" => "235.00", "discount" => "200.00",
                                     "treatment" => "gravado_15" }]
                     ))
    path
  end

  def test_version
    with_temp_home do |home|
      out, _err, status = run_cli("version", home: home)

      assert_predicate status, :success?
      assert_match(/invoicehn #{Invoicehn::VERSION}/, out)
    end
  end

  def test_check_refuses_before_setup
    with_temp_home do |home|
      out, = run_cli("check", home: home)

      assert_match(/No hay emisor configurado/, out)
      assert_match(/No se puede emitir/, out)
    end
  end

  def test_setup_then_check_reports_ready
    with_configured_cli do |home|
      out, = run_cli("check", home: home)

      assert_match(/Emisor configurado y completo/, out)
      assert_match(/Autorización vigente/, out)
      assert_match(/Próximo correlativo: 000-001-01-00000001/, out)
      assert_match(/Listo para emitir/, out)
    end
  end

  def test_issue_renders_a_compliant_document
    with_configured_cli do |home|
      out, _err, status = run_cli("issue", "-f", sale_file(home), home: home)

      assert_predicate status, :success?
      assert_match(/Factura emitida: 000-001-01-00000001/, out)
      assert_match(/FACTURA/, out)
      assert_match(/CAI: ABCD12-345678/, out)
      assert_match(/Descuentos y rebajas otorgados:/, out)
      assert_match(/Original: Cliente/, out)
    end
  end

  def test_numbering_advances_across_invocations
    with_configured_cli do |home|
      file = sale_file(home)
      3.times { run_cli("issue", "-f", file, "--print=false", home: home) }

      out, = run_cli("list", home: home)

      assert_match(/000-001-01-00000001/, out)
      assert_match(/000-001-01-00000002/, out)
      assert_match(/000-001-01-00000003/, out)
      assert_match(/3 documento\(s\)/, out)
    end
  end

  def test_show_returns_json
    with_configured_cli do |home|
      run_cli("issue", "-f", sale_file(home), "--print=false", home: home)
      out, _err, status = run_cli("show", "000-001-01-00000001", "--format", "json", home: home)

      assert_predicate status, :success?
      payload = JSON.parse(out)
      assert_equal "000-001-01-00000001", payload["correlative"]
    end
  end

  # Art. 41 — the number stays consumed.
  def test_annul_marks_the_document_and_keeps_the_number
    with_configured_cli do |home|
      file = sale_file(home)
      run_cli("issue", "-f", file, "--print=false", home: home)
      out, _err, status = run_cli("annul", "000-001-01-00000001", "-r", "Error en la cantidad",
                                  home: home)

      assert_predicate status, :success?
      assert_match(/anulada/, out)

      run_cli("issue", "-f", file, "--print=false", home: home)
      listed, = run_cli("list", home: home)

      assert_match(/000-001-01-00000001.*ANULADA/, listed)
      assert_match(/000-001-01-00000002/, listed)
    end
  end

  # Art. 62 — an expired authorization blocks issuance, and the exit status says so.
  def test_an_expired_authorization_blocks_issuance
    with_temp_home do |home|
      run_cli("setup", "--rtn", "08011990123456", "--legal-name", "X", "--trade-name", "X",
              "--address", "Y", "--phone", "1", "--email", "a@b.hn", home: home)
      run_cli("auth", "add", "--cai", "VENCIDA", "--from", "000-001-01-00000001",
              "--to", "000-001-01-00000010", "--limit", "2020-01-01", home: home)

      _out, err, status = run_cli("issue", "-f", sale_file(home), home: home)

      refute_predicate status, :success?
      assert_match(/vencidas o agotadas/, err)
    end
  end

  def test_a_missing_document_exits_non_zero
    with_configured_cli do |home|
      _out, err, status = run_cli("show", "000-001-01-00009999", home: home)

      refute_predicate status, :success?
      assert_match(/no existe la factura/, err)
    end
  end

  # Art. 53 num. 5 — the text export.
  def test_export_produces_csv
    with_configured_cli do |home|
      run_cli("issue", "-f", sale_file(home), "--print=false", home: home)
      out, _err, status = run_cli("export", "--format", "csv", home: home)

      assert_predicate status, :success?
      assert_match(/\Acorrelativo,fecha,estado,cai/, out)
      assert_match(/000-001-01-00000001/, out)
    end
  end

  def test_english_interface_still_issues_a_spanish_document
    with_configured_cli do |home|
      out, _err, _status = Open3.capture3(
        { "INVOICEHN_HOME" => home, "INVOICEHN_LANG" => "en" },
        RbConfig.ruby, "-I#{LIB}", EXE, "issue", "-f", sale_file(home)
      )

      # Interface in English…
      assert_match(/Invoice issued/, out)
      # …document still in Spanish, because its legends are legal text.
      assert_match(/FACTURA/, out)
      assert_match(/Original: Cliente/, out)
      assert_match(/Descuentos y rebajas otorgados:/, out)
      assert_match(/LEMPIRAS CON/, out)
    end
  end
end
