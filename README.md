# invoicehn

[![CI](https://github.com/JorgePadilla/invoicehn/actions/workflows/ci.yml/badge.svg)](https://github.com/JorgePadilla/invoicehn/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/invoicehn.svg)](https://rubygems.org/gems/invoicehn)

Facturación para Honduras conforme al **Reglamento del Régimen de Facturación,
Otros Documentos Fiscales y Registro Fiscal de Imprentas** (Acuerdo No. 481-2017
y sus reformas). Emite **Facturas** (tipo 01), **Notas de Crédito** (tipo 06) y
**Notas de Débito** (tipo 07). Biblioteca Ruby más una interfaz de terminal.

```
invoicehn setup      # datos del emisor (Art. 10 num. 1)
invoicehn auth add   # el CAI, el rango y la fecha límite que otorga el SAR
invoicehn new        # emitir una factura (asistente interactivo)
invoicehn check      # ¿se puede emitir ahora mismo?
```

---

## Lo que esta gema hace y lo que no

Esto es lo primero que debe quedar claro, porque el software sólo cubre una mitad
de lo que la ley exige.

**Cubre el contenido del documento.** Todos los campos que exigen los Artículos
10 (requisitos del formato) y 11 (requisitos al momento de la emisión) para la
Factura, y los Artículos 25-26 y 27-28 para las Notas de Crédito y de Débito: el
correlativo de 16 dígitos, el control del CAI, del rango autorizado y de la fecha
límite de emisión, la discriminación del ISV por tarifa, los descuentos, el total
en números y letras, y el redondeo estatutario.

**No otorga autorización.** Siguen siendo obligación del obligado tributario:

| Obligación | Artículo |
|---|---|
| Inscribirse en el Régimen de Facturación | Art. 45 |
| Inscribirse como autoimpresor | Art. 47 |
| Presentar la Declaración Jurada del sistema computarizado | Art. 53 |
| Obtener el CAI, el rango autorizado y la fecha límite | Arts. 59-61 |
| Comunicar los documentos no utilizados | Art. 42 |
| Custodiar los documentos por el plazo de prescripción | Art. 43 |

La gema **consume** el CAI, el rango y la fecha límite; nunca los inventa.
Una factura generada aquí sin una autorización real del SAR no es un documento
fiscal válido.

---

## Instalación

```ruby
# Gemfile
gem "invoicehn"
```

o `gem install invoicehn`. Requiere Ruby >= 3.1.

---

## Uso desde la terminal

### 1. Configurar el emisor

```
invoicehn setup
```

Pide los siete datos del Art. 10 num. 1: RTN, nombre o razón social, nombre
comercial, dirección de la casa matriz, dirección del establecimiento del punto
de emisión, teléfono y correo electrónico. Todos son obligatorios; la emisión se
bloquea si falta alguno.

También acepta banderas, para instalaciones desatendidas:

```
invoicehn setup --rtn 08011990123456 \
  --legal-name "Comercial Ejemplo, S. de R.L." \
  --trade-name "Ferretería Ejemplo" \
  --address "Col. Palmira, Tegucigalpa M.D.C." \
  --phone "2222-3333" --email "facturacion@ejemplo.hn"
```

### 2. Registrar la autorización del SAR

Copie los valores del documento de autorización:

```
invoicehn auth add --cai "ABCD12-345678-9ABCDE-F01234-567890-AB" \
  --from "000-001-01-00000001" --to "000-001-01-00000500" \
  --limit "2027-06-30"
```

El tercer grupo del correlativo es el **tipo de documento**, según la tabla
vigente tras el Acuerdo 609-2017 (ver *Los códigos de tipo de documento* más
abajo): `01` Factura, `06` Nota de Crédito, `07` Nota de Débito.

Un mismo identificador acumula autorizaciones con el tiempo: cuando un rango se
agota y el SAR concede otro que continúa la numeración, se registra el nuevo sin
borrar el anterior. El asignador elige la autorización vigente que cubra el
correlativo que sigue.

### 3. Emitir

Interactivo:

```
invoicehn new
```

O desde un archivo, para integrarlo con otro sistema:

```json
{
  "customer": {
    "kind": "taxpayer",
    "name": "Distribuidora del Norte, S.A.",
    "rtn": "05019005123456"
  },
  "items": [
    { "description": "Cemento gris bolsa 42.5 kg", "quantity": 20,
      "unit_price": "235.00", "discount": "200.00", "treatment": "gravado_15" },
    { "description": "Cerveza nacional caja 24 unidades", "quantity": 3,
      "unit_price": "480.00", "treatment": "gravado_18" },
    { "description": "Medicamento esencial", "quantity": 10,
      "unit_price": "12.50", "treatment": "exento" }
  ]
}
```

```
invoicehn issue -f venta.json
```

### Notas de Crédito y de Débito desde un archivo

Cada tipo de documento lleva su propio identificador, su propio contador y su
propia autorización del SAR (Art. 59: *"La autorización será por punto de
emisión y por tipo de documento"*). Registre primero el CAI de las notas:

```
invoicehn auth add --cai "..." --from "000-001-06-00000001" \
  --to "000-001-06-00000500" --limit "2027-06-30"
```

El archivo es el de una venta más `reference` (el correlativo de la factura a
la que se aplica) y `motivo`:

```json
{
  "customer": { "kind": "taxpayer", "name": "Distribuidora del Norte, S.A.",
                "rtn": "05019005123456" },
  "items": [{ "description": "Devolución: cemento gris bolsa 42.5 kg",
              "quantity": 2, "unit_price": "235.00", "treatment": "gravado_15" }],
  "reference": "000-001-01-00000001",
  "motivo": "Devolución de 2 bolsas dañadas"
}
```

```
invoicehn issue -f nota.json --identifier 000-001-06   # Nota de Crédito
invoicehn issue -f nota.json --identifier 000-001-07   # Nota de Débito
```

Si la factura se emitió fuera de esta instalación, `reference` puede ser un
objeto con sus tres datos: `{"correlative": "...", "cai": "...", "issue_date": "AAAA-MM-DD"}`.

### 4. Consultar, anular, exportar

```
invoicehn show 000-001-01-00000001            # texto
invoicehn show 000-001-01-00000001 -f json    # JSON
invoicehn pdf 000-001-01-00000001 -o f.pdf
invoicehn list --from 2026-01-01 --to 2026-12-31
invoicehn annul 000-001-01-00000002 -r "Error en la cantidad"
invoicehn export --format csv -o ventas.csv   # Art. 53 num. 5
invoicehn check
```

### Idioma

La interfaz está en español por defecto y en inglés con `--lang en` o
`INVOICEHN_LANG=en`. **El documento fiscal siempre se emite en español**: sus
leyendas ("FACTURA", "Original: Cliente", "CONSUMIDOR FINAL", "ANULADA") son
texto legal fijado por el Reglamento, no texto de interfaz, y viven como
constantes fuera del catálogo de traducciones.

---

## Uso como biblioteca

```ruby
require "invoicehn"

emisor = Invoicehn::Issuer.new(
  rtn: "08011990123456",
  legal_name: "Comercial Ejemplo, S. de R.L.",
  trade_name: "Ferretería Ejemplo",
  headquarters_address: "Col. Palmira, Tegucigalpa M.D.C.",
  phone: "2222-3333",
  email: "facturacion@ejemplo.hn"
)

autorizacion = Invoicehn::Authorization.new(
  cai: "ABCD12-345678-9ABCDE-F01234-567890-AB",
  range_start: "000-001-01-00000001",
  range_end: "000-001-01-00000500",
  limit_date: Date.new(2027, 6, 30)
)

factura = Invoicehn::Invoice.new(
  correlative: "000-001-01-00000042",
  issuer: emisor,
  customer: Invoicehn::Customer::ConsumidorFinal.new,
  authorization: autorizacion,
  line_items: [
    Invoicehn::LineItem.new(
      description: "Servicio de consultoría",
      quantity: 2,
      unit_price: Invoicehn::Money.new("1500.00"),
      treatment: :gravado_15
    )
  ]
)

factura.validate!                        # lanza ComplianceError con la lista
puts factura.total                       # => L 3,450.00
puts factura.total_in_words              # => TRES MIL CUATROCIENTOS ... CON 00/100
puts Invoicehn::Renderers::Text.new(factura).render
```

Para emitir con numeración y persistencia, use el servicio:

```ruby
issuance = Invoicehn::Issuance.new
factura = issuance.issue(customer: cliente, line_items: lineas)
```

### Notas de Crédito y de Débito

```ruby
# Nota de Crédito (tipo 06) — devoluciones, descuentos posteriores, anulación
# de operaciones (Art. 4 num. 32).
nc = issuance.issue_credit_note(
  reference: "000-001-01-00000042",           # factura en el store: CAI y fecha se copian
  motivo: "Devolución de 2 bolsas dañadas",   # Art. 26 num. 4
  customer: cliente,                          # con RTN: Art. 26 num. 1-2
  line_items: lineas_devueltas
)

# Nota de Débito (tipo 07) — ajustes a cargo del adquirente (Art. 4 num. 31).
nd = issuance.issue_debit_note(
  reference: Invoicehn::DocumentReference.new( # documento emitido fuera del store
    correlative: "000-001-01-00009999",
    cai: "ABCD12-345678-9ABCDE-F01234-567890-AB",
    issue_date: Date.new(2026, 9, 1)
  ),
  motivo: "Flete adicional",
  customer: cliente,
  line_items: lineas
)
```

Las firmas exactas:

```ruby
Invoicehn::Issuance#issue(customer:, line_items:, identifier: "000-001-01",
                          currency: "HNL", exchange_rate: nil, notes: nil,
                          issue_date: Invoicehn.today, reference: nil, motivo: nil)
Invoicehn::Issuance#issue_credit_note(reference:, motivo:, customer:, line_items:,
                                      identifier: "000-001-06", **opciones_de_issue)
Invoicehn::Issuance#issue_debit_note(reference:, motivo:, customer:, line_items:,
                                     identifier: "000-001-07", **opciones_de_issue)
Invoicehn::Issuance#annul(correlative, reason:, on: Invoicehn.today)  # Factura o nota
Invoicehn::DocumentReference.new(correlative:, cai:, issue_date:)
```

El **tipo de documento lo decide el identificador**: `NNN-NNN-01` Factura,
`NNN-NNN-06` Nota de Crédito, `NNN-NNN-07` Nota de Débito. `issue` con un
identificador `-06`/`-07` y `reference:`/`motivo:` es equivalente a los dos
atajos. `reference:` acepta:

- un correlativo (`String` o `Correlative`) de un documento que el store tiene:
  se busca y se copian su CAI y su fecha de emisión;
- un `DocumentReference` con los tres datos (Arts. 26 y 28 num. 3), para un
  documento emitido fuera del store. Si el store sí lo tiene, los datos se
  cotejan y una discrepancia se rechaza.

Cuando el original está en el store, además se rechaza la nota si el original
está ANULADO o si su adquirente tiene otro RTN. Esas dos verificaciones son de
coherencia, no texto del Reglamento.

### El reloj: la fecha de Honduras, no la del servidor

Honduras está en UTC-6 todo el año. Un servidor en UTC que leyera `Date.today`
estamparía, desde las 18:00 de Tegucigalpa, la fecha de **mañana** como fecha de
emisión, y daría por vencida una autorización horas antes de su fecha límite
(Art. 62). Todas las fechas por defecto de la gema (emisión, anulación,
validación, `health`, vigencia de la autorización) salen de `Invoicehn.today`:

```ruby
# config/initializers/invoicehn.rb, con config.time_zone = "America/Tegucigalpa"
Invoicehn.configure { |c| c.today = -> { Date.current } }
```

Sin configurar, el reloj es `Date.today` (la zona del proceso), como en la
0.1.0. El reloj debe devolver un `Date`; un `Time` o un `DateTime` se rechazan.

---

## Decisiones que conviene conocer

### El redondeo es estatutario, y equivocarse es delito

**Ley del Impuesto Sobre Ventas (Decreto-Ley 24), Artículo 9**, redactado por el
Decreto 135-94:

> Cuando al calcular dicho gravamen, resulte una fracción menor de 0.005 de
> Lempira, deberá reducirse el recargo hasta la cifra de centavos próxima
> inferior, en cambio, si la fracción citada es igual o mayor de 0.005 de
> Lempira, entonces podrá subirse el cómputo hasta la cifra de centavos próxima
> superior. **El recargo del impuesto al consumidor fuera de la regla establecida
> en el párrafo anterior, se considerará como hurto.**

Por eso todo importe es `BigDecimal` y **`Float` está prohibido** en el camino
del dinero: `Money.new(10.5)` lanza una excepción. Una prueba recorre el código
fuente y falla si aparece `Float` o `to_f` fuera de su propio rechazo.

### El ISV se calcula sobre el subtotal de cada tarifa

El Art. 11 num. 1 literales h) e i) exigen mostrar *subtotales por tarifa* y
*impuestos por tarifa*. Redondear línea por línea y sumar puede producir un total
de ISV que no coincida con la tarifa aplicada al subtotal impreso — justo la
discrepancia que un auditor cuestionaría. La norma no resuelve el punto (el
Art. 9 de la Ley del ISV habla del recargo "sobre el precio del artículo vendido
o servicio prestado", que se lee por ítem), así que la lectura elegida está
documentada en el código y cubierta por pruebas.

### Los descuentos reducen la base gravable

**Ley del ISV, Artículo 3**: *"No forman parte de la base gravable los descuentos
efectivos que consten en la factura o documento equivalente, siempre que resulten
normales según la costumbre comercial."* Mostrar el descuento pero gravar el valor
bruto le cobraría de más al cliente.

La línea de descuentos aparece siempre, con o sin descuento: el Acuerdo 725-2018
la agregó como **Art. 10 num. 10** ("Descuentos y rebajas otorgados"), es decir
como requisito **del formato**, además de los literales l) y j) del Art. 11.

