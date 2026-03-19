# Indexing and Databasing for Imagery

## Why Indexing Matters for Imagery Serving

Imagery serving systems face a fundamental lookup problem: given a tile request at coordinates (z, x, y), which of potentially millions of source imagery files contain data for that tile?

**Brute force** -- scanning every file's bounding box -- is O(n) per request where n is the number of imagery files. At 100,000 source images this becomes untenable for interactive map performance (sub-200ms responses).

**Spatial indexing** reduces this to O(log n) or better:

| Approach | Lookup Complexity | Insert Complexity | Best For |
|---|---|---|---|
| Brute force scan | O(n) | O(1) | Trivial datasets (<100 files) |
| Grid index | O(1) average | O(1) | Uniform density, known extent |
| Quadtree | O(log4 n) = O(log n) | O(log n) | Hierarchical tile access |
| R-tree (GiST) | O(log n) | O(log n) | Irregular geometries, arbitrary queries |

### Spatial Indexing Fundamentals

**R-tree**: Groups nearby objects into minimum bounding rectangles (MBRs) at each tree level. PostGIS uses a Generalized Search Tree (GiST) variant. Well-suited for mixed-size geometries and complex spatial predicates (intersects, contains, within).

**Quadtree**: Recursively subdivides 2D space into four quadrants. Natural fit for tile pyramids since the tiling scheme itself IS a quadtree. Each zoom level doubles resolution in both dimensions -- exactly matching quadtree subdivision. Google Earth Enterprise uses this approach.

**Grid index**: Divides the area into fixed-size cells. O(1) lookup but wastes space in sparse areas. MapServer uses this internally for shapefile spatial indexing.

---

## PostGIS for Geospatial Indexing

PostGIS extends PostgreSQL with spatial types (geometry, geography, raster) and spatial indexing.

### GiST Indexes

PostGIS spatial indexes use PostgreSQL's GiST (Generalized Search Tree) framework to build R-trees over geometry columns:

```sql
CREATE INDEX idx_imagery_footprint ON imagery_catalog
  USING GIST (footprint);
```

The GiST R-tree groups nearby geometries into bounding boxes at each tree level. A spatial query like `ST_Intersects(footprint, tile_bbox)` first checks the index to find candidate bounding boxes (fast), then performs exact geometry tests only on candidates (slower but on a small set).

### raster2pgsql: Importing Raster Metadata

`raster2pgsql` loads raster data or metadata into PostGIS tables. For tile serving, the metadata-only mode is most useful:

```bash
# Import only footprints/metadata (no pixel data), create spatial index
raster2pgsql -s 4326 -R -C -I /data/imagery/*.tif public.imagery_catalog \
  | psql -d geodb

# Flags:
#   -s 4326    SRID (WGS 84)
#   -R         Register rasters as out-of-db (reference file paths, not pixel data)
#   -C         Apply raster constraints
#   -I         Create GIST spatial index on the raster column
```

This registers each file's footprint and metadata in PostGIS while the actual pixel data remains on disk or object storage. The tile server queries PostGIS to find relevant files, then reads pixels directly from those files.

### Spatial Queries for Tile Serving

Common query patterns for resolving which imagery covers a requested tile:

```sql
-- Find all imagery files intersecting a tile bounding box
SELECT filepath, acquisition_date, resolution_m
FROM imagery_catalog
WHERE ST_Intersects(
  footprint,
  ST_MakeEnvelope(-105.5, 39.5, -105.0, 40.0, 4326)
)
ORDER BY acquisition_date DESC, resolution_m ASC;

-- Find imagery fully containing a region of interest
SELECT filepath FROM imagery_catalog
WHERE ST_Contains(footprint, ST_GeomFromText('POLYGON((...))'));

-- Find nearest imagery to a point (useful for oblique/aerial)
SELECT filepath, ST_Distance(footprint, ST_MakePoint(-105.2, 39.7)) AS dist
FROM imagery_catalog
ORDER BY footprint <-> ST_MakePoint(-105.2, 39.7)
LIMIT 5;
```

The `<->` operator uses the GiST index for k-nearest-neighbor (KNN) queries without scanning the full table.

### Vector Tile Generation

PostGIS can generate Mapbox Vector Tiles (MVT) directly:

