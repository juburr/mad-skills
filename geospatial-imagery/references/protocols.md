# OGC Web Service Protocols Reference

## WMS (Web Map Service)

WMS returns rendered map images from geospatial data. The server composes images on-the-fly based on requested layers, styles, and extent.

### Versions

Two versions are in widespread use: **1.1.1** and **1.3.0**. Key differences:

| Feature | WMS 1.1.1 | WMS 1.3.0 |
|---|---|---|
| CRS parameter name | `SRS` | `CRS` |
| Axis order for EPSG:4326 | lon, lat | lat, lon |
| Feature info pixel params | `X`, `Y` | `I`, `J` |
| Default exception format | `application/vnd.ogc.se_xml` | `XML` |

The axis order change in 1.3.0 is the single most common source of bugs. In 1.3.0, geographic CRS codes (like EPSG:4326) use latitude-first axis order, matching the EPSG database definition. Use `CRS:84` in 1.3.0 to get longitude-first order while still using WGS84 datum.

### Operations

**GetCapabilities** -- Returns XML describing available layers, supported CRS, bounding boxes, styles, and formats.

```
GET /wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetCapabilities
```

**GetMap** -- Returns a rendered map image.

| Parameter | Required | Description | Example |
|---|---|---|---|
| `SERVICE` | Yes | Service type | `WMS` |
| `VERSION` | Yes | Protocol version | `1.3.0` |
| `REQUEST` | Yes | Operation name | `GetMap` |
| `LAYERS` | Yes | Comma-separated layer names | `topp:states,sf:roads` |
| `STYLES` | Yes | Comma-separated style names (empty = default) | `` (empty string) |
| `CRS` / `SRS` | Yes | Coordinate reference system (CRS in 1.3.0, SRS in 1.1.1) | `EPSG:4326` |
| `BBOX` | Yes | Bounding box: `minx,miny,maxx,maxy` | `-180,-90,180,90` |
| `WIDTH` | Yes | Image width in pixels | `800` |
| `HEIGHT` | Yes | Image height in pixels | `600` |
| `FORMAT` | Yes | Output image MIME type | `image/png` |
| `TRANSPARENT` | No | Background transparency | `TRUE` |
| `BGCOLOR` | No | Background color hex | `0xFFFFFF` |
| `TIME` | No | Temporal filter (ISO 8601) | `2024-01-15T00:00:00Z` |
| `ELEVATION` | No | Elevation value | `500` |
| `SLD` | No | URL to external SLD document | |
| `SLD_BODY` | No | Inline SLD XML (URL-encoded) | |

**GetFeatureInfo** -- Returns attribute data for features at a pixel location. Uses the same map parameters as GetMap plus:

| Parameter | Required | Description |
|---|---|---|
| `QUERY_LAYERS` | Yes | Layers to query |
| `I` / `X` | Yes | Pixel column (I in 1.3.0, X in 1.1.1) |
| `J` / `Y` | Yes | Pixel row (J in 1.3.0, Y in 1.1.1) |
| `INFO_FORMAT` | No | Response format (`application/json`, `text/html`, `text/plain`, `application/vnd.ogc.gml`) |
| `FEATURE_COUNT` | No | Max features to return (default: 1) |

### BBOX Axis Order

```
WMS 1.1.1 + EPSG:4326:  BBOX=-180,-90,180,90       (lon,lat,lon,lat)
WMS 1.3.0 + EPSG:4326:  BBOX=-90,-180,90,180       (lat,lon,lat,lon)
WMS 1.3.0 + CRS:84:     BBOX=-180,-90,180,90       (lon,lat,lon,lat)
WMS 1.3.0 + EPSG:3857:  BBOX=-20037508,-20037508,20037508,20037508  (x,y,x,y -- meters)
```

### Example GetMap URLs

WMS 1.1.1:
```
https://example.com/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap
  &LAYERS=imagery&STYLES=&SRS=EPSG:4326
  &BBOX=-74.1,40.5,-73.7,40.9&WIDTH=800&HEIGHT=600
  &FORMAT=image/png&TRANSPARENT=TRUE
```

