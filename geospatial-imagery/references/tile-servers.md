# Tile Server Implementation Patterns

Comprehensive reference for building custom tile servers, covering coordinate systems,
storage strategies, serving architectures, caching, WMS compatibility, and Go-specific
implementation patterns.

---

## Table of Contents

1. [Tile Coordinate Systems](#tile-coordinate-systems)
2. [Tile Storage Strategies](#tile-storage-strategies)
3. [Serving Architecture Patterns](#serving-architecture-patterns)
4. [Implementation Components](#implementation-components)
5. [Reference Implementations](#reference-implementations)
6. [Go-Specific Implementation Notes](#go-specific-implementation-notes)
7. [Building a WMS-Compatible Endpoint](#building-a-wms-compatible-endpoint)

---

## Tile Coordinate Systems

The most common web map tile convention (XYZ / Slippy Map) uses Web Mercator (EPSG:3857)
with 256x256 pixel tiles. However, the OGC WMTS standard supports arbitrary projections
(polar stereographic, UTM, national grids) and tile sizes. Some systems (Mapbox GL, NASA
GIBS) default to 512x512 tiles. At zoom level `z`, the grid is `2^z x 2^z` tiles. The
tile systems differ in origin placement, axis direction, and encoding.

### XYZ (Slippy Map / Google / OSM)

The de facto standard used by Google Maps, OpenStreetMap, Mapbox, and most web mapping
libraries.

```
Origin: top-left (0,0)
URL pattern: /{z}/{x}/{y}.png
x range: 0 to 2^z - 1 (left to right)
y range: 0 to 2^z - 1 (top to bottom)

         x=0   x=1   x=2   x=3
       +-----+-----+-----+-----+
  y=0  | 0,0 | 1,0 | 2,0 | 3,0 |  <- North (top)
       +-----+-----+-----+-----+
  y=1  | 0,1 | 1,1 | 2,1 | 3,1 |
       +-----+-----+-----+-----+
  y=2  | 0,2 | 1,2 | 2,2 | 3,2 |
       +-----+-----+-----+-----+
  y=3  | 0,3 | 1,3 | 2,3 | 3,3 |  <- South (bottom)
       +-----+-----+-----+-----+
              z=2 example
```

### TMS (Tile Map Service)

OSGeo standard. Identical to XYZ except the y-axis is flipped -- origin is at bottom-left.

```
Origin: bottom-left (0,0)
URL pattern: /{z}/{x}/{y}.png
x range: 0 to 2^z - 1 (left to right)
y range: 0 to 2^z - 1 (bottom to top)

         x=0   x=1   x=2   x=3
       +-----+-----+-----+-----+
  y=3  | 0,3 | 1,3 | 2,3 | 3,3 |  <- North (top)
       +-----+-----+-----+-----+
  y=2  | 0,2 | 1,2 | 2,2 | 3,2 |
       +-----+-----+-----+-----+
  y=1  | 0,1 | 1,1 | 2,1 | 3,1 |
       +-----+-----+-----+-----+
  y=0  | 0,0 | 1,0 | 2,0 | 3,0 |  <- South (bottom)
       +-----+-----+-----+-----+
              z=2 example
```

**MBTiles uses TMS coordinates internally.** When serving from MBTiles over an XYZ endpoint,
apply the y-flip conversion.

### Quadkey (Bing Maps)

Encodes tile x/y/z into a single base-4 string by interleaving the bits of x and y. The
length of the quadkey equals the zoom level.

```
Encoding algorithm:
  For each bit position i from z down to 1:
    digit = 0
    mask = 1 << (i - 1)
    if (x & mask) != 0: digit += 1
    if (y & mask) != 0: digit += 2
    append digit to quadkey

Example: tile (3, 5) at z=3
  x = 3 = 011 (binary)
  y = 5 = 101 (binary)
  Interleaved: 10 01 11 -> base-4 digits: 2 1 3
  Quadkey: "213"

Properties:
  - Length equals zoom level
  - Parent tile's quadkey is a prefix of child quadkeys
  - Preserves spatial locality (nearby tiles have similar keys)
  - Good for B-tree database indexing
```

### WMTS TileMatrix

OGC Web Map Tile Service uses named TileMatrix levels (not necessarily numeric zoom), with
TileRow and TileCol coordinates. Each TileMatrixSet defines a CRS, scale denominators, and
tile grid origins.

```
URL pattern (RESTful):
  /{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.png

URL pattern (KVP):
  ?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0
  &LAYER=...&STYLE=...&FORMAT=image/png
  &TILEMATRIXSET=...&TILEMATRIX=...&TILEROW=...&TILECOL=...
```

### Conversion Formulas

#### Lat/Lon to XYZ Tile Coordinates

```
Constants:
  MIN_LAT = -85.05112878
  MAX_LAT =  85.05112878

lat_rad = latitude * PI / 180
n = 2^z
x = floor((longitude + 180) / 360 * n)
y = floor((1 - ln(tan(lat_rad) + sec(lat_rad)) / PI) / 2 * n)
```

#### XYZ Tile to Lat/Lon (northwest corner of tile)

```
n = 2^z
lon = x / n * 360 - 180
lat_rad = atan(sinh(PI * (1 - 2 * y / n)))
lat = lat_rad * 180 / PI
```

#### XYZ Tile to Bounding Box

```
north_lat = tile_to_lat(y, z)
south_lat = tile_to_lat(y + 1, z)
west_lon  = tile_to_lon(x, z)
east_lon  = tile_to_lon(x + 1, z)
```

#### XYZ <-> TMS Conversion

The formula is bidirectional (applying it converts in either direction):

```
tms_y = (2^z) - xyz_y - 1
xyz_y = (2^z) - tms_y - 1

// Optimized with bitwise shift:
tms_y = (1 << z) - xyz_y - 1
```

#### Lat/Lon to Pixel XY (Web Mercator)

```
sinLat = sin(latitude * PI / 180)
mapSize = 256 * 2^z

pixelX = ((longitude + 180) / 360) * mapSize
pixelY = (0.5 - ln((1 + sinLat) / (1 - sinLat)) / (4 * PI)) * mapSize

tileX = floor(pixelX / 256)
tileY = floor(pixelY / 256)
```

#### Pixel XY to Lat/Lon

```
mapSize = 256 * 2^z
x = (pixelX / mapSize) - 0.5
y = 0.5 - (pixelY / mapSize)

latitude = 90 - 360 * atan(exp(-y * 2 * PI)) / PI
longitude = 360 * x
```

#### Ground Resolution (meters per pixel)

```
resolution = cos(latitude * PI / 180) * 2 * PI * 6378137 / (256 * 2^z)
```

---

## Tile Storage Strategies

### Directory Hierarchy (z/x/y files)

The simplest approach: store each tile as an individual file on the filesystem.

```
tiles/
  0/
    0/
      0.png
  1/
    0/
      0.png
      1.png
    1/
      0.png
      1.png
  ...
```

| Pros | Cons |
|------|------|
| Trivial to serve (static file server / CDN) | Many small files (4^z at zoom z) |
| Easy to inspect, debug, replace individual tiles | Filesystem overhead (inodes, metadata) |
| CDN-friendly, HTTP cache headers just work | Slow bulk operations (copy, backup, transfer) |
| No special software needed to serve | Not portable as a single artifact |

### MBTiles (SQLite)

Mapbox specification for storing tiles in a single SQLite database. Widely supported across
the geospatial ecosystem.

```sql
-- Required tables
CREATE TABLE metadata (name text, value text);
CREATE TABLE tiles (
    zoom_level  integer,
    tile_column integer,
    tile_row    integer,    -- TMS y-coordinate (origin bottom-left)
    tile_data   blob
);
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);

-- Required metadata keys
-- name:   human-readable tileset name
-- format: "png", "jpg", "pbf", "webp", or IETF media type

-- Recommended metadata keys
-- bounds:  "west,south,east,north" in WGS 84
-- center:  "lon,lat,zoom"
-- minzoom: lowest zoom level
-- maxzoom: highest zoom level
```

| Pros | Cons |
|------|------|
| Single portable file | Write contention (single-writer SQLite) |
| Efficient concurrent reads | Larger file size than raw tiles |
| Built-in indexing | Not CDN-friendly without a serving layer |
| Atomic operations, transactional | Y-coordinate is TMS (flip for XYZ) |
| Deduplication possible via views | |

**Tile data format**: Raw binary image bytes (PNG, JPEG, WebP) for raster tiles, or
gzip-compressed PBF for vector tiles. GDAL's MBTiles driver supports JPEG, PNG, PNG8, and
WebP for raster tiles, and PBF (Mapbox Vector Tiles) for vector tiles.

**Y-axis conversion**: MBTiles stores tiles in TMS convention (origin bottom-left). GDAL's
MBTiles driver converts to top-left convention internally:
```c
// From GDAL mbtilesdataset.cpp (GetRowFromIntoTopConvention)
return m_nTileMatrixHeight - 1 - nRow;
```

**Spherical Mercator constants** (from GDAL source):
```c
#define SPHERICAL_RADIUS 6378137.0
#define MAX_GM (SPHERICAL_RADIUS * M_PI)  // 20037508.342789244
#define TMS_ORIGIN_X -MAX_GM              // top-left in WMTS convention
#define TMS_ORIGIN_Y  MAX_GM
```

**Concurrent read performance**: SQLite supports unlimited concurrent readers via SHARED
locks in any journal mode. For read-only MBTiles serving, WAL mode provides no benefit
(it helps concurrent reads *and writes*, not reads alone). For static tile files, open with
`?immutable=1` to skip all locking and change detection for best read performance.
Alternatively, open with `?mode=ro` in the default journal mode.

### GeoPackage

OGC standard extending SQLite. Stores tiles, vector features, and metadata in one file.

```sql
-- Tile table (each tile matrix set gets its own table)
CREATE TABLE my_tiles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    zoom_level  INTEGER NOT NULL,
    tile_column INTEGER NOT NULL,
    tile_row    INTEGER NOT NULL,
    tile_data   BLOB NOT NULL,
    UNIQUE (zoom_level, tile_column, tile_row)
);

-- Tile matrix metadata
CREATE TABLE gpkg_tile_matrix (
    table_name    TEXT NOT NULL,
    zoom_level    INTEGER NOT NULL,
    matrix_width  INTEGER NOT NULL,
    matrix_height INTEGER NOT NULL,
    tile_width    INTEGER NOT NULL,
    tile_height   INTEGER NOT NULL,
    pixel_x_size  DOUBLE NOT NULL,
    pixel_y_size  DOUBLE NOT NULL
);
```

| Pros | Cons |
|------|------|
| OGC standard, wide tool support | More complex schema than MBTiles |
| Multiple tilesets in one file | Same SQLite write limitations |
| Can store vectors + rasters together | Less ecosystem tooling than MBTiles |
| Multiple CRS support | |

### S3 / Object Storage

Store tiles as individual objects with structured key naming.

```
Key patterns:
  tiles/{z}/{x}/{y}.png           -- standard hierarchy
  tiles/{z}/{x}/{y}.pbf           -- vector tiles
  tiles/{quadkey}.png             -- quadkey-based (Bing-style)

With optional path prefix:
  {prefix}/tiles/{z}/{x}/{y}.png
```

| Pros | Cons |
|------|------|
| Virtually unlimited scale | Per-request cost (GET fees) |
| Built-in redundancy | Higher latency than local disk |
| CDN integration (CloudFront, etc.) | No atomic bulk operations |
| Pay-per-use | Many small objects can be expensive |

**Cost optimization**: Use S3 Intelligent-Tiering for tiles with varying access patterns. Set
lifecycle rules to move old zoom levels to S3 Glacier. Consider PMTiles format (below) to
reduce object count.

### PMTiles (Cloud-Optimized Single File)

A single-file archive designed for serverless access over HTTP range requests.

```
Architecture:
  +------------------+
  | Header (127 B)   |  Fixed metadata
  +------------------+
  | Root Directory    |  Hilbert-curve ordered tile index
  +------------------+
  | Leaf Directories  |  Optional for large tilesets
  +------------------+
  | Tile Data         |  Concatenated tile bytes
  +------------------+

Access pattern:
  1. Fetch header + root directory (1 HTTP request)
  2. Look up tile in directory -> byte offset + length
  3. Fetch tile data via HTTP Range request (1 HTTP request)
  Total: 2-3 HTTP requests per tile (cacheable)
```

| Pros | Cons |
|------|------|
| Single file on static storage (S3, GCS) | Requires HTTP range request support |
| No server process needed | Write-once (rebuild to update) |
| Hilbert curve preserves spatial locality | Newer format, less ecosystem support |
| 70%+ size reduction via deduplication | Not suitable for real-time updates |

### PostgreSQL

Store tiles directly in PostgreSQL, or generate vector tiles on-the-fly from PostGIS.

```sql
-- Static tile storage
CREATE TABLE tiles (
    z integer,
    x integer,
    y integer,
    data bytea,
    PRIMARY KEY (z, x, y)
);

-- Dynamic vector tile generation (pg_tileserv pattern)
SELECT ST_AsMVT(q, 'layer_name', 4096, 'geom') AS tile
FROM (
    SELECT ST_AsMVTGeom(
        geom,
        ST_TileEnvelope(z, x, y),
        4096, 256, true
    ) AS geom,
    attributes...
    FROM my_table
    WHERE geom && ST_TileEnvelope(z, x, y)
) q;
```

| Pros | Cons |
|------|------|
| Dynamic tiles from live data | Higher latency than static files |
| Leverages PostGIS spatial functions | Database load per tile request |
| Transactional updates | Requires PostgreSQL infrastructure |
| ST_AsMVT for efficient MVT encoding | Not suitable for raster tiles at scale |

---

## Serving Architecture Patterns

### Architecture Comparison

```
                    Freshness
                       ^
                       |
  On-the-fly ------>   *
  rendering            |
                       |
  COG-based -------->  *           * <------ Hybrid
  serving              |          /          (cache-on-demand)
                       |         /
                       |        /
                       |       /
  Pre-rendered --------|------*
  static tiles         |
                       +-------------------------> Speed
```

### 1. Pre-Rendered Static Tiles

Generate all tiles ahead of time, then serve from filesystem, object storage, or CDN.

```
Tile Generation Pipeline:
  +------------+    +-----------+    +------------+    +---------+
  | Source Data | -> | Renderer  | -> | Tile Store | -> | CDN/    |
  | (raster/   |    | (GDAL,    |    | (files,    |    | Static  |
  |  vector)   |    |  Mapnik)  |    |  MBTiles,  |    | Server  |
  +------------+    +-----------+    |  S3)       |    +---------+
                                     +------------+
```

**Tile count at each zoom level**: At zoom z, there are `4^z` tiles. Total tiles from zoom
0 to z: `(4^(z+1) - 1) / 3`.

| Zoom | Tiles at Level | Cumulative Total |
|------|---------------|-----------------|
| 0    | 1             | 1               |
| 5    | 1,024         | 1,365           |
| 10   | 1,048,576     | 1,398,101       |
| 15   | 1,073,741,824 | 1,431,655,765   |
| 18   | ~69 billion   | ~91 billion     |

Best for: Base maps, static imagery, datasets that change infrequently.

### 2. On-the-Fly Rendering

Render tiles per request directly from source raster/vector data.

```
Request Flow:
  Client          Tile Server              Source Data
    |                  |                        |
    | GET /z/x/y.png   |                        |
    |----------------->|                        |
    |                  | Read source extent      |
    |                  |----------------------->|
    |                  |<-----------------------|
    |                  | Resample + encode       |
    |                  |                        |
    |  200 image/png   |                        |
    |<-----------------|                        |
```

Best for: Data that changes frequently, dynamic styling, limited storage budget.

### 3. Hybrid (Cache-on-Demand)

Render on first request, cache the result for subsequent requests.

```
Request Flow:
  Client          Tile Server        Cache           Source Data
    |                  |               |                   |
    | GET /z/x/y.png   |               |                   |
    |----------------->|               |                   |
    |                  | Check cache    |                   |
    |                  |-------------->|                   |
    |                  | MISS          |                   |
    |                  |<-------------|                   |
    |                  | Render tile   |                   |
    |                  |--------------------------------->|
    |                  |<---------------------------------|
    |                  | Store in cache |                   |
    |                  |-------------->|                   |
    |  200 image/png   |               |                   |
    |<-----------------|               |                   |
    |                  |               |                   |
    | GET /z/x/y.png   |  (later)      |                   |
    |----------------->|               |                   |
    |                  | Check cache    |                   |
    |                  |-------------->|                   |
    |                  | HIT           |                   |
    |                  |<-------------|                   |
    |  200 image/png   |               |                   |
    |<-----------------|               |                   |
```

Best for: Large datasets where pre-rendering all tiles is impractical, but popular tiles
should be fast.

### 4. COG-Based Serving

Use Cloud-Optimized GeoTIFF with HTTP range requests. No tile pre-generation needed.

```
COG Internal Structure:
  +---------------------------+
  | TIFF Header + IFDs        |  <- Metadata (small, cacheable)
  +---------------------------+
  | Overview 1 (lowest res)   |  <- For low zoom levels
  | Overview 2                |
  | Overview 3                |
  +---------------------------+
  | Full Resolution Tiles     |  <- For high zoom levels
  | (internally tiled 256x256 |
  |  or 512x512)              |
  +---------------------------+

Request Flow:
  Client        Tile Server         COG on S3/HTTP
    |               |                     |
    | GET /z/x/y    |                     |
    |-------------->|                     |
    |               | Calculate byte range |
    |               | for tile extent      |
    |               | HTTP Range GET       |
    |               |-------------------->|
    |               |<--------------------|
    |               | Decode + resample    |
    |               | Encode to PNG        |
    |  200 PNG      |                     |
    |<--------------|                     |
```

**Key advantage**: Source data stays in a single, cloud-friendly format. No pre-generation
pipeline. Tiles are extracted on demand using efficient byte-range reads.

**COG creation options** (from GDAL `cogdriver.cpp`):
```
TILING_SCHEME:       "CUSTOM" (default) or named scheme like "GoogleMapsCompatible"
BLOCKSIZE:           512 (default for COG, vs 256 for standard GeoTIFF)
RESAMPLING:          Method for building overviews (nearest, bilinear, cubic, etc.)
OVERVIEW_RESAMPLING: Separate resampling for overviews (falls back to RESAMPLING)
TARGET_SRS:          Target CRS for reprojection during COG creation
```

GDAL's COG driver validates that the tiling scheme has consistent top-left corners, tile
sizes, and no variable matrix widths across all zoom levels. The driver supports warping
source data to match a target tiling scheme during creation.

Best for: Serverless architectures, large raster catalogs, STAC-integrated workflows.

---

## Implementation Components

### HTTP Handler and URL Routing

Parse tile coordinates from the URL path and serve the appropriate tile.

```go
// Route pattern: GET /tiles/{z}/{x}/{y}.png
func tileHandler(w http.ResponseWriter, r *http.Request) {
    z, err := strconv.Atoi(chi.URLParam(r, "z"))
    if err != nil || z < 0 || z > 24 {
        http.Error(w, "invalid zoom level", http.StatusBadRequest)
        return
    }
    x, err := strconv.Atoi(chi.URLParam(r, "x"))
    if err != nil {
        http.Error(w, "invalid x coordinate", http.StatusBadRequest)
        return
    }

    // Strip file extension from y
    yStr := chi.URLParam(r, "y")
    yStr = strings.TrimSuffix(yStr, filepath.Ext(yStr))
    y, err := strconv.Atoi(yStr)
    if err != nil {
        http.Error(w, "invalid y coordinate", http.StatusBadRequest)
        return
    }

    // Validate tile coordinates against zoom level bounds
    maxTile := 1 << z  // 2^z
    if x < 0 || x >= maxTile || y < 0 || y >= maxTile {
        http.Error(w, "tile coordinates out of range", http.StatusBadRequest)
        return
    }

    // Fetch/render tile
    tile, err := getTile(z, x, y)
    if err != nil {
        http.Error(w, "tile not found", http.StatusNotFound)
        return
    }

    w.Header().Set("Content-Type", "image/png")
    w.Write(tile)
}
```

### Tile Renderer

Read source raster data, extract the tile extent, resample to 256x256, and encode.

```
Rendering Pipeline:
  1. Compute tile bounding box in source CRS
  2. Open source dataset (GeoTIFF, COG, etc.)
  3. Read pixels for the tile extent (with overviews if available)
  4. Resample to 256x256 (or 512x512 for retina)
  5. Apply color mapping / styling
  6. Encode to output format (PNG, JPEG, WebP)

Resampling Methods:
  - Nearest Neighbor: Fastest, no interpolation, best for categorical data
  - Bilinear:         Good balance of speed and quality for continuous data
  - Cubic:            Smoother than bilinear, slightly slower
  - Lanczos:          Highest quality, slowest, best for downsampling imagery
```

### Meta-Tiling

Render a larger image (e.g., 3x3 tiles) in a single operation, then slice it into individual
tiles. This reduces rendering overhead and eliminates label/symbol duplication at tile edges.

```
Meta-tiling concept (3x3 metaX x metaY):
  +-------+-------+-------+
  | tile  | tile  | tile  |
  | (0,0) | (1,0) | (2,0) |
  +-------+-------+-------+
  | tile  | tile  | tile  |  <- Rendered as one 768x768 image,
  | (0,1) | (1,1) | (2,1) |     then sliced into 9 tiles
  +-------+-------+-------+
  | tile  | tile  | tile  |
  | (0,2) | (1,2) | (2,2) |
  +-------+-------+-------+

Gutter: extra pixels around meta-tile edges (e.g., 20px) to prevent
        label/symbol clipping, trimmed after slicing.
```

GeoServer/GeoWebCache implementation pattern (from `GeoServerTileLayer.java`):
1. Acquire a lock on the meta-tile grid position (prevents duplicate renders)
2. Check if the requested tile was already cached (double-check after lock)
3. Render the full meta-tile image via a WMS GetMap request
4. Slice the meta-tile into individual tiles
5. Store each tile to the blob store (optionally in parallel via an executor)
6. Release the meta-tile lock

GeoServer disables concurrent meta-tile encoding during seed operations to let administrators
control resource usage. During live requests, tiles within a meta-tile are encoded and saved
in parallel using a configurable executor thread pool.

### Cache Layer

Multi-tier caching reduces latency and backend load.

```
Cache Tiers:
  +----------+    +----------+    +-----------+    +--------+
  | CDN      | -> | In-Memory| -> | Disk/Redis| -> | Render |
  | (edge)   |    | LRU      |    | (warm)    |    | (cold) |
  +----------+    +----------+    +-----------+    +--------+
  ~1ms             ~0.1ms          ~1-5ms           ~50-500ms

Cache Key Format:
  "{layer}:{z}:{x}:{y}:{format}"
  "{layer}:{z}:{x}:{y}:{style_hash}"  // For dynamic styling
```

**In-memory LRU**: Best for hot tiles (zoom levels 0-12). Use a bounded LRU cache to prevent
memory exhaustion.

**Disk cache**: Store rendered tiles on local SSD. Good for warm cache tier.

**Distributed cache (Redis/Memcached)**: Shared across multiple server instances. Use for
horizontally scaled deployments.

**WMS-integrated caching** (GeoServer/GeoWebCache pattern from `CachingWebMapService.java`):
GeoServer intercepts WMS GetMap requests via an AOP method interceptor. If direct WMS
integration is enabled and the request matches a cached tile, the interceptor returns the
cached tile without invoking the full rendering pipeline. On a cache miss, the request
proceeds normally and the response header `geowebcache-cache-result: MISS` is set along
with a `geowebcache-miss-reason` explaining why. GeoWebCache configuration controls:
- `directWMSIntegrationEnabled`: Whether to intercept WMS GetMap calls
- `requireTiledParameter`: If true, only intercept requests with TILED=true
- `cacheLayersByDefault`: Auto-cache all layers vs. explicit opt-in
- Default cache formats: JPEG for coverage, PNG for vector, both for layer groups
- Meta-tiling factors (metaTilingX, metaTilingY) and gutter size

### Cache Headers

```
Response Headers for Tile Responses:
  Cache-Control: public, max-age=86400, s-maxage=604800, stale-while-revalidate=3600
  ETag: "a1b2c3d4"
  Last-Modified: Wed, 15 Jan 2025 10:30:00 GMT
  Content-Type: image/png
  Access-Control-Allow-Origin: *

Header Explanations:
  max-age=86400          Browser caches tile for 24 hours
  s-maxage=604800        CDN/proxy caches tile for 7 days
  stale-while-revalidate CDN serves stale tile while fetching fresh one
  ETag                   Content hash for conditional requests (If-None-Match)
  Last-Modified          Timestamp for conditional requests (If-Modified-Since)

Conditional Request Flow:
  Client                          Server
    |                                |
    | GET /tiles/5/10/15.png         |
    | If-None-Match: "a1b2c3d4"      |
    |------------------------------->|
    |                                | Compare ETags
    |                                | Match -> 304
    |  304 Not Modified              |
    |<-------------------------------|
    |  (no body transferred)         |
```

### Concurrent Request Handling (Singleflight)

Prevent redundant rendering when multiple clients request the same tile simultaneously.

```go
import "golang.org/x/sync/singleflight"

var group singleflight.Group

func getTileWithCoalescing(z, x, y int) ([]byte, error) {
    key := fmt.Sprintf("%d/%d/%d", z, x, y)

    result, err, _ := group.Do(key, func() (interface{}, error) {
        // Only one goroutine executes this for a given key
        return renderTile(z, x, y)
    })
    if err != nil {
        return nil, err
    }
    return result.([]byte), nil
}

// Without singleflight:       With singleflight:
//   Request A -> render          Request A -> render
//   Request B -> render          Request B -> wait for A's result
//   Request C -> render          Request C -> wait for A's result
//   3 renders                    1 render, 3 responses
```

### CORS Configuration

Required for cross-origin tile requests from web map clients.

```go
func corsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type")
        w.Header().Set("Access-Control-Max-Age", "86400")

        if r.Method == "OPTIONS" {
            w.WriteHeader(http.StatusNoContent)
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

### Health Checks and Metrics

```go
// Liveness: is the process running?
// GET /healthz -> 200 OK
func livenessHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("ok"))
}

// Readiness: can the server serve tiles?
// GET /readyz -> 200 OK or 503 Service Unavailable
func readinessHandler(w http.ResponseWriter, r *http.Request) {
    // Check source data accessibility
    if err := checkSourceData(); err != nil {
        http.Error(w, "source data unavailable", http.StatusServiceUnavailable)
        return
    }
    w.WriteHeader(http.StatusOK)
}

// Key Metrics to Track:
//   - tile_request_duration_seconds  (histogram, labels: z, format)
//   - tile_cache_hits_total          (counter, labels: cache_tier)
//   - tile_cache_misses_total        (counter, labels: cache_tier)
//   - tile_render_duration_seconds   (histogram, labels: z)
//   - tile_request_total             (counter, labels: z, status_code)
//   - tile_errors_total              (counter, labels: error_type)
```

---

## Reference Implementations

### TiTiler (Python / FastAPI)

Dynamic raster tile server built on rio-tiler and FastAPI.

```
Architecture:
  FastAPI App
    |
    +-- /cog endpoint       -> Serve tiles from Cloud-Optimized GeoTIFFs
    +-- /stac endpoint      -> Serve tiles from STAC items
    +-- /mosaicjson endpoint -> Serve tiles from mosaic of multiple COGs
    |
    +-- rio-tiler core
         |
         +-- rasterio     -> GDAL Python bindings for raster I/O
         +-- numpy        -> Array operations for pixel manipulation
         +-- Pillow/PNG   -> Image encoding

Key Patterns:
  - Dynamic rescaling, colormap application, band math per request
  - STAC integration for catalog-driven tile serving
  - No pre-generation: tiles rendered on demand from COGs
  - Designed for serverless (AWS Lambda) deployment
```

### MapProxy (Python)

Tile cache and WMS/WMTS proxy. Mature project for accelerating and transforming map services.

```
Architecture:
  +----------+                  +-----------+
  | Clients  |  WMS/WMTS/TMS   | MapProxy  |
  | (web,    | --------------> | (proxy +  |
  |  desktop)|                  |  cache)   |
  +----------+                  +-----+-----+
                                      |
                          +-----------+-----------+
                          |           |           |
                       +--+--+   +---+---+   +---+---+
                       |Cache|   | Cache |   | Cache |
                       |(disk|   |(MBTiles|  |(S3)   |
                       | FS) |   |SQLite) |  |       |
                       +--+--+   +---+---+   +---+---+
                          |           |           |
                       +--+-----------+-----------+--+
                       |     Source WMS/WMTS/TMS      |
                       +------------------------------+

Key Patterns:
  - Protocol translation (WMS <-> WMTS <-> TMS <-> XYZ)
  - Multi-source compositing and merging
  - Seed/reseed CLI tool for pre-populating cache
  - Configurable tile grids: GLOBAL_GEODETIC, GLOBAL_MERCATOR, GLOBAL_WEBMERCATOR
  - Cache backends: filesystem, MBTiles, SQLite, GeoPackage, S3, Redis
```

### Martin (Rust)

Blazing fast vector tile server from PostGIS, MBTiles, and PMTiles.

```
Architecture (4 crates):
  martin (binary)
    |
    +-- martin-tile-utils    -> Low-level tile encoding/decoding
    +-- martin-mbtiles       -> MBTiles format support
    +-- martin (core)        -> Source abstraction, HTTP service
    |
    Data Sources:
      - PostGIS              -> Dynamic vector tiles via SQL
      - MBTiles              -> Pre-generated tile archives
      - PMTiles              -> Cloud-optimized tile archives (local + remote)

Key Patterns:
  - Actix-web HTTP framework for high-throughput serving
  - Multiple sources combined dynamically into composite tiles
  - Automatic function discovery from PostGIS
  - CORS enabled by default
  - Connection pooling for database sources
```

### Tegola (Go)

Vector tile server written in Go. Generates Mapbox Vector Tiles from PostGIS and GeoPackage.

```
Architecture:
  HTTP Server (net/http)
    |
    +-- Tile Handler
    |     |
    |     +-- MVT Provider (PostGIS)
    |     |     +-- ST_AsMVT() encoding at database level
    |     |     +-- Connection pooling
    |     |
    |     +-- MVT Provider (GeoPackage)
    |           +-- SQLite-based feature access
    |
    +-- Cache Layer
          +-- File cache
          +-- S3 cache
          +-- Redis cache
          +-- Azure Blob Store cache

Key Patterns:
  - Native geometry processing (simplification, clipping, intersection)
  - Leverages PostGIS ST_AsMVT for server-side MVT encoding
  - Cache seeding and invalidation via ZXY, bounds, or tile lists
  - Parallelized tile serving and geometry processing
  - Serverless deployment support (AWS Lambda)
```

### mbtileserver (Go)

Lightweight server for serving MBTiles archives.

```
Architecture:
  HTTP Server
    |
    +-- Route: /services                 -> List available tilesets
    +-- Route: /services/{tileset}       -> Tileset metadata (TileJSON)
    +-- Route: /services/{tileset}/tiles/{z}/{x}/{y} -> Tile data
    |
    +-- MBTiles Reader
          +-- SQLite connection pool
          +-- Y-axis flip (TMS to XYZ)
          +-- Content-Encoding: gzip (for PBF tiles)

Key Patterns:
  - Auto-discovery of .mbtiles files in a directory
  - TileJSON metadata endpoint for each tileset
  - Transparent gzip handling for vector tiles
  - Minimal dependencies, single binary deployment
```

### Terracotta (Python)

Lightweight COG-based raster tile server.

```
Key Patterns:
  - Metadata database (SQLite/MySQL/PostgreSQL) for COG catalog
  - On-demand tile rendering from COGs via rasterio
  - Automatic colormap stretching based on dataset statistics
  - REST API for dataset management and tile serving
```

---

## Go-Specific Implementation Notes

### Image Processing

```go
import (
    "image"
    "image/color"
    "image/png"
    "image/jpeg"
    "bytes"

    _ "golang.org/x/image/tiff"  // Register TIFF decoder
    "golang.org/x/image/webp"    // WebP support
)

// Create a 256x256 RGBA tile
func newTileImage() *image.NRGBA {
    return image.NewNRGBA(image.Rect(0, 0, 256, 256))
}

// Set a pixel with transparency support
func setPixel(img *image.NRGBA, x, y int, r, g, b, a uint8) {
    img.SetNRGBA(x, y, color.NRGBA{R: r, G: g, B: b, A: a})
}

// Encode to PNG
func encodePNG(img image.Image) ([]byte, error) {
    var buf bytes.Buffer
    if err := png.Encode(&buf, img); err != nil {
        return nil, err
    }
    return buf.Bytes(), nil
}

// Encode to JPEG (for imagery where transparency is not needed)
func encodeJPEG(img image.Image, quality int) ([]byte, error) {
    var buf bytes.Buffer
    if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality}); err != nil {
        return nil, err
    }
    return buf.Bytes(), nil
}
```

### GDAL Bindings

Two main options for Go GDAL bindings:

**github.com/lukeroth/gdal** (legacy):
- Wraps GDAL C API directly via CGo
- Does not compile with GDAL 3+
- Most GDAL raster/OGR vector functionality exposed
- Not actively maintained

**github.com/airbusgeo/godal** (recommended):
- Idiomatic Go wrapper with proper error handling
- Requires GDAL >= 3.0
- Groups CGo calls to reduce overhead
- VSI handler for custom I/O (io.ReaderAt as virtual files)
- Raster API nearing completion, vector API still evolving

```go
import "github.com/airbusgeo/godal"

func readTileFromCOG(path string, z, x, y int) (*image.NRGBA, error) {
    godal.RegisterAll()

    ds, err := godal.Open(path)
    if err != nil {
        return nil, err
    }
    defer ds.Close()

    // Get dataset bounds and compute tile window
    gt, _ := ds.GeoTransform()
    // ... compute pixel window from tile BBOX and geotransform ...

    // Read raster data into buffer
    buf := make([]byte, 256*256*4) // RGBA
    err = ds.Read(xOff, yOff, xSize, ySize, buf, 256, 256)
    if err != nil {
        return nil, err
    }

    // Convert to image.NRGBA
    img := image.NewNRGBA(image.Rect(0, 0, 256, 256))
    copy(img.Pix, buf)
    return img, nil
}
```

### HTTP Serving Patterns

```go
import (
    "net/http"
    "github.com/go-chi/chi/v5"
    "github.com/go-chi/chi/v5/middleware"
)

func main() {
    r := chi.NewRouter()
    r.Use(middleware.Logger)
    r.Use(middleware.Recoverer)
    r.Use(middleware.Compress(5))
    r.Use(corsMiddleware)

    r.Get("/tiles/{z}/{x}/{y}", tileHandler)
    r.Get("/healthz", livenessHandler)
    r.Get("/readyz", readinessHandler)

    // WMS endpoint
    r.Get("/wms", wmsHandler)

    http.ListenAndServe(":8080", r)
}
```

### Concurrency Patterns

```go
import (
    "sync"
    "golang.org/x/sync/singleflight"
)

// Buffer pool for tile image encoding
var bufferPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func encodeTile(img image.Image) ([]byte, error) {
    buf := bufferPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufferPool.Put(buf)
    }()

    if err := png.Encode(buf, img); err != nil {
        return nil, err
    }
    // Return a copy since buf goes back to pool
    result := make([]byte, buf.Len())
    copy(result, buf.Bytes())
    return result, nil
}

// Image buffer pool for 256x256 RGBA tiles
// Each tile = 256 * 256 * 4 bytes = 256 KB
var imagePool = sync.Pool{
    New: func() interface{} {
        return image.NewNRGBA(image.Rect(0, 0, 256, 256))
    },
}

func getTileImage() *image.NRGBA {
    img := imagePool.Get().(*image.NRGBA)
    // Clear the image before reuse
    for i := range img.Pix {
        img.Pix[i] = 0
    }
    return img
}

func putTileImage(img *image.NRGBA) {
    imagePool.Put(img)
}

// Singleflight for request coalescing
var tileGroup singleflight.Group

func serveTile(z, x, y int) ([]byte, error) {
    key := fmt.Sprintf("%d/%d/%d", z, x, y)
    result, err, _ := tileGroup.Do(key, func() (interface{}, error) {
        return renderAndEncodeTile(z, x, y)
    })
    if err != nil {
        return nil, err
    }
    return result.([]byte), nil
}
```

### Memory Management Considerations

```
Tile rendering memory usage per request:
  - Source raster read buffer:   variable (depends on source resolution)
  - Tile image (256x256 RGBA):   256 KB
  - PNG encoder buffer:          ~64 KB typical
  - Total per concurrent tile:   ~320 KB minimum

For 100 concurrent tile renders: ~32 MB
For 1000 concurrent tile renders: ~320 MB

Strategies:
  1. Use sync.Pool for image buffers and encoding buffers
  2. Limit concurrent renders with a semaphore:
       sem := make(chan struct{}, maxConcurrentRenders)
  3. Pre-allocate source read buffers matching common tile sizes
  4. Use JPEG instead of PNG when transparency is not needed (faster encoding)
  5. Profile with pprof to identify allocation hotspots
  6. Be cautious with sync.Pool for varying-size buffers (memory bloat risk)
```

---

## Building a WMS-Compatible Endpoint

### WMS Request Types

A WMS endpoint must support at minimum GetCapabilities and GetMap requests.

### Parsing GetMap KVP Parameters

```
Required GetMap Parameters:
  SERVICE=WMS
  VERSION=1.1.1 (or 1.3.0)
  REQUEST=GetMap
  LAYERS=layer1,layer2
  STYLES=style1,style2        (or empty for defaults)
  SRS=EPSG:4326               (WMS 1.1.1) or CRS=EPSG:4326 (WMS 1.3.0)
  BBOX=minx,miny,maxx,maxy    (axis order depends on version + CRS)
  WIDTH=256
  HEIGHT=256
  FORMAT=image/png

Optional Standard Parameters:
  TRANSPARENT=TRUE
  BGCOLOR=0xFFFFFF
  EXCEPTIONS=application/vnd.ogc.se_xml
  TIME=2025-01-15
  SLD=<url>              Style URL for remote SLD
  SLD_BODY=<xml>         Inline SLD style document
  SLD_VERSION=1.1.0      SLD specification version

GeoServer Vendor Parameters (non-standard):
  CQL_FILTER=<expr>      CQL filter per layer
  FILTER=<ogc:Filter>    OGC XML filter per layer (standard OGC extension)
  FEATUREID=id1,id2      Feature ID filter
  FORMAT_OPTIONS=k:v     Output format specific options
  ENV=k:v;k2:v2          SLD variable substitution
  INTERPOLATIONS=method  Resampling (nearest, bilinear, bicubic)
  VIEWPARAMS=k:v         SQL view parameters
```

```go
type GetMapRequest struct {
    Version     string
    Layers      []string
    Styles      []string
    CRS         string
    BBox        [4]float64 // minx, miny, maxx, maxy
    Width       int
    Height      int
    Format      string
    Transparent bool
}

func parseGetMapRequest(r *http.Request) (*GetMapRequest, error) {
    q := r.URL.Query()

    req := &GetMapRequest{
        Version: q.Get("VERSION"),
        Format:  q.Get("FORMAT"),
    }

    // Parse layers
    req.Layers = strings.Split(q.Get("LAYERS"), ",")

    // Parse styles (may be empty)
    styles := q.Get("STYLES")
    if styles != "" {
        req.Styles = strings.Split(styles, ",")
    }

    // CRS: "SRS" in WMS 1.1.1, "CRS" in WMS 1.3.0
    if req.Version == "1.3.0" {
        req.CRS = q.Get("CRS")
    } else {
        req.CRS = q.Get("SRS")
    }

    // Parse BBOX
    bboxParts := strings.Split(q.Get("BBOX"), ",")
    if len(bboxParts) != 4 {
        return nil, fmt.Errorf("invalid BBOX: expected 4 values")
    }
    for i, part := range bboxParts {
        val, err := strconv.ParseFloat(strings.TrimSpace(part), 64)
        if err != nil {
            return nil, fmt.Errorf("invalid BBOX value: %s", part)
        }
        req.BBox[i] = val
    }

    // WMS 1.3.0 axis order: geographic CRSs (e.g., EPSG:4326) use lat/lon
    // order in BBOX, so BBOX=miny,minx,maxy,maxx. Normalize to lon/lat order.
    if req.Version == "1.3.0" && isGeographicCRS(req.CRS) {
        req.BBox = [4]float64{req.BBox[1], req.BBox[0], req.BBox[3], req.BBox[2]}
    }

    // Parse dimensions
    var err error
    req.Width, err = strconv.Atoi(q.Get("WIDTH"))
    if err != nil {
        return nil, fmt.Errorf("invalid WIDTH")
    }
    req.Height, err = strconv.Atoi(q.Get("HEIGHT"))
    if err != nil {
        return nil, fmt.Errorf("invalid HEIGHT")
    }

    // Transparent
    req.Transparent = strings.EqualFold(q.Get("TRANSPARENT"), "TRUE")

    return req, nil
}
```

### BBOX to Pixel Coordinate Mapping

```go
// GeoTransform maps between pixel coordinates and geographic coordinates.
// For a source raster with a known geotransform [originX, pixelWidth, 0, originY, 0, pixelHeight]:
//   geoX = originX + pixelX * pixelWidth
//   geoY = originY + pixelY * pixelHeight  (pixelHeight is negative)

func bboxToPixelWindow(gt [6]float64, bbox [4]float64) (xOff, yOff, xSize, ySize int) {
    minX, minY, maxX, maxY := bbox[0], bbox[1], bbox[2], bbox[3]

    // Convert geographic coordinates to pixel coordinates
    xOff = int((minX - gt[0]) / gt[1])
    yOff = int((maxY - gt[3]) / gt[5])  // gt[5] is negative
    xEnd := int((maxX - gt[0]) / gt[1])
    yEnd := int((minY - gt[3]) / gt[5])

    xSize = xEnd - xOff
    ySize = yEnd - yOff
    return
}
```

### SRS/CRS Handling

```
WMS 1.1.1 vs 1.3.0 Axis Order:

  WMS 1.1.1:
    SRS=EPSG:4326  -> BBOX=minlon,minlat,maxlon,maxlat (x,y = lon,lat)

  WMS 1.3.0:
    CRS=EPSG:4326  -> BBOX=minlat,minlon,maxlat,maxlon (x,y = lat,lon)
    CRS=EPSG:3857  -> BBOX=minx,miny,maxx,maxy         (no axis swap)

  Rule: In WMS 1.3.0, if the CRS has a northing-first axis order
  (like EPSG:4326), the BBOX values are lat,lon not lon,lat.
  EPSG:3857 (Web Mercator) uses easting-first, so no swap needed.
```

### GetCapabilities XML Response

```go
const capabilitiesTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<WMS_Capabilities version="1.3.0"
  xmlns="http://www.opengis.net/wms"
  xmlns:xlink="http://www.w3.org/1999/xlink">
  <Service>
    <Name>WMS</Name>
    <Title>{{.Title}}</Title>
    <Abstract>{{.Abstract}}</Abstract>
    <OnlineResource xlink:href="{{.ServiceURL}}"/>
  </Service>
  <Capability>
    <Request>
      <GetCapabilities>
        <Format>text/xml</Format>
        <DCPType><HTTP><Get>
          <OnlineResource xlink:href="{{.ServiceURL}}?"/>
        </Get></HTTP></DCPType>
      </GetCapabilities>
      <GetMap>
        {{range .Formats}}
        <Format>{{.}}</Format>
        {{end}}
        <DCPType><HTTP><Get>
          <OnlineResource xlink:href="{{.ServiceURL}}?"/>
        </Get></HTTP></DCPType>
      </GetMap>
    </Request>
    <Exception>
      <Format>XML</Format>
    </Exception>
    {{range .Layers}}
    <Layer queryable="0">
      <Name>{{.Name}}</Name>
      <Title>{{.Title}}</Title>
      <CRS>EPSG:4326</CRS>
      <CRS>EPSG:3857</CRS>
      <EX_GeographicBoundingBox>
        <westBoundLongitude>{{.West}}</westBoundLongitude>
        <eastBoundLongitude>{{.East}}</eastBoundLongitude>
        <southBoundLatitude>{{.South}}</southBoundLatitude>
        <northBoundLatitude>{{.North}}</northBoundLatitude>
      </EX_GeographicBoundingBox>
    </Layer>
    {{end}}
  </Capability>
</WMS_Capabilities>`
```

### WMS Error/Exception Handling

```go
func writeServiceException(w http.ResponseWriter, code, message string) {
    w.Header().Set("Content-Type", "application/vnd.ogc.se_xml")
    w.WriteHeader(http.StatusOK)  // WMS spec: exceptions use 200 status

    fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<ServiceExceptionReport version="1.3.0">
  <ServiceException code="%s">%s</ServiceException>
</ServiceExceptionReport>`, code, message)
}