### El CAI y el RTN se validan con prudencia

El Art. 4 num. 7 define el CAI únicamente como *"una serie alfanumérica generada
electrónicamente"*. Ninguna norma fija su longitud ni su agrupación, y el SAR no
publica un formato. Se almacena e imprime **tal cual**.

El RTN son 14 dígitos, para personas naturales y jurídicas. **No existe un dígito
verificador documentado públicamente**: la palabra "dígito" no aparece en el
Código Tributario, el Acuerdo 481-2017 exige el RTN sin especificar su
estructura, y el SAR no publica algoritmo alguno. Validar contra un esquema
adivinado — un módulo 11 tomado del RUT chileno o del RFC mexicano — rechazaría
RTN reales. Se valida longitud y dígitos, nada más.

### La numeración no se reutiliza ni se salta

El asignador se lleva por la terna (establecimiento, punto de emisión, tipo de
documento) — el *identificador del documento* del Art. 10 num. 7 — y trabaja bajo
un candado exclusivo de archivo, de modo que dos procesos simultáneos no pueden
repetir ni omitir un número. La asignación, el guardado y el asiento contable
ocurren dentro del mismo candado y son todo o nada: si el guardado falla, el
correlativo no se consume; si el libro contable rechaza el asiento, el documento
recién guardado se borra antes de que avance el contador. (La 0.1.0 dejaba el
documento en disco y el contador atrás, y toda emisión posterior fallaba.)