WMS 1.3.0:
```
https://example.com/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap
  &LAYERS=imagery&STYLES=&CRS=EPSG:4326
  &BBOX=40.5,-74.1,40.9,-73.7&WIDTH=800&HEIGHT=600
  &FORMAT=image/png&TRANSPARENT=TRUE
```

### Common Image Formats

| Format | MIME Type | Use Case |
|---|---|---|
| PNG | `image/png` | Transparency, crisp edges, labels |
| JPEG | `image/jpeg` | Imagery, smaller file size, no transparency |
| GIF | `image/gif` | Legacy support |
| WebP | `image/webp` | Modern browsers, good compression |
| TIFF | `image/tiff` | High quality, large files |

### Exception Formats

| Format | Description |
|---|---|
| `application/vnd.ogc.se_xml` | XML error document (default) |
| `application/vnd.ogc.se_inimage` | Error rendered in image |
| `application/vnd.ogc.se_blank` | Blank image on error |
| `application/json` | JSON error document |

---

## WMTS (Web Map Tile Service)

WMTS serves pre-rendered map tiles from a fixed grid. Unlike WMS, clients request individual tiles by their matrix position rather than arbitrary bounding boxes.

### Operations

- **GetCapabilities** -- XML describing available layers, tile matrix sets, formats
- **GetTile** -- Returns a single tile image
- **GetFeatureInfo** -- Returns attribute data at a tile pixel position

### Request Encodings

WMTS supports three encoding styles:
1. **KVP** (Key-Value Pairs) -- Standard query string parameters
2. **RESTful** -- Path-based URL templates
3. **SOAP** -- XML envelope (rarely used in practice)

### GetTile Parameters (KVP)

| Parameter | Required | Description | Example |
|---|---|---|---|
| `SERVICE` | Yes | Service type | `WMTS` |
| `VERSION` | Yes | Protocol version | `1.0.0` |
| `REQUEST` | Yes | Operation name | `GetTile` |
| `LAYER` | Yes | Layer identifier | `satellite_imagery` |
| `STYLE` | Yes | Style identifier | `default` |
| `FORMAT` | Yes | Tile image format | `image/png` |
| `TILEMATRIXSET` | Yes | Tile matrix set identifier | `GoogleMapsCompatible` |
| `TILEMATRIX` | Yes | Zoom level identifier | `12` |
| `TILEROW` | Yes | Row index (Y, origin top-left) | `1205` |
| `TILECOL` | Yes | Column index (X) | `2048` |

### KVP Example

```
https://example.com/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile
  &LAYER=satellite_imagery&STYLE=default&FORMAT=image/png
  &TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX=12
  &TILEROW=1205&TILECOL=2048
```

### RESTful URL Template

The GetCapabilities document provides a `<ResourceURL>` template:

```
https://example.com/wmts/1.0.0/{Layer}/{Style}/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.png
```

Concrete example:
```
https://example.com/wmts/1.0.0/satellite_imagery/default/GoogleMapsCompatible/12/1205/2048.png
```

### Tile Matrix Sets

A tile matrix set defines a tiling grid: the CRS, tile dimensions, origin, and scale at each zoom level. Tiles are typically 256x256 pixels (the most common default), but the WMTS spec allows each TileMatrix to define arbitrary `TileWidth` and `TileHeight` values. Always read tile dimensions from the capabilities document.

**Scale denominator** uses the OGC standardized rendering pixel size of 0.28mm:
```
scale_denominator = resolution_meters_per_pixel / 0.00028
```

### Well-Known Scale Sets

| Scale Set | CRS | Origin | Description |
|---|---|---|---|
| `GoogleMapsCompatible` | EPSG:3857 | Top-left (-20037508.34, 20037508.34) | Google Maps / OSM compatible |
| `GlobalCRS84Geometric` | EPSG:4326 | Top-left (-180, 90) | Geographic, resolution doubles per level |
| `GlobalCRS84Scale` | EPSG:4326 | Top-left (-180, 90) | Geographic, human-friendly scales (not quad-tree) |
| `EuropeanETRS89` | EPSG:3035 | Top-left | European Terrestrial Reference System |

