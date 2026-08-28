# frozen_string_literal: true

require_relative "invoicehn/version"
require_relative "invoicehn/errors"
require_relative "invoicehn/locale"
require_relative "invoicehn/money"
require_relative "invoicehn/spanish_numerals"
require_relative "invoicehn/rtn"
require_relative "invoicehn/correlative"
require_relative "invoicehn/tax_treatment"
require_relative "invoicehn/line_item"
require_relative "invoicehn/tax_summary"
require_relative "invoicehn/issuer"
require_relative "invoicehn/customer"
require_relative "invoicehn/authorization"
require_relative "invoicehn/exchange_rate"
require_relative "invoicehn/compliance/violation"
require_relative "invoicehn/compliance/validator"
require_relative "invoicehn/invoice"
require_relative "invoicehn/config"
require_relative "invoicehn/storage/json_store"
require_relative "invoicehn/sequence"
require_relative "invoicehn/ledger"
require_relative "invoicehn/issuance"
require_relative "invoicehn/renderers/text"
require_relative "invoicehn/renderers/json"
require_relative "invoicehn/renderers/pdf"

# Facturación electrónica/computarizada para Honduras conforme al Reglamento del
# Régimen de Facturación (Acuerdo 481-2017 y sus reformas 609-2017, 725-2018 y
# 817-2018).
#
# This library enforces *document content* compliance. It cannot confer
# authorization: registering in the Régimen de Facturación (Art. 45), enrolling
# as autoimpresor (Art. 47), filing the Declaración Jurada for a sistema
# computarizado (Art. 53), and obtaining the CAI, authorized range and fecha
# límite de emisión (Arts. 59-61) all remain the operator's obligations before
# any document produced here is valid.
module Invoicehn
end