Un documento emitido es inmutable. La única corrección es la anulación
(Art. 41), que marca el registro con la leyenda **ANULADA** y **conserva el
correlativo consumido**.

### Los códigos de tipo de documento son los reformados

El Acuerdo 609-2017 (*La Gaceta* 34,457) reescribió el literal c) de los
artículos de cada documento. La tabla vigente, según el texto consolidado:

| Código | Documento | Artículo |
|---|---|---|
| 01 | Factura | 10 num. 7 lit. c |
| 04 | Recibo por Honorarios Profesionales | 18 num. 7 lit. c (no reformado) |
| 05 | Comprobante de Retención | 33 num. 5 lit. c |
| 06 | **Nota de Crédito** | 25 num. 5 lit. c |
| 07 | **Nota de Débito** | 27 num. 5 lit. c |
| 08 | Guía de Remisión | 29 num. 4 lit. c |
| 09 | Ticket | 17 num. 4 lit. a |
| 10 | Factura Prevalorada | 15 num. 6 lit. c |
| 11 | Boleta de Compra | 20 num. 5 lit. c |
| 12 | Constancia de Donación | 23 num. 7 lit. c |

El texto original de 2017 numeraba distinto (02 Prevalorada, 03 Ticket, 07 Nota
de Crédito, 08 Nota de Débito, 10 Retención...). La 0.1.0 traía esa tabla; la
0.2.0 la corrige. 02 y 03 quedaron sin asignar y se rechazan. La gema **emite**
01, 06 y 07; los demás códigos se reconocen (para validar referencias) pero no
se emiten.