**GoogleMapsCompatible** tile matrix dimensions at each level:

| TileMatrix (Zoom) | MatrixWidth | MatrixHeight | Scale Denominator |
|---|---|---|---|
| 0 | 1 | 1 | 559,082,264.03 |
| 1 | 2 | 2 | 279,541,132.01 |
| 2 | 4 | 4 | 139,770,566.01 |
| 3 | 8 | 8 | 69,885,283.00 |
| ... | 2^z | 2^z | 559,082,264.03 / 2^z |

### Tile Coordinate System

- **Origin**: Top-left corner of the tile matrix
- **TILEROW**: Increases downward (top-to-bottom)
- **TILECOL**: Increases rightward (left-to-right)

---

## TMS (Tile Map Service)

TMS is an OSGeo specification that is simpler than WMTS. The critical difference from WMTS/XYZ is the **Y-axis direction**.

### URL Pattern

```
https://example.com/tms/1.0.0/{layer}/{z}/{x}/{y}.{format}
```

Example:
```
https://example.com/tms/1.0.0/imagery/12/2048/2890.png
```

### Y-Axis Convention

TMS places the origin at the **bottom-left** (southwest corner). Y coordinates increase northward (upward). This is the **opposite** of WMTS and XYZ, which use a top-left origin.

### TMS-to-XYZ Y Conversion

```
y_xyz = (2^z - 1) - y_tms
y_tms = (2^z - 1) - y_xyz
```

At zoom level 12 with 4096 tiles per axis:
```
y_xyz = 4095 - y_tms
y_tms = 4095 - y_xyz
```

### When You Encounter TMS

Some servers (GeoServer, MapProxy) serve TMS by default. If tiles appear vertically flipped, the Y-axis convention is likely wrong. Some servers support a `flipY=true` parameter for compatibility.

---

## XYZ (Slippy Map) Tiles

XYZ is the de facto standard used by OpenStreetMap, Google Maps, Mapbox, and most web mapping libraries. It is not a formal OGC standard but is ubiquitous.

### URL Pattern

```
https://tile.example.com/{z}/{x}/{y}.png
```

Example (OpenStreetMap):
```
https://tile.openstreetmap.org/12/2048/1205.png
```

### Coordinate System

- **Origin**: Top-left (northwest corner, -180 longitude, ~85.05 latitude)
- **z**: Zoom level (0 = whole world in one tile)
- **x**: Column index, increases eastward (left-to-right)
- **y**: Row index, increases southward (top-to-bottom)

### Zoom Level Properties

| Zoom | Total Tiles | Tile Width (degrees) | Meters/Pixel (equator) | Approx Scale |
|---|---|---|---|---|
| 0 | 1 | 360 | 156,543 | 1:500M |
| 1 | 4 | 180 | 78,272 | 1:250M |
| 5 | 1,024 | 11.25 | 4,892 | 1:15M |
| 8 | 65,536 | 1.406 | 611 | 1:2M |
| 10 | 1,048,576 | 0.352 | 152.874 | 1:500K |
| 12 | 16,777,216 | 0.088 | 38.219 | 1:150K |
| 15 | 1,073,741,824 | 0.011 | 4.777 | 1:15K |
| 18 | 68,719,476,736 | 0.0014 | 0.597 | 1:2K |
| 20 | 1,099,511,627,776 | 0.00034 | 0.149 | 1:500 |

Total tiles at zoom z: `2^z * 2^z = 2^(2z)`

### Quadkey Encoding (Bing Maps)

Quadkeys encode tile XY coordinates into a single string by interleaving the bits of X and Y, then interpreting the result as base-4 digits.

Algorithm:
```
for i = levelOfDetail down to 1:
    digit = '0'
    mask = 1 << (i - 1)
    if (tileX AND mask) != 0: digit += 1
    if (tileY AND mask) != 0: digit += 2
    append digit to quadkey
```

