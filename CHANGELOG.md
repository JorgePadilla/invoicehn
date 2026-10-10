# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [Sin publicar]

## [0.2.0] — 2026-10-10

Notas de Crédito y de Débito, la tabla de códigos reformada, y correcciones
que una aplicación anfitriona con su propia base de datos necesita. Las líneas
citadas son de `doc/fuentes/acuerdo_481_2017_consolidado.txt` (texto
consolidado) y `doc/fuentes/acuerdo_609_2017_gaceta_34457_ocr.txt`.

### Corregido

- **Códigos de tipo de documento (Art. 10 num. 7 lit. c y sus pares).** La 0.1.0
  traía la tabla del texto original de 2017. El Art. 1 del Acuerdo 609-2017
  (*La Gaceta* 34,457) reescribió el literal c) de los Arts. 15, 17, 20, 23, 25,
  27, 29 y 33 (OCR del 609, líneas 209, 231, 273, 320, 359, 378, 404 y 438). La
  tabla vigente: 01 Factura (l. 626), 04 Recibo por Honorarios Profesionales
  (l. 1039, no reformado), 05 Comprobante de Retención (l. 1750), 06 Nota de
  Crédito (l. 1345), 07 Nota de Débito (l. 1438), 08 Guía de Remisión (l. 1535),
  09 Ticket (l. 969), 10 Factura Prevalorada (l. 889), 11 Boleta de Compra
  (l. 1122), 12 Constancia de Donación (l. 1259). 02 y 03 quedan sin asignar y se
  rechazan.
- **Correlativo trabado.** Si el libro contable fallaba después de guardar el
  documento, el documento quedaba en el store y el contador no avanzaba: toda
  emisión posterior de ese identificador fallaba con `ImmutableDocument`. Ahora
  el documento se borra si el asiento falla, dentro del bloque de `allocate`.
- **Fechas en servidores UTC.** Honduras es UTC-6; `Date.today` en un servidor UTC
  estampaba la fecha de mañana desde las 18:00. Todas las fechas por defecto
  salen de un reloj configurable (ver *Añadido*).
- **`invoicehn check` / `Issuance#health`** informaba "listo" con una
  autorización de rango agotado y documentos restantes negativos.
  `JsonStore#active_authorization` con `next_sequence:` ya no recurre a una
  autorización que no cubre ese número, y `remaining` nunca es negativo.

### Añadido

- **Nota de Crédito (tipo 06, Arts. 25-26, l. 1300-1391) y Nota de Débito
  (tipo 07, Arts. 27-28, l. 1393-1496).** `Invoice` acepta `reference:`
  (`Invoicehn::DocumentReference` con CAI, correlativo y fecha de emisión del
  comprobante, Arts. 26 y 28 num. 3) y `motivo:` (num. 4); el tipo lo declara
  el correlativo. `Issuance#issue` acepta `reference:` y `motivo:`, y hay
  atajos `issue_credit_note` / `issue_debit_note`. Cada identificador lleva su
  propio contador y su propia autorización (Art. 59, l. 2259).
- **Reglas del validador para las notas**: referencia obligatoria; la de la NC
  debe ser un Comprobante Fiscal (Art. 4 num. 32 y Art. 6) y la de la ND puede
  ser "el Comprobante Fiscal o el documento" (Art. 28 num. 3 lit. b); motivo
  obligatorio; nombre y RTN del adquirente (num. 1-2, sin alternativa de
  CONSUMIDOR FINAL); moneda nacional (Art. 26 num. 9, Art. 28 num. 8); la
  referencia no puede ser posterior a la nota. Las reglas propias de la
  Factura (umbral de L 10,000.00, aviso de ventas mixtas, documentos del
  exonerado del Art. 10 num. 8, moneda extranjera del Art. 11) se aplican sólo
  a la Factura. No se encontró en las fuentes un monto máximo para las notas y
  no se impone ninguno.
- **Renderers Text y PDF**: título "NOTA DE CRÉDITO" / "NOTA DE DÉBITO" (Arts. 25
  y 27 num. 2), bloque del documento de referencia y motivo, leyenda "Copia:
  Obligado Tributario" (Arts. 25 y 27 num. 7) y, en la NC, campos en blanco para
  nombre, identidad y firma de quien la recibe (Art. 26 num. 7).
- **Reloj configurable**: `Invoicehn.configure { |c| c.today = -> { Date.current } }`
  e `Invoicehn.today`. Por defecto `Date.today`, como antes. Una prueba recorre
  `lib/` y falla si alguien vuelve a leer `Date.today` directamente.
- **Contrato del store/sequence/ledger** documentado en el README, con
  `require "invoicehn/testing"` (verificaciones que lanzan
  `Invoicehn::Testing::ContractError`), `require "invoicehn/test_support/contracts"`
  (módulos de minitest `StoreContract`, `SequenceContract`, `LedgerContract`,
  `IssuanceContract`) y `require "invoicehn/test_support/memory"` (adaptadores
  en memoria de referencia).
- `Correlative::COMPROBANTES_FISCALES` (Art. 6) y `DOCUMENTOS_COMPLEMENTARIOS`
  (Art. 7); `Correlative#credit_note?`, `#debit_note?`, `#note?`,
  `#comprobante_fiscal?`; `Invoice#document_type`, `#document_name`,
  `#factura?`, `#credit_note?`, `#debit_note?`, `#note?`.
- `invoicehn issue -f` acepta `reference` y `motivo` en el JSON.
- Pruebas del PDF leyéndolo de vuelta con `pdf-reader` (dependencia sólo de
  desarrollo).