### Las notas exigen el RTN del adquirente y se emiten en lempiras

Los Arts. 26 y 28 num. 1-2 piden *"Nombres y Apellidos, Razón o Denominación
Social del adquirente"* y *"Número de Registro Tributario Nacional (RTN) del
adquirente"*. A diferencia del Art. 11 num. 2 para la Factura, no ofrecen la
alternativa de CONSUMIDOR FINAL: una nota a un adquirente sin RTN se rechaza.

Los Arts. 26 num. 9 y 28 num. 8 piden la *"Denominación literal de la Moneda
Nacional Lempira o símbolo (L)"*. El permiso de emitir en *"otra denominación
monetaria"* con la tasa de cambio está en el párrafo final del Art. 11 y habla
sólo de *facturas*; los artículos de las notas no tienen ese párrafo. Una nota
en otra moneda se rechaza.

La Nota de Crédito debe aplicarse a un **Comprobante Fiscal** (Art. 4 num. 32,
Art. 26 num. 3 lit. b; la lista está en el Art. 6). La Nota de Débito admite
*"el Comprobante Fiscal o el documento"* (Art. 28 num. 3 lit. b). Ninguno de
los artículos fija un monto máximo para la nota, y la gema no inventa uno.

La Nota de Crédito imprime en blanco los campos de quien la recibe (nombres,
identidad y firma, Art. 26 num. 7), que se llenan a mano al entregarla.