Example: tile (3, 5) at zoom 3:
```
tileX = 3 = 011 (binary)
tileY = 5 = 101 (binary)
interleaved = 100111 (binary) = 213 (base-4)
quadkey = "213"
```

Properties:
- Quadkey length equals the zoom level
- A tile's quadkey always starts with its parent tile's quadkey
- Nearby tiles tend to have similar quadkey prefixes (spatial locality)

---

## WCS (Web Coverage Service)

WCS provides access to raw coverage data (not rendered images). Use WCS when you need actual data values (e.g., elevation, temperature) rather than styled map images.

### Operations

| Operation | Description |
|---|---|
| **GetCapabilities** | Lists available coverages and service metadata |
| **DescribeCoverage** | Returns detailed metadata for a specific coverage (CRS, dimensions, formats) |
| **GetCoverage** | Returns raw coverage data, optionally subsetted and reprojected |

### Version Differences

| Feature | WCS 1.0 | WCS 1.1 | WCS 2.0 |
|---|---|---|---|
| Coverage parameter | `COVERAGE` | `IDENTIFIER` | `COVERAGEID` |
| Spatial subsetting | `BBOX` | `BoundingBox` | `SUBSET` |
| Format parameter | `FORMAT` | `FORMAT` (MIME type) | `FORMAT` (MIME type) |
| Output CRS | `RESPONSE_CRS` | N/A | `OUTPUTCRS` |
| Subsetting CRS | N/A | N/A | `SUBSETTINGCRS` |

### WCS 2.0 GetCoverage Parameters

| Parameter | Required | Description | Example |
|---|---|---|---|
| `SERVICE` | Yes | Service type | `WCS` |
| `VERSION` | Yes | Protocol version | `2.0.1` |
| `REQUEST` | Yes | Operation name | `GetCoverage` |
| `COVERAGEID` | Yes | Coverage identifier | `elevation_dem` |
| `FORMAT` | No | Output format MIME type | `image/tiff` |
| `SUBSET` | No | Dimension subsetting (repeatable) | `x(10,200)` |
| `SUBSETTINGCRS` | No | CRS for SUBSET values | `http://www.opengis.net/def/crs/EPSG/0/4326` |
| `OUTPUTCRS` | No | CRS for output data | `http://www.opengis.net/def/crs/EPSG/0/3857` |
| `SCALEFACTOR` | No | Scaling factor for output | `0.5` |
| `RANGESUBSET` | No | Select specific bands/variables | `Band1,Band3` |

### Subsetting Syntax (WCS 2.0)

**Trimming** (range of values):
```
SUBSET=x(-74.1,-73.7)&SUBSET=y(40.5,40.9)
```

**Slicing** (single value on a dimension):
```
SUBSET=time("2024-01-15T00:00:00Z")
```

### Example GetCoverage URL (WCS 2.0)

```
https://example.com/wcs?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage
  &COVERAGEID=elevation_dem
  &FORMAT=image/tiff
  &SUBSET=x(-74.1,-73.7)&SUBSET=y(40.5,40.9)
  &SUBSETTINGCRS=http://www.opengis.net/def/crs/EPSG/0/4326
  &OUTPUTCRS=http://www.opengis.net/def/crs/EPSG/0/3857
```

### Example GetCoverage URL (WCS 1.1)

```
https://example.com/wcs?SERVICE=WCS&VERSION=1.1.1&REQUEST=GetCoverage
  &IDENTIFIER=elevation_dem
  &FORMAT=image/tiff
  &BOUNDINGBOX=-74.1,40.5,-73.7,40.9,urn:ogc:def:crs:EPSG::4326
  &GridBaseCRS=urn:ogc:def:crs:EPSG::4326
```

### Common Output Formats

| Format | MIME Type | Use Case |
|---|---|---|
| GeoTIFF | `image/tiff` | Most common, widely supported |
| NetCDF | `application/netcdf` | Multidimensional scientific data |
| JPEG2000 | `image/jp2` | High compression, lossy/lossless |
| HDF-EOS | `application/x-hdf` | NASA Earth science data |
| NITF | `application/x-nitf` | Defense/intelligence imagery |