// Standard exception codes:
//   InvalidFormat         - Unsupported output format
//   InvalidCRS            - Unsupported CRS/SRS
//   LayerNotDefined       - Requested layer does not exist
//   StyleNotDefined       - Requested style does not exist
//   LayerNotQueryable     - GetFeatureInfo on non-queryable layer
//   InvalidPoint          - GetFeatureInfo point outside BBOX
//   MissingDimensionValue - Required dimension not specified
//   InvalidDimensionValue - Invalid dimension value
```

### Complete WMS Handler

```go
func wmsHandler(w http.ResponseWriter, r *http.Request) {
    request := r.URL.Query().Get("REQUEST")

    switch strings.ToUpper(request) {
    case "GETCAPABILITIES":
        serveCapabilities(w, r)
    case "GETMAP":
        serveGetMap(w, r)
    default:
        writeServiceException(w, "InvalidRequest",
            fmt.Sprintf("Unsupported request: %s", request))
    }
}

func serveGetMap(w http.ResponseWriter, r *http.Request) {
    req, err := parseGetMapRequest(r)
    if err != nil {
        writeServiceException(w, "InvalidParameterValue", err.Error())
        return
    }

    // Validate layers exist
    for _, layer := range req.Layers {
        if !layerExists(layer) {
            writeServiceException(w, "LayerNotDefined",
                fmt.Sprintf("Layer not found: %s", layer))
            return
        }
    }

    // Validate CRS
    if !supportedCRS(req.CRS) {
        writeServiceException(w, "InvalidCRS",
            fmt.Sprintf("Unsupported CRS: %s", req.CRS))
        return
    }

    // Render the map image
    img, err := renderMapImage(req)
    if err != nil {
        writeServiceException(w, "InternalError", "Failed to render map")
        return
    }

    // Encode and respond
    contentType, data, err := encodeImage(img, req.Format)
    if err != nil {
        writeServiceException(w, "InvalidFormat",
            fmt.Sprintf("Unsupported format: %s", req.Format))
        return
    }

    w.Header().Set("Content-Type", contentType)
    w.Write(data)
}
```
