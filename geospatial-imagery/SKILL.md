---
name: geospatial-imagery
description: >-
  Guides georeferenced raster imagery work, including inspecting, converting,
  reprojecting, and mosaicking GeoTIFF, COG, NITF, or other rasters with GDAL.
  Applies to building or debugging imagery services and clients using WMS,
  WMTS, WCS, OGC API Tiles, XYZ, TMS, GeoServer, or Google Earth Enterprise.
  Also covers imagery storage, discovery, rendering performance, and
  satellite or aerial raster workflows in Earth Engine.
---

# Geospatial imagery

Start with the intended product. A rendered map needs display bands, styling, and
transparency. A coverage needs sample values, units, validity, and georeferencing.
A pre-rendered tile also needs a precise tile matrix and row convention.

- Inspect the actual input with `gdalinfo -json` or the format reader. Confirm
  the CRS, affine transform or sensor model, band types and roles, masks,
  nodata, overviews, and any sidecars or subdatasets that affect interpretation.
- Establish the target grid and resampling policy before conversion. Decide
  which source wins overlaps, how invalid pixels participate, and which
  sample values or metadata must survive. Use a categorical resampler for
  classes and choose a continuous-data kernel based on the intended use.
- For services and clients, record the protocol version, CRS and wire axis
  order, tile matrix identifiers, origin, dimensions, and advertised limits.
  Test with an asymmetric extent or a tile whose north and south differ.
- Use the specification for wire and file contracts. Check source and tests
  for the deployed release when relying on implementation behavior, driver
  options, or compatibility quirks. Record the version, options, and fixture
  used when a result depends on them.
- Verify the output at the consumer boundary. Compare placement, values,
  masks, and overlap or edge behavior. For a service, issue requests against
  the advertised metadata. For a COG, validate the layout and, when serving
  it remotely, check range responses separately.

## References

| Task | Read |
|---|---|
| Identify an input format, select a codec, or interpret georeferencing and masks | [Formats](references/formats.md) |
| Inspect, convert, warp, mosaic, validate a COG, or generate tiles with GDAL | [GDAL](references/gdal.md) |
| Implement or debug WMS, WMTS, WCS, OGC API Tiles, XYZ, or TMS | [Protocols and tile matrices](references/protocols.md) |
| Trace GeoServer catalog, WMS rendering, ImageMosaic, or GeoWebCache | [GeoServer](references/geoserver.md) |
| Connect CesiumJS, OpenLayers, or Leaflet to an imagery service | [Map clients](references/clients.md) |
| Design or implement an imagery tile endpoint, renderer, or cache | [Tile servers](references/tile-servers.md) |
| Trace a source window through reprojection, overviews, and COG range reads | [Tiling pipeline](references/tiling-pipeline.md) |
| Measure or tune ingest, rendering, or delivery | [Performance](references/performance.md) |
| Select an imagery fixture or assess a satellite or aerial data product | [Imagery sources](references/sources.md) |
| Select a footprint index, tile archive, or inspect Earth Enterprise GEIndex and FileBundle | [Indexing](references/indexing.md) |
| Analyze or export imagery with the Google Earth Engine API | [Earth Engine](references/earth-engine.md) |
