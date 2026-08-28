# frozen_string_literal: true

require_relative "lib/invoicehn/version"

Gem::Specification.new do |spec|
  spec.name        = "invoicehn"
  spec.version     = Invoicehn::VERSION
  spec.authors     = ["Jorge Padilla"]
  spec.email       = ["jorgep4dill4@gmail.com"]

  spec.summary     = "Facturación para Honduras conforme al Régimen de Facturación (Acuerdo 481-2017)"
  spec.description = <<~DESC
    Genera Facturas que cumplen los requisitos de contenido de los Artículos 10 y 11 del
    Reglamento del Régimen de Facturación (Acuerdo 481-2017 y sus reformas), incluyendo el
    correlativo de 16 dígitos, control del CAI, rango autorizado y fecha límite de emisión,
    discriminación del ISV por tarifa, y el redondeo estatutario del Artículo 9 de la Ley
    del Impuesto Sobre Ventas. Incluye biblioteca Ruby y una interfaz de terminal.
  DESC

  spec.homepage    = "https://github.com/JorgePadilla/invoicehn"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "config/locales/*.yml",
    "exe/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.bindir      = "exe"
  spec.executables = ["invoicehn"]
  spec.require_paths = ["lib"]

  spec.add_dependency "bigdecimal", "~> 3.1"
  spec.add_dependency "prawn", "~> 2.5"
  spec.add_dependency "prawn-table", "~> 0.2"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-prompt", "~> 0.23"
end