### La fecha de emisión es la del sistema

No hay bandera para retrofechar. El Art. 43 obliga a custodiar los documentos en
orden cronológico, y un libro cuya numeración no concuerde con sus fechas es lo
primero que una auditoría cuestiona.

### La tasa del 18% está redactada de forma ambigua

El Decreto 278-2013 Art. 16 fija la tasa general en 15% y en 18% la de *"las
bebidas alcohólicas, cerveza y cigarrillos al igual que los boletos aéreos de
clase ejecutiva"*. La enumeración del Art. 6 que reforma agrega *"otros productos
elaborados de tabaco"*, y las guías tributarias incluyen además primera clase.
Decidir si un producto concreto califica es del obligado tributario; la gema
calcula una vez tomada esa decisión.

### Lo que NO es obligatorio, pese a lo que se repite

La leyenda **"La factura es beneficio de todos, exíjala"** **no** está exigida por
ninguna norma. Se verificó su ausencia en el texto completo del Acuerdo 481-2017,
en su texto consolidado y en su antecesor el Acuerdo 189-2014. Se admite como
texto opcional, nunca como regla de cumplimiento.

Las leyendas que sí exige el Reglamento son `CONSUMIDOR FINAL` (Art. 11 num. 2
lit. a), `ANULADA` (Art. 41) y el destino de los ejemplares (Art. 10 num. 6).

---

## Matriz de cumplimiento

Cada fila corresponde a pruebas automatizadas.

