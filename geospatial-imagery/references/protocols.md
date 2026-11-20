# Imagery protocols and tile matrices

## WMS and WCS

WMS `GetMap` returns a rendered image over a requested bounding box and
pixel size. Use the service's `GetCapabilities` to check layer names,
styles, supported CRSs, formats, dimensions, and operation URLs. Send
`SERVICE`, `REQUEST`, `VERSION`, `LAYERS`, `STYLES`, `BBOX`, `WIDTH`,
`HEIGHT`, `FORMAT`, and the version-specific CRS parameter for a
standards-based KVP request. An empty `STYLES` requests default styling.
Inspect the content type and exception payload before treating a
response as an image.

For the geographic extent west 12°, south 45°, east 13°, north 47°:

| WMS request | Spatial parameters |
|---|---|
| 1.1.1 with EPSG:4326 | `SRS=EPSG:4326&BBOX=12,45,13,47` |
| 1.3.0 with EPSG:4326 | `CRS=EPSG:4326&BBOX=45,12,47,13` |
| 1.3.0 with CRS:84, when advertised | `CRS=CRS:84&BBOX=12,45,13,47` |

WMS 1.3.0 uses the CRS axis order. Determine it for the selected CRS.
For optional `GetFeatureInfo`, use `X,Y` in 1.1.1 and `I,J` in 1.3.0,
with the corresponding `GetMap` window and the advertised queryable layers
and response formats. [OGC WMS](https://www.ogc.org/standards/wms/),
[GeoServer WMS version behavior](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/doc/en/user/services/wms/basics.md).

WCS serves coverage values. For WCS 2.x, use `GetCapabilities` and
`DescribeCoverage` to discover coverage identifiers, domain axes, and
supported extensions. Build `GetCoverage` with the service version and
`COVERAGEID`. Repeat `SUBSET` for each axis, using the advertised axis
labels and units. For example, `SUBSET=E(500000,501000)` trims the
`E` axis of a coverage that declares that label in metres. Check support
for alternate CRS, format, scaling, or range subsetting in the relevant
extension. [OGC WCS](https://www.ogc.org/standards/wcs/).

## WMTS 1.0.0 and OGC API Tiles

- WMTS `GetTile` KVP requests identify the layer, style, format,
  `TileMatrixSet`, `TileMatrix`, `TileRow`, and `TileCol`. Use the
  advertised endpoint or `ResourceURL` template and dimension values.
  Matrix IDs are strings and may include prefixes. WMTS rows increase
  downward from the matrix's advertised `TopLeftCorner`.
- OGC API Tiles exposes tileset links and tileset metadata. Use the
  advertised links/templates, media types, Tile Matrix Set, and conformance
  classes for the desired data or map tileset. A common tile path suffix is
  `/{tileMatrix}/{tileRow}/{tileCol}`. Follow the advertised path.
- Use matrix metadata for the CRS, axis order, origin, tile dimensions,
  cell size, matrix dimensions, and any limits. In WMTS derive cell size from
  scale denominator × 0.00028 m per pixel ÷ metres per CRS unit, with the
  standard's conversion for angular units. OGC Tile Matrix Set 2.0 also
  publishes `cellSize` and can declare a bottom-left origin or variable
  matrix widths. Honor these when targeting a grid that declares them.
  Validate both matrix bounds and layer-specific limits.

[OGC WMTS](https://www.ogc.org/standards/wmts/),
[OGC API Tiles 1.0](https://docs.ogc.org/is/20-057/20-057.html),
[OGC Tile Matrix Set 2.0](https://docs.ogc.org/is/17-083r4/17-083r4.html).

## XYZ and legacy Tile Map Service

The common Web Mercator XYZ profile uses a square `2^z × 2^z` matrix with
rows increasing southward. Clamp latitude to approximately ±85.05112878°
for this profile. Define a policy for longitude at the antimeridian and
split a crossing extent when querying an index that expects ordinary
west-to-east intervals. Other grids can have a different root size, extent,
resolution sequence, or origin.

The legacy Tile Map Service 1.0 uses rows increasing northward and can
publish `TileMapService` and `TileMap` XML for discovery. For aligned
top-down and bottom-up versions of the same matrix,
`row_from_bottom = matrix_height - 1 - row_from_top`. If the matrix
height is 3, its top row 0 is bottom-up row 2. Use the full matrix
height, including when layer coverage contains only a subset of its rows.
[Legacy Tile Map Service 1.0](https://wiki.osgeo.org/wiki/Tile_Map_Service_Specification),
[GeoWebCache WMTS row conversion](https://github.com/GeoWebCache/geowebcache/blob/da254e37117d409d4f13c356a2d542c314978f21/geowebcache/wmts/src/main/java/org/geowebcache/service/wmts/WMTSService.java#L467-L526).

For a uniform top-left grid in internal east/north order, set
`span_x = tile_width * cell_size` and `span_y = tile_height * cell_size`.
The tile's west and north edges are
`west = origin_x + col * span_x` and
`north = origin_y - row * span_y`. East is `west + span_x` and south is
`north - span_y`. Apply the protocol's axis order at its boundary. Test
edges and the valid index range before evaluating the transform.