### Cambiado — revisar al actualizar

- **El store debe responder a `delete_document(document)`** (y `Issuance` usa
  ahora `exists?`). Un store propio escrito para la 0.1.0 debe agregarlos.
- `Issuance.new` ya no construye `Config` cuando se le inyectan store, sequence
  y ledger: no toca `~/.invoicehn`.
- **Autorizaciones registradas con la tabla vieja**: una autorización con
  código 02 o 03 ya no se carga; una con 07 u 08 cambia de significado (07 es
  ahora Nota de Débito, 08 Guía de Remisión). La 0.1.0 sólo emitía 01, así que
  sólo afecta autorizaciones registradas y no usadas; revise
  `authorizations.json`.
- La exportación CSV agrega al final las columnas `tipo`,
  `documento_referencia` y `motivo`; el JSON del documento agrega
  `document_type` (y `reference`/`motivo` en las notas); el libro JSONL agrega
  `document_type` y `reference`.
- Mensajes: "no existe el documento …" en lugar de "no existe la factura …".

### Pendiente de criterio (no resuelto por las fuentes)

- Los Arts. 26 y 28 exigen RTN del adquirente sin alternativa: la gema rechaza
  notas a consumidores finales sin RTN. Si el SAR admite otra práctica, es una
  decisión del obligado tributario.
- El Art. 17 conserva la frase "El Ticket tendrá como código 03" (l. 988)
  aunque el 609-2017 reformó su num. 4 a "09=Ticket"; la tabla sigue el
  numeral reformado.
- Las notas se rechazan en moneda extranjera: el permiso del párrafo final del
  Art. 11 habla sólo de "facturas" y los Arts. 26 num. 9 y 28 num. 8 piden la
  Moneda Nacional Lempira. Una factura en dólares se ajustaría con una nota en
  lempiras.
- La referencia de la Nota de Crédito debe ser un Comprobante Fiscal del Art. 6
  (01, 04, 09, 10, 11, 12), no sólo una Factura; la de la Nota de Débito acepta
  cualquier tipo reconocido por el "o el documento" del Art. 28 num. 3 lit. b.
- Ningún artículo (4 num. 31-32, 25-28) fija un monto máximo para las notas.
- `Issuance#annul` todavía guarda la forma anulada antes del asiento contable:
  si el libro falla, el documento queda anulado sin asiento. Queda para una
  versión siguiente.

## [0.1.0] — 2026-08-28

Primera versión. Emisión de Facturas (Comprobante Fiscal tipo 01) conforme al
Reglamento del Régimen de Facturación, Acuerdo 481-2017 y sus reformas
(609-2017, 725-2018 y 817-2018).

### Añadido

- **Requisitos del formato (Art. 10)**: datos de identificación del emisor,
  denominación "Factura", CAI, fecha límite de emisión, rango autorizado,
  destino de los ejemplares, correlativo de 16 dígitos
  `NNN-NNN-NN-NNNNNNNN`, datos del adquirente exonerado, y la línea de
  descuentos y rebajas del numeral 10.
- **Requisitos al momento de la emisión (Art. 11)**: identificación del cliente
  según su tipo, discriminación de valores exentos, exonerados y gravados,
  subtotales e impuestos por tarifa, descuentos, denominación de la moneda,
  importe total en números y letras, umbral de L 10,000.00 para consumidores
  finales, y tasa de cambio vigente en facturas en moneda extranjera.
- **Redondeo estatutario** del Artículo 9 de la Ley del Impuesto Sobre Ventas:
  medio hacia arriba en 0.005 de Lempira. `Float` está prohibido en todo el
  camino del dinero, con una prueba que recorre el código fuente y falla si
  aparece.
- **Los descuentos reducen la base gravable**, conforme al Artículo 3 de la Ley
  del ISV.
- **Tasas del ISV** del Decreto 278-2013: 15% general y 18% especial.
- **Control de autorizaciones**: un identificador acumula autorizaciones; el
  asignador elige la vigente que cubra el correlativo siguiente. La emisión se
  bloquea si la autorización venció (Art. 62) o el número queda fuera del rango.
- **Numeración sin huecos ni reutilización**, bajo candado exclusivo de archivo;
  la asignación y el guardado ocurren en un solo paso atómico.
- **Anulación (Art. 41)** que conserva el correlativo consumido.
- **Libro contable (Art. 53 num. 1)** con interfaz `Invoicehn::Ledger` e
  implementación JSONL incluida, y exportación en texto (Art. 53 num. 5).
- **Interfaz de terminal** con subcomandos y asistente interactivo, en español o
  inglés. El documento fiscal se emite siempre en español.
- **Salidas** en texto, PDF y JSON/CSV.

### Notas

- La gema cubre el contenido del documento. La inscripción al Régimen de
  Facturación (Art. 45), la inscripción como autoimpresor (Art. 47), la
  Declaración Jurada del sistema computarizado (Art. 53) y la obtención del CAI,
  el rango y la fecha límite (Arts. 59-61) siguen siendo obligación del obligado
  tributario.
- El RTN se valida por longitud y dígitos únicamente: no existe un dígito
  verificador documentado públicamente. El CAI se almacena e imprime tal cual,
  porque ninguna norma fija su formato.
- La leyenda "La factura es beneficio de todos, exíjala" no está exigida por
  ninguna norma; se admite como texto opcional.

[Sin publicar]: https://github.com/JorgePadilla/invoicehn/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/JorgePadilla/invoicehn/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/JorgePadilla/invoicehn/releases/tag/v0.1.0