| Artículo | Requisito | Implementado en |
|---|---|---|
| 10 num. 1 | Datos de identificación del emisor | `Issuer` |
| 10 num. 2 | Denominación "Factura" | `Renderers::Text`, `Renderers::Pdf` |
| 10 num. 3-5 | CAI, fecha límite y rango vigentes | `Authorization` |
| 10 num. 6 | Destino de los ejemplares | `Renderers::Text` |
| 10 num. 7 | Correlativo de 16 dígitos; códigos reformados por el 609-2017 | `Correlative` |
| 10 num. 8 | Datos del adquirente exonerado | `Customer::Exonerado` |
| 10 num. 10 | Descuentos y rebajas (formato) | `Renderers::Text` |
| 11 num. 1 | Requisitos para crédito fiscal | `Compliance::Validator` |
| 11 num. 1 g-i | Discriminación por tratamiento y tarifa | `TaxSummary` |
| 11 num. 1 k | Importe total en números y letras | `SpanishNumerals` |
| 11 num. 1 l / 2 j | Discriminación de descuentos | `LineItem`, `TaxSummary` |
| 11 num. 2 | CONSUMIDOR FINAL; datos sobre L 10,000.00 | `Customer::ConsumidorFinal` |
| 11 num. 3 | Crédito fiscal sólo por ventas gravadas | `TaxSummary#credito_fiscal_base` |
| 11 párrafo final | Tasa de cambio a la fecha de emisión | `ExchangeRate` |
| 12 | Exportaciones con tasa cero | `TaxTreatment::GRAVADO_0` |
| 25 num. 2, 7 / 27 num. 2, 7 | "Nota de Crédito" / "Nota de Débito"; destino de los ejemplares | `Renderers::Text`, `Renderers::Pdf` |
| 25 num. 5 / 27 num. 5 | Códigos 06 y 07, serie propia | `Correlative`, `Sequence` |
| 26 num. 1-2 / 28 num. 1-2 | Nombre y RTN del adquirente | `Compliance::Validator` |
| 26 num. 3 / 28 num. 3 | CAI, correlativo y fecha del comprobante | `DocumentReference` |
| 26 num. 4 / 28 num. 4 | Motivo de la emisión | `Invoice#motivo` |
| 26 num. 7 | Datos y firma de quien recibe la NC | `Renderers::Text`, `Renderers::Pdf` |
| 26 num. 9 / 28 num. 8 | Moneda Nacional Lempira | `Compliance::Validator` |
| 41 | Leyenda ANULADA; correlativo conservado | `Invoice#annul` |
| 42 | Aviso de autorizaciones vencidas sin usar | `invoicehn check` |
| 43 | Custodia cronológica | `Storage::JsonStore` |
| 53 num. 1 | Integración contable o de inventarios | `Ledger` |
| 53 num. 5 | Exportación en archivos de texto | `invoicehn export` |
| 62 | La autorización vencida bloquea la emisión | `Authorization#expired?` |
| ISV Art. 3 | Los descuentos no forman base gravable | `LineItem#taxable_base` |
| ISV Art. 9 | Redondeo a centavos, medio hacia arriba | `Money#round_statutory` |

### Art. 9 del Reglamento: por qué no hay consolidación de fin de día

El Art. 9 permite no extender comprobante en el acto para ventas a consumidores
finales que no excedan L 50.00. Ese alivio **no aplica** a los autoimpresores por
máquina registradora ni por sistema computarizado — y esta gema es un sistema
computarizado. Por eso emite siempre un documento por venta: la ausencia de esa
función es deliberada.

---

## Integración contable (Art. 53 num. 1)

El Art. 53 num. 1 condiciona la autorización como autoimpresor a que el sistema
de facturación esté integrado al menos a un sistema contable o de inventarios.
`Invoicehn::Ledger` es esa interfaz; la gema incluye una implementación en JSONL
que cumple el requisito por sí sola.

```ruby
class MiContabilidad < Invoicehn::Ledger
  def record(invoice, event: :emision)
    MiERP::Asiento.crear!(invoice.to_h)
    invoice
  end

  def entries(from: nil, to: nil) = MiERP::Asiento.entre(from, to)
end

Invoicehn::Issuance.new(
  ledger: Invoicehn::Ledger::Multi.new(
    Invoicehn::Ledger::JsonlLedger.new,
    MiContabilidad.new
  )
)
```

---

## Integración con la aplicación anfitriona: store, sequence y ledger