```sql
-- Generate MVT for a tile at z/x/y
SELECT ST_AsMVT(tile, 'imagery_footprints') FROM (
  SELECT ST_AsMVTGeom(footprint, ST_TileEnvelope(12, 680, 1588))
  FROM imagery_catalog
  WHERE ST_Intersects(footprint, ST_TileEnvelope(12, 680, 1588))
) AS tile;
```

### Coverage Metadata Table Design

A practical schema for tracking imagery footprints in a tile-serving system:

```sql
CREATE TABLE imagery_catalog (
  id            SERIAL PRIMARY KEY,
  filepath      TEXT NOT NULL,          -- Path to source file (local or S3 URI)
  footprint     GEOMETRY(Polygon, 4326) NOT NULL,
  acquisition   TIMESTAMPTZ,
  resolution_m  REAL,                   -- Ground sample distance in meters
  cloud_cover   REAL CHECK (cloud_cover BETWEEN 0 AND 100),
  sensor        TEXT,                   -- e.g., 'Landsat-8', 'Sentinel-2'
  band_count    SMALLINT,
  bit_depth     SMALLINT,
  format        TEXT,                   -- 'GeoTIFF', 'COG', 'JPEG2000'
  file_size     BIGINT,
  min_zoom      SMALLINT,              -- Appropriate zoom level range
  max_zoom      SMALLINT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_catalog_footprint ON imagery_catalog USING GIST (footprint);
CREATE INDEX idx_catalog_acquisition ON imagery_catalog (acquisition DESC);
CREATE INDEX idx_catalog_resolution ON imagery_catalog (resolution_m);
```

### Connection Pooling

High-throughput tile serving generates many short-lived database queries. Connection poolers are essential:

- **PgBouncer**: Lightweight, single-process. Transaction-mode pooling (connections returned after each transaction) is ideal for tile serving. Typical config: 20 server connections serving 1000+ client connections.
- **PgPool-II**: Heavier, adds load balancing and replication. More complex to configure but useful when read replicas are involved.

For tile serving, PgBouncer in transaction mode is the standard choice. Set `pool_size` based on available PostgreSQL `max_connections` (typically 20-50 per pooler instance).

### Partitioning Strategies

For large catalogs (millions of entries), partition the imagery_catalog table:

- **By date**: `PARTITION BY RANGE (acquisition)` -- fast queries when filtering by time window
- **By region**: `PARTITION BY LIST (region_code)` or hash-partition by geohash prefix -- useful for geographically distributed deployments
- **By zoom level**: If storing pre-rendered tiles, partition by zoom level to isolate hot (frequently accessed) zoom ranges

```sql
-- Example: partition by year
CREATE TABLE imagery_catalog (
  id SERIAL, filepath TEXT, footprint GEOMETRY, acquisition TIMESTAMPTZ
) PARTITION BY RANGE (acquisition);

CREATE TABLE imagery_2024 PARTITION OF imagery_catalog
  FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE imagery_2025 PARTITION OF imagery_catalog
  FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
```

---

## Google Earth Enterprise Index System

The Google Earth Enterprise (GEE) index system, as found in the Open GEE source code, is a purpose-built file-based spatial index optimized for quadtree tile access. It avoids database dependencies entirely, achieving high throughput through direct file I/O.

### QuadtreePath Addressing

The core addressing unit is `QuadtreePath` (defined in `common/quadtreepath.h`). A tile's position in the quadtree is encoded as a path of quadrant choices from the root:

- Each level selects one of 4 quadrants (children 0-3)
- The path is packed into a **uint64**: the upper 48 bits store up to **24 levels** of path (2 bits per level), and the lower bits store the level count
- Quadrant layout at each level:

```
+---+---+
| 2 | 3 |
+---+---+
| 0 | 1 |
+---+---+
```

Example: `QuadtreePath("2031")` = level 4, quadrants 2->0->3->1. The `AsIndex()` method converts a path prefix to an array offset: `QuadtreePath("23121").AsIndex(4)` yields binary `10110110` = 182.

Maximum supported depth is 24 levels (sufficient for sub-meter resolution globally).

### Bucket-Based Index Structure

The geindex system (in `common/geindex/`) organizes the quadtree into **buckets** that group 4 levels of the tree:

- **`kQuadLevelsPerBucket = 4`**: Each bucket covers 4 quadtree levels
- **`kChildAddrsPerBucket = 256`** (4^4): Max child pointers per bucket
- **`kEntrySlotsPerBucket = 85`** (1 + 4 + 16 + 64): Total entry slots per bucket (nodes at levels 0-3 within the bucket)

