# frozen_string_literal: true

require_relative "cli/builder"
require_relative "cli/reporter"
require_relative "cli/wizard"
require_relative "cli/main"

module Invoicehn
  # The terminal interface.
  #
  # Interface strings are translatable (es/en); the fiscal document's own
  # legends are not — they are legal text fixed by the Reglamento and live as
  # constants in Renderers::Text.
  module CLI
  end
end