---

## OGC API - Tiles

OGC API - Tiles is the modern REST-based successor to WMTS. It follows OpenAPI 3.0 conventions and returns JSON metadata.

### Key Endpoints

| Endpoint | Description |
|---|---|
| `GET /tiles` | List available tilesets |
| `GET /tiles/{tileMatrixSetId}` | Tileset metadata |
| `GET /tiles/{tileMatrixSetId}/{tileMatrix}/{tileRow}/{tileCol}` | Retrieve a tile |
| `GET /tileMatrixSets` | List available tile matrix sets |
| `GET /tileMatrixSets/{tileMatrixSetId}` | Tile matrix set details |
| `GET /collections/{collectionId}/tiles` | Collection-specific tilesets |
| `GET /collections/{collectionId}/map/tiles` | Rendered map tiles for a collection |
| `GET /map/tiles` | Dataset-level rendered map tiles |
| `GET /styles/{styleId}/map/tiles` | Styled map tiles |

### Query Parameters

| Parameter | Description |
|---|---|
| `collections` | Filter by collection IDs: `?collections=roads,buildings` |
| `datetime` | Temporal filter: `?datetime=2024-01-15T00:00:00Z` |
| `f` | Response format: `?f=json`, `?f=png`, `?f=mvt` |

### Example Tile Request

```
GET /tiles/WebMercatorQuad/12/1205/2048?f=png
```

### Tileset Metadata Response (JSON)

```json
{
  "title": "Satellite Imagery",
  "dataType": "map",
  "crs": "http://www.opengis.net/def/crs/EPSG/0/3857",
  "tileMatrixSetURI": "http://www.opengis.net/def/tilematrixset/OGC/1.0/WebMercatorQuad",
  "links": [
    {
      "rel": "item",
      "type": "image/png",
      "title": "Tiles",
      "href": "https://example.com/tiles/WebMercatorQuad/{tileMatrix}/{tileRow}/{tileCol}?f=png",
      "templated": true
    },
    {
      "rel": "http://www.opengis.net/def/rel/ogc/1.0/tiling-scheme",
      "type": "application/json",
      "href": "https://example.com/tileMatrixSets/WebMercatorQuad"
    }
  ]
}
```

### Supported Tile Formats

| Format | Content Type | Description |
|---|---|---|
| PNG | `image/png` | Raster map tiles |
| JPEG | `image/jpeg` | Imagery tiles |
| WebP | `image/webp` | Modern compressed tiles |
| MVT | `application/vnd.mapbox-vector-tile` | Mapbox Vector Tiles |
| GeoJSON | `application/geo+json` | Vector tiles as GeoJSON |
| TIFF | `image/tiff` | Coverage tiles |
| NetCDF | `application/netcdf` | Multidimensional coverage tiles |

---

## Coordinate Reference Systems

### Common CRS Codes

| Code | Name | Type | Units | Axis Order | Use Case |
|---|---|---|---|---|---|
| EPSG:4326 | WGS 84 | Geographic | Degrees | lat, lon | GPS, data storage, GeoJSON |
| CRS:84 | WGS 84 (lon/lat) | Geographic | Degrees | lon, lat | WMS 1.3.0 lon-first alternative |
| EPSG:3857 | Web Mercator | Projected | Meters | x (east), y (north) | Web maps, tiling |
| EPSG:326xx | UTM Zone N | Projected | Meters | x (east), y (north) | High-accuracy local work |
| EPSG:327xx | UTM Zone S | Projected | Meters | x (east), y (north) | Southern hemisphere UTM |

### Axis Order Pitfalls

The axis order issue is the most common source of misaligned maps:

- **EPSG:4326** in the EPSG database: latitude first, longitude second (y, x)
- **CRS:84**: longitude first, latitude second (x, y) -- same datum as EPSG:4326
- **Most software/APIs**: Use longitude first regardless of CRS definition (GeoJSON, Leaflet, OpenLayers)
- **WMS 1.3.0**: Follows EPSG axis order strictly (lat, lon for EPSG:4326)
- **WMS 1.1.1**: Always lon, lat regardless of CRS