A `BucketPath` truncates a `QuadtreePath` to an even multiple of 4 levels. Within a bucket, entry positions are computed as pre-order slot indices via `SubAddrAsEntrySlot()`.

The two-level bucket structure:

1. **ChildBucket**: Contains 256 `ChildBucketAddr` pointers (to deeper ChildBuckets) and 256 `EntryBucketAddr` pointers (to leaf data). Stored contiguously with separate CRC32 checksums for each half.
2. **EntryBucket**: Contains up to 85 entry slots, each holding data references. Supports both single-entry slots (imagery/terrain) and multiple-entry slots (vector layers, blend stacks).

### Entry Types

Entries reference external data packets via `ExternalDataAddress` (file offset + file number + size). The index supports several entry types (from `Entries.h`):

| Entry Type | Use | Multi-per-slot |
|---|---|---|
| `BlendEntry` | Intermediate imagery/terrain indexes | Yes (one per inset in blend stack) |
| `SimpleInsetEntry` | Combined terrain mesh | No |
| `ChannelledEntry` | Vector packets | Yes (one per channel) |
| `TypedEntry` | Unified final index (all data types) | Yes (imagery, terrain, vector, QT packets) |

The `TypedEntry` unifies all types into a single index with a `TypeEnum` discriminator: `QTPacket`, `Imagery`, `Terrain`, `VectorGE`, `VectorMaps`, `DatedImagery`, etc.

### FileBundle Storage Layer

The underlying storage is `FileBundle` (in `common/filebundle/`), a virtual large file implemented as multiple segment files:

- Each segment is capped at ~1GB (configurable) to work with 32-bit file addressing
- A `bundle.hdr` file lists segments, sizes, and the segment break value
- Addressing is via 64-bit offset across the virtual file
- CRC32 integrity checking on reads

The `IndexBundle` wraps `FileBundle` with geindex-specific semantics: an `index.hdr` header containing root bucket addresses, a list of external packet files, and file format versioning.

### Lookup Flow

When serving a tile request (e.g., for quadtree path "203112"):

1. Compute the `BucketPath` by truncating to a multiple of 4 levels: "2031"
2. Start at the root `ChildBucket` (address stored in `index.hdr`)
3. Navigate through ChildBuckets: first bucket level covers levels 0-3, next covers 4-7, etc.
4. At each level, compute the child slot via `SubAddrAsChildSlot()` (converts 4-level subpath to 0-255 index)
5. Follow the `ChildBucketAddr` pointer to load the next bucket from disk
6. Once at the correct depth, follow the `EntryBucketAddr` pointer
7. Within the EntryBucket, compute the slot via `SubAddrAsEntrySlot()` (pre-order index 0-84)
8. Read the `ExternalDataAddress` to get the file number and offset of the actual tile data
9. Read the tile data from the referenced packet file

A **read cache** (`ChildBucketCache`) keeps recently accessed ChildBuckets in memory, with configurable cache depth (`numBucketLevelsCached`). For 24 levels, there are only 6 bucket levels, so caching the top 2-3 levels eliminates most disk reads.

### Index Generation

Two tools generate indexes:

- **`geindexgen`**: Creates type-specific indexes (Imagery, Terrain, VectorGE) from packet file stacks. Uses a `BlendGenerator` or `VectorGenerator` that traverses input packets in quadtree pre-order and writes entries.
- **`geunifiedindexgen`**: Merges multiple type-specific indexes into a single `UnifiedIndex`. Uses a merge-sort across traversers (one per input index), translating file numbers into the unified namespace.

Both enforce **pre-order insertion** -- entries must be written in quadtree pre-order, which enables streaming writes and efficient bucket flushing.

### Portable Globe PacketBundle System

For portable/disconnected deployments, GEE uses a simpler `PacketBundle` system (in `fusion/portableglobe/shared/`):

- An `IndexItem` struct (24 bytes) stores: quadtree address (6 bytes as btree_high + btree_low), level, packet_type, channel, file_id, packet_size, and offset
- Index items are sorted and stored contiguously in an index file
- Lookup uses **binary search** (O(log n)) over the sorted index
- The `PacketBundleFinder` reads index entries directly from disk during binary search
- A **cached binary search** variant (`packetbundle_cached_finder.cpp`) stores the index entries visited at each depth of the binary search. Since nearby tile requests follow similar binary search paths, most steps hit the cache. Cache size is O(log2(n)) entries -- negligible memory for significant speedup.

