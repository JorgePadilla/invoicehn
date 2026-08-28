# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [Sin publicar]

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

[Sin publicar]: https://github.com/JorgePadilla/invoicehn/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JorgePadilla/invoicehn/releases/tag/v0.1.0