`Invoicehn::Issuance.new(store:, sequence:, ledger:)` acepta cualquier objeto
que responda a los métodos de abajo (*duck typing*); la gema no depende de
Rails ni de ActiveRecord. Cuando se inyectan los tres, `Issuance` no toca el
sistema de archivos: no construye `Config` ni lee `~/.invoicehn`.

### store

| Método | Contrato |
|---|---|
| `issuer` → `Issuer` o `nil` | El emisor con los siete datos del Art. 10 num. 1. |
| `authorizations_for(identifier)` → `Array<Authorization>` | Todas las autorizaciones de ese `NNN-NNN-TT`, vencidas incluidas. |
| `active_authorization(identifier, next_sequence:, on:)` → `Authorization` o `nil` | Una autorización no vencida en `on` cuyo rango **cubra** `next_sequence` (la de menor inicio si hay varias). `nil` si ninguna lo cubre; no devolver una agotada. Con `next_sequence: nil`, la vigente de menor inicio. |
| `save_document(document)` → `document` | Guarda el documento (`document.to_h` es su forma serializable). Si ya existe y el nuevo **no** está anulado, lanza `Invoicehn::ImmutableDocument`; la forma anulada reemplaza a la emitida (Art. 41). |
| `delete_document(document)` → `document` | Borra el documento. `Issuance` lo llama **sólo** para deshacer una emisión cuyo asiento contable falló, dentro del bloque de `allocate`. |
| `find(correlative)` → `Invoice` | El documento con ese correlativo (`String` o `Correlative`); `Invoicehn::DocumentNotFound` si no existe. `find(c).to_h` debe ser igual a lo guardado, incluidos `reference` y `motivo` de las notas. |
| `exists?(correlative)` → `Boolean` | |

La CLI usa además `save_issuer`, `authorizations`, `add_authorization`, `all(from:, to:)`, `settings` y `save_settings`; una aplicación que no use la CLI no los necesita.

### sequence

| Método | Contrato |
|---|---|
| `allocate(identifier) { \|correlative\| ... }` → valor del bloque | Calcula el siguiente correlativo, lo entrega al bloque **bajo candado** (en Postgres: `SELECT ... FOR UPDATE` dentro de una transacción) y avanza el contador **sólo si el bloque termina sin excepción**. Si el bloque lanza, el contador queda igual y la excepción se propaga. |
| `peek(identifier)` → `Correlative` | El próximo correlativo, sin consumirlo. |
| `issued_count(identifier)` → `Integer` | La última secuencia consumida (0 si ninguna). |

Cada identificador (`000-001-01`, `000-001-06`, `000-001-07`...) es una serie
independiente que empieza en 00000001.

### ledger

| Método | Contrato |
|---|---|
| `record(document, event:)` → cualquier cosa | Asienta la emisión (`event: :emision`) o la anulación (`event: :anulacion`). Si lanza, `Issuance` borra el documento recién guardado y el correlativo no se consume. |

`entries(from:, to:)` sólo lo usa la exportación de la CLI. `Ledger::Multi`
reparte a varios libros, pero no puede deshacer el asiento de uno si el
siguiente falla: un libro transaccional debería participar en la transacción
de la aplicación.

Si la aplicación envuelve la emisión en una transacción de base de datos
(recomendado), cualquier fallo revierte también el contador y el documento.

### Verificar los adaptadores

```ruby
require "invoicehn/test_support/contracts"

class InvoicehnStoreContractTest < ActiveSupport::TestCase
  include Invoicehn::TestSupport::StoreContract
  # Un store con emisor completo y autorización vigente para 000-001-01
  # (y, opcionalmente, para 000-001-06 para probar las notas).
  def contract_store = Facturacion::InvoicehnStore.new
end

class InvoicehnSequenceContractTest < ActiveSupport::TestCase
  include Invoicehn::TestSupport::SequenceContract
  def contract_sequence = Facturacion::InvoicehnSequence.new
end

class InvoicehnLedgerContractTest < ActiveSupport::TestCase
  include Invoicehn::TestSupport::LedgerContract
  def contract_ledger = Facturacion::InvoicehnLedger.new
end

class InvoicehnIssuanceContractTest < ActiveSupport::TestCase
  include Invoicehn::TestSupport::IssuanceContract   # emite una factura real
  def contract_store = Facturacion::InvoicehnStore.new
  def contract_sequence = Facturacion::InvoicehnSequence.new
  def contract_ledger = Facturacion::InvoicehnLedger.new
end
```