### Comparison: File-Based vs Database-Backed

| Aspect | GEE File Index | Database (PostGIS) |
|---|---|---|
| Dependencies | None (files only) | PostgreSQL server |
| Lookup speed | O(log n), direct I/O | O(log n), SQL overhead |
| Concurrent reads | Excellent (stateless) | Good (connection pooling) |
| Ad-hoc queries | Not supported | Full SQL + spatial predicates |
| Update flexibility | Rebuild or delta merge | Row-level INSERT/UPDATE/DELETE |
| Deployment | Copy files | Run database server |
| Best for | Fixed datasets, embedded | Dynamic catalogs, complex queries |

---

## Tile Cache Storage and Indexing

### MBTiles (SQLite)

MBTiles stores tiles in a single SQLite database file:

```sql
-- MBTiles schema
CREATE TABLE tiles (
  zoom_level  INTEGER,
  tile_column INTEGER,
  tile_row    INTEGER,
  tile_data   BLOB
);
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);

CREATE TABLE metadata (
  name  TEXT,
  value TEXT
);
```

**Performance characteristics**:
- Excellent concurrent read performance (SQLite SHARED locks support unlimited concurrent readers)
- Single-writer limitation (SQLite locking)
- Compact single-file format, easy to transfer
- B-tree index on (z, x, y) provides O(log n) lookup
- Practical limit: ~1-2 billion tiles per file (SQLite max db size 281 TB)

**When to use**: Offline/embedded tile serving, transferable tile packages, moderate-scale deployments.

### GeoPackage

OGC standard extending SQLite with spatial capabilities, including a tile storage extension:

```sql
-- GeoPackage tile tables
CREATE TABLE gpkg_tile_matrix_set (...);
CREATE TABLE gpkg_tile_matrix (...);       -- zoom levels, tile dimensions
CREATE TABLE my_tiles (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  zoom_level  INTEGER NOT NULL,
  tile_column INTEGER NOT NULL,
  tile_row    INTEGER NOT NULL,
  tile_data   BLOB NOT NULL,
  UNIQUE (zoom_level, tile_column, tile_row)
);
```

Advantages over MBTiles: standardized by OGC, supports vector features and raster tiles in one file, has formal spatial reference system tables. Disadvantage: slightly more complex schema, less tooling support than MBTiles.

### PMTiles

Single-file tile archive using **Hilbert curve ordering** for spatial locality:

- Tiles are sorted by their Hilbert curve index rather than (z, x, y) lexicographic order
- This means spatially nearby tiles are stored near each other on disk
- The index is a compact B-tree stored at the beginning of the file
- Designed for HTTP range request access (serves tiles directly from cloud storage without a server)
- A single metadata fetch loads the root index; subsequent tile reads are 1-2 range requests

**Architecture**: Header (127 bytes) -> Root index entries -> Leaf index entries -> Tile data. The root index fits in a single HTTP request. Leaf directories are loaded on demand and cached client-side.

**When to use**: Serverless tile serving from S3/GCS/Azure Blob, static site hosting, CDN-friendly deployments.

### Redis/Memcached for In-Memory Caching

For hot tile caching in front of a tile server:

**Key design pattern**:
```
tile:{layer}:{z}:{x}:{y}        -> tile bytes
tile:{layer}:{z}:{x}:{y}:meta   -> JSON metadata (content-type, etag)
```

**Redis configuration for tile caching**:
- Use `maxmemory-policy allkeys-lfu` (Least Frequently Used) -- hot tiles stay cached
- Set TTL based on update frequency: static basemaps (24h+), live imagery (minutes)
- Use Redis Cluster for horizontal scaling across multiple nodes
- Typical: 10GB Redis instance caches ~2-5 million 256x256 PNG tiles

**Memcached** is simpler (no persistence, no data structures) but has slightly lower per-key overhead. Use when persistence is unnecessary and the cache is purely ephemeral.

**Eviction strategies**:
- **LRU** (Least Recently Used): Simple, good default
- **LFU** (Least Frequently Used): Better for tile caching since popular areas (cities) should persist
- **TTL-based**: Combine with LRU/LFU to ensure stale tiles expire
- **Explicit invalidation**: Purge tiles when source imagery is updated

### Filesystem Directory Hierarchy

The simplest tile cache: files organized as `{z}/{x}/{y}.png`:

