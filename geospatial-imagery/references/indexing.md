# Imagery indexes and archives

## Choose the index for the lookup

| Lookup | Approach |
|---|---|
| Find granules that intersect a request and match its time or other dimensions | Index footprints and query by extent plus properties. A static packed spatial index can suit a published snapshot. Use a database when the index needs frequent updates or richer queries. |
| Fetch a rendered tile from a known grid | Use its matrix, column, row, and render variant as the lookup key. A directory, object store, or tile archive can store the bytes. |
| Discover acquisitions and data assets | Publish STAC Items and Collections. Use a STAC API with Item Search for interactive spatial or temporal queries when supported. |
| Read a source raster window | Use the raster reader's own block/overview layout after finding the source asset. |

For PostGIS, add a GiST index on the footprint geometry and use
`ST_Intersects(footprint, query_geometry)` in a common SRID. It can use the
bounding-box index as a prefilter before checking intersection. Inspect
the query plan with representative extents and temporal filters.
Transform the query geometry to the indexed CRS where practical.
Apply a deterministic secondary sort and priority before compositing.
[PostGIS ST_Intersects](https://postgis.net/docs/ST_Intersects.html).

When present, STAC Item geometry and bbox describe a footprint in WGS 84
longitude and latitude. Check the asset's own CRS, resolution, and validity
before rendering it. Use the document's `stac_version` for parsing and
the API's advertised conformance classes when building queries.
[STAC Item 1.1.0](https://github.com/radiantearth/stac-spec/blob/v1.1.0/item-spec/item-spec.md),
[STAC API 1.0.0](https://github.com/radiantearth/stac-api-spec/tree/v1.0.0),
[pinned PySTAC Item implementation](https://github.com/stac-utils/pystac/blob/f7b676b56b60e15553f56bd0080c090bb5060c01/core/pystac/item.py).

## Tile archives

- **MBTiles 1.3** uses SQLite with Web Mercator tile data and
  bottom-origin `tile_row`. The logical `tiles` relation can be a view.
  For an XYZ request on the same global grid, `tile_row = (1 << z) - 1 - y`
  after validating the zoom and indices. For example, XYZ `4/3/5`
  maps to `zoom_level=4, tile_column=3, tile_row=10`. Metadata
  `bounds` uses longitude and latitude. Check the declared tile format.
  [MBTiles 1.3](https://github.com/mapbox/mbtiles-spec/blob/master/1.3/spec.md).
- **GeoPackage** records the CRS and grid bounds in `gpkg_tile_matrix_set`
  and the matrix dimensions and pixel sizes in `gpkg_tile_matrix`. Use
  top-origin rows for its tile pyramid. [GeoPackage 1.4](https://www.geopackage.org/spec140/index.html).
- **PMTiles v3** uses a single archive with a directory hierarchy and
  cumulative Hilbert tile IDs. Follow the specification for directory
  and tile compression, byte ranges, and tile ordering. Publish
  versioned archives for stable range reads.
  [PMTiles v3](https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md).

## Google Earth Enterprise GEIndex and FileBundle

Identify the database and request path first. OpenGEE's 2D flat and
Mercator map tilespaces and its 3D clients use different conventions.
Trace the deployed tilespace and server request before converting from
XYZ or a geographic tile matrix.
[Pinned tilespace definitions](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/khTileAddr.cpp),
[Fusion database request handler](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/server/mod_fdb/fusiondbservice.cpp).

1. In the pinned `QuadtreePath`, each level occupies two bits in
   the high part of a 64-bit value and the depth is stored in the
   low part. The representation supports up to 24 levels. The
   quadtree digits are 0 southwest, 1 southeast, 2 northeast, and
   3 northwest. Check row direction and any wire-format prefix
   separately from the packed representation.
2. GEIndex groups four quadtree levels per bucket. The entry bucket
   spans 85 slots across those levels. The child bucket addresses
   descendant buckets at the next four-level boundary. A reader walks
   bucket addresses to find the entry and may cache upper buckets.
   Match the entry type and key for the database being read.
3. The external data address names a packetfile and contains an offset
   and size. FileBundle maps a logical offset to a segment using the
   segment break from the bundle header. Check declared sizes,
   segment boundaries, and the CRC rules for the addressed record.
   FileBundle storage and wire packet encoding are separate contracts.

[Pinned QuadtreePath](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/quadtreepath.cpp#L31-L75),
[representation limits](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/quadtreepath.h),
[GEIndex bucket layout](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/geindex/shared.h),
[GEIndex reader](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/geindex/Reader.cpp),
[GEIndex data address](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/geindex/Entries.h),
[FileBundle reader and CRC](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/common/filebundle/filebundle.cpp),
[imagery protobuf schema](https://github.com/google/earthenterprise/blob/893f6b470673e2bad4cacdd8eec5ad1f179b6249/earth_enterprise/src/keyhole/proto/streaming_imagery.proto).

Test a known path in each quadrant, a lookup across a bucket boundary,
an absent entry, and an addressed packet in a later bundle segment.
For server compatibility, also compare the response to a request from
the target client.