When in doubt, use CRS:84 (lon, lat) or EPSG:3857 (meters, no ambiguity).

### Web Mercator Limitations

- Valid latitude range: -85.05112878 to 85.05112878 degrees (poles excluded)
- Significant area distortion at high latitudes
- Not suitable for area or distance measurements
- Conformal: preserves local shape and angles

---

## Tile Math Formulas

All formulas assume 256x256 pixel tiles and the Web Mercator (EPSG:3857) tiling scheme with origin at the top-left.

### Lon/Lat to Tile Coordinates

```
n = 2^zoom
x_tile = floor(n * (lon + 180) / 360)
y_tile = floor(n * (1 - ln(tan(lat_rad) + sec(lat_rad)) / pi) / 2)
```

Where `lat_rad = lat * pi / 180`.

Expanded `y_tile` formula:
```
y_tile = floor(n * (1 - ln(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2)
```

### Tile Coordinates to Lon/Lat (Northwest Corner)

```
n = 2^zoom
lon = x_tile / n * 360 - 180
lat = atan(sinh(pi * (1 - 2 * y_tile / n))) * 180 / pi
```

### Tile Bounding Box

Get all four corners by computing coordinates for both (x, y) and (x+1, y+1):
```
west  = x_tile / n * 360 - 180
east  = (x_tile + 1) / n * 360 - 180
north = atan(sinh(pi * (1 - 2 * y_tile / n))) * 180 / pi
south = atan(sinh(pi * (1 - 2 * (y_tile + 1) / n))) * 180 / pi
```

### Ground Resolution

Meters per pixel at a given latitude and zoom level:
```
resolution = cos(lat * pi / 180) * 2 * pi * 6378137 / (256 * 2^zoom)
```

Simplified at the equator:
```
resolution = 156543.03 / 2^zoom    (meters/pixel)
```

### Scale Denominator (OGC Convention)

Using the OGC standardized pixel size of 0.28mm:
```
scale_denominator = resolution / 0.00028
```

At zoom 0 (equator): `156543.03 / 0.00028 = 559,082,264`

### Lon/Lat to Pixel Coordinates

```
map_size = 256 * 2^zoom
pixel_x = floor((lon + 180) / 360 * map_size)

sin_lat = sin(lat * pi / 180)
pixel_y = floor((0.5 - ln((1 + sin_lat) / (1 - sin_lat)) / (4 * pi)) * map_size)
```

### Pixel to Tile

```
tile_x = floor(pixel_x / 256)
tile_y = floor(pixel_y / 256)
```

### TMS Y-Flip

Convert between XYZ (top-left origin) and TMS (bottom-left origin):
```
y_tms = (2^zoom - 1) - y_xyz
y_xyz = (2^zoom - 1) - y_tms
```

### Bounding Box to Tile Range

To find all tiles that cover a given bounding box at a zoom level:
```
x_min = lon_to_tile_x(west, zoom)
x_max = lon_to_tile_x(east, zoom)
y_min = lat_to_tile_y(north, zoom)   -- note: north gives smaller y (top-left origin)
y_max = lat_to_tile_y(south, zoom)
total_tiles = (x_max - x_min + 1) * (y_max - y_min + 1)
```

---

## Protocol Selection Guide

| Need | Protocol | Reason |
|---|---|---|
| Pre-rendered basemap tiles | XYZ or WMTS | Best performance, widely cached |
| Custom-styled map images | WMS | Dynamic rendering per request |
| Raw data values (elevation, temperature) | WCS | Returns actual data, not rendered images |
| Modern REST API for tiles | OGC API - Tiles | JSON metadata, OpenAPI, content negotiation |
| Simple tile server integration | TMS | Minimal complexity, OSGeo standard |
| Feature attributes at a point | WMS GetFeatureInfo or WFS | Returns attribute data, not images |