```
tiles/
  0/0/0.png
  1/0/0.png
  1/0/1.png
  1/1/0.png
  1/1/1.png
  ...
  18/262144/...
```

**Limitations at scale**:
- **Directory entry limits**: ext4 supports ~10 million entries per directory (with dir_index). At zoom 18, x ranges 0-262143 -- a single z directory has 262,144 subdirectories.
- **Inode limits**: Default ext4 creates 1 inode per 16KB. A filesystem with 100M tiles needs 100M inodes. Check with `df -i`.
- **Metadata overhead**: Each file consumes an inode (~256 bytes on ext4). 100M tiles = ~25GB of inode metadata alone.
- **ls/find performance**: Listing directories with >100K entries is extremely slow.

**Mitigations**: Use deeper directory nesting (e.g., split x/y digits: `18/26/21/44/...`), or switch to a database/archive format above ~10M tiles.

---

## Metadata Catalogs and Discovery

### STAC (SpatioTemporal Asset Catalog)

STAC is the modern standard for organizing and discovering geospatial data. It defines a JSON-based structure:

- **Item**: A single spatiotemporal asset (one satellite scene). Has geometry, datetime, and links to asset files (COGs, thumbnails).
- **Collection**: A group of related Items (e.g., all Sentinel-2 L2A scenes). Defines shared metadata, spatial/temporal extent, license.
- **Catalog**: A top-level grouping of Collections and other Catalogs. Can be a simple set of JSON files (static catalog) or a searchable API.

**STAC API** extends the static catalog with search:
```
GET /search?bbox=-105.5,39.5,-105.0,40.0&datetime=2024-01-01/2024-12-31&collections=sentinel-2-l2a
```

**Indexing for STAC**: A STAC API backend typically stores Items in PostGIS with GiST indexes on geometry and B-tree indexes on datetime. Tools like `pgstac` provide an optimized PostgreSQL schema and SQL functions for STAC search.

**Key STAC extensions for imagery**: `eo` (bands, cloud cover), `view` (sun/view angles), `projection` (EPSG, transform), `raster` (band statistics).

### OGC CSW (Catalog Service for the Web)

Legacy XML-based catalog standard. Still used in government and military systems (NGA, USGS). Supports:
- `GetCapabilities`, `GetRecords`, `GetRecordById`
- Dublin Core and ISO 19115/19139 metadata profiles
- Spatial and temporal filters via OGC Filter Encoding

Being superseded by STAC and OGC API - Records in new deployments, but existing enterprise GIS infrastructure often depends on CSW.

### GeoServer Catalog

GeoServer maintains an internal catalog of configured resources:

- **Workspaces** contain **Stores** (data sources) which contain **Layers**
- The catalog is stored as XML files on disk (default) or in a database (JDBC catalog)
- Each store connection (PostGIS, GeoTIFF, ImageMosaic) is configured with connection parameters
- Layer metadata includes bounding box, CRS, default style, and enabled status

### GeoServer ImageMosaic Indexing

The ImageMosaic module indexes collections of raster files (granules) for dynamic mosaicking. From the GeoServer importer extension (`MosaicIndex.java`), the indexing process:

1. **Granule discovery**: Scans a directory for raster files, reads each file's bounding box and CRS
2. **Index creation**: Writes a shapefile (`.shp`) containing each granule's footprint polygon and filename:
   - `the_geom` (Polygon): Bounding box of the granule
   - `location` (String): Filename of the raster file
   - `time` (Date, optional): Acquisition timestamp for time-series mosaics
3. **Property files**: `indexer.properties` configures the mosaic (name, schema), and a `{name}.properties` file stores runtime parameters (time attribute, etc.)
4. **Alternative backends**: Instead of shapefiles, ImageMosaic can use PostGIS or H2 databases for the granule index -- necessary at scale since shapefiles have a 2GB size limit and no concurrent write support

**Granule query at request time**: When a WMS GetMap request arrives, ImageMosaic queries the index for granules whose footprints intersect the requested bounding box, reads matching granules, and composites them into the output image.

**Time/elevation dimensions**: The index can include additional attributes (time, elevation, custom dimensions) enabling WMS requests like `TIME=2024-06-15` to select the correct granules.

---

## Caching Strategy: Memory vs Disk vs Database

### Decision Framework

