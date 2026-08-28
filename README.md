# invoicehn

Facturación para Honduras conforme al **Reglamento del Régimen de Facturación,
Otros Documentos Fiscales y Registro Fiscal de Imprentas** (Acuerdo No. 481-2017
y sus reformas). Biblioteca Ruby más una interfaz de terminal.

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
10 (requisitos del formato) y 11 (requisitos al momento de la emisión): el
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
repetir ni omitir un número. La asignación y el guardado ocurren dentro del mismo
candado: si el guardado falla, el correlativo no se consume.

Un documento emitido es inmutable. La única corrección es la anulación
(Art. 41), que marca el registro con la leyenda **ANULADA** y **conserva el
correlativo consumido**.

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
| 10 num. 2 | Denominación "Factura" | `Renderers::Text` |
| 10 num. 3-5 | CAI, fecha límite y rango vigentes | `Authorization` |
| 10 num. 6 | Destino de los ejemplares | `Renderers::Text` |
| 10 num. 7 | Correlativo de 16 dígitos | `Correlative` |
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