`IssuanceContract` emite primero con un libro que rechaza el asiento y verifica
que no quede documento ni avance el contador; luego emite de verdad y verifica
que `find` devuelva lo emitido. Fuera de minitest, las mismas verificaciones
están en `require "invoicehn/testing"` (`Invoicehn::Testing.assert_store_contract`,
`assert_sequence_contract`, `assert_ledger_contract`, `assert_issuance_round_trip`),
que lanzan `Invoicehn::Testing::ContractError`. `invoicehn/test_support/memory`
trae adaptadores en memoria: la implementación completa más corta del contrato,
útil como modelo.

La CLI (`thor`, `tty-prompt`) y el PDF (`prawn`) no se cargan con
`require "invoicehn"`: una aplicación Rails los instala como dependencias de la
gema, pero no los carga si no los usa.

## Almacenamiento

Por defecto en `~/.invoicehn` (configurable con `INVOICEHN_HOME` o `--data-dir`):

```
~/.invoicehn/
├── issuer.json           # datos del emisor
├── authorizations.json   # los CAI registrados
├── sequences.json        # contadores por identificador
├── ledger.jsonl          # libro append-only
└── documentos/AAAA/MM/000-001-01-00000001.json
```

Archivos JSON planos, legibles sin esta gema — algo que importa en registros que
deben sobrevivir al software que los escribió.

---

## Fuentes

Textos primarios, por número de *La Gaceta*:

| Gaceta | Norma |
|---|---|
| 34,413 | Acuerdo 481-2017 (original) |
| 34,457 | Acuerdo 609-2017 (primera reforma) |
| 34,792 | Acuerdo 725-2018 (segunda reforma — agrega los descuentos) |
| 34,811 | Acuerdo 817-2018 (tercera reforma) |

El Acuerdo 609-2017 es el que cambió los códigos de tipo de documento; las
notas siguen los Arts. 25-28 del texto consolidado
(`doc/fuentes/acuerdo_481_2017_consolidado.txt`, líneas 1300-1497).
| 33,316 | Decreto 278-2013 (tasas del ISV) |

Más la Ley del Impuesto Sobre Ventas (Decreto-Ley 24, Arts. 3 y 9) y el Código
Tributario (Decreto 170-2016, Art. 66). Los PDF y las extracciones están en
`doc/fuentes/`.

> Dos trampas encontradas al investigar, por si le ahorran tiempo: la copia de la
> Ley del ISV que publica el TSC es una consolidación que se detiene en el
> Decreto 171-98 y todavía muestra 12%/15% — no sirve para citar tasas, aunque sí
> es buena fuente del Art. 9. Y el texto de 2017 del Acuerdo 481-2017 fue
> reformado tres veces: hay que trabajar sobre el *texto consolidado* del SAR.

---

## Desarrollo

```
bundle install
bundle exec rake        # pruebas y linter
bundle exec rake test
bundle exec rake rubocop
```

### Publicar una versión

Un número de versión publicado en RubyGems **no se puede reutilizar**: `gem yank`
retira el paquete pero deja el número quemado para siempre. Por eso `rake build`
y `rake release` ejecutan las pruebas y el linter antes de hacer nada.

```
gem signin                      # una sola vez por máquina; requiere MFA
# subir la versión en lib/invoicehn/version.rb
# anotar los cambios en CHANGELOG.md
bundle exec rake release        # etiqueta vX.Y.Z, la sube y publica la gema
```

`rake release` se niega a continuar si el árbol de trabajo tiene cambios sin
confirmar o si la etiqueta ya existe.

## Licencia

MIT. El texto de la licencia incluye la exención de garantías habitual: esta
gema ayuda a cumplir los requisitos de contenido del Reglamento, pero la
responsabilidad tributaria sigue siendo del obligado tributario.