| Storage Tier | What to Store | Access Time | Cost/GB |
|---|---|---|---|
| **In-memory** (Redis, app cache) | Hot tiles (popular zoom/area), tile metadata, small index structures | <1ms | $$$$ |
| **SSD/NVMe** | Warm tiles, rendered tile cache, COG files for range reads | 0.1-1ms | $$ |
| **HDD** | Cool tiles, full tile archive | 5-10ms | $ |
| **Database** (PostGIS) | Imagery metadata, footprint indexes, access control, search/discovery | 1-10ms | $$ |
| **Object storage** (S3/GCS) | Cold tiles, archival imagery, COGs for HTTP range-request serving | 50-200ms (first byte) | $0.02/GB/mo |

### Memory Budgeting

Rough sizing for tile caches:

| Tile Format | Avg Size | Tiles per 1GB RAM | Coverage at z14 |
|---|---|---|---|
| PNG 256x256 | 20-50 KB | 20K-50K tiles | ~5-12% of Earth |
| JPEG 256x256 | 10-25 KB | 40K-100K tiles | ~10-25% of Earth |
| WebP 256x256 | 8-20 KB | 50K-125K tiles | ~12-30% of Earth |
| PBF vector | 5-30 KB | 33K-200K tiles | varies |

For a typical regional deployment (one country, zooms 0-16): 8-16GB Redis handles the hot working set. Global basemap at all zooms: 100GB+ distributed cache (Redis Cluster or CDN).

### Cache Warming Strategies

- **Seed on deploy**: Pre-render tiles for popular zoom levels (0-12) and known high-traffic areas
- **Lazy fill**: Render on first request, cache result. Simple but cold starts are slow.
- **Predictive**: Analyze access logs, pre-warm tiles for anticipated events (e.g., weather event areas)
- **Tiered**: Warm zoom 0-10 fully (small), warm zoom 11-14 for populated areas, leave zoom 15+ on-demand

---

## Database Selection Guide

| Use Case | Recommended | Why |
|---|---|---|
| Tile metadata/footprints | PostGIS | GiST spatial indexing, complex spatial+temporal queries, SQL flexibility |
| Pre-rendered tile cache | MBTiles / filesystem / S3 | Simple key-value access, high read throughput, no query overhead |
| In-memory hot cache | Redis | Sub-millisecond reads, LFU eviction, TTL, cluster scaling |
| Imagery catalog/discovery | PostGIS + STAC API | Standard search API, spatial+temporal indexing, interoperability |
| Small/embedded deployments | SQLite / GeoPackage | Zero dependencies, single-file, portable |
| Large-scale cloud | S3 + CloudFront + DynamoDB | Serverless, auto-scaling, global CDN, pay-per-request |
| Serverless tile hosting | PMTiles on S3/GCS | No server needed, HTTP range requests, Hilbert-ordered |
| Fixed offline dataset | GEE-style file index | No dependencies, fast direct I/O, copy to deploy |

---

## Indexing for Scale

### Scale Breakpoints

**Thousands of tiles** (<100K): Filesystem directories work fine. Simple z/x/y layout. No special tooling needed.

**Hundreds of thousands to millions** (100K-10M): MBTiles or GeoPackage. SQLite B-tree handles this well. Filesystem still works but directory listing becomes slow. Consider a tile server with LRU cache.

**Tens of millions** (10M-100M): Filesystem starts to struggle (inode limits, directory sizes). MBTiles remains viable. Add Redis caching for hot tiles. PostGIS for metadata if sources are dynamic.

**Hundreds of millions** (100M-1B): Filesystem is impractical without deep nesting. MBTiles approaches SQLite practical limits. Consider PMTiles for static datasets, or S3 + DynamoDB for dynamic serving. Redis Cluster for distributed caching.

**Billions** (1B+): Object storage (S3) with CDN caching. PMTiles or custom tile archive formats. Database for metadata only (not tile storage). Hybrid approach: database indexes which tiles exist, object storage holds tile bytes.

### Hybrid Strategies Used in Production

Most production systems combine multiple approaches:

1. **PostGIS** for source imagery metadata and discovery (STAC API)
2. **File/object storage** for actual tile data (COGs on S3, or pre-rendered tiles on NVMe)
3. **Redis** for hot tile caching (most-requested tiles stay in memory)
4. **CDN** (CloudFront, Fastly) as the outermost cache layer (geographically distributed, handles burst traffic)
5. **PMTiles or MBTiles** for offline/disconnected deployments extracted from the main system

The PostGIS catalog answers "what imagery exists here?" while the tile cache answers "what does this tile look like?" These are fundamentally different questions with different performance requirements.
